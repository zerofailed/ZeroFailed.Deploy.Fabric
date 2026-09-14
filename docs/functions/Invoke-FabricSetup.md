---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 09/18/2026
PlatyPS schema version: 2024-05-01
title: Invoke-FabricSetup
---

# Invoke-FabricSetup

## SYNOPSIS

Orchestrates the full Fabric workspace provisioning pipeline from a topology config.

## SYNTAX

### Object (Default)

```
Invoke-FabricSetup [-Config] <psobject> [-Environment <string>] [-SkipGit] [-SkipIdentity]
 [-SkipMonitoring] [-SkipEnvironment] [-SkipVariableLibrary] [-SkipRbac] [-WhatIf] [-Confirm]
```

### File

```
Invoke-FabricSetup -ConfigPath <string> [-Environment <string>] [-SkipGit] [-SkipIdentity]
 [-SkipMonitoring] [-SkipEnvironment] [-SkipVariableLibrary] [-SkipRbac] [-WhatIf] [-Confirm]
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
Provisions Workspace Identity and grants it Contributor on the workspace (if enabled)
  6.
Enables workspace monitoring (if enabled)
  7.
Provisions a Spark Environment and (optionally) sets it as workspace default (if enabled
     for the type and the current environment is in the type's configured stages)
  8.
Provisions a Variable Library (if enabled for the type and the current environment is in the
     type's configured stages) and, if default values are enabled, populates the default variables
     in a value set for the current stage and activates it
  9.
Applies RBAC role assignments (if configured)
Returns a structured results object with a summary, identity report, monitoring report,
environment report, variable library report, role assignment report, and failure details.

Deployment pipelines span every environment, so they are not configured here: run
Invoke-FabricDeploymentPipelineSetup once each environment's workspaces have been provisioned.

## EXAMPLES

### EXAMPLE 1

Invoke-FabricSetup -Config $topology -Environment "Dev" -WhatIf

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

### -Environment

Single environment name to process.
Defaults to all environments in config.

```yaml
Type: System.String
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

### -SkipManagedPrivateEndpoints

Skip managed private endpoint creation for all workspaces.

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

### -SkipVariableLibrary

Skip Variable Library provisioning for all workspaces.

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

A results object with a summary and the identity, monitoring, environment, variable library, role assignment, and failure reports for the provisioning run.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/)
