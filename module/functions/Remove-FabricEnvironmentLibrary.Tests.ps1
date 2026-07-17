#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Remove-FabricEnvironmentLibrary' {

    It 'deletes the named library from the staging endpoint' {
        Mock _Invoke-FabricRestMethod { $null } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Remove-FabricEnvironmentLibrary -WorkspaceId 'ws-1' -EnvironmentId 'env-1' `
            -LibraryName 'a-1.0-py3-none-any.whl' -Token 'tok'

        $result.Action | Should -Be 'Removed'
        Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $Method -eq 'DELETE' -and
            $RelativeUri -eq 'workspaces/ws-1/environments/env-1/staging/libraries?libraryToDelete=a-1.0-py3-none-any.whl'
        }
    }

    It 'url-encodes the library name' {
        Mock _Invoke-FabricRestMethod { $null } -ModuleName ZeroFailed.Deploy.Fabric

        Remove-FabricEnvironmentLibrary -WorkspaceId 'ws-1' -EnvironmentId 'env-1' `
            -LibraryName 'my package+1.0.tar.gz' -Token 'tok' | Out-Null

        Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $RelativeUri -eq 'workspaces/ws-1/environments/env-1/staging/libraries?libraryToDelete=my%20package%2B1.0.tar.gz'
        }
    }

    It 'treats a 404 as already removed' {
        Mock _Invoke-FabricRestMethod { throw 'Fabric API error 404 on DELETE : NotFound' } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Remove-FabricEnvironmentLibrary -WorkspaceId 'ws-1' -EnvironmentId 'env-1' `
            -LibraryName 'gone.whl' -Token 'tok'

        $result.Action | Should -Be 'NotFound'
    }

    It 'rethrows other API errors' {
        Mock _Invoke-FabricRestMethod { throw 'Fabric API error 403 on DELETE : Forbidden' } -ModuleName ZeroFailed.Deploy.Fabric

        { Remove-FabricEnvironmentLibrary -WorkspaceId 'ws-1' -EnvironmentId 'env-1' `
            -LibraryName 'a.whl' -Token 'tok' } | Should -Throw '*403*'
    }

    It 'does not call the API under -WhatIf' {
        Mock _Invoke-FabricRestMethod { $null } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Remove-FabricEnvironmentLibrary -WorkspaceId 'ws-1' -EnvironmentId 'env-1' `
            -LibraryName 'a.whl' -Token 'tok' -WhatIf

        $result.Action | Should -Be 'whatif'
        Should -Invoke _Invoke-FabricRestMethod -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }
}
