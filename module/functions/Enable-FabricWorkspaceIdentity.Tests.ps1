#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Enable-FabricWorkspaceIdentity' {

    It 'returns WhatIf placeholder when -WhatIf is specified' {
        $result = Enable-FabricWorkspaceIdentity -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok' -WhatIf
        $result.WorkspaceName            | Should -Be 'my-ws'
        $result.WorkspaceId              | Should -Be 'ws-id'
        $result.ServicePrincipalObjectId | Should -Be 'whatif-sp-object-id'
        $result.ApplicationId            | Should -Be 'whatif-app-id'
    }

    It 'skips provisioning when identity already exists' {
        Mock _Invoke-FabricRestMethod {
            return [pscustomobject]@{ servicePrincipalId = 'sp-123'; applicationId = 'app-456' }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Enable-FabricWorkspaceIdentity -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok'
        $result.ServicePrincipalObjectId | Should -Be 'sp-123'
        $result.ApplicationId            | Should -Be 'app-456'

        Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'provisions identity and waits for LRO when no identity exists' {
        Mock _Invoke-FabricRestMethod { throw 'not found' } -ModuleName ZeroFailed.Deploy.Fabric

        Mock Add-FabricWorkspaceIdentity {
            return [pscustomobject]@{ OperationId = 'op-001'; Location = 'https://api/ops/op-001'; RetryAfter = 5 }
        } -ModuleName ZeroFailed.Deploy.Fabric

        Mock Get-FabricLongRunningOperation {
            return [pscustomobject]@{ status = 'Succeeded' }
        } -ModuleName ZeroFailed.Deploy.Fabric

        Mock Get-FabricLongRunningOperationResult {
            return [pscustomobject]@{ servicePrincipalId = 'sp-new'; applicationId = 'app-new' }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Enable-FabricWorkspaceIdentity -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok'
        $result.ServicePrincipalObjectId | Should -Be 'sp-new'
        $result.ApplicationId            | Should -Be 'app-new'

        Should -Invoke Add-FabricWorkspaceIdentity          -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Get-FabricLongRunningOperation        -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Get-FabricLongRunningOperationResult  -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'handles LRO result returned as an array' {
        Mock _Invoke-FabricRestMethod { throw 'not found' } -ModuleName ZeroFailed.Deploy.Fabric

        Mock Add-FabricWorkspaceIdentity {
            return [pscustomobject]@{ OperationId = 'op-002'; Location = ''; RetryAfter = 5 }
        } -ModuleName ZeroFailed.Deploy.Fabric

        Mock Get-FabricLongRunningOperation {
            return [pscustomobject]@{ status = 'Succeeded' }
        } -ModuleName ZeroFailed.Deploy.Fabric

        Mock Get-FabricLongRunningOperationResult {
            # Module returns List.ToArray() — simulate an array result
            return @([pscustomobject]@{ servicePrincipalId = 'sp-arr'; applicationId = 'app-arr' })
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Enable-FabricWorkspaceIdentity -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok'
        $result.ServicePrincipalObjectId | Should -Be 'sp-arr'
        $result.ApplicationId            | Should -Be 'app-arr'
    }

    It 'throws if LRO operation ends in a failed status' {
        Mock _Invoke-FabricRestMethod { throw 'not found' } -ModuleName ZeroFailed.Deploy.Fabric

        Mock Add-FabricWorkspaceIdentity {
            return [pscustomobject]@{ OperationId = 'op-003'; Location = ''; RetryAfter = 5 }
        } -ModuleName ZeroFailed.Deploy.Fabric

        Mock Get-FabricLongRunningOperation {
            return [pscustomobject]@{ status = 'Failed' }
        } -ModuleName ZeroFailed.Deploy.Fabric

        { Enable-FabricWorkspaceIdentity -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok' } |
            Should -Throw
    }
}
