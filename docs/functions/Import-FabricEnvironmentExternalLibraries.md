---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: ''
Locale: en-GB
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 08/25/2026
PlatyPS schema version: 2024-05-01
title: Import-FabricEnvironmentExternalLibraries
---

# Import-FabricEnvironmentExternalLibraries

## SYNOPSIS

Imports the external (public) libraries of a Fabric environment from an environment.yml.

## SYNTAX

### __AllParameterSets

```
Import-FabricEnvironmentExternalLibraries [-WorkspaceId] <string> [-EnvironmentId] <string>
 [-EnvironmentYml] <string> [-Token] <string> [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Uploads an environment.yml describing public PyPI/conda packages to the environment's staging area
via POST /workspaces/{id}/environments/{id}/staging/libraries/importExternalLibraries.
The call OVERRIDES the whole external library list, so the supplied document is the complete
desired set — stale external libraries are removed automatically on the next publish.

Like custom library uploads, this stages only; the environment must be published (see
Publish-FabricEnvironment) for the changes to take effect.
The document is sent as the raw request body via _Invoke-FabricFileUpload, which also gives it
retry-on-5xx behaviour.

## EXAMPLES

### EXAMPLE 1

Import-FabricEnvironmentExternalLibraries -WorkspaceId $ws.id -EnvironmentId $env.id `
    -EnvironmentYml $yml -Token $token

Replaces the environment's staged external libraries with those declared in $yml.

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

The Fabric environment GUID to import into.

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

### -EnvironmentYml

The environment.yml content (as a string) listing the public libraries.

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

A hashtable with keys: EnvironmentId and Action ('Imported' or 'whatif').

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/)
