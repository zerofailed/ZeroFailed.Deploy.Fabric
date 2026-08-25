#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    $script:tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "fabtest-$([guid]::NewGuid()).whl"
    Set-Content -LiteralPath $script:tempFile -Value 'dummy wheel content'
}

AfterAll {
    if (Test-Path -LiteralPath $script:tempFile) { Remove-Item -LiteralPath $script:tempFile -Force }
}

Describe '_Invoke-FabricFileUpload' {

    It 'throws when the file does not exist' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            { _Invoke-FabricFileUpload -RelativeUri 'workspaces/ws/environments/env/staging/libraries' `
                -FilePath '/no/such/file.whl' -Token 'tok' } | Should -Throw '*File not found*'
        }
    }

    It 'posts the raw file to the absolute Fabric URL as octet-stream' {
        InModuleScope ZeroFailed.Deploy.Fabric -Parameters @{ file = $script:tempFile } {
            param($file)
            Mock Invoke-RestMethod {
                param($Method, $Uri, $Headers, $InFile, $ContentType)
                return [pscustomobject]@{ ok = $true }
            }

            $result = _Invoke-FabricFileUpload `
                -RelativeUri 'workspaces/ws-1/environments/env-1/staging/libraries/pkg.whl' `
                -FilePath $file -Token 'tok'

            $result.ok | Should -BeTrue
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'Post' -and
                $Uri -eq 'https://api.fabric.microsoft.com/v1/workspaces/ws-1/environments/env-1/staging/libraries/pkg.whl' -and
                $Headers.Authorization -eq 'Bearer tok' -and
                $InFile -eq $file -and
                $ContentType -eq 'application/octet-stream'
            }
        }
    }

    It 'retries a 5xx failure and succeeds on a later attempt' {
        InModuleScope ZeroFailed.Deploy.Fabric -Parameters @{ file = $script:tempFile } {
            param($file)
            $script:calls = 0
            Mock Invoke-RestMethod {
                $script:calls++
                if ($script:calls -lt 3) {
                    $resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::InternalServerError)
                    $ex   = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Server Error', $resp)
                    $rec  = [System.Management.Automation.ErrorRecord]::new($ex, 'x', 'InvalidResult', $null)
                    $rec.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('EnvironmentInternalServerError')
                    throw $rec
                }
                return [pscustomobject]@{ ok = $true }
            }

            $result = _Invoke-FabricFileUpload `
                -RelativeUri 'workspaces/ws/environments/env/staging/libraries/pkg.whl' `
                -FilePath $file -Token 'tok' -MaxAttempts 4 -RetryBaseDelaySec 0

            $result.ok | Should -BeTrue
            Should -Invoke Invoke-RestMethod -Times 3 -Exactly
        }
    }

    It 'gives up after MaxAttempts on a persistent 5xx' {
        InModuleScope ZeroFailed.Deploy.Fabric -Parameters @{ file = $script:tempFile } {
            param($file)
            Mock Invoke-RestMethod {
                $resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::InternalServerError)
                $ex   = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Server Error', $resp)
                $rec  = [System.Management.Automation.ErrorRecord]::new($ex, 'x', 'InvalidResult', $null)
                $rec.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('EnvironmentInternalServerError')
                throw $rec
            }

            { _Invoke-FabricFileUpload -RelativeUri 'workspaces/ws/environments/env/staging/libraries/pkg.whl' `
                -FilePath $file -Token 'tok' -MaxAttempts 3 -RetryBaseDelaySec 0 } |
                Should -Throw '*Fabric API error 500*EnvironmentInternalServerError*'
            Should -Invoke Invoke-RestMethod -Times 3 -Exactly
        }
    }

    It 'does not retry a 4xx client error' {
        InModuleScope ZeroFailed.Deploy.Fabric -Parameters @{ file = $script:tempFile } {
            param($file)
            Mock Invoke-RestMethod {
                $resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::BadRequest)
                $ex   = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Bad Request', $resp)
                $rec  = [System.Management.Automation.ErrorRecord]::new($ex, 'x', 'InvalidResult', $null)
                $rec.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('EnvironmentValidationFailed')
                throw $rec
            }

            { _Invoke-FabricFileUpload -RelativeUri 'workspaces/ws/environments/env/staging/libraries/pkg.whl' `
                -FilePath $file -Token 'tok' -MaxAttempts 4 -RetryBaseDelaySec 0 } |
                Should -Throw '*Fabric API error 400*'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }
    }

    It 'unwraps a Fabric HttpResponseException into a descriptive error' {
        InModuleScope ZeroFailed.Deploy.Fabric -Parameters @{ file = $script:tempFile } {
            param($file)
            Mock Invoke-RestMethod {
                $resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::BadRequest)
                $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Bad Request', $resp)
                $errRecord = [System.Management.Automation.ErrorRecord]::new($ex, 'x', 'InvalidResult', $null)
                $errRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('PayloadTooLarge')
                throw $errRecord
            }

            { _Invoke-FabricFileUpload -RelativeUri 'workspaces/ws/environments/env/staging/libraries' `
                -FilePath $file -Token 'tok' } | Should -Throw '*Fabric API error 400*PayloadTooLarge*'
        }
    }
}
