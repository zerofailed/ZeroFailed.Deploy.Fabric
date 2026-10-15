---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: ''
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 10/15/2026
PlatyPS schema version: 2024-05-01
title: Invoke-FabricPythonLibraryDeploy
---

# Invoke-FabricPythonLibraryDeploy

## SYNOPSIS

Deploys a Python package (and its dependencies) into a Fabric Spark Environment.

## SYNTAX

### __AllParameterSets

```
Invoke-FabricPythonLibraryDeploy [-WorkspaceName] <string> [-EnvironmentName] <string>
 [-PackageName] <string> [-PackageVersion] <string> [-FeedOrganisation] <string>
 [-FeedProject] <string> [-FeedName] <string> [-FeedToken] <string> [[-StagingPath] <string>]
 [[-ConstraintsPath] <string>] [[-PrivatePackageName] <string[]>] [[-ExtraIndexUrl] <string>]
 [[-PythonExecutable] <string>] [[-TargetPythonVersion] <string>] [[-TargetPlatform] <string>]
 [[-PublishTimeoutSeconds] <int>] [-SkipDownload] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

The Python-library counterpart to Invoke-FabricSetup, intended to run after provisioning as a
separate pipeline (typically from the repo that builds the package).
For a single target
workspace and Spark Environment it:
  1.
Downloads the named package plus its full dependency closure from an Azure Artifacts
     feed, via Save-FabricLibraryPackage.
  2.
Splits the closure into private packages (feed-only) and public packages (resolvable on
     PyPI).
Private packages are uploaded as custom libraries; public packages are declared
     in an environment.yml for Fabric to resolve from PyPI directly.
This keeps large public
     binary wheels out of the custom-library upload path, whose size limit a big wheel (e.g.
     deltalake, ~50 MB) exceeds with a server-side 500.
Classification is automatic via a
     PyPI lookup per package, unless -PrivatePackageName is supplied.
  3.
Resolves the workspace and its Spark Environment by display name.
Both must already
     exist from provisioning.
  4.
Clears down staged custom libraries not in the private set, imports the environment.yml
     external libraries (which overrides the whole external set), uploads the private custom
     wheels, and publishes — unless the desired custom and external sets are already
     published (idempotent) and -Force is not set.

No topology config is needed: the workspace and environment are named directly, and the
package coordinates and feed are supplied as parameters so versions can flow from the build.
To deploy the same package into several environments, call this once per target, passing the
same -StagingPath with -SkipDownload on the later calls to reuse the first download.

Any failure (including a missing workspace or environment) is terminating.

## EXAMPLES

### EXAMPLE 1

Invoke-FabricPythonLibraryDeploy `
    -WorkspaceName 'THX-DataPrep [DEV]' -EnvironmentName 'THX-DataPrep Env' `
    -PackageName mycompany.dataprep -PackageVersion 1.4.2 `
    -FeedOrganisation contoso -FeedProject Analytics -FeedName fabric-python `
    -FeedToken $env:SYSTEM_ACCESSTOKEN

Deploys mycompany.dataprep 1.4.2 into the 'THX-DataPrep Env' Spark Environment of the
'THX-DataPrep [DEV]' workspace.

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

### -ConstraintsPath

Path to a pip constraints file pinning versions in the dependency closure.
It lives in the
calling repo.
Ignored when -SkipDownload is set.

```yaml
Type: System.String
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

### -EnvironmentName

The display name of the target Spark Environment within the workspace, e.g.
'THX-DataPrep Env'.

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
  Position: 11
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
  Position: 6
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
  Position: 4
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
  Position: 5
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
  Position: 7
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
  Position: 2
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
  Position: 3
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PrivatePackageName

The package names that are private (feed-only) and must be uploaded as custom libraries;
every other package in the closure is treated as public and declared in environment.yml.
Names are matched case-insensitively with PEP 503 normalisation.
When omitted, each package
is classified automatically by looking it up on PyPI (present at that version = public).

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

### -PublishTimeoutSeconds

Maximum seconds to wait for the environment publish.
Default: 600.

```yaml
Type: System.Int32
DefaultValue: 600
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
  Position: 12
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
  Position: 8
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
  Position: 14
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

```yaml
Type: System.String
DefaultValue: 3.11
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

### -WorkspaceName

The display name of the target Fabric workspace, e.g.
'THX-DataPrep [DEV]'.

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

### System.Management.Automation.PSObject

A single result object for the target: WorkspaceName, EnvironmentName, EnvironmentId, Files (the
private wheels uploaded as custom libraries), ExternalLibraries (the public packages declared in
environment.yml, as name==version), Removed (staged custom libraries that were cleared down) and
Action (Published, Skipped or whatif).

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/)
