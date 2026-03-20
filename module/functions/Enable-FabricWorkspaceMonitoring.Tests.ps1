#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Enable-FabricWorkspaceMonitoring' {

    It 'returns WhatIf placeholder when -WhatIf is specified' {
        $result = Enable-FabricWorkspaceMonitoring -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok' -WhatIf
        $result.WorkspaceName | Should -Be 'my-ws'
        $result.WorkspaceId   | Should -Be 'ws-id'
        $result.Enabled       | Should -Be 'whatif'
    }

    It 'returns Enabled = true when Monitoring Eventhouse exists' {
        Mock _Invoke-FabricRestMethod {
            return [pscustomobject]@{
                value = @(
                    [pscustomobject]@{ type = 'Eventhouse'; displayName = 'Monitoring Eventhouse' }
                )
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Enable-FabricWorkspaceMonitoring -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok'
        $result.Enabled | Should -Be $true
        Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'matches Monitoring Eventhouse case-insensitively' {
        Mock _Invoke-FabricRestMethod {
            return [pscustomobject]@{
                value = @(
                    [pscustomobject]@{ type = 'Eventhouse'; displayName = 'monitoring eventhouse' }
                )
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        { Enable-FabricWorkspaceMonitoring -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok' } |
            Should -Not -Throw
    }

    It 'throws when no Monitoring Eventhouse is found in items' {
        Mock _Invoke-FabricRestMethod {
            return [pscustomobject]@{
                value = @(
                    [pscustomobject]@{ type = 'Notebook';   displayName = 'My Notebook' }
                    [pscustomobject]@{ type = 'Eventhouse'; displayName = 'Analytics Store' }
                )
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        { Enable-FabricWorkspaceMonitoring -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok' } |
            Should -Throw -ExpectedMessage '*Workspace Settings*'
    }

    It 'throws when workspace has no items at all' {
        Mock _Invoke-FabricRestMethod {
            return [pscustomobject]@{ value = @() }
        } -ModuleName ZeroFailed.Deploy.Fabric

        { Enable-FabricWorkspaceMonitoring -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok' } |
            Should -Throw
    }

    It 'propagates error when items API call fails' {
        Mock _Invoke-FabricRestMethod { throw 'API unavailable' } -ModuleName ZeroFailed.Deploy.Fabric

        { Enable-FabricWorkspaceMonitoring -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -Token 'tok' } |
            Should -Throw
    }
}
