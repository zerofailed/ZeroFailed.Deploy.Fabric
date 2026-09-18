#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    function Resolve-Name($Name) {
        & (Get-Module ZeroFailed.Deploy.Fabric) { _Resolve-VariableLibraryName -Name $args[0] } $Name
    }
}

Describe '_Resolve-VariableLibraryName' {

    It 'returns the configured name' {
        Resolve-Name 'Sales Config' | Should -Be 'Sales Config'
    }

    It 'trims surrounding whitespace from the configured name' {
        Resolve-Name '  Sales_Config ' | Should -Be 'Sales_Config'
    }

    It 'defaults to DefaultVariableLibrary when no name is configured' -TestCases @(
        @{ Name = $null }
        @{ Name = '' }
        @{ Name = '   ' }
    ) {
        Resolve-Name $Name | Should -Be 'DefaultVariableLibrary'
    }

    It 'throws when the name does not start with a letter' {
        { Resolve-Name '1Variables' } | Should -Throw '*is invalid*'
    }

    It 'throws when the name contains a character Fabric does not allow' {
        { Resolve-Name 'Variables [Dev]' } | Should -Throw '*is invalid*'
    }

    It 'throws when the name is longer than 256 characters' {
        { Resolve-Name ('a' * 257) } | Should -Throw '*is invalid*'
    }
}
