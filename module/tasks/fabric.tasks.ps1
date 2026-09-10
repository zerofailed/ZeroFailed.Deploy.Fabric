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

    # Publish the results for subsequently-running tasks BEFORE the failure throw below, so partial
    # results (workspace IDs, identity principal IDs, etc.) are still available after a failed run.
    $script:FabricProvisioningResult = $result

    if ($FabricProvisioningResultPath) {
        $resultDir = Split-Path -Parent $FabricProvisioningResultPath
        if ($resultDir -and -not (Test-Path $resultDir)) {
            New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
        }
        $result | ConvertTo-Json -Depth 10 | Set-Content -Path $FabricProvisioningResultPath -Encoding utf8
        Write-Build Green "Fabric provisioning result written to: $FabricProvisioningResultPath"
    }

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

# Ensures Python/pip is available before the Python library deployment task runs (used to download
# the package and its dependencies from the Azure Artifacts feed).
task ensureFabricPythonLibraryTooling -Before deployFabricPythonLibraries {
    Write-Build Cyan 'Checking Python/pip availability for Python library deployment...'

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

# Deploys a Python library (a .whl + its dependencies from Azure Artifacts) into the Spark
# Environments of a single stage. Standalone (not chained after provisioning) — intended to be
# invoked by a separate deployment pipeline, once per stage.
task deployFabricPythonLibraries {
    if ($FabricSkipPythonLibraryDeploy) {
        Write-Build Yellow 'Skipping Fabric Python library deployment (FabricSkipPythonLibraryDeploy is set).'
        return
    }

    foreach ($required in @(
        @{ Name = 'FabricPythonLibraryStage'; Value = $FabricPythonLibraryStage }
        @{ Name = 'FabricPackageName';   Value = $FabricPackageName }
        @{ Name = 'FabricPackageVersion'; Value = $FabricPackageVersion }
        @{ Name = 'FabricFeedOrganisation'; Value = $FabricFeedOrganisation }
        @{ Name = 'FabricFeedProject';   Value = $FabricFeedProject }
        @{ Name = 'FabricFeedName';      Value = $FabricFeedName }
        @{ Name = 'FabricFeedToken';     Value = $FabricFeedToken }
    )) {
        if ([string]::IsNullOrWhiteSpace($required.Value)) {
            throw "Required property '$($required.Name)' is not set for Python library deployment."
        }
    }

    if (-not (Test-Path $FabricPythonLibraryConfigPath)) {
        throw "Fabric topology config not found: $FabricPythonLibraryConfigPath"
    }

    Write-Build Cyan "Deploying '$FabricPackageName==$FabricPackageVersion' into stage '$FabricPythonLibraryStage' from: $FabricPythonLibraryConfigPath"

    $deployParams = @{
        ConfigPath          = $FabricPythonLibraryConfigPath
        Stage               = $FabricPythonLibraryStage
        PackageName         = $FabricPackageName
        PackageVersion      = $FabricPackageVersion
        FeedOrganisation    = $FabricFeedOrganisation
        FeedProject         = $FabricFeedProject
        FeedName            = $FabricFeedName
        FeedToken           = $FabricFeedToken
        Force               = $FabricPythonLibraryForce
        PythonExecutable    = $FabricPythonExecutable
        TargetPythonVersion = $FabricTargetPythonVersion
        TargetPlatform      = $FabricTargetPlatform
        WhatIf              = $FabricWhatIf
    }

    if ($FabricPythonLibraryStagingPath) {
        $deployParams.StagingPath = $FabricPythonLibraryStagingPath
    }

    if ($FabricConstraintsPath) {
        if (-not (Test-Path $FabricConstraintsPath)) {
            throw "Fabric pip constraints file not found: $FabricConstraintsPath"
        }
        Write-Build Cyan "Applying pip constraints from: $FabricConstraintsPath"
        $deployParams.ConstraintsPath = $FabricConstraintsPath
    }

    $result = Invoke-FabricPythonLibraryDeploy @deployParams

    $s = $result.Summary
    Write-Build Green "Python library deploy complete — Deployed: $($s.Deployed)  Skipped: $($s.Skipped)  Failed: $($s.Failed)"

    if ($result.Failures.Count -gt 0) {
        Write-Build Red "$($result.Failures.Count) workspace(s) failed:"
        $result.Failures | ForEach-Object {
            Write-Build Red "  $($_.WorkspaceName) [$($_.Stage)]: $($_.Error)"
        }
        throw "Fabric Python library deployment completed with $($result.Failures.Count) failure(s)."
    }
}

# Resolves the current Fabric topology state via read-only lookups (no provisioning, no changes) and
# publishes it as $script:FabricProvisioningResult — the same handoff variable that
# 'provisionFabricWorkspaces' populates. Lets a deploy-only pipeline consume workspace / identity /
# environment / pipeline IDs without running provisioning. Standalone: not chained via -Before/-After;
# invoke it by name from the deploy-only pipeline.
# The condition allows other tasks to include it as a dependency, but skipping it if the
# 'provisionFabricWorkspaces' task has already run.
task resolveFabricTopologyState -If { $FabricProvisioningResult -eq $null } {
    Write-Build Cyan "Resolving Fabric topology state from: $FabricTopologyConfigPath"

    if (-not (Test-Path $FabricTopologyConfigPath)) {
        throw "Fabric topology config not found: $FabricTopologyConfigPath"
    }

    $stateParams = @{
        ConfigPath      = $FabricTopologyConfigPath
        SkipGit         = $FabricSkipGit
        SkipIdentity    = $FabricSkipIdentity
        SkipEnvironment = $FabricSkipEnvironment
        SkipPipeline    = $FabricSkipPipeline
    }

    if ($FabricEnvironmentFilter -and $FabricEnvironmentFilter.Count -gt 0) {
        $stateParams.Environments = $FabricEnvironmentFilter
    }

    $result = Get-FabricTopologyState @stateParams

    # Same handoff variable + JSON artifact as provisionFabricWorkspaces, so downstream tasks are
    # agnostic about whether provisioning or discovery populated it.
    $script:FabricProvisioningResult = $result

    if ($FabricProvisioningResultPath) {
        $resultDir = Split-Path -Parent $FabricProvisioningResultPath
        if ($resultDir -and -not (Test-Path $resultDir)) {
            New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
        }
        $result | ConvertTo-Json -Depth 10 | Set-Content -Path $FabricProvisioningResultPath -Encoding utf8
        Write-Build Green "Fabric topology state written to: $FabricProvisioningResultPath"
    }

    $s = $result.Summary
    Write-Build Green "Topology state resolved — Found: $($s.Found)  Missing: $($s.Missing)  Failed: $($s.Failed)"

    # A read-only scan tolerates partial lookup failures — record them and still publish the result.
    if ($result.Failures.Count -gt 0) {
        Write-Build Yellow "$($result.Failures.Count) lookup(s) failed:"
        $result.Failures | ForEach-Object {
            Write-Build Yellow "  $($_.WorkspaceName) [$($_.Environment)]: $($_.Error)"
        }
    }
}
