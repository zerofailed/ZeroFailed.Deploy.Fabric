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
