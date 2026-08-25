function Invoke-FabricPythonLibraryDeploy {
    <#
    .SYNOPSIS
        Deploys a Python package (and its dependencies) into the Fabric Spark Environments of a stage.
    .DESCRIPTION
        The Python-library counterpart to Invoke-FabricSetup, intended to run after provisioning as a
        separate pipeline. For a single deployment stage it:
          1. Downloads the named package plus its full dependency closure from an Azure Artifacts
             feed (once), via Save-FabricLibraryPackage.
          2. Splits the closure into private packages (feed-only) and public packages (resolvable on
             PyPI). Private packages are uploaded as custom libraries; public packages are declared
             in an environment.yml for Fabric to resolve from PyPI directly. This keeps large public
             binary wheels out of the custom-library upload path, whose size limit a big wheel (e.g.
             deltalake, ~50 MB) exceeds with a server-side 500. Classification is automatic via a
             PyPI lookup per package, unless -PrivatePackageName is supplied.
          3. For every workspace in the topology that has a Spark Environment enabled for the given
             stage, resolves the workspace and its environment for that stage.
          4. Clears down staged custom libraries not in the private set, imports the environment.yml
             external libraries (which overrides the whole external set), uploads the private custom
             wheels, and publishes — unless the desired custom and external sets are already
             published (idempotent) and -Force is not set.

        Stages are owned by the calling pipeline: this runs one stage per invocation. The topology
        config is used only to resolve workspace and environment names — the package coordinates and
        feed are supplied as parameters so versions can flow from the build.

        Per-workspace failures are non-fatal and collected; the function throws at the end if any
        workspace failed, so the pipeline step fails while still attempting every target.
    .PARAMETER Config
        Topology config object produced by New-FabricTopologyConfig.
    .PARAMETER ConfigPath
        Path to a JSON topology config file (alternative to -Config).
    .PARAMETER Stage
        The single environment/stage name (as defined in config.environments) to deploy into.
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
        Path to a pip constraints file pinning versions in the dependency closure. Like -ConfigPath,
        it lives in the calling repo. Ignored when -SkipDownload is set.
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
        Default: '3.11' (Fabric runtime 1.3). Use '3.10' for runtime 1.2. Because the download
        happens once for the whole stage, all target workspaces must share a runtime version.
    .PARAMETER TargetPlatform
        The platform tag wheels are resolved for. Default: 'manylinux2014_x86_64'.
    .PARAMETER PublishTimeoutSeconds
        Maximum seconds to wait for each environment publish. Default: 600.
    .EXAMPLE
        Invoke-FabricPythonLibraryDeploy -ConfigPath ./topology.json -Stage DEV `
            -PackageName mycompany.dataprep -PackageVersion 1.4.2 `
            -FeedOrganisation contoso -FeedProject Analytics -FeedName fabric-python `
            -FeedToken $env:SYSTEM_ACCESSTOKEN

        Deploys mycompany.dataprep 1.4.2 into every Spark Environment in the DEV stage.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object', SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Object', Position = 0)]
        [pscustomobject]$Config,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [string]$Stage,

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

    # --- 1. Load config ---
    if ($PSCmdlet.ParameterSetName -eq 'File') {
        if (-not (Test-Path $ConfigPath)) {
            throw "Config file not found: $ConfigPath"
        }
        $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json -Depth 20
    }

    # Checked here as well as in Save-FabricLibraryPackage so a bad path fails before the auth
    # round-trip rather than several steps in.
    if ($ConstraintsPath -and -not $SkipDownload -and -not (Test-Path -LiteralPath $ConstraintsPath -PathType Leaf)) {
        throw "Constraints file not found: $ConstraintsPath"
    }

    # --- 2. Validate the stage exists ---
    $stageObj = $Config.environments | Where-Object { $_.name -eq $Stage }
    if (-not $stageObj) {
        throw "Stage '$Stage' not found in config. Available: $(($Config.environments.name) -join ', ')."
    }

    # --- 3. Determine target workspaces (those with a Spark Environment provisioned for this stage) ---
    # A workspace is a target only if its type has a Spark Environment enabled AND the stage is in the
    # type's configured stages. A config without a 'stages' list (older config) applies to all stages.
    $targetWorkspaces = $Config.workspaces | Where-Object {
        $_.PSObject.Properties.Name -contains 'environment' -and
        $_.environment.enabled -and
        (
            -not ($_.environment.PSObject.Properties.Name -contains 'stages') -or
            -not $_.environment.stages -or
            $Stage -in @($_.environment.stages)
        )
    }
    if (-not $targetWorkspaces) {
        Write-Warning "No workspaces in the topology have a Spark Environment enabled for stage '$Stage'; nothing to deploy."
        return [pscustomobject]@{
            Summary  = [pscustomobject]@{ Deployed = 0; Skipped = 0; Failed = 0 }
            Deployed = @()
            Failures = @()
        }
    }

    # --- 4. Acquire auth token ---
    Write-Verbose 'Acquiring Fabric auth token...'
    $tokenInfo = _Get-FabricAuthToken
    $token     = $tokenInfo.Token

    # --- 5. Download the package + dependencies once ---
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

    # --- 5b. Split the closure: private (feed-only) packages are uploaded as custom libraries;
    #         public packages are declared in environment.yml for Fabric to pull from PyPI, keeping
    #         large public binary wheels out of the size-limited custom-library upload path. ---
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

    Write-Verbose ("Stage '{0}': {1} private wheel(s) to upload as custom libraries, {2} public package(s) via environment.yml." -f `
        $Stage, $privateFiles.Count, $publicPackages.Count)
    if ($privateFiles.Count -gt 0) {
        Write-Verbose ("Private (custom-library) wheels: {0}" -f ($desiredCustomNames -join ', '))
    }

    # --- 6. Deploy to each target workspace's environment ---
    $results = [pscustomobject]@{
        Summary  = [pscustomobject]@{ Deployed = 0; Skipped = 0; Failed = 0 }
        Deployed = [System.Collections.Generic.List[hashtable]]::new()
        Failures = [System.Collections.Generic.List[hashtable]]::new()
    }

    foreach ($ws in $targetWorkspaces) {

        # Refresh the token if it is close to expiring (publishes can take several minutes each).
        if (_Test-FabricTokenExpiry -TokenInfo $tokenInfo) {
            Write-Verbose 'Token nearing expiry — refreshing...'
            $tokenInfo = _Get-FabricAuthToken
            $token     = $tokenInfo.Token
        }

        $resolvedName = _Resolve-WorkspaceName   -Config $Config -WorkspaceId $ws.id -EnvironmentName $Stage
        $envName      = _Resolve-EnvironmentName -Config $Config -WorkspaceId $ws.id -EnvironmentName $Stage

        try {
            # a. Resolve the workspace (must already exist from provisioning).
            $workspaceObj = Test-FabricWorkspaceExists -DisplayName $resolvedName -Token $token
            if (-not $workspaceObj) {
                throw "Workspace '$resolvedName' does not exist. Run provisioning before deploying."
            }
            $workspaceId = $workspaceObj.id

            # b. Resolve the Spark Environment (must already exist from provisioning).
            $environmentObj = _Resolve-FabricEnvironment -WorkspaceId $workspaceId -DisplayName $envName -Token $token
            if (-not $environmentObj) {
                throw "Environment '$envName' does not exist in workspace '$resolvedName'. Run provisioning before deploying."
            }
            $environmentId = $environmentObj.id

            # c. Idempotency — skip only when both the custom (private) set and the external (public)
            #    set already match the desired state exactly. Extra published custom files are stale
            #    versions that must be cleared down, so their presence forces a deploy.
            $publishedCustom   = Get-FabricEnvironmentLibraries -WorkspaceId $workspaceId -EnvironmentId $environmentId -Token $token
            $publishedExternal = Get-FabricEnvironmentLibraries -WorkspaceId $workspaceId -EnvironmentId $environmentId -Token $token -External

            $missingCustom = $desiredCustomNames    | Where-Object { $_ -notin $publishedCustom }
            $staleCustom   = $publishedCustom        | Where-Object { $_ -notin $desiredCustomNames }
            $missingExt    = $desiredExternalTokens  | Where-Object { $_ -notin $publishedExternal }
            $staleExt      = $publishedExternal      | Where-Object { $_ -notin $desiredExternalTokens }

            if (-not $Force -and -not $missingCustom -and -not $staleCustom -and -not $missingExt -and -not $staleExt) {
                Write-Verbose "'$resolvedName' already has exactly the desired custom and external libraries published. Skipping."
                $results.Deployed.Add(@{
                    WorkspaceName     = $resolvedName
                    EnvironmentName   = $envName
                    EnvironmentId     = $environmentId
                    Files             = $desiredCustomNames
                    ExternalLibraries = $desiredExternalTokens
                    Removed           = @()
                    Action            = 'Skipped'
                })
                $results.Summary.Skipped++
                continue
            }

            # d. Clear down staged custom libraries that are not part of the desired private set.
            #    Staging starts as a copy of the published libraries, so this is what retires
            #    previous versions (and any public wheels uploaded before the split) on publish. The
            #    external libraries need no clear-down — importExternalLibraries overrides them wholesale.
            $staged  = Get-FabricEnvironmentLibraries -WorkspaceId $workspaceId -EnvironmentId $environmentId -Token $token -Staging
            $toRemove = $staged | Where-Object { $_ -notin $desiredCustomNames }

            foreach ($libraryName in $toRemove) {
                Remove-FabricEnvironmentLibrary `
                    -WorkspaceId   $workspaceId `
                    -EnvironmentId $environmentId `
                    -LibraryName   $libraryName `
                    -Token         $token | Out-Null
            }

            # e. Import the public libraries (environment.yml), upload the private wheels, then publish.
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

            $results.Deployed.Add(@{
                WorkspaceName     = $resolvedName
                EnvironmentName   = $envName
                EnvironmentId     = $environmentId
                Files             = $desiredCustomNames
                ExternalLibraries = $desiredExternalTokens
                Removed           = @($toRemove)
                Action            = $publishResult.Action
            })
            if (-not $WhatIfPreference) {
                $results.Summary.Deployed++
            }
        }
        catch {
            Write-Error "FAILED: $resolvedName — $_" -ErrorAction Continue
            $results.Failures.Add(@{
                WorkspaceName = $resolvedName
                Stage         = $Stage
                Error         = $_.ToString()
            })
            $results.Summary.Failed++
        }
    }

    # --- 7. Report ---
    $s = $results.Summary
    Write-Verbose "=== Python library deploy complete — Deployed: $($s.Deployed)  Skipped: $($s.Skipped)  Failed: $($s.Failed) ==="

    if ($results.Failures.Count -gt 0) {
        Write-Warning "$($results.Failures.Count) workspace(s) failed. See `$result.Failures for details."
    }

    return $results
}
