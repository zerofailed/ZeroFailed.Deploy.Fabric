---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/core/workspaces/create-workspace
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 06/11/2026
PlatyPS schema version: 2024-05-01
title: New-FabricWorkspace
---

# New-FabricWorkspace

## SYNOPSIS

Creates a Fabric workspace idempotently (skips creation if it already exists).

## SYNTAX

### __AllParameterSets

```
New-FabricWorkspace [-DisplayName] <string> [-CapacityName] <string> [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Checks whether a workspace with the given display name already exists and returns it if so.
Otherwise creates a new workspace on the specified capacity and returns the created object.

## EXAMPLES

### EXAMPLE 1

New-FabricWorkspace -DisplayName 'SalesAnalytics-ETL [DEV]' -CapacityName 'cap-dev'

Creates the workspace on the cap-dev capacity, or returns it if it already exists.

## PARAMETERS

### -CapacityName

The Fabric capacity to assign to the workspace.

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

### -DisplayName

The display name for the workspace.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Management.Automation.PSObject

The Fabric workspace object, whether it already existed or was newly created.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/core/workspaces/create-workspace)
