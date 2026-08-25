#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe '_Test-PackageOnPyPI' {

    It 'returns true when PyPI returns the package (200)' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            Mock Invoke-RestMethod { [pscustomobject]@{ info = @{} } }
            _Test-PackageOnPyPI -Name 'deltalake' -Version '1.6.2' | Should -BeTrue
        }
    }

    It 'returns false on a 404 (not on PyPI at that version)' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            Mock Invoke-RestMethod {
                $resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::NotFound)
                $ex   = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Not Found', $resp)
                $rec  = [System.Management.Automation.ErrorRecord]::new($ex, 'x', 'InvalidResult', $null)
                throw $rec
            }
            _Test-PackageOnPyPI -Name 'edap-thx' -Version '0.1.3' | Should -BeFalse
        }
    }

    It 'rethrows non-404 failures rather than guessing' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            Mock Invoke-RestMethod {
                $resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::ServiceUnavailable)
                $ex   = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Unavailable', $resp)
                $rec  = [System.Management.Automation.ErrorRecord]::new($ex, 'x', 'InvalidResult', $null)
                throw $rec
            }
            { _Test-PackageOnPyPI -Name 'deltalake' -Version '1.6.2' } | Should -Throw '*PyPI lookup*failed*'
        }
    }
}
