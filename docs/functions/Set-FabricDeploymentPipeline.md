---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/core/deployment-pipelines
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 08/18/2026
PlatyPS schema version: 2024-05-01
title: Set-FabricDeploymentPipeline
---

# Set-FabricDeploymentPipeline

## SYNOPSIS

Creates or updates a Fabric deployment pipeline for a workspace type across all environments.

## SYNTAX

### __AllParameterSets

```
Set-FabricDeploymentPipeline [-Config] <psobject> [-WorkspaceType] <string> [-Token] <string>
 [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Provisions a deployment pipeline for a single workspace type.
Each environment in the
topology config becomes a named stage in the pipeline.
Workspaces are assigned to stages
where they exist; stages for environments whose workspaces have not yet been provisioned
are left unassigned and can be assigned on a subsequent run.

Idempotent: safe to call on an existing pipeline.
Already-assigned stages are skipped.
If a stage is already assigned to a different workspace, a warning is emitted.

## EXAMPLES

### EXAMPLE 1

Set-FabricDeploymentPipeline -Config $topology -WorkspaceType 'Bronze' -Token $token

Creates or updates the deployment pipeline for the Bronze workspace type across all environments.

## PARAMETERS

### -Config

The topology config object produced by New-FabricTopologyConfig.

```yaml
Type: System.Management.Automation.PSObject
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

### -WorkspaceType

The workspace type name to create the pipeline for (e.g.
"Bronze").
The workspace type name to create the pipeline for (e.g.
"Bronze").

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

A report entry with the pipeline name and ID, the workspace type, the number of stages assigned, and the action taken (created or updated).

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/core/deployment-pipelines)
