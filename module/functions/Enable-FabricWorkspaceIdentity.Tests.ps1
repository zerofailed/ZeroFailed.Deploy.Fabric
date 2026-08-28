#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # MicrosoftFabricMgmt is a runtime-only dependency that is not installed in CI. Define
    # stubs in the module's scope so its cmdlets can be mocked below without the real module.
    InModuleScope ZeroFailed.Deploy.Fabric {
        foreach ($cmd in 'Add-FabricWorkspaceIdentity', 'Get-FabricLongRunningOperation', 'Get-FabricLongRunningOperationResult') {
            if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
                Set-Item -Path "function:script:$cmd" -Value { }
            }
        }
    }
}

Describe 'Enable-FabricWorkspaceIdentity' {

    It 'returns WhatIf placeholder when -WhatIf is specified' {
        $result = Enable-FabricWorkspaceIdentity -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok' -WhatIf
        $result.WorkspaceName            | Should -Be 'my-ws'
        $result.WorkspaceId              | Should -Be 'ws-id'
        $result.ServicePrincipalObjectId | Should -Be 'whatif-sp-object-id'
        $result.ApplicationId            | Should -Be 'whatif-app-id'
    }

    It 'provisions identity and waits for LRO when provisionIdentity returns 202' {
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

        Should -Invoke Add-FabricWorkspaceIdentity         -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Get-FabricLongRunningOperation       -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Get-FabricLongRunningOperationResult -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'handles LRO result returned as an array' {
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

    It 'reads the existing identity from the workspace when provisionIdentity returns $null' {
        # Add-FabricWorkspaceIdentity swallows 409/200-no-op and returns $null. The function
        # should treat this as "already provisioned" and recover the SP details from the workspace.
        Mock Add-FabricWorkspaceIdentity { return $null } -ModuleName ZeroFailed.Deploy.Fabric
        Mock _Invoke-FabricRestMethod {
            return [pscustomobject]@{
                id                = 'ws-id'
                workspaceIdentity = [pscustomobject]@{ servicePrincipalId = 'sp-existing'; applicationId = 'app-existing' }
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Enable-FabricWorkspaceIdentity -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok'
        $result.ServicePrincipalObjectId | Should -Be 'sp-existing'
        $result.ApplicationId            | Should -Be 'app-existing'

        Should -Invoke Add-FabricWorkspaceIdentity -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric `
            -ParameterFilter { $Method -eq 'GET' -and $RelativeUri -eq 'workspaces/ws-id' }
    }

    It 'reads the existing identity from the workspace when provisionIdentity returns an empty array' {
        Mock Add-FabricWorkspaceIdentity { return @() } -ModuleName ZeroFailed.Deploy.Fabric
        Mock _Invoke-FabricRestMethod {
            return [pscustomobject]@{
                id                = 'ws-id'
                workspaceIdentity = [pscustomobject]@{ servicePrincipalId = 'sp-existing'; applicationId = 'app-existing' }
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Enable-FabricWorkspaceIdentity -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok'
        $result.ServicePrincipalObjectId | Should -Be 'sp-existing'
    }

    It 'returns $null when the workspace has no identity to read back' {
        Mock Add-FabricWorkspaceIdentity { return $null } -ModuleName ZeroFailed.Deploy.Fabric
        # No workspaceIdentity property — the workspace genuinely has no identity.
        Mock _Invoke-FabricRestMethod { return [pscustomobject]@{ id = 'ws-id' } } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Enable-FabricWorkspaceIdentity -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok'
        $result | Should -BeNullOrEmpty
    }

    It 'uses identity details from 200 response when provisionIdentity returns existing identity inline' {
        # provisionIdentity can return 200 with identity data when identity already exists.
        # Invoke-FabricAPIRequest wraps this in an array via ToArray().
        Mock Add-FabricWorkspaceIdentity {
            return @([pscustomobject]@{ servicePrincipalId = 'sp-existing'; applicationId = 'app-existing' })
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Enable-FabricWorkspaceIdentity -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok'
        $result.ServicePrincipalObjectId | Should -Be 'sp-existing'
        $result.ApplicationId            | Should -Be 'app-existing'

    }

    It 'throws if LRO operation ends in a failed status' {
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
