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

    It 'parses the GA libraries shape, keeping only custom libraries' {
        Mock _Invoke-FabricRestMethod {
            [pscustomobject]@{
                libraries = @(
                    [pscustomobject]@{ name = 'a-1.0-py3-none-any.whl'; libraryType = 'Custom' }
                    [pscustomobject]@{ name = 'fuzzywuzzy'; libraryType = 'External'; version = '0.0.1' }
                    [pscustomobject]@{ name = 'helper.py'; libraryType = 'Custom' }
                )
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Get-FabricEnvironmentLibraries -WorkspaceId 'ws-1' -EnvironmentId 'env-1' -Token 'tok'
        $result | Should -HaveCount 2
        $result | Should -Contain 'a-1.0-py3-none-any.whl'
        $result | Should -Contain 'helper.py'
        $result | Should -Not -Contain 'fuzzywuzzy'
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

    It '-External parses normalised name==version tokens from the beta environmentYml' {
        Mock _Invoke-FabricRestMethod {
            [pscustomobject]@{
                customLibraries = [pscustomobject]@{ wheelFiles = @('mypackage-1.0-py3-none-any.whl') }
                environmentYml  = "name: env`ndependencies:`n  - pip:`n    - deltalake==1.6.2`n    - charset_normalizer==3.5.1`n"
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Get-FabricEnvironmentLibraries -WorkspaceId 'ws-1' -EnvironmentId 'env-1' -Token 'tok' -External
        $result | Should -HaveCount 2
        $result | Should -Contain 'deltalake==1.6.2'
        $result | Should -Contain 'charset-normalizer==3.5.1'   # underscore normalised to hyphen
    }

    It '-External parses External entries from the GA libraries shape' {
        Mock _Invoke-FabricRestMethod {
            [pscustomobject]@{
                libraries = @(
                    [pscustomobject]@{ name = 'mypackage-1.0-py3-none-any.whl'; libraryType = 'Custom' }
                    [pscustomobject]@{ name = 'deltalake'; libraryType = 'External'; version = '1.6.2' }
                    [pscustomobject]@{ name = 'pydantic_core'; libraryType = 'External'; version = '2.46.4' }
                )
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Get-FabricEnvironmentLibraries -WorkspaceId 'ws-1' -EnvironmentId 'env-1' -Token 'tok' -External
        $result | Should -HaveCount 2
        $result | Should -Contain 'deltalake==1.6.2'
        $result | Should -Contain 'pydantic-core==2.46.4'
    }
}
