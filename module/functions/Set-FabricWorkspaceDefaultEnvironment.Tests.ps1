#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Set-FabricWorkspaceDefaultEnvironment' {

    It 'PATCHes the spark settings with the environment block when not already set' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') { return [pscustomobject]@{ environment = [pscustomobject]@{ name = ''; runtimeVersion = '1.3' } } }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricWorkspaceDefaultEnvironment -WorkspaceId 'ws-1' -WorkspaceName 'ws [DEV]' `
            -EnvironmentName 'ws [DEV] Env' -Token 'tok'

        $result.Action | Should -Be 'Set'
        Should -Invoke _Invoke-FabricRestMethod -ParameterFilter {
            $Method -eq 'PATCH' -and
            $RelativeUri -eq 'workspaces/ws-1/spark/settings' -and
            $Body.environment.name -eq 'ws [DEV] Env' -and
            $Body.environment.runtimeVersion -eq '1.3'
        } -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'passes a custom runtime version through to the PATCH body' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') { return [pscustomobject]@{ environment = [pscustomobject]@{ name = '' } } }
        } -ModuleName ZeroFailed.Deploy.Fabric

        Set-FabricWorkspaceDefaultEnvironment -WorkspaceId 'ws-1' -WorkspaceName 'ws [DEV]' `
            -EnvironmentName 'ws [DEV] Env' -RuntimeVersion '1.2' -Token 'tok' | Out-Null

        Should -Invoke _Invoke-FabricRestMethod -ParameterFilter {
            $Method -eq 'PATCH' -and $Body.environment.runtimeVersion -eq '1.2'
        } -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'skips the PATCH when the default environment already matches' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') { return [pscustomobject]@{ environment = [pscustomobject]@{ name = 'ws [DEV] Env'; runtimeVersion = '1.3' } } }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricWorkspaceDefaultEnvironment -WorkspaceId 'ws-1' -WorkspaceName 'ws [DEV]' `
            -EnvironmentName 'ws [DEV] Env' -Token 'tok'

        $result.Action | Should -Be 'Skipped'
        Should -Invoke _Invoke-FabricRestMethod -ParameterFilter { $Method -eq 'PATCH' } -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'returns a whatif report and does not call the API under -WhatIf' {
        Mock _Invoke-FabricRestMethod {} -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricWorkspaceDefaultEnvironment -WorkspaceId 'ws-1' -WorkspaceName 'ws [DEV]' `
            -EnvironmentName 'ws [DEV] Env' -Token 'tok' -WhatIf

        $result.Action | Should -Be 'whatif'
        Should -Invoke _Invoke-FabricRestMethod -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }
}
