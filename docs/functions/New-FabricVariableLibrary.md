---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/variablelibrary/items/create-variable-library
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 09/14/2026
PlatyPS schema version: 2024-05-01
title: New-FabricVariableLibrary
---

# New-FabricVariableLibrary

## SYNOPSIS

Creates a Fabric Variable Library idempotently (never modifies one that already exists).

## SYNTAX

### __AllParameterSets

```
New-FabricVariableLibrary [-WorkspaceId] <string> [-DisplayName] <string> [[-Description] <string>]
 [-Token] <string> [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Checks whether a variable library with the given display name already exists in the workspace
and returns it unchanged if so — its variables, value sets and active value set are never
overwritten or modified.
Otherwise creates an empty variable library via the Fabric REST API
(POST /workspaces/{id}/variableLibraries), returning the created object.

An ItemDisplayNameAlreadyInUse (HTTP 409) conflict is treated idempotently: the existing
variable library is resolved and returned.

This provisions an empty library only — no definition is supplied, so no variables or value
sets are populated.

## EXAMPLES

### EXAMPLE 1

New-FabricVariableLibrary -WorkspaceId $ws.id -DisplayName 'SalesAnalytics-ETL Variables' -Token $token

Creates the variable library in the workspace, or returns it unchanged if it already exists.

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

Optional description for the variable library.

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

The display name for the variable library.

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

The Fabric workspace GUID that will contain the variable library.

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

The Fabric variable library object, whether it already existed (returned unchanged) or was newly created.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/variablelibrary/items/create-variable-library)
