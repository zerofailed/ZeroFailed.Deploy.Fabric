---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: ''
Locale: en-GB
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 08/25/2026
PlatyPS schema version: 2024-05-01
title: Get-FabricEnvironmentLibraries
---

# Get-FabricEnvironmentLibraries

## SYNOPSIS

Returns the custom library file names configured on a Fabric environment.

## SYNTAX

### __AllParameterSets

```
Get-FabricEnvironmentLibraries [-WorkspaceId] <string> [-EnvironmentId] <string> [-Token] <string>
 [-Staging] [-External] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Reads the environment's libraries and returns the flat set of custom library file names
(wheel, py, jar and tar files).
Reads the published libraries via
GET /workspaces/{id}/environments/{id}/libraries, or the staging libraries via
GET .../staging/libraries when -Staging is specified.

The returned names are used to decide, idempotently, whether a desired set of files is
already deployed (so upload and the expensive publish can be skipped).
Safe under
Set-StrictMode — all optional properties are guarded.
A 404 (no libraries yet) returns an
empty array.

## EXAMPLES

### EXAMPLE 1

Get-FabricEnvironmentLibraries -WorkspaceId $ws.id -EnvironmentId $env.id -Token $token

Returns the published custom library file names, e.g.
@('mypackage-1.4.2-py3-none-any.whl').

### EXAMPLE 2

Get-FabricEnvironmentLibraries -WorkspaceId $ws.id -EnvironmentId $env.id -Token $token -External

Returns the published external libraries, e.g.
@('deltalake==1.6.2', 'pyarrow==20.0.0').

## PARAMETERS

### -EnvironmentId

The Fabric environment GUID to query.

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

### -External

Return the external (public) libraries as normalised 'name==version' tokens instead of the
custom library file names.
Used to compare the declared environment.yml set idempotently.

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

### -Staging

Query the staging libraries instead of the published libraries.

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

### System.String[]

The flat set of custom library file names (wheel, py, jar and tar files) configured on the
environment, or an empty array if none are configured.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/)

