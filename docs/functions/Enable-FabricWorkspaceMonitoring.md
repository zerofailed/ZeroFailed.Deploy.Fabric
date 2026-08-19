---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/fabric/fundamentals/workspace-monitoring-overview
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 08/18/2026
PlatyPS schema version: 2024-05-01
title: Enable-FabricWorkspaceMonitoring
---

# Enable-FabricWorkspaceMonitoring

## SYNOPSIS

Verifies that workspace monitoring has been provisioned for a Fabric workspace.

## SYNTAX

### __AllParameterSets

```
Enable-FabricWorkspaceMonitoring [-WorkspaceId] <string> [-WorkspaceName] <string> [-Token] <string>
 [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Checks whether the Monitoring Eventhouse already exists in the workspace by querying the
workspace items list.
Returns success if found (idempotent).

NOTE: There is no public Fabric REST API to provision the Monitoring Eventhouse
programmatically.
It must be created via the Fabric portal before running provisioning:
Workspace Settings → Monitoring → +Eventhouse.

If monitoring has not yet been set up this function throws a clear, actionable error.

## EXAMPLES

### EXAMPLE 1

Enable-FabricWorkspaceMonitoring -WorkspaceId $ws.id -WorkspaceName 'SalesAnalytics-ETL [DEV]' -Token $token

Verifies that the Monitoring Eventhouse exists for the workspace and returns a report entry.

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

A report entry with the workspace name and ID and whether monitoring is enabled.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/fabric/fundamentals/workspace-monitoring-overview)
