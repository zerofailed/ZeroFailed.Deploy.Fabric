---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: ''
Locale: en-GB
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 08/18/2026
PlatyPS schema version: 2024-05-01
title: Save-FabricLibraryPackage
---

# Save-FabricLibraryPackage

## SYNOPSIS

Downloads a Python package and its full dependency closure from an Azure Artifacts feed.

## SYNTAX

### __AllParameterSets

```
Save-FabricLibraryPackage [-PackageName] <string> [-PackageVersion] <string>
 [-FeedOrganisation] <string> [-FeedProject] <string> [-FeedName] <string> [-FeedToken] <string>
 [-DestinationPath] <string> [[-ConstraintsPath] <string>] [[-ExtraIndexUrl] <string>]
 [[-PythonExecutable] <string>] [[-TargetPythonVersion] <string>] [[-TargetPlatform] <string>]
 [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Runs 'pip download' against an Azure DevOps Artifacts feed to fetch the named package at the
given version, plus every transitive dependency, into a destination directory.
pip resolves
the dependency graph from the package metadata in the feed — no dependency list is required.

Dependencies not present in the feed are resolved from the -ExtraIndexUrl (PyPI by default),
which relies on the feed being configured with upstream sources or the build agent having
outbound access to PyPI.

Wheels are resolved for the *target* Fabric Spark runtime, not for the build agent.
Without
this, pip would select wheels matching the agent's interpreter (e.g.
a cp312 wheel on a
Python 3.12 agent), and any dependency with a compiled C extension would fail to import
inside Fabric.
Fabric runtime 1.2 runs Python 3.10; runtime 1.3 runs Python 3.11.

Because pip cannot build an sdist for a foreign platform, cross-targeting requires
--only-binary=:all:.
A dependency that publishes no wheel for the target therefore fails the
download rather than silently shipping something unusable.

The feed is authenticated with a bearer token / PAT embedded in the index URL as the
password of a 'build' user.
The URL is never logged.
Returns the FileInfo objects for the
downloaded wheel files, ready to hand to Add-FabricEnvironmentLibrary.

## EXAMPLES

### EXAMPLE 1

Save-FabricLibraryPackage -PackageName 'mycompany.dataprep' -PackageVersion '1.4.2' `
    -FeedOrganisation 'contoso' -FeedProject 'Analytics' -FeedName 'fabric-python' `
    -FeedToken $env:SYSTEM_ACCESSTOKEN -DestinationPath './.packages'

Downloads the wheel and all dependency wheels into ./.packages and returns them.

### EXAMPLE 2

Save-FabricLibraryPackage ... -TargetPythonVersion '3.10'

Resolves wheels for Fabric Spark runtime 1.2 (Python 3.10) instead of the 1.3 default.

### EXAMPLE 3

Save-FabricLibraryPackage ... -ConstraintsPath './fabric/constraints.txt'

Pins transitive dependency versions to those listed in the constraints file.

## PARAMETERS

### -ConstraintsPath

Path to a pip constraints file pinning versions in the dependency closure.
Supplied by the
calling repo (like the topology config), not carried in this module.
Omitted by default,
in which case pip resolves versions itself.

```yaml
Type: System.String
DefaultValue: ''
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

### -DestinationPath

Directory to download the packages into.
Created if it does not exist.

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

### -ExtraIndexUrl

Secondary package index used for dependencies not in the feed.
Default: PyPI.

```yaml
Type: System.String
DefaultValue: https://pypi.org/simple
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

### -FeedName

The Azure Artifacts feed name.

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

### -FeedOrganisation

The Azure DevOps organisation that hosts the Artifacts feed.

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

### -FeedProject

The Azure DevOps project that hosts the Artifacts feed.

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
  Position: 5
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PackageName

The package (distribution) name to download, e.g.
'mycompany.dataprep'.

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

### -PackageVersion

The exact package version to download, e.g.
'1.4.2'.

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

### -PythonExecutable

The python executable to use.
Default: 'python'.

```yaml
Type: System.String
DefaultValue: python
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

### -TargetPlatform

The platform tag wheels are resolved for.
Default: 'manylinux2014_x86_64'.
Platform-independent ('any') wheels are always eligible regardless of this value.

```yaml
Type: System.String
DefaultValue: manylinux2014_x86_64
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
  Position: 10
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

### System.IO.FileInfo[]

The downloaded package file plus every file in its dependency closure.

## NOTES

## RELATED LINKS

- [](https://pip.pypa.io/en/stable/cli/pip_download/)

