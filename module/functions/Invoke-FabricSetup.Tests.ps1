#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Invoke-FabricSetup' {

    It 'throws when ConfigPath does not exist' {
        { Invoke-FabricSetup -ConfigPath './nonexistent.json' } | Should -Throw
    }
}
