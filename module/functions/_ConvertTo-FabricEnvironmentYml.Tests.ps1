#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe '_ConvertTo-FabricEnvironmentYml' {

    It 'emits a pip dependency list, sorted and pinned' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            $pkgs = @(
                [pscustomobject]@{ NormalizedName = 'pyarrow';   Version = '20.0.0' }
                [pscustomobject]@{ NormalizedName = 'deltalake'; Version = '1.6.2' }
            )
            $yml = _ConvertTo-FabricEnvironmentYml -Package $pkgs

            $yml | Should -Match '(?m)^dependencies:$'
            $yml | Should -Match '(?m)^  - pip:$'
            # Fabric's UI validator only accepts 'channels'/'dependencies' — no 'name:' section.
            $yml | Should -Not -Match '(?m)^name:'
            $yml | Should -Match '(?m)^    - deltalake==1\.6\.2$'
            $yml | Should -Match '(?m)^    - pyarrow==20\.0\.0$'

            # Sorted: deltalake precedes pyarrow.
            $yml.IndexOf('deltalake==') | Should -BeLessThan $yml.IndexOf('pyarrow==')
        }
    }

    It 'de-duplicates identical pins' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            $pkgs = @(
                [pscustomobject]@{ NormalizedName = 'six'; Version = '1.17.0' }
                [pscustomobject]@{ NormalizedName = 'six'; Version = '1.17.0' }
            )
            $yml = _ConvertTo-FabricEnvironmentYml -Package $pkgs
            ([regex]::Matches($yml, 'six==1\.17\.0')).Count | Should -Be 1
        }
    }

    It 'handles an empty package set' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            $yml = _ConvertTo-FabricEnvironmentYml -Package @()
            $yml | Should -Match '(?m)^  - pip:$'
            $yml | Should -Not -Match '=='
        }
    }
}
