#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'New-FabricWorkspace' {

    It 'returns existing workspace without creating when it already exists' {
        $existing = [pscustomobject]@{ id = 'existing-id'; displayName = 'my-workspace' }
        Mock Test-FabricWorkspaceExists { return $existing } -ModuleName ZeroFailed.Deploy.Fabric
        Mock _Invoke-FabricRestMethod {} -ModuleName ZeroFailed.Deploy.Fabric

        $result = New-FabricWorkspace -DisplayName 'my-workspace' -CapacityName 'cap-dev' -Token 'tok'
        $result.id | Should -Be 'existing-id'
        Should -Invoke _Invoke-FabricRestMethod -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'returns WhatIf placeholder when -WhatIf is specified and workspace does not exist' {
        Mock Test-FabricWorkspaceExists { return $null } -ModuleName ZeroFailed.Deploy.Fabric

        $result = New-FabricWorkspace -DisplayName 'new-workspace' -CapacityName 'cap-dev' -Token 'tok' -WhatIf
        $result.id | Should -Be 'whatif-id'
        $result.displayName | Should -Be 'new-workspace'
    }

    It 'creates the workspace via POST when it does not exist' {
        Mock Test-FabricWorkspaceExists { return $null } -ModuleName ZeroFailed.Deploy.Fabric
        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri)
            if ($Method -eq 'GET' -and $RelativeUri -eq 'capacities') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'cap-1'; displayName = 'cap-dev' }) }
            }
            if ($Method -eq 'POST' -and $RelativeUri -eq 'workspaces') {
                return [pscustomobject]@{ id = 'ws-new'; displayName = 'new-workspace'; capacityId = 'cap-1' }
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = New-FabricWorkspace -DisplayName 'new-workspace' -CapacityName 'cap-dev' -Token 'tok'
        $result.id | Should -Be 'ws-new'
        # GET capacities + POST workspaces
        Should -Invoke _Invoke-FabricRestMethod -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'throws when the named capacity cannot be found' {
        Mock Test-FabricWorkspaceExists { return $null } -ModuleName ZeroFailed.Deploy.Fabric
        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri)
            if ($Method -eq 'GET' -and $RelativeUri -eq 'capacities') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'other'; displayName = 'cap-other' }) }
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        { New-FabricWorkspace -DisplayName 'new-workspace' -CapacityName 'cap-dev' -Token 'tok' } |
            Should -Throw "*Capacity 'cap-dev' not found*"
    }

    Context 'idempotency on 409 conflict' {

        BeforeEach {
            # Module-scoped counter shared with the -ModuleName mock body.
            InModuleScope ZeroFailed.Deploy.Fabric { $script:nfwLookups = 0 }
        }

        It 'resolves and returns the existing workspace when creation reports a conflict' {
            Mock Test-FabricWorkspaceExists {
                $script:nfwLookups++
                if ($script:nfwLookups -eq 1) { $null } else { [pscustomobject]@{ id = 'ws-existing'; displayName = 'dup' } }
            } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Invoke-FabricRestMethod {
                param($Method, $RelativeUri)
                if ($Method -eq 'GET' -and $RelativeUri -eq 'capacities') {
                    return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'cap-1'; displayName = 'cap-dev' }) }
                }
                if ($Method -eq 'POST') {
                    throw 'Fabric API error 409 on POST https://api.fabric.microsoft.com/v1/workspaces : WorkspaceNameAlreadyExists'
                }
            } -ModuleName ZeroFailed.Deploy.Fabric

            $result = New-FabricWorkspace -DisplayName 'dup' -CapacityName 'cap-dev' -Token 'tok'
            $result.id | Should -Be 'ws-existing'
        }

        It 'throws a clear visibility error when a conflicting workspace cannot be resolved' {
            Mock Test-FabricWorkspaceExists { $null } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Invoke-FabricRestMethod {
                param($Method, $RelativeUri)
                if ($Method -eq 'GET' -and $RelativeUri -eq 'capacities') {
                    return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'cap-1'; displayName = 'cap-dev' }) }
                }
                if ($Method -eq 'POST') {
                    throw 'Fabric API error 409 on POST https://api.fabric.microsoft.com/v1/workspaces : WorkspaceNameAlreadyExists'
                }
            } -ModuleName ZeroFailed.Deploy.Fabric

            { New-FabricWorkspace -DisplayName 'dup' -CapacityName 'cap-dev' -Token 'tok' } |
                Should -Throw '*not visible to the deploying identity*'
        }
    }

    It 'rethrows non-conflict creation errors' {
        Mock Test-FabricWorkspaceExists { $null } -ModuleName ZeroFailed.Deploy.Fabric
        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri)
            if ($Method -eq 'GET' -and $RelativeUri -eq 'capacities') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'cap-1'; displayName = 'cap-dev' }) }
            }
            if ($Method -eq 'POST') { throw 'Fabric API error 500 on POST https://api.fabric.microsoft.com/v1/workspaces : InternalError' }
        } -ModuleName ZeroFailed.Deploy.Fabric

        { New-FabricWorkspace -DisplayName 'doomed' -CapacityName 'cap-dev' -Token 'tok' } |
            Should -Throw '*Failed to create workspace*'
    }
}
