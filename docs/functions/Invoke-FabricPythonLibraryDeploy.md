---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: ''
Locale: en-GB
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 08/18/2026
PlatyPS schema version: 2024-05-01
title: Invoke-FabricPythonLibraryDeploy
---

# Invoke-FabricPythonLibraryDeploy

## SYNOPSIS

Deploys a Python package (and its dependencies) into the Fabric Spark Environments of a stage.

## SYNTAX

### Object (Default)

```
Invoke-FabricPythonLibraryDeploy [-Config] <psobject> -Stage <string> -PackageName <string>
 -PackageVersion <string> -FeedOrganisation <string> -FeedProject <string> -FeedName <string>
 -FeedToken <string> [-StagingPath <string>] [-ConstraintsPath <string>] [-SkipDownload] [-Force]
 [-ExtraIndexUrl <string>] [-PythonExecutable <string>] [-TargetPythonVersion <string>]
 [-TargetPlatform <string>] [-PublishTimeoutSeconds <int>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### File

```
Invoke-FabricPythonLibraryDeploy -ConfigPath <string> -Stage <string> -PackageName <string>
 -PackageVersion <string> -FeedOrganisation <string> -FeedProject <string> -FeedName <string>
 -FeedToken <string> [-StagingPath <string>] [-ConstraintsPath <string>] [-SkipDownload] [-Force]
 [-ExtraIndexUrl <string>] [-PythonExecutable <string>] [-TargetPythonVersion <string>]
 [-TargetPlatform <string>] [-PublishTimeoutSeconds <int>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

The Python-library counterpart to Invoke-FabricSetup, intended to run after provisioning as a
separate pipeline.
For a single deployment stage it:
  1.
Downloads the named package plus its full dependency closure from an Azure Artifacts
     feed (once), via Save-FabricLibraryPackage.
  2.
For every workspace in the topology that has a Spark Environment enabled for the given
     stage, resolves the workspace and its environment for that stage.
  3.
Clears down any staged custom libraries that are not part of the downloaded set, so
     previous versions cannot conflict with the ones being deployed.
  4.
Uploads the downloaded files to the environment's custom (staging) libraries and
     publishes, unless exactly those files are already published (idempotent) and -Force
     is not set.

Stages are owned by the calling pipeline: this runs one stage per invocation.
The topology
config is used only to resolve workspace and environment names — the package coordinates and
feed are supplied as parameters so versions can flow from the build.

Per-workspace failures are non-fatal and collected; the function throws at the end if any
workspace failed, so the pipeline step fails while still attempting every target.

## EXAMPLES

### EXAMPLE 1

Invoke-FabricPythonLibraryDeploy -ConfigPath ./topology.json -Stage DEV `
    -PackageName mycompany.dataprep -PackageVersion 1.4.2 `
    -FeedOrganisation contoso -FeedProject Analytics -FeedName fabric-python `
    -FeedToken $env:SYSTEM_ACCESSTOKEN

Deploys mycompany.dataprep 1.4.2 into every Spark Environment in the DEV stage.

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

Path to a JSON topology config file (alternative to -Config).

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

### -ConstraintsPath

Path to a pip constraints file pinning versions in the dependency closure.
Like -ConfigPath,
it lives in the calling repo.
Ignored when -SkipDownload is set.

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

### -ExtraIndexUrl

Secondary package index for dependencies not in the feed.
Default: PyPI.

```yaml
Type: System.String
DefaultValue: https://pypi.org/simple
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

### -FeedName

The Azure Artifacts feed name.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -FeedOrganisation

The Azure DevOps organisation hosting the Artifacts feed.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -FeedProject

The Azure DevOps project hosting the Artifacts feed.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -FeedToken

Bearer token / PAT with Feed Reader access (e.g.
the pipeline's System.AccessToken).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Force

Upload and publish even when the desired files are already published.

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

### -PackageName

The package (distribution) name to deploy, e.g.
'mycompany.dataprep'.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PackageVersion

The exact package version to deploy, e.g.
'1.4.2'.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PublishTimeoutSeconds

Maximum seconds to wait for each environment publish.
Default: 600.

```yaml
Type: System.Int32
DefaultValue: 600
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

### -PythonExecutable

The python executable to use for downloading.
Default: 'python'.

```yaml
Type: System.String
DefaultValue: python
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

### -SkipDownload

Skip the pip download and use the files already present in -StagingPath.

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

### -Stage

The single environment/stage name (as defined in config.environments) to deploy into.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -StagingPath

Directory used to download packages into.
Defaults to a new temp directory.

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

### -TargetPlatform

The platform tag wheels are resolved for.
Default: 'manylinux2014_x86_64'.

```yaml
Type: System.String
DefaultValue: manylinux2014_x86_64
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

### -TargetPythonVersion

The Python version of the target Fabric Spark runtime that wheels are resolved for.
Default: '3.11' (Fabric runtime 1.3).
Use '3.10' for runtime 1.2.
Because the download
happens once for the whole stage, all target workspaces must share a runtime version.

```yaml
Type: System.String
DefaultValue: 3.11
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

A results object with a Summary (Deployed/Skipped/Failed counts), a Deployed list of per-workspace
deployment details, and a Failures list of any non-fatal per-workspace errors.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/)

