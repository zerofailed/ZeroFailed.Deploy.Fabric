---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/spark/workspace-settings/update-spark-settings
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 07/03/2026
PlatyPS schema version: 2024-05-01
title: Set-FabricWorkspaceDefaultEnvironment
---

# Set-FabricWorkspaceDefaultEnvironment

## SYNOPSIS

Sets a Fabric environment as the workspace default (idempotent).

## SYNTAX

### __AllParameterSets

```
Set-FabricWorkspaceDefaultEnvironment [-WorkspaceId] <string> [-WorkspaceName] <string>
 [-EnvironmentName] <string> [[-RuntimeVersion] <string>] [-Token] <string> [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Configures the workspace Spark settings so that notebooks and Spark job definitions using
"Workspace default" inherit the given environment's compute and library configuration.

The environment is referenced by display name (an empty string clears the default).
Uses PATCH /workspaces/{id}/spark/settings; the caller must have the workspace Admin role.

Idempotent: reads the current Spark settings first and skips the PATCH if the default
environment is already set to the requested name.

## EXAMPLES

### EXAMPLE 1

Set-FabricWorkspaceDefaultEnvironment -WorkspaceId $ws.id -WorkspaceName 'SalesAnalytics-ETL [DEV]' `
    -EnvironmentName 'SalesAnalytics-ETL [DEV] Env' -Token $token

Sets the environment as the workspace default, or reports Skipped if already set.

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

### -EnvironmentName

Display name of the environment to set as the workspace default.

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

### -RuntimeVersion

Spark runtime version for the default environment. Default: 1.3.

```yaml
Type: System.String
DefaultValue: '1.3'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
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
  Position: 4
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

A report entry with the workspace name and ID, the environment name, and the action taken
(Set, Skipped, or whatif).

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/spark/workspace-settings/update-spark-settings)
