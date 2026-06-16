#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Get-AzContext/Get-AzADServicePrincipal/Get-AzADUser come from Az modules not installed in CI.
    # Provide stubs so the commands exist and can be mocked from within the module's scope.
    if (Get-Module _AzIdentityStub) { Remove-Module _AzIdentityStub -Force }
    New-Module -Name _AzIdentityStub {
        function Get-AzContext { }
        function Get-AzADServicePrincipal { param([string]$ApplicationId, $ErrorAction) }
        function Get-AzADUser { param([string]$UserPrincipalName, $ErrorAction) }
        Export-ModuleMember -Function Get-AzContext, Get-AzADServicePrincipal, Get-AzADUser
    } | Import-Module
}

AfterAll {
    if (Get-Module _AzIdentityStub) { Remove-Module _AzIdentityStub -Force }
}

Describe '_Get-FabricDeploymentIdentity' {

    It 'resolves a service principal object id from its application id' {
        Mock Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'app-123'; Type = 'ServicePrincipal' } } } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Get-AzADServicePrincipal { [pscustomobject]@{ Id = 'sp-oid-1' } } -ModuleName ZeroFailed.Deploy.Fabric

        $result = & (Get-Module ZeroFailed.Deploy.Fabric) { _Get-FabricDeploymentIdentity }
        $result.Id   | Should -Be 'sp-oid-1'
        $result.Type | Should -Be 'ServicePrincipal'
        Should -Invoke Get-AzADServicePrincipal -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ApplicationId -eq 'app-123' }
    }

    It 'treats a ClientAssertion (federated) identity as a service principal' {
        Mock Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'app-456'; Type = 'ClientAssertion' } } } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Get-AzADServicePrincipal { [pscustomobject]@{ Id = 'sp-oid-2' } } -ModuleName ZeroFailed.Deploy.Fabric

        $result = & (Get-Module ZeroFailed.Deploy.Fabric) { _Get-FabricDeploymentIdentity }
        $result.Id   | Should -Be 'sp-oid-2'
        $result.Type | Should -Be 'ServicePrincipal'
    }

    It 'resolves a user object id from the user principal name' {
        Mock Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'james@contoso.com'; Type = 'User' } } } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Get-AzADUser { [pscustomobject]@{ Id = 'user-oid-1' } } -ModuleName ZeroFailed.Deploy.Fabric

        $result = & (Get-Module ZeroFailed.Deploy.Fabric) { _Get-FabricDeploymentIdentity }
        $result.Id   | Should -Be 'user-oid-1'
        $result.Type | Should -Be 'User'
    }

    It 'falls back to the HomeAccountId object id for a guest user' {
        Mock Get-AzContext {
            [pscustomobject]@{ Account = [pscustomobject]@{
                Id                = 'guest@external.com'
                Type              = 'User'
                ExtendedProperties = @{ HomeAccountId = 'guest-oid-9.tenant-abc' }
            } }
        } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Get-AzADUser { $null } -ModuleName ZeroFailed.Deploy.Fabric

        $result = & (Get-Module ZeroFailed.Deploy.Fabric) { _Get-FabricDeploymentIdentity }
        $result.Id   | Should -Be 'guest-oid-9'
        $result.Type | Should -Be 'User'
    }

    It 'returns $null when there is no signed-in account' {
        Mock Get-AzContext { [pscustomobject]@{ Account = $null } } -ModuleName ZeroFailed.Deploy.Fabric

        $result = & (Get-Module ZeroFailed.Deploy.Fabric) { _Get-FabricDeploymentIdentity }
        $result | Should -BeNullOrEmpty
    }

    It 'returns $null when the service principal lookup fails' {
        Mock Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'app-789'; Type = 'ServicePrincipal' } } } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Get-AzADServicePrincipal { throw 'Insufficient privileges' } -ModuleName ZeroFailed.Deploy.Fabric

        $result = & (Get-Module ZeroFailed.Deploy.Fabric) { _Get-FabricDeploymentIdentity }
        $result | Should -BeNullOrEmpty
    }
}
