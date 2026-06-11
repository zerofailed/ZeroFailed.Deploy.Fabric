---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/core/workspaces/list-workspaces
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 06/11/2026
PlatyPS schema version: 2024-05-01
title: Test-FabricWorkspaceExists
---

# Test-FabricWorkspaceExists

## SYNOPSIS

Checks whether a Fabric workspace with the given display name already exists.

## SYNTAX

### __AllParameterSets

```
Test-FabricWorkspaceExists [-DisplayName] <string> [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Queries the Fabric workspaces for one matching the given display name and returns it if
found.
Returns $null when no matching workspace exists.

## EXAMPLES

### EXAMPLE 1

Test-FabricWorkspaceExists -DisplayName 'SalesAnalytics-ETL [DEV]'

Returns the workspace object if it exists, otherwise $null.

## PARAMETERS

### -DisplayName

The workspace display name to search for.

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

The matching Fabric workspace object, or `$null` when no workspace with that display name exists.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/core/workspaces/list-workspaces)
