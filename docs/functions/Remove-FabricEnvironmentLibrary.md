---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: ''
Locale: en-GB
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 08/18/2026
PlatyPS schema version: 2024-05-01
title: Remove-FabricEnvironmentLibrary
---

# Remove-FabricEnvironmentLibrary

## SYNOPSIS

Removes a single custom library file from a Fabric environment's staging area.

## SYNTAX

### __AllParameterSets

```
Remove-FabricEnvironmentLibrary [-WorkspaceId] <string> [-EnvironmentId] <string>
 [-LibraryName] <string> [-Token] <string> [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Deletes the file from the environment's staging libraries via
DELETE /workspaces/{id}/environments/{id}/staging/libraries?libraryToDelete={name}.

Staging starts as a copy of the published libraries, so removing a file from staging and
then publishing (see Publish-FabricEnvironment) is how a published library is retired.
Until the publish happens the library remains usable by notebooks/jobs.

A 404 (the library is not staged) is treated as success so this is safe to call repeatedly.

## EXAMPLES

### EXAMPLE 1

Remove-FabricEnvironmentLibrary -WorkspaceId $ws.id -EnvironmentId $env.id `
    -LibraryName 'mypackage-1.4.1-py3-none-any.whl' -Token $token

Removes the stale wheel from the environment's staging libraries.

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

### -EnvironmentId

The Fabric environment GUID to remove the library from.

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

### -LibraryName

The library file name to remove, e.g.
'mypackage-1.4.2-py3-none-any.whl'.
The library file name to remove, e.g.
'mypackage-1.4.2-py3-none-any.whl'.

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

The Fabric workspace GUID that contains the environment.

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

### System.Collections.Hashtable

A hashtable with keys: EnvironmentId, FileName, and Action ('Removed', 'NotFound' if the library
wasn't staged, or 'whatif').

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/)

