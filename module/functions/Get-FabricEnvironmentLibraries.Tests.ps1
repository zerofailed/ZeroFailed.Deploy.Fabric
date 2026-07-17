#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Get-FabricEnvironmentLibraries' {

    It 'flattens all custom library file collections into a single name list' {
        Mock _Invoke-FabricRestMethod {
            [pscustomobject]@{
                customLibraries = [pscustomobject]@{
                    wheelFiles = @('a-1.0-py3-none-any.whl', 'b-2.0-py3-none-any.whl')
                    pyFiles    = @('helper.py')
                }
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Get-FabricEnvironmentLibraries -WorkspaceId 'ws-1' -EnvironmentId 'env-1' -Token 'tok'
        $result | Should -HaveCount 3
        $result | Should -Contain 'a-1.0-py3-none-any.whl'
        $result | Should -Contain 'helper.py'
    }

    It 'queries the published endpoint by default and the staging endpoint with -Staging' {
        Mock _Invoke-FabricRestMethod { [pscustomobject]@{ customLibraries = $null } } -ModuleName ZeroFailed.Deploy.Fabric

        Get-FabricEnvironmentLibraries -WorkspaceId 'ws-1' -EnvironmentId 'env-1' -Token 'tok' | Out-Null
        Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $RelativeUri -eq 'workspaces/ws-1/environments/env-1/libraries'
        }

        Get-FabricEnvironmentLibraries -WorkspaceId 'ws-1' -EnvironmentId 'env-1' -Token 'tok' -Staging | Out-Null
        Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $RelativeUri -eq 'workspaces/ws-1/environments/env-1/staging/libraries'
        }
    }

    It 'returns an empty array when there are no custom libraries' {
        Mock _Invoke-FabricRestMethod { [pscustomobject]@{ customLibraries = $null } } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Get-FabricEnvironmentLibraries -WorkspaceId 'ws-1' -EnvironmentId 'env-1' -Token 'tok'
        @($result) | Should -HaveCount 0
    }

    It 'returns an empty array on a 404' {
        Mock _Invoke-FabricRestMethod { throw 'Fabric API error 404 on GET : EnvironmentLibrariesNotFound' } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Get-FabricEnvironmentLibraries -WorkspaceId 'ws-1' -EnvironmentId 'env-1' -Token 'tok'
        @($result) | Should -HaveCount 0
    }
}
