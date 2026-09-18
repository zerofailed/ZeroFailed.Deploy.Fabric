#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    function Invoke-Sut {
        InModuleScope ZeroFailed.Deploy.Fabric { _Get-FabricWorkspaceIdentity -WorkspaceId 'ws-1' -Token 'tok' }
    }
}

Describe '_Get-FabricWorkspaceIdentity' {

    It 'returns the workspace identity' {
        Mock _Invoke-FabricRestMethod {
            [pscustomobject]@{ id = 'ws-1'; workspaceIdentity = [pscustomobject]@{ applicationId = 'app-1'; servicePrincipalId = 'sp-1' } }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Invoke-Sut
        $result.applicationId      | Should -Be 'app-1'
        $result.servicePrincipalId | Should -Be 'sp-1'
        Should -Invoke _Invoke-FabricRestMethod -ModuleName ZeroFailed.Deploy.Fabric -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $RelativeUri -eq 'workspaces/ws-1'
        }
    }

    It 'returns $null when the workspace has no identity' {
        Mock _Invoke-FabricRestMethod { [pscustomobject]@{ id = 'ws-1' } } -ModuleName ZeroFailed.Deploy.Fabric
        Invoke-Sut | Should -BeNullOrEmpty
    }
}
