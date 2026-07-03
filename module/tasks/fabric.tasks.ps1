. $PSScriptRoot/fabric.properties.ps1

# Registers Az.Accounts, Az.Resources and MicrosoftFabricMgmt as required modules before the
# main setupModules task runs.
task ensureFabricModules -Before setupModules {
    Write-Build Cyan 'Registering Fabric required modules...'

    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        Write-Build Yellow 'Az.Accounts not found — installing...'
        Install-Module Az.Accounts -Scope CurrentUser -Force -ErrorAction Stop
    }

    # Az.Resources provides Get-AzADServicePrincipal / Get-AzADUser, used to resolve the
    # deploying identity's object id so it can be granted Admin on each workspace.
    if (-not (Get-Module -ListAvailable -Name Az.Resources)) {
        Write-Build Yellow 'Az.Resources not found — installing...'
        Install-Module Az.Resources -Scope CurrentUser -Force -ErrorAction Stop
    }

    if (-not (Get-Module -ListAvailable -Name MicrosoftFabricMgmt)) {
        Write-Build Yellow 'MicrosoftFabricMgmt not found — installing...'
        Install-Module MicrosoftFabricMgmt -Scope CurrentUser -Force -ErrorAction Stop
    }

    Write-Build Green 'Fabric required modules are available.'
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
