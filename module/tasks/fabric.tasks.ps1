. $PSScriptRoot/fabric.properties.ps1

# Registers Az.Accounts, Az.Resources, Az.Network and MicrosoftFabricMgmt with ZeroFailed.DevOps.Common's
# 'RequiredPowerShellModules' mechanism, so the 'setupModules' task installs/imports them — same
# pattern as ZeroFailed.Build.PowerShell's 'EnsurePlatyPSModule' task. Az.Resources provides
# Get-AzADServicePrincipal / Get-AzADUser, used to resolve the deploying identity's object id so
# it can be granted Admin on each workspace. Az.Network provides the private endpoint connection
# cmdlets used by ZeroFailed.Deploy.Azure when approving managed private endpoint connections.
task ensureFabricModules -Before setupModules {
    Write-Build Cyan 'Registering Fabric required modules...'

    foreach ($moduleName in @('Az.Accounts', 'Az.Resources', 'Az.Network', 'MicrosoftFabricMgmt')) {
        if (-not $RequiredPowerShellModules.ContainsKey($moduleName)) {
            $script:RequiredPowerShellModules += @{ $moduleName = @{} }
        }
    }
}

# Provisions Fabric workspaces after the core deploy tasks complete. Set $FabricEnvironment (e.g.
# per ADO pipeline stage) to provision a single environment; leave it unset to provision all of
# them in one run.
task provisionFabricWorkspaces -After DeployCore {
    $envMessage = if ([string]::IsNullOrWhiteSpace($FabricEnvironment)) { 'all environments' } else { "environment '$FabricEnvironment'" }
    Write-Build Cyan "Provisioning Fabric workspaces ($envMessage) from: $FabricTopologyConfigPath"

    if (-not (Test-Path $FabricTopologyConfigPath)) {
        throw "Fabric topology config not found: $FabricTopologyConfigPath"
    }

    $setupParams = @{
        ConfigPath    = $FabricTopologyConfigPath
        SkipGit       = $FabricSkipGit
        SkipIdentity  = $FabricSkipIdentity
        SkipMonitoring = $FabricSkipMonitoring
        SkipEnvironment = $FabricSkipEnvironment
        SkipVariableLibrary = $FabricSkipVariableLibrary
        SkipRbac      = $FabricSkipRbac
        SkipManagedPrivateEndpoints = $FabricSkipManagedPrivateEndpoints
        WhatIf        = $FabricWhatIf
    }

    if (-not [string]::IsNullOrWhiteSpace($FabricEnvironment)) {
        $setupParams.Environment = $FabricEnvironment
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

# Approves the private endpoint connections requested by the workspaces' managed private endpoints.
# Runs after provisioning, since an endpoint has to exist before its connection can be approved.
# Approving needs permission on each target Azure resource, which the identity provisioning the
# workspaces may not have — set $FabricSkipManagedPrivateEndpointApproval to leave the connections for
# someone else (or another pipeline stage) to approve.
task approveFabricManagedPrivateEndpoints -After provisionFabricWorkspaces {
    if ($FabricSkipManagedPrivateEndpoints -or $FabricSkipManagedPrivateEndpointApproval) {
        Write-Build Yellow 'Skipping Fabric managed private endpoint approval.'
        return
    }

    $envMessage = if ([string]::IsNullOrWhiteSpace($FabricEnvironment)) { 'all environments' } else { "environment '$FabricEnvironment'" }
    Write-Build Cyan "Approving Fabric managed private endpoint connections ($envMessage) from: $FabricTopologyConfigPath"

    $approvalParams = @{
        ConfigPath          = $FabricTopologyConfigPath
        TimeoutSeconds      = $FabricManagedPrivateEndpointApprovalTimeoutSeconds
        PollIntervalSeconds = $FabricManagedPrivateEndpointApprovalPollIntervalSeconds
        FailOnError         = $FabricFailOnManagedPrivateEndpointApprovalError
        WhatIf              = $FabricWhatIf
    }

    if (-not [string]::IsNullOrWhiteSpace($FabricEnvironment)) {
        $approvalParams.Environment = $FabricEnvironment
    }
    if (-not [string]::IsNullOrWhiteSpace($FabricManagedPrivateEndpointNamePattern)) {
        $approvalParams.EndpointNamePattern = $FabricManagedPrivateEndpointNamePattern
    }

    $result = Invoke-FabricManagedPrivateEndpointApproval @approvalParams

    $s = $result.Summary
    Write-Build Green "Managed private endpoint approval complete — Approved: $($s.Approved)  Skipped: $($s.Skipped)  Failed: $($s.Failed)"

    if ($result.Failures.Count -gt 0) {
        Write-Build Yellow "$($result.Failures.Count) managed private endpoint(s) were not approved:"
        $result.Failures | ForEach-Object {
            Write-Build Yellow "  $($_.WorkspaceName) [$($_.Environment)]: $($_.Error)"
        }
    }
}

# Creates or updates Fabric deployment pipelines (one per pipeline-enabled workspace type, spanning
# every environment) and applies their role assignments. Standalone (not chained after provisioning):
# pipelines need every environment's workspaces to exist, so invoke this from a dedicated stage that
# runs after each environment has been provisioned, under an identity with Admin on those workspaces.
task provisionFabricDeploymentPipelines {
    if ($FabricSkipPipeline) {
        Write-Build Yellow 'Skipping Fabric deployment pipeline setup (FabricSkipPipeline is set).'
        return
    }

    Write-Build Cyan "Configuring Fabric deployment pipelines from: $FabricTopologyConfigPath"

    if (-not (Test-Path $FabricTopologyConfigPath)) {
        throw "Fabric topology config not found: $FabricTopologyConfigPath"
    }

    $pipelineParams = @{
        ConfigPath       = $FabricTopologyConfigPath
        SkipPipelineRbac = $FabricSkipPipelineRbac
        WhatIf           = $FabricWhatIf
    }

    $result = Invoke-FabricDeploymentPipelineSetup @pipelineParams

    $s = $result.Summary
    Write-Build Green "Deployment pipeline setup complete — Created: $($s.Created)  Updated: $($s.Updated)  Skipped: $($s.Skipped)  Failed: $($s.Failed)"

    if ($result.Failures.Count -gt 0) {
        Write-Build Red "$($result.Failures.Count) deployment pipeline step(s) failed:"
        $result.Failures | ForEach-Object {
            Write-Build Red "  $($_.WorkspaceType) pipeline [$($_.Step)]: $($_.Error)"
        }
        throw "Fabric deployment pipeline setup completed with $($result.Failures.Count) failure(s)."
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
