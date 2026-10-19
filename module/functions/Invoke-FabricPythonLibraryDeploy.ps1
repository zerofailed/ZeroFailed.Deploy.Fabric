function Invoke-FabricPythonLibraryDeploy {
    <#
    .SYNOPSIS
        Deploys a Python package (and its dependencies) into a Fabric Spark Environment.
    .DESCRIPTION
        The Python-library counterpart to Invoke-FabricSetup, intended to run after provisioning as a
        separate pipeline (typically from the repo that builds the package). For a single target
        workspace and Spark Environment it:
          1. Downloads the named package plus its full dependency closure from an Azure Artifacts
             feed, via Save-FabricLibraryPackage.
          2. Splits the closure into private packages (feed-only) and public packages (resolvable on
             PyPI). Private packages are uploaded as custom libraries; public packages are declared
             in an environment.yml for Fabric to resolve from PyPI directly. This keeps large public
             binary wheels out of the custom-library upload path, whose size limit a big wheel (e.g.
             deltalake, ~50 MB) exceeds with a server-side 500. Classification is automatic via a
             PyPI lookup per package, unless -PrivatePackageName is supplied.
          3. Resolves the workspace and its Spark Environment by display name. Both must already
             exist from provisioning.
          4. Clears down staged custom libraries not in the private set, imports the environment.yml
             external libraries (which overrides the whole external set), uploads the private custom
             wheels, and publishes — unless the desired custom and external sets are already
             published (idempotent) and -Force is not set.

        No topology config is needed: the workspace and environment are named directly, and the
        package coordinates and feed are supplied as parameters so versions can flow from the build.
        To deploy the same package into several environments, call this once per target, passing the
        same -StagingPath with -SkipDownload on the later calls to reuse the first download.

        Any failure (including a missing workspace or environment) is terminating.
    .PARAMETER WorkspaceName
        The display name of the target Fabric workspace, e.g. 'THX-DataPrep [DEV]'.
    .PARAMETER EnvironmentName
        The display name of the target Spark Environment within the workspace, e.g. 'THX-DataPrep Env'.
    .PARAMETER PackageName
        The package (distribution) name to deploy, e.g. 'mycompany.dataprep'.
    .PARAMETER PackageVersion
        The exact package version to deploy, e.g. '1.4.2'.
    .PARAMETER FeedOrganisation
        The Azure DevOps organisation hosting the Artifacts feed.
    .PARAMETER FeedProject
        The Azure DevOps project hosting the Artifacts feed.
    .PARAMETER FeedName
        The Azure Artifacts feed name.
    .PARAMETER FeedToken
        Bearer token / PAT with Feed Reader access (e.g. the pipeline's System.AccessToken).
    .PARAMETER StagingPath
        Directory used to download packages into. Defaults to a new temp directory.
    .PARAMETER ConstraintsPath
        Path to a pip constraints file pinning versions in the dependency closure. It lives in the
        calling repo. Ignored when -SkipDownload is set.
    .PARAMETER SkipDownload
        Skip the pip download and use the files already present in -StagingPath.
    .PARAMETER Force
        Upload and publish even when the desired files are already published.
    .PARAMETER PrivatePackageName
        The package names that are private (feed-only) and must be uploaded as custom libraries;
        every other package in the closure is treated as public and declared in environment.yml.
        Names are matched case-insensitively with PEP 503 normalisation. When omitted, each package
        is classified automatically by looking it up on PyPI (present at that version = public).
    .PARAMETER ExtraIndexUrl
        Secondary package index for dependencies not in the feed. Default: PyPI.
    .PARAMETER PythonExecutable
        The python executable to use for downloading. Default: 'python'.
    .PARAMETER TargetPythonVersion
        The Python version of the target Fabric Spark runtime that wheels are resolved for.
        Default: '3.11' (Fabric runtime 1.3). Use '3.10' for runtime 1.2.
    .PARAMETER TargetPlatform
        The platform tag wheels are resolved for. Default: 'manylinux2014_x86_64'.
    .PARAMETER PublishTimeoutSeconds
        Maximum seconds to wait for the environment publish. Default: 600.
    .EXAMPLE
        Invoke-FabricPythonLibraryDeploy `
            -WorkspaceName 'THX-DataPrep [DEV]' -EnvironmentName 'THX-DataPrep Env' `
            -PackageName mycompany.dataprep -PackageVersion 1.4.2 `
            -FeedOrganisation contoso -FeedProject Analytics -FeedName fabric-python `
            -FeedToken $env:SYSTEM_ACCESSTOKEN

        Deploys mycompany.dataprep 1.4.2 into the 'THX-DataPrep Env' Spark Environment of the
        'THX-DataPrep [DEV]' workspace.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkspaceName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EnvironmentName,

        [Parameter(Mandatory)]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [string]$PackageVersion,

        [Parameter(Mandatory)]
        [string]$FeedOrganisation,

        [Parameter(Mandatory)]
        [string]$FeedProject,

        [Parameter(Mandatory)]
        [string]$FeedName,

        [Parameter(Mandatory)]
        [string]$FeedToken,

        [string]$StagingPath,

        [string]$ConstraintsPath,

        [switch]$SkipDownload,

        [switch]$Force,

        [string[]]$PrivatePackageName,

        [string]$ExtraIndexUrl = 'https://pypi.org/simple',

        [string]$PythonExecutable = 'python',

        [ValidatePattern('^\d+\.\d+$')]
        [string]$TargetPythonVersion = '3.11',

        [ValidateNotNullOrEmpty()]
        [string]$TargetPlatform = 'manylinux2014_x86_64',

        [int]$PublishTimeoutSeconds = 600
    )

    $ErrorActionPreference = 'Stop'

    # Checked here as well as in Save-FabricLibraryPackage so a bad path fails before the auth
    # round-trip rather than several steps in.
    if ($ConstraintsPath -and -not $SkipDownload -and -not (Test-Path -LiteralPath $ConstraintsPath -PathType Leaf)) {
        throw "Constraints file not found: $ConstraintsPath"
    }

    # --- 1. Acquire auth token ---
    Write-Verbose 'Acquiring Fabric auth token...'
    $token = (_Get-FabricAuthToken).Token

    # --- 2. Resolve the target before downloading, so a typo in a name fails fast ---
    # The workspace must already exist from provisioning.
    $workspaceObj = Test-FabricWorkspaceExists -DisplayName $WorkspaceName -Token $token
    if (-not $workspaceObj) {
        throw "Workspace '$WorkspaceName' does not exist. Run provisioning before deploying."
    }
    $workspaceId = $workspaceObj.id

    # The Spark Environment must already exist from provisioning.
    $environmentObj = _Resolve-FabricEnvironment -WorkspaceId $workspaceId -DisplayName $EnvironmentName -Token $token
    if (-not $environmentObj) {
        throw "Environment '$EnvironmentName' does not exist in workspace '$WorkspaceName'. Run provisioning before deploying."
    }
    $environmentId = $environmentObj.id

    # --- 3. Download the package + dependencies ---
    if (-not $StagingPath) {
        $StagingPath = Join-Path ([System.IO.Path]::GetTempPath()) "fabric-python-library-$([guid]::NewGuid())"
    }

    if ($SkipDownload) {
        Write-Verbose "Skipping download; using existing files in '$StagingPath'."
        $files = Get-ChildItem -LiteralPath $StagingPath -File |
            Where-Object { $_.Name -match '\.(whl|tar\.gz|zip)$' }
        if (-not $files) {
            throw "-SkipDownload was specified but no package files were found in '$StagingPath'."
        }
    }
    else {
        $files = Save-FabricLibraryPackage `
            -PackageName         $PackageName `
            -PackageVersion      $PackageVersion `
            -FeedOrganisation    $FeedOrganisation `
            -FeedProject         $FeedProject `
            -FeedName            $FeedName `
            -FeedToken           $FeedToken `
            -DestinationPath     $StagingPath `
            -ConstraintsPath     $ConstraintsPath `
            -ExtraIndexUrl       $ExtraIndexUrl `
            -PythonExecutable    $PythonExecutable `
            -TargetPythonVersion $TargetPythonVersion `
            -TargetPlatform      $TargetPlatform
    }

    # --- 4. Split the closure: private (feed-only) packages are uploaded as custom libraries;
    #        public packages are declared in environment.yml for Fabric to pull from PyPI, keeping
    #        large public binary wheels out of the size-limited custom-library upload path. ---
    # Guard the null case: '$null | ForEach-Object' runs the block once and would yield @('') — a
    # non-empty set — which would wrongly switch off PyPI auto-classification.
    $privateSet = @()
    if ($PrivatePackageName) {
        $privateSet = @($PrivatePackageName | ForEach-Object { ($_ -replace '[-_.]+', '-').ToLower() })
    }

    $privateFiles   = [System.Collections.Generic.List[object]]::new()
    $publicPackages = [System.Collections.Generic.List[object]]::new()

    foreach ($file in $files) {
        $id = _Get-WheelIdentity -FileName $file.Name

        $isPrivate = if ($privateSet.Count -gt 0) {
            $id.NormalizedName -in $privateSet
        }
        else {
            -not (_Test-PackageOnPyPI -Name $id.NormalizedName -Version $id.Version)
        }

        if ($isPrivate) { $privateFiles.Add($file) } else { $publicPackages.Add($id) }
    }

    $environmentYml        = _ConvertTo-FabricEnvironmentYml -Package $publicPackages.ToArray()
    $desiredCustomNames    = @($privateFiles | ForEach-Object { $_.Name })
    $desiredExternalTokens = @($publicPackages | ForEach-Object { "$($_.NormalizedName)==$($_.Version)" } | Sort-Object -Unique)

    Write-Verbose ("{0} private wheel(s) to upload as custom libraries, {1} public package(s) via environment.yml." -f `
        $privateFiles.Count, $publicPackages.Count)
    if ($privateFiles.Count -gt 0) {
        Write-Verbose ("Private (custom-library) wheels: {0}" -f ($desiredCustomNames -join ', '))
    }

    $result = [pscustomobject]@{
        WorkspaceName     = $WorkspaceName
        EnvironmentName   = $EnvironmentName
        EnvironmentId     = $environmentId
        Files             = $desiredCustomNames
        ExternalLibraries = $desiredExternalTokens
        Removed           = @()
        Action            = $null
    }

    # --- 5. Idempotency — skip only when both the custom (private) set and the external (public)
    #        set already match the desired state exactly. Extra published custom files are stale
    #        versions that must be cleared down, so their presence forces a deploy. ---
    $publishedCustom   = Get-FabricEnvironmentLibraries -WorkspaceId $workspaceId -EnvironmentId $environmentId -Token $token
    $publishedExternal = Get-FabricEnvironmentLibraries -WorkspaceId $workspaceId -EnvironmentId $environmentId -Token $token -External

    $missingCustom = $desiredCustomNames    | Where-Object { $_ -notin $publishedCustom }
    $staleCustom   = $publishedCustom        | Where-Object { $_ -notin $desiredCustomNames }
    $missingExt    = $desiredExternalTokens  | Where-Object { $_ -notin $publishedExternal }
    $staleExt      = $publishedExternal      | Where-Object { $_ -notin $desiredExternalTokens }

    if (-not $Force -and -not $missingCustom -and -not $staleCustom -and -not $missingExt -and -not $staleExt) {
        Write-Verbose "'$EnvironmentName' in '$WorkspaceName' already has exactly the desired custom and external libraries published. Skipping."
        $result.Action = 'Skipped'
        return $result
    }

    # --- 6. Clear down staged custom libraries that are not part of the desired private set.
    #        Staging starts as a copy of the published libraries, so this is what retires
    #        previous versions (and any public wheels uploaded before the split) on publish. The
    #        external libraries need no clear-down — importExternalLibraries overrides them wholesale. ---
    $staged   = Get-FabricEnvironmentLibraries -WorkspaceId $workspaceId -EnvironmentId $environmentId -Token $token -Staging
    $toRemove = @($staged | Where-Object { $_ -notin $desiredCustomNames })

    foreach ($libraryName in $toRemove) {
        Remove-FabricEnvironmentLibrary `
            -WorkspaceId   $workspaceId `
            -EnvironmentId $environmentId `
            -LibraryName   $libraryName `
            -Token         $token | Out-Null
    }

    # --- 7. Import the public libraries (environment.yml), upload the private wheels, then publish. ---
    Import-FabricEnvironmentExternalLibraries `
        -WorkspaceId    $workspaceId `
        -EnvironmentId  $environmentId `
        -EnvironmentYml $environmentYml `
        -Token          $token | Out-Null

    foreach ($file in $privateFiles) {
        Add-FabricEnvironmentLibrary `
            -WorkspaceId   $workspaceId `
            -EnvironmentId $environmentId `
            -FilePath      $file.FullName `
            -Token         $token | Out-Null
    }

    $publishResult = Publish-FabricEnvironment `
        -WorkspaceId    $workspaceId `
        -EnvironmentId  $environmentId `
        -Token          $token `
        -TimeoutSeconds $PublishTimeoutSeconds

    $result.Removed = $toRemove
    $result.Action  = $publishResult.Action

    Write-Verbose "=== Python library deploy complete — '$EnvironmentName' in '$WorkspaceName': $($result.Action) ==="

    return $result
}
