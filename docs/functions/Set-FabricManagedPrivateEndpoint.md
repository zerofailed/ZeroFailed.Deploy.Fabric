---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/core/managed-private-endpoints/create-workspace-managed-private-endpoint
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 09/14/2026
PlatyPS schema version: 2024-05-01
title: Set-FabricManagedPrivateEndpoint
---

# Set-FabricManagedPrivateEndpoint

## SYNOPSIS

Ensures a managed private endpoint exists in a Fabric workspace, idempotently.

## SYNTAX

### __AllParameterSets

```
Set-FabricManagedPrivateEndpoint [-WorkspaceId] <string> [-WorkspaceName] <string> [-Token] <string>
 [-Name] <string> [-TargetPrivateLinkResourceId] <string> [[-TargetSubresourceType] <string>]
 [[-RequestMessage] <string>] [[-TargetFQDNs] <string[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Lists the workspace's managed private endpoints (following continuation tokens), then:
  - Creates the endpoint via POST if none with that name exists
  - Skips if an endpoint with that name already targets the same resource and sub-resource
  - Throws if an endpoint with that name targets a different resource or sub-resource

Fabric has no API to update a managed private endpoint, so a changed target can only be
applied by deleting and re-creating the endpoint.
That is deliberately left to a person:
deleting an endpoint drops its approved private link connection, and the replacement has to
be approved again.

Creating an endpoint only sends a private link connection request to the target resource.
Its
owner must approve the request (Azure portal -> the resource -> Networking -> Private endpoint
connections) before the endpoint can be used.
The returned ConnectionStatus reports the
approval state, and a warning is written while the endpoint is not yet usable.

Requires the workspace Admin role, and a workspace on a Fabric capacity that supports managed
private endpoints.

## EXAMPLES

### EXAMPLE 1

Set-FabricManagedPrivateEndpoint -WorkspaceId $ws.id -WorkspaceName 'SalesAnalytics-ETL [DEV]' -Token $token -Name 'SalesAnalytics-ETL-KeyVault-DEV' -TargetPrivateLinkResourceId '/subscriptions/{id}/resourceGroups/rg-sales-dev/providers/Microsoft.KeyVault/vaults/kv-sales-dev' -TargetSubresourceType 'vault'

Ensures the workspace has a managed private endpoint to the Dev Key Vault, creating it if it is absent.

## PARAMETERS

### -Confirm

Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- cf
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Name

The managed private endpoint name (at most 64 characters).
Invoke-FabricSetup resolves this
from the topology's naming convention.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RequestMessage

Message shown to the target resource's owner with the approval request (at most 140 characters).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TargetFQDNs

Fully qualified domain names to associate with the endpoint (at most 20), for resource types
that need them, such as Azure API Management.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 7
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TargetPrivateLinkResourceId

Azure resource ID of the private link resource to connect to, e.g.
a Key Vault or storage account.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 4
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TargetSubresourceType

The private link sub-resource to connect to, e.g.
'vault' for Key Vault, or 'blob' or 'dfs' for
a storage account.
Storage needs a separate endpoint for each sub-resource that is used.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 5
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Token

Bearer token string for the Fabric REST API.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -WhatIf

Runs the command in a mode that only reports what would happen without performing the actions.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- wi
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -WorkspaceId

The Fabric workspace GUID.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -WorkspaceName

Display name used in log messages and the returned report entry.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Collections.Hashtable

A report entry with the workspace name and ID, the endpoint name and ID, the target resource ID and sub-resource, the provisioning state, the private endpoint connection (approval) status, and the action taken (`Created`, `Skipped`, or `WhatIf`).

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/core/managed-private-endpoints/create-workspace-managed-private-endpoint)
