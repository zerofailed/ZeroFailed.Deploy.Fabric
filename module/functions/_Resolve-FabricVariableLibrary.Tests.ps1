#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe '_Resolve-FabricVariableLibrary' {

    It 'returns the variable library whose display name matches' {
        Mock _Invoke-FabricRestMethod {
            [pscustomobject]@{ value = @(
                [pscustomobject]@{ id = 'vl-1'; displayName = 'other' }
                [pscustomobject]@{ id = 'vl-2'; displayName = 'wanted' }
            ) }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = InModuleScope ZeroFailed.Deploy.Fabric { _Resolve-FabricVariableLibrary -WorkspaceId 'ws-1' -DisplayName 'wanted' -Token 'tok' }
        $result.id | Should -Be 'vl-2'
        Should -Invoke _Invoke-FabricRestMethod -ParameterFilter { $RelativeUri -eq 'workspaces/ws-1/variableLibraries' } -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'follows continuation tokens to find a variable library beyond the first page' {
        Mock _Invoke-FabricRestMethod {
            param($RelativeUri)
            if ($RelativeUri -like '*continuationToken=page2') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'vl-late'; displayName = 'wanted' }) }
            }
            return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'vl-1'; displayName = 'other' }); continuationToken = 'page2' }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = InModuleScope ZeroFailed.Deploy.Fabric { _Resolve-FabricVariableLibrary -WorkspaceId 'ws-1' -DisplayName 'wanted' -Token 'tok' }
        $result.id | Should -Be 'vl-late'
    }

    It 'returns null when no variable library matches' {
        Mock _Invoke-FabricRestMethod { [pscustomobject]@{ value = @() } } -ModuleName ZeroFailed.Deploy.Fabric

        $result = InModuleScope ZeroFailed.Deploy.Fabric { _Resolve-FabricVariableLibrary -WorkspaceId 'ws-1' -DisplayName 'missing' -Token 'tok' }
        $result | Should -BeNullOrEmpty
    }
}
