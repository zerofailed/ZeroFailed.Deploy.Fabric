#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe '_Get-WheelIdentity' {

    It 'parses name and version from a simple wheel name' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            $id = _Get-WheelIdentity -FileName 'deltalake-1.6.2-cp310-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl'
            $id.Name           | Should -Be 'deltalake'
            $id.Version        | Should -Be '1.6.2'
            $id.NormalizedName | Should -Be 'deltalake'
        }
    }

    It 'normalises underscores and dots in the distribution name' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            (_Get-WheelIdentity -FileName 'charset_normalizer-3.5.1-cp311-cp311-manylinux2014_x86_64.whl').NormalizedName |
                Should -Be 'charset-normalizer'
            (_Get-WheelIdentity -FileName 'ruamel.yaml-0.18.6-py3-none-any.whl').NormalizedName |
                Should -Be 'ruamel-yaml'
        }
    }

    It 'strips any leading directory' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            (_Get-WheelIdentity -FileName '/tmp/dl/pyarrow-20.0.0-cp311-cp311-manylinux2014_x86_64.whl').Version |
                Should -Be '20.0.0'
        }
    }

    It 'throws on a non-wheel file name' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            { _Get-WheelIdentity -FileName 'something.tar.gz' } | Should -Throw '*Not a wheel*'
        }
    }
}
