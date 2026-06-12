#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Shared parameters used across most tests
    $script:baseParams = @{
        PipelineId    = 'pipe-001'
        PipelineName  = 'my-pipeline'
        Token         = 'tok'
        PrincipalId   = 'grp-aaa'
        PrincipalType = 'Group'
    }
}

Describe 'Set-FabricDeploymentPipelineRoleAssignment' {

    It 'returns WhatIf entry when -WhatIf is specified' {
        $result = Set-FabricDeploymentPipelineRoleAssignment @script:baseParams -WhatIf
        $result.Action        | Should -Be 'WhatIf'
        $result.Role          | Should -Be 'Admin'
        $result.PrincipalId   | Should -Be 'grp-aaa'
        $result.PrincipalType | Should -Be 'Group'
    }

    It 'defaults Role to Admin' {
        Mock _Invoke-FabricRestMethod {
            return [pscustomobject]@{ value = @() }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricDeploymentPipelineRoleAssignment @script:baseParams
        $result.Role | Should -Be 'Admin'
    }

    It 'rejects a Role other than Admin' {
        $params = $script:baseParams.Clone()
        $params.Role = 'Viewer'
        { Set-FabricDeploymentPipelineRoleAssignment @params } | Should -Throw
    }

    It 'skips assignment when principal already holds the role' {
        Mock _Invoke-FabricRestMethod {
            return [pscustomobject]@{
                value = @(
                    [pscustomobject]@{
                        role      = 'Admin'
                        principal = [pscustomobject]@{ id = 'grp-aaa'; type = 'Group' }
                    }
                )
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricDeploymentPipelineRoleAssignment @script:baseParams
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

        $result = Set-FabricDeploymentPipelineRoleAssignment @script:baseParams
        $result.Action | Should -Be 'Created'
        $result.Role   | Should -Be 'Admin'

        Should -Invoke _Invoke-FabricRestMethod -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'propagates error when GET role assignments fails' {
        Mock _Invoke-FabricRestMethod { throw 'API error' } -ModuleName ZeroFailed.Deploy.Fabric

        { Set-FabricDeploymentPipelineRoleAssignment @script:baseParams } | Should -Throw
    }

    It 'propagates error when POST fails' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
            if ($Method -eq 'POST') { throw 'POST failed' }
        } -ModuleName ZeroFailed.Deploy.Fabric

        { Set-FabricDeploymentPipelineRoleAssignment @script:baseParams } | Should -Throw
    }

    It 'returns correct report fields on successful creation' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricDeploymentPipelineRoleAssignment @script:baseParams
        $result.PipelineName  | Should -Be 'my-pipeline'
        $result.PipelineId    | Should -Be 'pipe-001'
        $result.PrincipalId   | Should -Be 'grp-aaa'
        $result.PrincipalType | Should -Be 'Group'
        $result.Role          | Should -Be 'Admin'
    }

    It 'accepts User as PrincipalType' {
        Mock _Invoke-FabricRestMethod {
            return [pscustomobject]@{ value = @() }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $params = $script:baseParams.Clone()
        $params.PrincipalType = 'User'
        { Set-FabricDeploymentPipelineRoleAssignment @params } | Should -Not -Throw
    }

    It 'accepts ServicePrincipal as PrincipalType' {
        Mock _Invoke-FabricRestMethod {
            return [pscustomobject]@{ value = @() }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $params = $script:baseParams.Clone()
        $params.PrincipalType = 'ServicePrincipal'
        { Set-FabricDeploymentPipelineRoleAssignment @params } | Should -Not -Throw
    }
}
