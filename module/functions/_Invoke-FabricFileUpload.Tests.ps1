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

    It 'posts to the absolute Fabric URL with a multipart file part' {
        InModuleScope ZeroFailed.Deploy.Fabric -Parameters @{ file = $script:tempFile } {
            param($file)
            Mock Invoke-RestMethod {
                param($Method, $Uri, $Headers, $Form)
                return [pscustomobject]@{ ok = $true }
            }

            $result = _Invoke-FabricFileUpload `
                -RelativeUri 'workspaces/ws-1/environments/env-1/staging/libraries' `
                -FilePath $file -Token 'tok'

            $result.ok | Should -BeTrue
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'Post' -and
                $Uri -eq 'https://api.fabric.microsoft.com/v1/workspaces/ws-1/environments/env-1/staging/libraries' -and
                $Headers.Authorization -eq 'Bearer tok' -and
                $Form.file -is [System.IO.FileInfo]
            }
        }
    }

    It 'does not set a Content-Type header (boundary is auto-generated)' {
        InModuleScope ZeroFailed.Deploy.Fabric -Parameters @{ file = $script:tempFile } {
            param($file)
            Mock Invoke-RestMethod { [pscustomobject]@{ ok = $true } }

            _Invoke-FabricFileUpload -RelativeUri 'workspaces/ws/environments/env/staging/libraries' `
                -FilePath $file -Token 'tok' | Out-Null

            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                -not $Headers.ContainsKey('Content-Type')
            }
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
