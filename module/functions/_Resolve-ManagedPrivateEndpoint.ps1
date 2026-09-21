function _Resolve-ManagedPrivateEndpoint {
    <#
    .SYNOPSIS
        Resolves a topology managed private endpoint resource into the values the Fabric API needs.
    .DESCRIPTION
        Builds the target's Azure resource ID from its parts:
            /subscriptions/{SubscriptionId}/resourceGroups/{ResourceGroup}/providers/{provider path}/{ResourceName}
        where the provider path comes from the resource type. ResourceType is one of the known types
        below, or any provider path such as 'Microsoft.Search/searchServices'.

          KeyVault     — Microsoft.KeyVault/vaults             (default sub-resource 'vault')
          Storage      — Microsoft.Storage/storageAccounts     (no default: 'blob', 'dfs', ... must be given)
          SqlServer    — Microsoft.Sql/servers                 (default sub-resource 'sqlServer')
          CosmosDb     — Microsoft.DocumentDB/databaseAccounts (default sub-resource 'Sql')
          EventHubs    — Microsoft.EventHub/namespaces         (default sub-resource 'namespace')
          DataExplorer — Microsoft.Kusto/clusters              (default sub-resource 'cluster')

        The endpoint is named '{ResourceName}.{sub-resource}' in lower case (e.g. 'kv-sales-dev.vault'),
        so one resource can have an endpoint per sub-resource in the same workspace. A type with no
        sub-resource (e.g. a Private Link Service given as a provider path) uses the resource name alone.

        Throws if the resource type is unknown, a required value is missing, or the endpoint name is
        longer than Fabric's 64-character limit.
    .PARAMETER SubscriptionId
        The Azure subscription ID holding the resource.
    .PARAMETER ResourceGroup
        The resource group holding the resource.
    .PARAMETER ResourceName
        The Azure resource name.
    .PARAMETER ResourceType
        A known resource type (see above) or a provider path.
    .PARAMETER SubResourceType
        The private link sub-resource. Defaults from the resource type when omitted.
    .OUTPUTS
        A hashtable with Name, TargetPrivateLinkResourceId and TargetSubresourceType.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$SubscriptionId,

        [string]$ResourceGroup,

        [string]$ResourceName,

        [string]$ResourceType,

        [string]$SubResourceType
    )

    $knownTypes = @{
        KeyVault     = @{ Provider = 'Microsoft.KeyVault/vaults';             DefaultSubresource = 'vault' }
        Storage      = @{ Provider = 'Microsoft.Storage/storageAccounts';     DefaultSubresource = $null; SubresourceRequired = $true }
        SqlServer    = @{ Provider = 'Microsoft.Sql/servers';                 DefaultSubresource = 'sqlServer' }
        CosmosDb     = @{ Provider = 'Microsoft.DocumentDB/databaseAccounts'; DefaultSubresource = 'Sql' }
        EventHubs    = @{ Provider = 'Microsoft.EventHub/namespaces';         DefaultSubresource = 'namespace' }
        DataExplorer = @{ Provider = 'Microsoft.Kusto/clusters';              DefaultSubresource = 'cluster' }
    }

    if (-not $ResourceType) {
        throw "A managed private endpoint resource must have a resourceType (e.g. 'KeyVault', 'Storage', or a provider path such as 'Microsoft.KeyVault/vaults')."
    }
    $knownType = $knownTypes[$ResourceType]
    if (-not $knownType -and $ResourceType -notmatch '^[A-Za-z0-9]+(\.[A-Za-z0-9]+)+/[A-Za-z0-9]+(/[A-Za-z0-9]+)*$') {
        throw "Unknown managed private endpoint resourceType '$ResourceType'. Use one of $(($knownTypes.Keys | Sort-Object) -join ', '), or a provider path such as 'Microsoft.KeyVault/vaults'."
    }
    if (-not $ResourceGroup -or -not $ResourceName) {
        throw "Managed private endpoint resource '$ResourceName' ($ResourceType) must have both a resourceGroup and a resourceName."
    }
    if ($SubscriptionId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw "Managed private endpoint resource '$ResourceName' needs a valid subscription ID (a GUID), but got '$SubscriptionId'."
    }

    $subresource = if ($SubResourceType) { $SubResourceType } elseif ($knownType) { $knownType.DefaultSubresource } else { $null }
    if (-not $subresource -and $knownType -and $knownType.SubresourceRequired) {
        throw "Managed private endpoint resource '$ResourceName' ($ResourceType) must have a subResourceType (e.g. 'blob' or 'dfs'). Storage needs a separate endpoint for each sub-resource."
    }

    $provider = if ($knownType) { $knownType.Provider } else { $ResourceType }
    $name     = if ($subresource) { "$ResourceName.$subresource" } else { $ResourceName }
    $name     = $name.ToLowerInvariant()

    if ($name.Length -gt 64) {
        throw "Managed private endpoint name '$name' is $($name.Length) characters, over Fabric's 64-character limit."
    }

    return @{
        Name                        = $name
        TargetPrivateLinkResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/$provider/$ResourceName"
        TargetSubresourceType       = $subresource
    }
}
