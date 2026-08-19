---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 08/18/2026
PlatyPS schema version: 2024-05-01
title: New-FabricTopologyConfig
---

# New-FabricTopologyConfig

## SYNOPSIS

Generates a Fabric topology configuration object from input parameters.

## SYNTAX

### __AllParameterSets

```
New-FabricTopologyConfig [-Project] <string> [-WorkspaceTypes] <string[]> [-Environments] <string[]>
 [-CapacityMap] <hashtable> [[-GitProvider] <string>] [[-GitOrganisation] <string>]
 [[-GitProject] <string>] [[-GitEnvironment] <string>] [[-GitWorkspaceConfig] <hashtable>]
 [[-EnableIdentity] <string[]>] [[-EnableMonitoring] <string[]>] [[-RoleAssignments] <hashtable[]>]
 [[-EnablePipelines] <string[]>] [[-PipelineRoleAssignments] <hashtable[]>]
 [[-EnableEnvironments] <string[]>] [[-EnvironmentStages] <hashtable>]
 [[-EnvironmentRuntimeVersion] <string>] [[-TypeShortCodes] <hashtable>]
 [[-EnvShortCodes] <hashtable>] [[-OutputPath] <string>] [-SetEnvironmentAsDefault]
```

## ALIASES

## DESCRIPTION

Produces a structured config describing all workspaces, environments, naming convention,
Git settings, and identity requirements.
The output can be passed directly to
Invoke-FabricSetup, or serialised to JSON for version control.

Git integration is designed for a single environment (typically Dev) and is opt-in per
workspace type.
Each workspace type that needs Git specifies its own repository, folder,
and branch via -GitWorkspaceConfig.

## EXAMPLES

### EXAMPLE 1

New-FabricTopologyConfig `
  -Project             "SalesAnalytics" `
  -WorkspaceTypes      @("ETL","Reporting") `
  -Environments        @("Dev","Test","Acceptance","Production") `
  -CapacityMap         @{ Dev="cap-dev"; Test="cap-test"; Acceptance="cap-acc"; Production="cap-prod" } `
  -GitProvider         "AzureDevOps" `
  -GitOrganisation     "contoso" `
  -GitProject          "SalesAnalytics" `
  -GitEnvironment      "Dev" `
  -GitWorkspaceConfig  @{
      ETL       = @{ RepositoryName = "salesanalytics-etl"; Branch = "develop" }
      Reporting = @{ RepositoryName = "salesanalytics-reporting" }
  } `
  -EnableIdentity      @("ETL") `
  -EnableMonitoring    @("ETL","Reporting") `
  -OutputPath          "./topology.json"

## PARAMETERS

### -CapacityMap

Hashtable mapping each environment name to its Fabric capacity name.
E.g.
@{ Dev="cap-dev"; Test="cap-test"; Acceptance="cap-acc"; Production="cap-prod" }

```yaml
Type: System.Collections.Hashtable
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

### -EnableEnvironments

Array of workspace type names that should have a Fabric Spark Environment provisioned
(one environment per workspace).
Defaults to no workspace types (opt-in).

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 14
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -EnableIdentity

Array of workspace type names that should have Workspace Identity provisioned.
Defaults to all workspace types.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 9
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -EnableMonitoring

Array of workspace type names that should have monitoring enabled.
Defaults to no workspace types (opt-in).

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 10
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -EnablePipelines

Array of workspace type names that should have a Fabric deployment pipeline created.
Each pipeline spans all environments in order, with one stage per environment.
Defaults to no workspace types (opt-in).

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 12
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -EnvironmentRuntimeVersion

Spark runtime version used for provisioned environments.
Default: 1.3.

```yaml
Type: System.String
DefaultValue: 1.3
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 16
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Environments

Array of environment names.
Any name is accepted.
Dev, Test, Acceptance, and Production have built-in display short codes (DEV, TEST, ACC, PROD);
any other name is uppercased with whitespace removed to form its short code,
unless overridden via -EnvShortCodes.

