---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/core/deployment-pipelines
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 09/21/2026
PlatyPS schema version: 2024-05-01
title: Invoke-FabricDeploymentPipelineSetup
---

# Invoke-FabricDeploymentPipelineSetup

## SYNOPSIS

Creates or updates Fabric deployment pipelines from a topology config.

## SYNTAX

### Object (Default)

```
Invoke-FabricDeploymentPipelineSetup [-Config] <psobject> [-SkipPipelineRbac] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

### File

```
Invoke-FabricDeploymentPipelineSetup -ConfigPath <string> [-SkipPipelineRbac] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

For each workspace type with pipelines enabled in the config:
  1.
Creates or updates the deployment pipeline, with one stage per environment, and assigns
     each environment's workspace to its stage
  2.
Applies deployment pipeline role assignments (if configured)
Returns a structured results object with a summary, pipeline report, pipeline role assignment
report, and failure details.

Deployment pipelines span every environment, so this runs separately from Invoke-FabricSetup —
typically as a dedicated pipeline stage once each environment's workspaces have been
provisioned.
The identity running it must be able to see every workspace, and assigning a
workspace to a pipeline stage requires workspace Admin: grant this through the topology's
role assignments for every environment.
A workspace type whose workspaces cannot all be found
is recorded as a failure and its pipeline is left untouched.

## EXAMPLES

### EXAMPLE 1

Invoke-FabricDeploymentPipelineSetup -Config $topology -WhatIf

Simulates deployment pipeline setup for every pipeline-enabled workspace type.

### EXAMPLE 2

Invoke-FabricDeploymentPipelineSetup -ConfigPath "./topology.json" -SkipPipelineRbac

Creates or updates the deployment pipelines from a saved topology config, without applying
pipeline role assignments.

## PARAMETERS

### -Config

Topology config object produced by New-FabricTopologyConfig.

```yaml
Type: System.Management.Automation.PSObject
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Object
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ConfigPath

Path to a JSON file containing the topology config (alternative to -Config).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: File
  Position: Named
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

### -SkipPipelineRbac

Skip deployment pipeline role assignment application for all workspace types.

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

A results object with a summary of pipelines by action, and the pipeline, pipeline role assignment, and failure reports for the run.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/core/deployment-pipelines)
