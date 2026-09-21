#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    $script:sub = '11111111-1111-1111-1111-111111111111'

    # Calls the private function inside the module, splatting the given parameters.
    function Resolve-Mpe([hashtable]$Params) {
        & (Get-Module ZeroFailed.Deploy.Fabric) { param($p) _Resolve-ManagedPrivateEndpoint @p } $Params
    }
}

Describe '_Resolve-ManagedPrivateEndpoint' {

    It 'builds the resource ID, name and sub-resource for a known type' {
        $r = Resolve-Mpe @{ SubscriptionId = $script:sub; ResourceGroup = 'rg-sales-dev'; ResourceName = 'kv-sales-dev'; ResourceType = 'KeyVault' }
        $r.Name                        | Should -BeExactly 'kv-sales-dev.vault'
        $r.TargetPrivateLinkResourceId | Should -Be "/subscriptions/$($script:sub)/resourceGroups/rg-sales-dev/providers/Microsoft.KeyVault/vaults/kv-sales-dev"
        $r.TargetSubresourceType       | Should -Be 'vault'
    }

    It 'uses an explicit sub-resource over the default' {
        $r = Resolve-Mpe @{ SubscriptionId = $script:sub; ResourceGroup = 'rg'; ResourceName = 'stsalesdev'; ResourceType = 'Storage'; SubResourceType = 'dfs' }
        $r.Name                        | Should -BeExactly 'stsalesdev.dfs'
        $r.TargetPrivateLinkResourceId | Should -BeLike '*/providers/Microsoft.Storage/storageAccounts/stsalesdev'
        $r.TargetSubresourceType       | Should -Be 'dfs'
    }

    It 'maps each known type to its provider path and default sub-resource' -ForEach @(
        @{ Type = 'KeyVault';     Provider = 'Microsoft.KeyVault/vaults';             Sub = 'vault' }
        @{ Type = 'SqlServer';    Provider = 'Microsoft.Sql/servers';                 Sub = 'sqlServer' }
        @{ Type = 'CosmosDb';     Provider = 'Microsoft.DocumentDB/databaseAccounts'; Sub = 'Sql' }
        @{ Type = 'EventHubs';    Provider = 'Microsoft.EventHub/namespaces';         Sub = 'namespace' }
        @{ Type = 'DataExplorer'; Provider = 'Microsoft.Kusto/clusters';              Sub = 'cluster' }
    ) {
        $r = Resolve-Mpe @{ SubscriptionId = $script:sub; ResourceGroup = 'rg'; ResourceName = 'res'; ResourceType = $Type }
        $r.TargetPrivateLinkResourceId | Should -BeLike "*/providers/$Provider/res"
        $r.TargetSubresourceType       | Should -BeExactly $Sub
    }

    It 'accepts a known type name in any case' {
        $r = Resolve-Mpe @{ SubscriptionId = $script:sub; ResourceGroup = 'rg'; ResourceName = 'kv'; ResourceType = 'keyvault' }
        $r.TargetPrivateLinkResourceId | Should -BeLike '*/Microsoft.KeyVault/vaults/kv'
    }

    It 'passes a provider path through, with no sub-resource unless one is given' {
        $r = Resolve-Mpe @{ SubscriptionId = $script:sub; ResourceGroup = 'rg'; ResourceName = 'pls-sales-dev'; ResourceType = 'Microsoft.Network/privateLinkServices' }
        $r.Name                        | Should -BeExactly 'pls-sales-dev'
        $r.TargetPrivateLinkResourceId | Should -BeLike '*/providers/Microsoft.Network/privateLinkServices/pls-sales-dev'
        $r.TargetSubresourceType       | Should -BeNullOrEmpty
    }

    It 'lower-cases the endpoint name but not the resource ID or sub-resource' {
        $r = Resolve-Mpe @{ SubscriptionId = $script:sub; ResourceGroup = 'RG-Dev'; ResourceName = 'Cosmos-Sales-Dev'; ResourceType = 'CosmosDb' }
        $r.Name                        | Should -BeExactly 'cosmos-sales-dev.sql'
        $r.TargetPrivateLinkResourceId | Should -BeLike '*/resourceGroups/RG-Dev/*/databaseAccounts/Cosmos-Sales-Dev'
        $r.TargetSubresourceType       | Should -BeExactly 'Sql'
    }

    It 'throws when the resource type is missing' {
        { Resolve-Mpe @{ SubscriptionId = $script:sub; ResourceGroup = 'rg'; ResourceName = 'kv' } } | Should -Throw '*must have a resourceType*'
    }

    It 'throws when the resource type is unknown' {
        { Resolve-Mpe @{ SubscriptionId = $script:sub; ResourceGroup = 'rg'; ResourceName = 'kv'; ResourceType = 'Vault' } } | Should -Throw "*Unknown managed private endpoint resourceType 'Vault'*"
    }

    It 'throws when Storage has no sub-resource' {
        { Resolve-Mpe @{ SubscriptionId = $script:sub; ResourceGroup = 'rg'; ResourceName = 'st'; ResourceType = 'Storage' } } | Should -Throw '*must have a subResourceType*'
    }

    It 'throws when the resource group or name is missing' {
        { Resolve-Mpe @{ SubscriptionId = $script:sub; ResourceName = 'kv'; ResourceType = 'KeyVault' } } | Should -Throw '*must have both a resourceGroup and a resourceName*'
        { Resolve-Mpe @{ SubscriptionId = $script:sub; ResourceGroup = 'rg'; ResourceType = 'KeyVault' } } | Should -Throw '*must have both a resourceGroup and a resourceName*'
    }

    It 'throws when the subscription ID is missing or not a GUID' {
        { Resolve-Mpe @{ ResourceGroup = 'rg'; ResourceName = 'kv'; ResourceType = 'KeyVault' } } | Should -Throw '*valid subscription ID*'
        { Resolve-Mpe @{ SubscriptionId = 'sub-dev'; ResourceGroup = 'rg'; ResourceName = 'kv'; ResourceType = 'KeyVault' } } | Should -Throw '*valid subscription ID*'
    }

    It 'throws when the endpoint name is longer than 64 characters' {
        { Resolve-Mpe @{ SubscriptionId = $script:sub; ResourceGroup = 'rg'; ResourceName = ('x' * 59); ResourceType = 'KeyVault' } } | Should -Throw '*64-character*'
    }
}
