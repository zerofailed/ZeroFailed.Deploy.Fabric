---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 08/18/2026
PlatyPS schema version: 2024-05-01
title: Invoke-FabricSetup
---

# Invoke-FabricSetup

## SYNOPSIS

Orchestrates the full Fabric workspace provisioning pipeline from a topology config.

## SYNTAX

### Object (Default)

```
Invoke-FabricSetup [-Config] <psobject> [-Environments <string[]>] [-SkipGit] [-SkipIdentity]
 [-SkipIdentityGroup] [-SkipMonitoring] [-SkipEnvironment] [-SkipRbac] [-SkipPipeline]
 [-SkipPipelineRbac] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### File

```
Invoke-FabricSetup -ConfigPath <string> [-Environments <string[]>] [-SkipGit] [-SkipIdentity]
 [-SkipIdentityGroup] [-SkipMonitoring] [-SkipEnvironment] [-SkipRbac] [-SkipPipeline]
 [-SkipPipelineRbac] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

For each environment x workspace combination in the config:
  1.
Resolves the workspace name via naming convention
  2.
Creates the workspace (idempotent)
  3.
Grants the deploying identity Admin on the workspace (so re-runs can resolve it)
  4.
Connects to Git (idempotent)
  5.
Provisions Workspace Identity, grants it Contributor on the workspace, and adds it to
the configured Entra security group (if enabled)
  6.
Enables workspace monitoring (if enabled)
  7.
Provisions a Spark Environment and (optionally) sets it as workspace default (if enabled)
  8.
Applies RBAC role assignments (if configured)
Then, for each workspace type with pipelines enabled:
  8.
Creates or updates the deployment pipeline across all environments
  9.
Applies deployment pipeline role assignments (if configured)
Returns a structured results object with a summary, identity report, monitoring report,
role assignment report, pipeline report, and pipeline role assignment report.

## EXAMPLES

### EXAMPLE 1

Invoke-FabricSetup -Config $topology -Environments @("Dev") -WhatIf

Runs the provisioning pipeline for the Dev environment in WhatIf mode.

### EXAMPLE 2

Invoke-FabricSetup -ConfigPath "./topology.json" -SkipGit

Runs the full provisioning pipeline from a saved topology config, skipping Git integration.

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

### -Environments

Subset of environment names to process.
Defaults to all environments in config.

```yaml
Type: System.String[]
DefaultValue: ''
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

### -SkipEnvironment

Skip Spark Environment provisioning for all workspaces.

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

### -SkipGit

Skip Git integration for all workspaces.

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

### -SkipIdentity

Skip identity provisioning for all workspaces.

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

### -SkipIdentityGroup

Skip adding provisioned Workspace Identities to the security group named by the config's
identityGroup block.

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

### -SkipMonitoring

Skip monitoring enablement for all workspaces.

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

### -SkipPipeline

Skip deployment pipeline setup for all workspace types.

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

### -SkipRbac

Skip role assignment application for all workspaces.

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

A results object with a summary and the identity, monitoring, environment, role assignment, pipeline, and failure reports for the provisioning run.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/)
