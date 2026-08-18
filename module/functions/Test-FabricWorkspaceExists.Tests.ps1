#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Test-FabricWorkspaceExists' {

    It 'returns the workspace object when a displayName matches' {
        Mock _Invoke-FabricRestMethod {
            [pscustomobject]@{
                value = @(
                    [pscustomobject]@{ id = 'abc-123'; displayName = 'my-workspace' }
                    [pscustomobject]@{ id = 'def-456'; displayName = 'other-workspace' }
                )
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Test-FabricWorkspaceExists -DisplayName 'my-workspace' -Token 'tok'
        $result.id | Should -Be 'abc-123'
    }

    It 'returns $null when no displayName matches' {
        Mock _Invoke-FabricRestMethod {
            [pscustomobject]@{ value = @([pscustomobject]@{ id = 'def-456'; displayName = 'other-workspace' }) }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Test-FabricWorkspaceExists -DisplayName 'nonexistent-workspace' -Token 'tok'
        $result | Should -BeNullOrEmpty
    }

    It 'matches displayName exactly (not as a substring)' {
        Mock _Invoke-FabricRestMethod {
            [pscustomobject]@{ value = @([pscustomobject]@{ id = 'x'; displayName = 'my-workspace [DEV]' }) }
        } -ModuleName ZeroFailed.Deploy.Fabric

        Test-FabricWorkspaceExists -DisplayName 'my-workspace' -Token 'tok' | Should -BeNullOrEmpty
    }

    It 'follows the continuation token to a later page' {
        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri)
            if ($RelativeUri -eq 'workspaces') {
                return [pscustomobject]@{
                    value             = @([pscustomobject]@{ id = 'p1'; displayName = 'page-one-ws' })
                    continuationToken = 'tok-2'
                }
            }
            # second page
            return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'p2'; displayName = 'target-ws' }) }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Test-FabricWorkspaceExists -DisplayName 'target-ws' -Token 'tok'
        $result.id | Should -Be 'p2'
        Should -Invoke _Invoke-FabricRestMethod -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'does not throw under StrictMode when the list response omits continuationToken' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            Set-StrictMode -Version Latest
            Mock _Invoke-FabricRestMethod {
                # Real API omits continuationToken on the last/only page
                [pscustomobject]@{ value = @([pscustomobject]@{ id = 'abc'; displayName = 'ws' }) }
            }
            $result = Test-FabricWorkspaceExists -DisplayName 'ws' -Token 'tok'
            $result.id | Should -Be 'abc'
        }
    }
}
