#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe '_Assert-Prerequisites' {

    It 'passes when both required modules are available' {
        Mock Get-Module { [pscustomobject]@{ Name = $Name } } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ListAvailable }
        { & (Get-Module ZeroFailed.Deploy.Fabric) { _Assert-Prerequisites } } | Should -Not -Throw
    }

    It 'throws a helpful error when Az.Accounts is missing' {
        Mock Get-Module {
            if ($Name -eq 'Az.Accounts') { return $null }
            return [pscustomobject]@{ Name = $Name }
        } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ListAvailable }

        { & (Get-Module ZeroFailed.Deploy.Fabric) { _Assert-Prerequisites } } | Should -Throw '*Az.Accounts*'
    }

    It 'throws a helpful error when MicrosoftFabricMgmt is missing' {
        Mock Get-Module {
            if ($Name -eq 'MicrosoftFabricMgmt') { return $null }
            return [pscustomobject]@{ Name = $Name }
        } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ListAvailable }

        { & (Get-Module ZeroFailed.Deploy.Fabric) { _Assert-Prerequisites } } | Should -Throw '*MicrosoftFabricMgmt*'
    }
}
