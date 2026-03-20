#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Shared parameters used across most tests
    $script:baseParams = @{
        WorkspaceId   = 'ws-001'
        WorkspaceName = 'my-ws'
        Token         = 'tok'
        PrincipalId   = 'grp-aaa'
        PrincipalType = 'Group'
        Role          = 'Viewer'
    }
}

Describe 'Set-FabricWorkspaceRoleAssignment' {

    It 'returns WhatIf entry when -WhatIf is specified' {
        $result = Set-FabricWorkspaceRoleAssignment @script:baseParams -WhatIf
        $result.Action        | Should -Be 'WhatIf'
        $result.Role          | Should -Be 'Viewer'
        $result.PrincipalId   | Should -Be 'grp-aaa'
        $result.PrincipalType | Should -Be 'Group'
    }

    It 'skips assignment when principal already holds the correct role' {
        Mock _Invoke-FabricRestMethod {
            return [pscustomobject]@{
                value = @(
                    [pscustomobject]@{
                        id        = 'ra-001'
                        role      = 'Viewer'
                        principal = [pscustomobject]@{ id = 'grp-aaa'; type = 'Group' }
                    }
                )
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricWorkspaceRoleAssignment @script:baseParams
        $result.Action | Should -Be 'Skipped'
        Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'creates assignment via POST when principal has no existing assignment' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') {
                return [pscustomobject]@{ value = @() }
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricWorkspaceRoleAssignment @script:baseParams
        $result.Action | Should -Be 'Created'
        $result.Role   | Should -Be 'Viewer'

        Should -Invoke _Invoke-FabricRestMethod -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'updates assignment via PATCH when principal has a different role' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') {
                return [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{
                            id        = 'ra-002'
                            role      = 'Member'
                            principal = [pscustomobject]@{ id = 'grp-aaa'; type = 'Group' }
                        }
                    )
                }
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricWorkspaceRoleAssignment @script:baseParams
        $result.Action | Should -Be 'Updated'
        $result.Role   | Should -Be 'Viewer'

        Should -Invoke _Invoke-FabricRestMethod -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'propagates error when GET role assignments fails' {
        Mock _Invoke-FabricRestMethod { throw 'API error' } -ModuleName ZeroFailed.Deploy.Fabric

        { Set-FabricWorkspaceRoleAssignment @script:baseParams } | Should -Throw
    }

    It 'propagates error when POST fails' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
            if ($Method -eq 'POST') { throw 'POST failed' }
        } -ModuleName ZeroFailed.Deploy.Fabric

        { Set-FabricWorkspaceRoleAssignment @script:baseParams } | Should -Throw
    }

    It 'returns correct report fields on successful creation' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricWorkspaceRoleAssignment @script:baseParams
        $result.WorkspaceName | Should -Be 'my-ws'
        $result.WorkspaceId   | Should -Be 'ws-001'
        $result.PrincipalId   | Should -Be 'grp-aaa'
        $result.PrincipalType | Should -Be 'Group'
        $result.Role          | Should -Be 'Viewer'
    }

    It 'accepts User as PrincipalType' {
        Mock _Invoke-FabricRestMethod {
            return [pscustomobject]@{ value = @() }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $params = $script:baseParams.Clone()
        $params.PrincipalType = 'User'
        { Set-FabricWorkspaceRoleAssignment @params } | Should -Not -Throw
    }

    It 'accepts ServicePrincipal as PrincipalType' {
        Mock _Invoke-FabricRestMethod {
            return [pscustomobject]@{ value = @() }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $params = $script:baseParams.Clone()
        $params.PrincipalType = 'ServicePrincipal'
        { Set-FabricWorkspaceRoleAssignment @params } | Should -Not -Throw
    }
}
