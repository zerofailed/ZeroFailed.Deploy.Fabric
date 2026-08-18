---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: ''
Locale: en-GB
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 08/18/2026
PlatyPS schema version: 2024-05-01
title: Add-FabricEnvironmentLibrary
---

# Add-FabricEnvironmentLibrary

## SYNOPSIS

Uploads a single library file (.whl, .tar.gz, .jar, .py) to a Fabric environment's staging area.

## SYNTAX

### __AllParameterSets

```
Add-FabricEnvironmentLibrary [-WorkspaceId] <string> [-EnvironmentId] <string> [-FilePath] <string>
 [-Token] <string> [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Uploads the file to the environment's staging libraries via
POST /workspaces/{id}/environments/{id}/staging/libraries (multipart/form-data).

Uploading places the file in staging only — it is not usable by notebooks/jobs until the
environment is published (see Publish-FabricEnvironment).
The maximum file size is 200 MB.

Re-uploading a file with the same name overwrites the existing staged copy, so this is safe
to call repeatedly.

## EXAMPLES

### EXAMPLE 1

Add-FabricEnvironmentLibrary -WorkspaceId $ws.id -EnvironmentId $env.id `
    -FilePath './dist/mypackage-1.4.2-py3-none-any.whl' -Token $token

Uploads the wheel into the environment's staging libraries.

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

The Fabric environment GUID to upload the library into.

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

### -FilePath

Path to the library file to upload.

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

A hashtable with keys: EnvironmentId, FileName, and Action ('Uploaded' or 'whatif').

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/)