```yaml
Type: System.String[]
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

### -EnvironmentStages

Optional hashtable keyed by workspace type name, restricting which environments (stages)
get a Spark Environment for that type.
Each value is an array of environment names.
Only meaningful for types listed in -EnableEnvironments.
A type that is environment-enabled
but absent from this hashtable gets a Spark Environment in every environment (the default).
E.g.
@{ ETL = @('Dev','Production'); Reporting = @('Production') }

```yaml
Type: System.Collections.Hashtable
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 15
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -EnvShortCodes

Optional hashtable mapping environment names to the display short code used in workspace names.
Overrides built-in defaults and the generated fallback.
E.g.
@{ Staging = 'STG' }.

```yaml
Type: System.Collections.Hashtable
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 18
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -GitEnvironment

The single environment name where Git integration is enabled (e.g.
"Dev").
Defaults to "Dev".
Set to an empty string to disable Git for all workspaces.

```yaml
Type: System.String
DefaultValue: Dev
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 7
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -GitOrganisation

Azure DevOps organisation name (or GitHub owner name).
Required when -GitWorkspaceConfig is specified.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 5
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -GitProject

Azure DevOps project name.
Required when -GitProvider is AzureDevOps and -GitWorkspaceConfig is specified.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -GitProvider

Git provider: AzureDevOps or GitHub.
Required when -GitWorkspaceConfig is specified.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 4
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -GitWorkspaceConfig

Hashtable keyed by workspace type name.
Only types present here get Git integration.
Each entry is a hashtable with:
  RepositoryName  (required) — the Git repository name
  RootFolder      (optional) — root folder within the repo; defaults to "fabric"
  Branch          (optional) — branch to connect; defaults to "main"
E.g.
@{
    ETL       = @{ RepositoryName = "salesanalytics-etl"; Branch = "develop" }
    Reporting = @{ RepositoryName = "salesanalytics-reporting"; RootFolder = "reporting" }
}

```yaml
Type: System.Collections.Hashtable
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 8
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -OutputPath

Optional file path to write the generated config as JSON.
If omitted, the config object is returned only.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 19
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PipelineRoleAssignments

Array of role assignment rules to apply to deployment pipelines.
Each rule is a hashtable with:
  PrincipalId    (required) — Entra object ID of the group, user, or service principal
  PrincipalType  (required) — Group, User, or ServicePrincipal
  Role           (optional) — only 'Admin' is supported by Fabric deployment pipelines; defaults to 'Admin'
  WorkspaceTypes (optional) — array of workspace type names this rule applies to; omit for all types
Pipelines span all environments, so these rules are not environment-scoped.
Each rule is
resolved per workspace type and stored on the workspace's pipeline block in the topology config.

```yaml
Type: System.Collections.Hashtable[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 13
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Project

Project name used as the first segment of every workspace name (e.g.
"SalesAnalytics").
Casing is preserved as-is; only characters outside [A-Za-z0-9-] are replaced with hyphens.

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

### -RoleAssignments

Array of role assignment rules to apply to workspaces.
Each rule is a hashtable with:
  PrincipalId    (required) — Entra object ID of the group, user, or service principal
  PrincipalType  (required) — Group, User, or ServicePrincipal
  Role           (required) — Admin, Contributor, Member, or Viewer
  WorkspaceTypes (optional) — array of workspace type names this rule applies to; omit for all types
  Environments   (optional) — array of environment names this rule applies to; omit for all environments
Each rule is resolved per workspace type and environment and stored in the topology config.

```yaml
Type: System.Collections.Hashtable[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 11
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SetEnvironmentAsDefault

When set, environment-enabled workspaces have their environment registered as the
workspace default (so notebooks/jobs using "Workspace default" inherit it).

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

### -TypeShortCodes

Optional hashtable mapping workspace type names to the display short code used in workspace names.
Overrides built-in defaults and the generated fallback.
E.g.
@{ Lakehouse = 'LH' }.

```yaml
Type: System.Collections.Hashtable
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 17
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -WorkspaceTypes

Array of workspace type names to provision.
Any name is accepted.
Bronze, Silver, Gold, ETL, Storage, and Reporting have built-in display short codes;
any other name uses the name itself (with whitespace removed) as its short code,
unless overridden via -TypeShortCodes.

```yaml
Type: System.String[]
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

### System.Management.Automation.PSObject

A topology configuration object describing all workspaces, environments, naming convention, Git, identity, monitoring, pipeline, environment, and role assignment settings.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/)
