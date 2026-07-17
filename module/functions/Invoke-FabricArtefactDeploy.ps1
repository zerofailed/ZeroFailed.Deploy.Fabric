function Invoke-FabricArtefactDeploy {
    <#
    .SYNOPSIS
        Deploys a Python package (and its dependencies) into the Fabric Spark Environments of a stage.
    .DESCRIPTION
        The code-artefact counterpart to Invoke-FabricSetup, intended to run after provisioning as a
        separate pipeline. For a single deployment stage it:
          1. Downloads the named package plus its full dependency closure from an Azure Artifacts
             feed (once), via Save-FabricLibraryPackage.
          2. For every workspace in the topology that has a Spark Environment enabled, resolves the
             workspace and its environment for the given stage.
          3. Clears down any staged custom libraries that are not part of the downloaded set, so
             previous versions cannot conflict with the ones being deployed.
          4. Uploads the downloaded files to the environment's custom (staging) libraries and
             publishes, unless exactly those files are already published (idempotent) and -Force
             is not set.

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
        Invoke-FabricArtefactDeploy -ConfigPath ./topology.json -Stage DEV `
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
        $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
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

    # --- 3. Determine target workspaces (those with a Spark Environment provisioned) ---
    $targetWorkspaces = $Config.workspaces | Where-Object {
        $_.PSObject.Properties.Name -contains 'environment' -and $_.environment.enabled
    }
    if (-not $targetWorkspaces) {
        Write-Warning "No workspaces in the topology have a Spark Environment enabled; nothing to deploy."
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
        $StagingPath = Join-Path ([System.IO.Path]::GetTempPath()) "fabric-artefacts-$([guid]::NewGuid())"
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

    $desiredFileNames = @($files.Name)
    Write-Verbose "Deploying $($desiredFileNames.Count) file(s) to stage '$Stage'."

    # --- 6. Deploy to each target workspace's environment ---
    $results = [pscustomobject]@{
        Summary  = [pscustomobject]@{ Deployed = 0; Skipped = 0; Failed = 0 }
        Deployed = [System.Collections.Generic.List[hashtable]]::new()
        Failures = [System.Collections.Generic.List[hashtable]]::new()
    }

    $envTemplate = if ($Config.namingConvention.PSObject.Properties.Name -contains 'environmentNameTemplate') {
        $Config.namingConvention.environmentNameTemplate
    }
    else { '{workspace} Env' }

    foreach ($ws in $targetWorkspaces) {

        # Refresh the token if it is close to expiring (publishes can take several minutes each).
        if (_Test-FabricTokenExpiry -TokenInfo $tokenInfo) {
            Write-Verbose 'Token nearing expiry — refreshing...'
            $tokenInfo = _Get-FabricAuthToken
            $token     = $tokenInfo.Token
        }

        $resolvedName = _Resolve-WorkspaceName -Config $Config -WorkspaceId $ws.id -EnvironmentName $Stage
        $envName      = $envTemplate -replace '\{workspace\}', $resolvedName

        try {
            # a. Resolve the workspace (must already exist from provisioning).
            $workspaceObj = Test-FabricWorkspaceExists -DisplayName $resolvedName -Token $token
            if (-not $workspaceObj) {
                throw "Workspace '$resolvedName' does not exist. Run provisioning before deploying artefacts."
            }
            $workspaceId = $workspaceObj.id

            # b. Resolve the Spark Environment (must already exist from provisioning).
            $environmentObj = _Resolve-FabricEnvironment -WorkspaceId $workspaceId -DisplayName $envName -Token $token
            if (-not $environmentObj) {
                throw "Environment '$envName' does not exist in workspace '$resolvedName'. Run provisioning before deploying artefacts."
            }
            $environmentId = $environmentObj.id

            # c. Idempotency — skip only when the published set matches the desired set exactly.
            #    Extra published files are stale versions that must be cleared down, so their
            #    presence has to force a deploy even when nothing is missing.
            $published = Get-FabricEnvironmentLibraries -WorkspaceId $workspaceId -EnvironmentId $environmentId -Token $token
            $missing   = $desiredFileNames | Where-Object { $_ -notin $published }
            $stale     = $published | Where-Object { $_ -notin $desiredFileNames }

            if (-not $Force -and -not $missing -and -not $stale) {
                Write-Verbose "'$resolvedName' already has exactly the $($desiredFileNames.Count) desired file(s) published. Skipping."
                $results.Deployed.Add(@{
                    WorkspaceName   = $resolvedName
                    EnvironmentName = $envName
                    EnvironmentId   = $environmentId
                    Files           = $desiredFileNames
                    Removed         = @()
                    Action          = 'Skipped'
                })
                $results.Summary.Skipped++
                continue
            }

            # d. Clear down staged libraries that are not part of the desired set. Staging starts
            #    as a copy of the published libraries, so this is what retires previous versions
            #    on publish. Desired names are left alone — the upload below overwrites them.
            $staged  = Get-FabricEnvironmentLibraries -WorkspaceId $workspaceId -EnvironmentId $environmentId -Token $token -Staging
            $toRemove = $staged | Where-Object { $_ -notin $desiredFileNames }

            foreach ($libraryName in $toRemove) {
                Remove-FabricEnvironmentLibrary `
                    -WorkspaceId   $workspaceId `
                    -EnvironmentId $environmentId `
                    -LibraryName   $libraryName `
                    -Token         $token | Out-Null
            }

            # e. Upload each file to staging, then publish.
            foreach ($file in $files) {
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
                WorkspaceName   = $resolvedName
                EnvironmentName = $envName
                EnvironmentId   = $environmentId
                Files           = $desiredFileNames
                Removed         = @($toRemove)
                Action          = $publishResult.Action
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
    Write-Verbose "=== Artefact deploy complete — Deployed: $($s.Deployed)  Skipped: $($s.Skipped)  Failed: $($s.Failed) ==="

    if ($results.Failures.Count -gt 0) {
        Write-Warning "$($results.Failures.Count) workspace(s) failed. See `$result.Failures for details."
    }

    return $results
}
