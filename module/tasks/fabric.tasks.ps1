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
        SkipRbac      = $FabricSkipRbac
        WhatIf        = $FabricWhatIf
    }

    if (-not [string]::IsNullOrWhiteSpace($FabricEnvironment)) {
        $setupParams.Environment = $FabricEnvironment
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
        Environment     = $FabricEnvironment
        SkipGit         = $FabricSkipGit
        SkipIdentity    = $FabricSkipIdentity
        SkipEnvironment = $FabricSkipEnvironment
        SkipPipeline    = $FabricSkipPipeline
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

# Synopsis: Ensures that provisioned Fabric Workspace Identities are members of a group that can be used for granting Azure RBAC permissions.
task grantWorkspaceIdentitiesAzurePermissions `
        -If { !$FabricSkipEntra } `
        -After provisionFabricWorkspaces `
        -Jobs resolveFabricTopologyState,{

    # If the group gets created below, we need to ensure that the
    # deployment identity is set as a group owner, so it can manage
    # the membership going forward.
    $currentIdentity = _Get-FabricDeploymentIdentity

    # Establish which environments we need to process
    $availableFabricEnvs = $FabricProvisioningResult.Workspaces | Select-Object -Unique -ExpandProperty Environment
    $targetFabricEnvs = if ($FabricEnvironment) {
        $availableFabricEnvs | Where-Object { $_.name -in $FabricEnvironment }
    }
    else {
        $availableFabricEnvs
    }

    # RBAC is managed on a per-environment basis
    foreach ($fabricEnv in $targetFabricEnvs) {
        $azureEnv = $FabricAzureEnvironmentMapping[$fabricEnv]
        Write-Verbose "Fabric -> Azure environment mapping: $fabricEnv -> $azureEnv"

        $groupName = $FabricWorkspaceIdentitiesAzureAccessGroupName -f $azureEnv
        $splat = @{
            DisplayName = $groupName
            MailNickname = $groupName
            Description = "Used to grant Fabric Workspace Identities permissions to '$azureEnv' environment Azure resources"
            OwnersToAssignOnCreation = @(
                $currentIdentity.Id
            )
        }
        # Ensure the central group for managing RBAC permissions for Fabric Workspace IDs is setup
        Write-Build White "Ensuring Azure RBAC management group exists: $groupName"
        $group = Assert-AzureAdSecurityGroup @splat
        
        # Ensure all the Workspace IDs associated with the current environment are group members
        $workspaceIdentities = $FabricProvisioningResult.Workspaces |
                                    Where-Object { $_.Environment -eq $fabricEnv } |
                                    Select-Object -ExpandProperty Identity |
                                    Select-Object -ExpandProperty PrincipalId
        Write-Build White "Ensuring workspace identities are members: $($workspaceIdentities -join ',')"
        Assert-AzureAdGroupMembership -ObjectId $group.Id -RequiredMembers $workspaceIdentities | Out-Null
    }
}