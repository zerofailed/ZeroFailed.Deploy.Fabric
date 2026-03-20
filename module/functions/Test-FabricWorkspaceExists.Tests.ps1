#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    $script:fabricMgmtAvailable = $null -ne (Get-Module -ListAvailable -Name MicrosoftFabricMgmt)
}

Describe 'Test-FabricWorkspaceExists' {

    It 'returns $null when Get-FabricWorkspace is unavailable or throws' {
        # When MicrosoftFabricMgmt is not installed, CommandNotFoundException is caught
        # and the function returns $null.
        if ($script:fabricMgmtAvailable) {
            Mock Get-FabricWorkspace { throw 'workspace not found' } -ModuleName ZeroFailed.Deploy.Fabric
        }
        $result = Test-FabricWorkspaceExists -DisplayName 'nonexistent-workspace'
        $result | Should -BeNullOrEmpty
    }

    It 'returns workspace object when Get-FabricWorkspace returns one' -Skip:(-not $script:fabricMgmtAvailable) {
        $fakeWorkspace = [pscustomobject]@{ id = 'abc-123'; displayName = 'my-workspace' }
        Mock Get-FabricWorkspace { return $fakeWorkspace } -ModuleName ZeroFailed.Deploy.Fabric
        $result = Test-FabricWorkspaceExists -DisplayName 'my-workspace'
        $result.id | Should -Be 'abc-123'
    }
}
