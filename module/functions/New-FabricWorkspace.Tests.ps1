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

        $result = New-FabricWorkspace -DisplayName 'my-workspace' -CapacityName 'cap-dev' -Token 'tok'
        $result.id | Should -Be 'existing-id'
    }

    It 'returns WhatIf placeholder when -WhatIf is specified and workspace does not exist' {
        Mock Test-FabricWorkspaceExists { return $null } -ModuleName ZeroFailed.Deploy.Fabric

        $result = New-FabricWorkspace -DisplayName 'new-workspace' -CapacityName 'cap-dev' -Token 'tok' -WhatIf
        $result.id | Should -Be 'whatif-id'
        $result.displayName | Should -Be 'new-workspace'
    }
}
