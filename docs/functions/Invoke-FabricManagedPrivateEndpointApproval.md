---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: ''
Locale: en-GB
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 09/23/2026
PlatyPS schema version: 2024-05-01
title: Invoke-FabricManagedPrivateEndpointApproval
---

# Invoke-FabricManagedPrivateEndpointApproval

## SYNOPSIS

Approves the private endpoint connections requested by a topology's managed private endpoints.

## SYNTAX

### Object (Default)

```
Invoke-FabricManagedPrivateEndpointApproval [-Config] <psobject> [-Environment <string>]
 [-EndpointNamePattern <string>] [-TimeoutSeconds <int>] [-PollIntervalSeconds <int>] [-FailOnError]
 [-WhatIf] [-Confirm] [<CommonParameters>]
```

### File

```
Invoke-FabricManagedPrivateEndpointApproval -ConfigPath <string> [-Environment <string>]
 [-EndpointNamePattern <string>] [-TimeoutSeconds <int>] [-PollIntervalSeconds <int>] [-FailOnError]
 [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Creating a managed private endpoint only sends a private link connection request to the target
Azure resource; the endpoint cannot be used until the resource's owner approves it.
For each
managed private endpoint in the topology config, this:
  1.
Finds the endpoint on its workspace, waiting for it to finish provisioning
  2.
Skips it when its connection is already approved
  3.
Otherwise approves the connection on the target resource, via
     ZeroFailed.Deploy.Azure's Assert-PrivateEndpointConnectionApproval
Returns a structured results object with a summary, approval report and failure details.

This runs separately from Invoke-FabricSetup because approving a connection needs permission on
the target Azure resource (`privateEndpointConnectionsApproval/action`, included in Owner and
Contributor), which the identity provisioning the workspaces often does not have.
By default a
failed approval is reported as a failure and leaves the connection pending, so provisioning is
not blocked by it; use -FailOnError to fail instead.

Fabric names the private endpoint it creates on the target resource after the managed private
endpoint, prefixed with the workspace id.
The connection to approve is identified by matching
that name against -EndpointNamePattern.

## EXAMPLES

### EXAMPLE 1

Invoke-FabricManagedPrivateEndpointApproval -Config $topology -Environment 'Dev'

Approves the connections for the Dev workspaces' managed private endpoints.

### EXAMPLE 2

Invoke-FabricManagedPrivateEndpointApproval -ConfigPath './topology.json' -WhatIf

Reports what would be approved, without approving anything.

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

### -EndpointNamePattern

Wildcard pattern identifying the private endpoint on the target resource, with the tokens
{workspaceId} and {name} (the managed private endpoint's name).
Defaults to
'*{workspaceId}*{name}'.
Wildcard pattern identifying the private endpoint on the target resource, with the tokens
{workspaceId} and {name} (the managed private endpoint's name).
Defaults to
'*{workspaceId}*{name}'.

```yaml
Type: System.String
DefaultValue: '*{workspaceId}*{name}'
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

### -Environment

Single environment name to process.
Defaults to every environment in the config.
Single environment name to process.
Defaults to every environment in the config.

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

### -FailOnError

Throw at the end when any endpoint could not be approved, rather than reporting it as a failure.

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

### -PollIntervalSeconds

How long to wait between checks.
Default: 15.
How long to wait between checks.
Default: 15.

```yaml
Type: System.Int32
DefaultValue: 15
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

### -TimeoutSeconds

How long to wait for each endpoint to finish provisioning, for its connection to appear on the
target resource, and for an approval to take effect.
Default: 600.
How long to wait for each endpoint to finish provisioning, for its connection to appear on the
target resource, and for an approval to take effect.
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

A results object with a summary of endpoints by action, and the approval and failure reports for the run.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/core/managed-private-endpoints)
- [](https://github.com/zerofailed/ZeroFailed.Deploy.Azure)

