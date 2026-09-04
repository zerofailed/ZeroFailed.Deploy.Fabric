---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/graph/api/group-post-members
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 09/04/2026
PlatyPS schema version: 2024-05-01
title: Add-FabricWorkspaceIdentityToGroup
---

# Add-FabricWorkspaceIdentityToGroup

## SYNOPSIS

Adds a Fabric Workspace Identity to an existing Entra security group, idempotently.

## SYNTAX

### __AllParameterSets

```
Add-FabricWorkspaceIdentityToGroup [-ServicePrincipalObjectId] <string> [-GroupId] <string>
 [-WorkspaceName] <string> [-WorkspaceId] <string> [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Ensures the workspace identity's service principal is a member of a known, existing Entra
security group — the group that the "Service principals can use Fabric APIs" tenant setting
is scoped to.
A workspace identity is a service principal, so without that setting it
cannot call the Fabric REST APIs; joining the group is what lets it do so (for example, a
pipeline's Invoke Pipeline activity running as the workspace identity).

Idempotent: the group's current membership is checked first, so an identity that is already
a member is reported as 'Skipped' rather than re-added.
An "already exists" response from
Entra is also treated as 'Skipped', so concurrent runs do not fail each other.

Uses the Az.Resources Entra cmdlets (as _Get-FabricDeploymentIdentity does) rather than
calling Microsoft Graph directly, so the signed-in Az context supplies the credentials and
no second token has to be managed alongside the Fabric one.

The group is never created — it must already exist.
The caller needs directory permissions
to read and modify the group's membership (for example Group Owner, or a directory role
such as Groups Administrator).

## EXAMPLES

### EXAMPLE 1

Add-FabricWorkspaceIdentityToGroup -ServicePrincipalObjectId $identity.ServicePrincipalObjectId -GroupId $groupId -WorkspaceName 'SalesAnalytics-ETL [DEV]' -WorkspaceId $ws.id

Ensures the workspace identity is a member of the given security group.

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

### -GroupId

The Entra object ID of the existing security group to add the identity to.

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

### -ServicePrincipalObjectId

The Entra object ID of the workspace identity's service principal, as returned by
Enable-FabricWorkspaceIdentity.

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

The Fabric workspace GUID, recorded on the returned report entry.

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

### -WorkspaceName

Display name used in log messages and the returned report entry.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Collections.Hashtable

A report entry describing the group membership, including the workspace name and ID, the identity service principal object ID, the group ID, and the action taken (`Added`, `Skipped`, or `WhatIf`).

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/graph/api/group-post-members)
