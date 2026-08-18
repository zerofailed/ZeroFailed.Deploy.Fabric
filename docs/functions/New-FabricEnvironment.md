---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/environment/items/create-environment
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 07/03/2026
PlatyPS schema version: 2024-05-01
title: New-FabricEnvironment
---

# New-FabricEnvironment

## SYNOPSIS

Creates a Fabric Spark Environment idempotently (skips creation if it already exists).

## SYNTAX

### __AllParameterSets

```
New-FabricEnvironment [-WorkspaceId] <string> [-DisplayName] <string> [[-Description] <string>]
 [-Token] <string> [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Checks whether an environment with the given display name already exists in the workspace
and returns it if so. Otherwise creates it via the Fabric REST API
(POST /workspaces/{id}/environments), returning the created object.

An EnvironmentDisplayNameAlreadyInUse (HTTP 409) conflict is treated idempotently: the
existing environment is resolved and returned.

This provisions an empty environment only. Uploading libraries (.whl) and publishing are
handled by a separate action — creating and referencing an empty environment does not
require a publish.

## EXAMPLES

### EXAMPLE 1

New-FabricEnvironment -WorkspaceId $ws.id -DisplayName 'SalesAnalytics-ETL [DEV] Env' -Token $token

Creates the environment in the workspace, or returns it if it already exists.

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

### -Description

Optional description for the environment.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DisplayName

The display name for the environment.

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

### -Token

Bearer token string for the Fabric REST API.

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

The Fabric workspace GUID that will contain the environment.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Management.Automation.PSObject

The Fabric environment object, whether it already existed or was newly created.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/environment/items/create-environment)
