---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/
Locale: en-GB
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 09/10/2026
PlatyPS schema version: 2024-05-01
title: Get-FabricTopologyState
---

# Get-FabricTopologyState

## SYNOPSIS

Discovers the current state of a Fabric topology using read-only lookups, with no changes.

## SYNTAX

### Object (Default)

```
Get-FabricTopologyState [-Config] <psobject> [-Environments <string[]>] [-SkipGit] [-SkipIdentity]
 [-SkipEnvironment] [-SkipPipeline] [<CommonParameters>]
```

### File

```
Get-FabricTopologyState -ConfigPath <string> [-Environments <string[]>] [-SkipGit] [-SkipIdentity]
 [-SkipEnvironment] [-SkipPipeline] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

The read-only counterpart to Invoke-FabricSetup.
It walks the same topology config but issues
only Fabric REST GETs — it never creates or mutates a workspace, identity, Spark environment
or deployment pipeline, never calls MicrosoftFabricMgmt, and does not resolve the deploying
identity.

It returns the same result-object model as Invoke-FabricSetup:
  - Workspaces        : one record per workspace type x environment (Type, Environment, Name,
                        WorkspaceId, CapacityName, Status, GitConnected, Identity,
                        SparkEnvironment).
Status is 'Existing' or 'NotFound'.
  - WorkspacesByType  : the same records indexed as .<type>.<environment>.
  - Identities        : one entry per workspace whose Workspace Identity was found.
  - Environments      : one entry per resolved Spark Environment.
  - Pipelines         : one entry per pipeline-enabled workspace type, with a Stages map
                        (environment -> assigned workspace id) and Action 'Existing'/'NotFound'.
  - Failures          : non-fatal per-lookup errors.
  - Monitoring, RoleAssignments, PipelineRoleAssignments : always empty — there is no
                        non-invasive read-only equivalent.

The Summary differs from Invoke-FabricSetup: it reports @{ Found; Missing; Failed } (workspace
discovery counts) rather than @{ Created; Skipped; Failed }.

Intended use: a deployment pipeline that runs separately from provisioning can call this (or
the 'resolveFabricTopologyState' task) to populate $FabricProvisioningResult with real
workspace / identity / environment / pipeline IDs without deploying anything.

## EXAMPLES

### EXAMPLE 1

$state = Get-FabricTopologyState -Config $topology

Discovers the full current state of every workspace and pipeline in the topology.

### EXAMPLE 2

$state = Get-FabricTopologyState -ConfigPath "./topology.json" -Environments @("Dev") -SkipPipeline

Discovers only the Dev workspaces (workspace id, identity, environment, git), skipping pipelines.

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

### -Environments

Subset of environment names to inspect.
Defaults to all environments in config.
Subset of environment names to inspect.
Defaults to all environments in config.
Subset of environment names to inspect.
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

Skip the per-workspace Spark Environment lookup (SparkEnvironment stays $null).

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

Skip the per-workspace Git connection lookup (GitConfig stays $false).

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

Skip the per-workspace Workspace Identity lookup (Identity stays $null).

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

Skip the deployment pipeline lookups (Pipelines stays empty).

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

### System.Management.Automation.PSObject

A results object with a Found/Missing/Failed summary, the per-workspace model (Workspaces and WorkspacesByType), and the identity, environment, pipeline and failure reports discovered by read-only lookups. Monitoring, RoleAssignments and PipelineRoleAssignments are always empty.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/)
