---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/core/deployment-pipelines/add-deployment-pipeline-role-assignment
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 08/18/2026
PlatyPS schema version: 2024-05-01
title: Set-FabricDeploymentPipelineRoleAssignment
---

# Set-FabricDeploymentPipelineRoleAssignment

## SYNOPSIS

Applies a single role assignment to a Fabric deployment pipeline idempotently.

## SYNTAX

### __AllParameterSets

```
Set-FabricDeploymentPipelineRoleAssignment [-PipelineId] <string> [-PipelineName] <string>
 [-Token] <string> [-PrincipalId] <string> [-PrincipalType] <string> [[-Role] <string>] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Checks the current role assignments on a deployment pipeline, then:
  - Skips if the principal already holds the role (idempotent)
  - Creates the assignment via POST if the principal has no current assignment
Supports Entra Group, User, and Service Principal object IDs.

Fabric deployment pipelines only support the 'Admin' role, so an existing principal already holds
the only available role and the assignment is skipped.

## EXAMPLES

### EXAMPLE 1

Set-FabricDeploymentPipelineRoleAssignment -PipelineId $pipe.id -PipelineName 'SalesAnalytics-Bronze Pipeline' -PrincipalId $groupId -PrincipalType 'Group' -Token $token

Ensures the given Entra group holds the Admin role on the deployment pipeline, applying the change idempotently.

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

### -PipelineId

The Fabric deployment pipeline GUID.

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

### -PipelineName

Display name used in log messages and the returned report entry.

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

### -PrincipalId

The Entra object ID of the group, user, or service principal to assign.

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

### -PrincipalType

The type of principal: Group, User, or ServicePrincipal.

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
AcceptedValues:
- Group
- User
- ServicePrincipal
HelpMessage: ''
```

### -Role

The deployment pipeline role to assign. Only 'Admin' is supported. Defaults to 'Admin'.
The deployment pipeline role to assign.
Only 'Admin' is supported.
Defaults to 'Admin'.

```yaml
Type: System.String
DefaultValue: Admin
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
AcceptedValues:
- Admin
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Collections.Hashtable

A report entry with the pipeline name and ID, the principal ID and type, the role, and the action taken (skipped or created).

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/core/deployment-pipelines/add-deployment-pipeline-role-assignment)
