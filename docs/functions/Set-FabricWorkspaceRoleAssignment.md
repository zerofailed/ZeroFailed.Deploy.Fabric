---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/rest/api/fabric/core/workspaces/add-workspace-role-assignment
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 08/18/2026
PlatyPS schema version: 2024-05-01
title: Set-FabricWorkspaceRoleAssignment
---

# Set-FabricWorkspaceRoleAssignment

## SYNOPSIS

Applies a single RBAC role assignment to a Fabric workspace idempotently.

## SYNTAX

### __AllParameterSets

```
Set-FabricWorkspaceRoleAssignment [-WorkspaceId] <string> [-WorkspaceName] <string>
 [-Token] <string> [-PrincipalId] <string> [-PrincipalType] <string> [-Role] <string> [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Checks the current role assignments on a workspace, then:
  - Skips if the principal already holds the target role (idempotent)
  - Updates the role via PATCH if the principal exists with a different role
  - Creates the assignment via POST if the principal has no current assignment
Supports Entra Group, User, and Service Principal object IDs.

## EXAMPLES

### EXAMPLE 1

Set-FabricWorkspaceRoleAssignment -WorkspaceId $ws.id -WorkspaceName 'SalesAnalytics-ETL [DEV]' -PrincipalId $groupId -PrincipalType 'Group' -Role 'Member' -Token $token

Ensures the given Entra group holds the Member role on the workspace, applying the change idempotently.

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
AcceptedValues: []
HelpMessage: ''
```

### -Role

The workspace role to assign: Admin, Contributor, Member, or Viewer.

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

### -WorkspaceId

The Fabric workspace GUID.

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

### -WorkspaceName

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Collections.Hashtable

A report entry with the workspace name and ID, the principal ID and type, the role, and the action taken (skipped, updated, or created).

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/rest/api/fabric/core/workspaces/add-workspace-role-assignment)
