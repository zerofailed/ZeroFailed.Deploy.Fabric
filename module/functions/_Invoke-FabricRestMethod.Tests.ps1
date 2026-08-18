#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    function Invoke-Sut {
        param([hashtable]$Params)
        & (Get-Module ZeroFailed.Deploy.Fabric) { _Invoke-FabricRestMethod @args } @Params
    }
}

Describe '_Invoke-FabricRestMethod' {

    It 'sends a GET to the resolved Fabric API URL and returns the response' {
        Mock Invoke-RestMethod { [pscustomobject]@{ value = @('a', 'b') } } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Invoke-Sut @{ Method = 'GET'; RelativeUri = 'workspaces'; Token = 'tok' }
        $result.value | Should -HaveCount 2

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $Method -eq 'GET' -and
            $Uri -eq 'https://api.fabric.microsoft.com/v1/workspaces' -and
            $Headers.Authorization -eq 'Bearer tok'
        }
    }

    It 'trims a leading slash from the relative URI' {
        Mock Invoke-RestMethod { [pscustomobject]@{ ok = $true } } -ModuleName ZeroFailed.Deploy.Fabric

        Invoke-Sut @{ Method = 'GET'; RelativeUri = '/workspaces/1'; Token = 'tok' } | Out-Null

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $Uri -eq 'https://api.fabric.microsoft.com/v1/workspaces/1'
        }
    }

    It 'serialises the body to a JSON string for a POST' {
        Mock Invoke-RestMethod { [pscustomobject]@{ id = 'new' } } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Invoke-Sut @{ Method = 'POST'; RelativeUri = 'workspaces'; Token = 'tok'; Body = @{ displayName = 'ws' } }
        $result.id | Should -Be 'new'

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $Body -is [string] -and $Body -match 'displayName'
        }
    }
}
