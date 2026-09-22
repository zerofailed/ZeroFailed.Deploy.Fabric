---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/graph/api/resources/directoryobject
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 09/21/2026
PlatyPS schema version: 2024-05-01
title: Get-AzureAdDirectoryObject
---

# Get-AzureAdDirectoryObject

## SYNOPSIS

Searches the different types of AzureAD directory objects to find a match for the specified criterion.

## SYNTAX

### __AllParameterSets

```
Get-AzureAdDirectoryObject [-Criterion] <string> [-Single] [-SuppressMultipleMatchWarning]
 [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Searches for groups, service principals and users in AzureAD that match the specified criteria.

## EXAMPLES

## PARAMETERS

### -Criterion

When a GUID, will be compared with the ApplicationId and/or ObjectId properties of the relevant AzureAD directory objects.
Non-GUID values will
be queried as exact matches against the 'DisplayName' property.

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

### -Single

When true, an exception will be thrown if multiple matches are found.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
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

### -SuppressMultipleMatchWarning

When true, no warnings will be logged if multiple matches are found.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
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

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/graph/api/resources/directoryobject)
