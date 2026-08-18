---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/core/workspaces/provision-identity
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 06/11/2026
PlatyPS schema version: 2024-05-01
title: Enable-FabricWorkspaceIdentity
---

# Enable-FabricWorkspaceIdentity

## SYNOPSIS

Provisions a Workspace Identity (managed identity) for a Fabric workspace.

## SYNTAX

### __AllParameterSets

```
Enable-FabricWorkspaceIdentity [-WorkspaceId] <string> [-WorkspaceName] <string> [-Token] <string>
 [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Uses the MicrosoftFabricMgmt module to provision a workspace identity.
Waits for the
asynchronous provisioning operation to complete using the module's LRO tracking functions
before returning the service principal details.

Idempotent: if the identity is already provisioned, Add-FabricWorkspaceIdentity returns
an empty response (the module silently swallows the 409/200-no-op from the API).
In that
case the function returns $null — no error is raised, but no identity report entry is
produced (the SP details are not retrievable via this code path on re-runs).

## EXAMPLES

### EXAMPLE 1

Enable-FabricWorkspaceIdentity -WorkspaceId $ws.id -WorkspaceName 'SalesAnalytics-ETL [DEV]' -Token $token

Provisions a workspace identity and returns its service principal details.

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

A report entry describing the provisioned workspace identity, including the workspace name and ID and the identity service principal object ID and application ID. Returns `$null` on an idempotent re-run where the identity already exists.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/core/workspaces/provision-identity)
