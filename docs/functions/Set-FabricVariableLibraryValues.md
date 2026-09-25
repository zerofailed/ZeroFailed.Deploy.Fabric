---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/variablelibrary/items/update-variable-library-definition
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 09/22/2026
PlatyPS schema version: 2024-05-01
title: Set-FabricVariableLibraryValues
---

# Set-FabricVariableLibraryValues

## SYNOPSIS

Sets variables and a stage value set on a Fabric Variable Library, preserving everything else.

## SYNTAX

### __AllParameterSets

```
Set-FabricVariableLibraryValues [-WorkspaceId] <string> [-WorkspaceName] <string>
 [-VariableLibraryId] <string> [-VariableLibraryName] <string> [-ValueSetName] <string>
 [-Values] <IDictionary> [[-DefaultValue] <string>] [-Token] <string> [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Merges the given variables into an existing variable library:
  1.
Each variable is added as a String variable if missing.
Its default value (the library's
     default value set) is always -DefaultValue — a placeholder, never a real value.
  2.
The value set named -ValueSetName is created if missing, and its overrides for the given
     variables are set to the supplied values.
  3.
That value set is made the library's active value set.

All other variables, value sets and overrides are left unchanged.
The definition is read with
getDefinition and written back in full with updateDefinition (which replaces the whole
definition) — and only when something has changed.
Parts that are not modified are written
back byte-for-byte.
The active value set is only updated when it differs.

## EXAMPLES

### EXAMPLE 1

Set-FabricVariableLibraryValues -WorkspaceId $ws.id -WorkspaceName 'SalesAnalytics-ETL [DEV]' `
    -VariableLibraryId $library.id -VariableLibraryName 'DefaultVariableLibrary' `
    -ValueSetName 'DEV' -Values ([ordered]@{ workspace_id = $ws.id }) -Token $token

Adds workspace_id (default value: the placeholder), sets it to the workspace id in the DEV
value set, and activates the DEV value set.

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

### -DefaultValue

Default value (default value set) for each variable.
Default: 'PLACEHOLDER - NO VALUE SET ACTIVE'.

```yaml
Type: System.String
DefaultValue: PLACEHOLDER - NO VALUE SET ACTIVE
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

### -Token

Bearer token string for the Fabric REST API.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 7
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Values

Dictionary of variable name to value, set as overrides in the value set.

```yaml
Type: System.Collections.IDictionary
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 5
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ValueSetName

Name of the value set to create/update and activate, e.g.
the stage short code 'DEV'.

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

### -VariableLibraryId

The variable library GUID.

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

### -VariableLibraryName

Display name used in log messages and the returned report entry.

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

The Fabric workspace GUID containing the variable library.

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

A report entry with the workspace, variable library, value set and variable names, whether the definition was Updated or Skipped, and whether the active value set was Set or Skipped (both WhatIf under -WhatIf).

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/variablelibrary/items/update-variable-library-definition)
