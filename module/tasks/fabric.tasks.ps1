. $PSScriptRoot/fabric.properties.ps1

# Registers Az.Accounts, Az.Resources and MicrosoftFabricMgmt with ZeroFailed.DevOps.Common's
# 'RequiredPowerShellModules' mechanism, so the 'setupModules' task installs/imports them — same
# pattern as ZeroFailed.Build.PowerShell's 'EnsurePlatyPSModule' task. Az.Resources provides
# Get-AzADServicePrincipal / Get-AzADUser, used to resolve the deploying identity's object id so
# it can be granted Admin on each workspace.
task ensureFabricModules -Before setupModules {
    Write-Build Cyan 'Registering Fabric required modules...'

    foreach ($moduleName in @('Az.Accounts', 'Az.Resources', 'MicrosoftFabricMgmt')) {
        if (-not $RequiredPowerShellModules.ContainsKey($moduleName)) {
            $script:RequiredPowerShellModules += @{ $moduleName = @{} }
        }
    }
}

# Provisions Fabric workspaces after the core deploy tasks complete.
task provisionFabricWorkspaces -After DeployCore {
    Write-Build Cyan "Provisioning Fabric workspaces from: $FabricTopologyConfigPath"

    if (-not (Test-Path $FabricTopologyConfigPath)) {
        throw "Fabric topology config not found: $FabricTopologyConfigPath"
    }

    $setupParams = @{
        ConfigPath    = $FabricTopologyConfigPath
        SkipGit       = $FabricSkipGit
        SkipIdentity  = $FabricSkipIdentity
        SkipMonitoring = $FabricSkipMonitoring
        SkipEnvironment = $FabricSkipEnvironment
        SkipRbac      = $FabricSkipRbac
        SkipPipeline  = $FabricSkipPipeline
        SkipPipelineRbac = $FabricSkipPipelineRbac
        WhatIf        = $FabricWhatIf
    }

    if ($FabricEnvironmentFilter -and $FabricEnvironmentFilter.Count -gt 0) {
        $setupParams.Environments = $FabricEnvironmentFilter
    }

    $result = Invoke-FabricSetup @setupParams

    $s = $result.Summary
    Write-Build Green "Provisioning complete — Created: $($s.Created)  Skipped: $($s.Skipped)  Failed: $($s.Failed)"

    if ($result.Failures.Count -gt 0) {
        Write-Build Red "$($result.Failures.Count) workspace(s) failed:"
        $result.Failures | ForEach-Object {
            Write-Build Red "  $($_.WorkspaceName) [$($_.Environment)]: $($_.Error)"
        }
        throw "Fabric provisioning completed with $($result.Failures.Count) failure(s)."
    }
}

# Ensures Python/pip is available before the artefact deployment task runs (used to download the
# package and its dependencies from the Azure Artifacts feed).
task ensureFabricArtefactTooling -Before deployFabricArtefacts {
    Write-Build Cyan 'Checking Python/pip availability for artefact deployment...'

    $python = Get-Command $FabricPythonExecutable -ErrorAction SilentlyContinue
    if (-not $python) {
        throw "Python executable '$FabricPythonExecutable' not found. Install Python (with pip) on the build agent, or set `$FabricPythonExecutable."
    }

    & $FabricPythonExecutable -m pip --version | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "pip is not available for '$FabricPythonExecutable'. Ensure pip is installed."
    }

    Write-Build Green "Python/pip available: $($python.Source)"
}

# Deploys a code artefact (Python .whl + dependencies from Azure Artifacts) into the Spark
# Environments of a single stage. Standalone (not chained after provisioning) — intended to be
# invoked by a separate deployment pipeline, once per stage.
task deployFabricArtefacts {
    if ($FabricSkipArtefactDeploy) {
        Write-Build Yellow 'Skipping Fabric artefact deployment (FabricSkipArtefactDeploy is set).'
        return
    }

    foreach ($required in @(
        @{ Name = 'FabricArtefactStage'; Value = $FabricArtefactStage }
        @{ Name = 'FabricPackageName';   Value = $FabricPackageName }
        @{ Name = 'FabricPackageVersion'; Value = $FabricPackageVersion }
        @{ Name = 'FabricFeedOrganisation'; Value = $FabricFeedOrganisation }
        @{ Name = 'FabricFeedProject';   Value = $FabricFeedProject }
        @{ Name = 'FabricFeedName';      Value = $FabricFeedName }
        @{ Name = 'FabricFeedToken';     Value = $FabricFeedToken }
    )) {
        if ([string]::IsNullOrWhiteSpace($required.Value)) {
            throw "Required property '$($required.Name)' is not set for artefact deployment."
        }
    }

    if (-not (Test-Path $FabricArtefactConfigPath)) {
        throw "Fabric topology config not found: $FabricArtefactConfigPath"
    }

    Write-Build Cyan "Deploying '$FabricPackageName==$FabricPackageVersion' into stage '$FabricArtefactStage' from: $FabricArtefactConfigPath"

    $deployParams = @{
        ConfigPath          = $FabricArtefactConfigPath
        Stage               = $FabricArtefactStage
        PackageName         = $FabricPackageName
        PackageVersion      = $FabricPackageVersion
        FeedOrganisation    = $FabricFeedOrganisation
        FeedProject         = $FabricFeedProject
        FeedName            = $FabricFeedName
        FeedToken           = $FabricFeedToken
        Force               = $FabricArtefactForce
        PythonExecutable    = $FabricPythonExecutable
        TargetPythonVersion = $FabricTargetPythonVersion
        TargetPlatform      = $FabricTargetPlatform
        WhatIf              = $FabricWhatIf
    }

    if ($FabricArtefactStagingPath) {
        $deployParams.StagingPath = $FabricArtefactStagingPath
    }

    if ($FabricConstraintsPath) {
        if (-not (Test-Path $FabricConstraintsPath)) {
            throw "Fabric pip constraints file not found: $FabricConstraintsPath"
        }
        Write-Build Cyan "Applying pip constraints from: $FabricConstraintsPath"
        $deployParams.ConstraintsPath = $FabricConstraintsPath
    }

    $result = Invoke-FabricArtefactDeploy @deployParams

    $s = $result.Summary
    Write-Build Green "Artefact deploy complete — Deployed: $($s.Deployed)  Skipped: $($s.Skipped)  Failed: $($s.Failed)"

    if ($result.Failures.Count -gt 0) {
        Write-Build Red "$($result.Failures.Count) workspace(s) failed:"
        $result.Failures | ForEach-Object {
            Write-Build Red "  $($_.WorkspaceName) [$($_.Stage)]: $($_.Error)"
        }
        throw "Fabric artefact deployment completed with $($result.Failures.Count) failure(s)."
    }
}
