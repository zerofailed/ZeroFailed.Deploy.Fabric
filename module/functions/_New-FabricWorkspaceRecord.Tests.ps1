#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe '_New-FabricWorkspaceRecord' {

    It 'returns a record with the full property set in a stable order' {
        $rec = & (Get-Module ZeroFailed.Deploy.Fabric) {
            _New-FabricWorkspaceRecord -Type 'Bronze' -Environment 'Dev' -Name 'sa-Bronze [DEV]' -CapacityName 'cap-dev'
        }

        $rec.PSObject.Properties.Name | Should -Be @(
            'Type', 'Environment', 'Name', 'WorkspaceId', 'CapacityName',
            'Status', 'GitConnected', 'Identity', 'SparkEnvironment'
        )
    }

    It 'sets the passed-through values and the correct defaults' {
        $rec = & (Get-Module ZeroFailed.Deploy.Fabric) {
            _New-FabricWorkspaceRecord -Type 'Silver' -Environment 'Test' -Name 'sa-Silver [TEST]' -CapacityName 'cap-test'
        }

        $rec.Type             | Should -Be 'Silver'
        $rec.Environment      | Should -Be 'Test'
        $rec.Name             | Should -Be 'sa-Silver [TEST]'
        $rec.CapacityName     | Should -Be 'cap-test'
        $rec.WorkspaceId      | Should -BeNullOrEmpty
        $rec.Status           | Should -Be 'Pending'
        $rec.GitConnected     | Should -BeFalse
        $rec.Identity         | Should -BeNullOrEmpty
        $rec.SparkEnvironment | Should -BeNullOrEmpty
    }

    It 'tolerates a null or empty capacity name' {
        $rec = & (Get-Module ZeroFailed.Deploy.Fabric) {
            _New-FabricWorkspaceRecord -Type 'Gold' -Environment 'Prod' -Name 'x' -CapacityName $null
        }
        $rec.CapacityName | Should -BeNullOrEmpty
    }
}
