#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Get-AzAccessToken comes from Az.Accounts, which is not installed in CI. Provide a stub so
    # the command exists and can be mocked from within the module's scope.
    if (Get-Module _AzAccountsStub) { Remove-Module _AzAccountsStub -Force }
    New-Module -Name _AzAccountsStub {
        function Get-AzAccessToken {
            [CmdletBinding()]
            param([string]$ResourceUrl, [switch]$AsSecureString, $ErrorAction, $WarningAction)
        }
        Export-ModuleMember -Function Get-AzAccessToken
    } | Import-Module
}

AfterAll {
    if (Get-Module _AzAccountsStub) { Remove-Module _AzAccountsStub -Force }
}

Describe '_Get-FabricAuthToken' {

    It 'returns the decoded token and its expiry' {
        $expiry = [DateTimeOffset]::UtcNow.AddHours(1)
        Mock Get-AzAccessToken {
            [pscustomobject]@{
                Token     = (ConvertTo-SecureString 'secret-token' -AsPlainText -Force)
                ExpiresOn = $expiry
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = & (Get-Module ZeroFailed.Deploy.Fabric) { _Get-FabricAuthToken }
        $result.Token     | Should -Be 'secret-token'
        $result.ExpiresOn | Should -Be $expiry
    }

    It 'throws a helpful error when token acquisition fails' {
        Mock Get-AzAccessToken { throw 'not logged in' } -ModuleName ZeroFailed.Deploy.Fabric
        { & (Get-Module ZeroFailed.Deploy.Fabric) { _Get-FabricAuthToken } } | Should -Throw '*access token*'
    }
}

Describe '_Test-FabricTokenExpiry' {

    It 'returns $true when fewer than 5 minutes remain' {
        $info = @{ ExpiresOn = [DateTimeOffset]::UtcNow.AddMinutes(2) }
        $result = & (Get-Module ZeroFailed.Deploy.Fabric) { _Test-FabricTokenExpiry -TokenInfo $args[0] } $info
        $result | Should -BeTrue
    }

    It 'returns $false when more than 5 minutes remain' {
        $info = @{ ExpiresOn = [DateTimeOffset]::UtcNow.AddMinutes(30) }
        $result = & (Get-Module ZeroFailed.Deploy.Fabric) { _Test-FabricTokenExpiry -TokenInfo $args[0] } $info
        $result | Should -BeFalse
    }
}
