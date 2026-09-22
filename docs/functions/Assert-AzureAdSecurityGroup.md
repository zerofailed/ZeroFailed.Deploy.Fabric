---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/graph/api/group-post-groups
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 09/21/2026
PlatyPS schema version: 2024-05-01
title: Assert-AzureAdSecurityGroup
---

# Assert-AzureAdSecurityGroup

## SYNOPSIS

Creates or updates a AzureAD group.

## SYNTAX

### __AllParameterSets

```
Assert-AzureAdSecurityGroup [-DisplayName] <string> [-MailNickname] <string>
 [[-Description] <string>] [[-OwnersToAssignOnCreation] <string[]>] [[-StrictMode] <bool>]
 [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Uses Azure PowerShell to create an AzureAD security group.
 This function assumes that the caller will not have full AzureAD
permissions (i.e.
'Group.Create' instead of 'Group.ReadWrite.All') as this is typically the case for least-privilege
automation scenarios.
 It therefore assumes that group owners can only be configured as part of the creation request, as this
is supported for callers with 'Group.Create' permissions.

## EXAMPLES

## PARAMETERS

### -Description

The description of the group

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DisplayName

The display name of the group.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases:
- Name
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

### -MailNickname

The username portion of the email address associated with the group

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases:
- EmailName
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

### -OwnersToAssignOnCreation

The DisplayName, UserPrincipalName, ObjectId or ApplicationId of the users, groups, service principals to assign as owners to the group.
Note, that if the group already exists, we will not attempt to assign the owners (see the note in the description for more details)

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -StrictMode

When true, the group's description forms part of the idempotency check.
 If the specified description does not match the group's
definition in AzureAD, then it will be updated to ensure it matches.

```yaml
Type: System.Boolean
DefaultValue: True
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AzureAD group definition object

The AzureAD group definition, as returned by `Get-AzADGroup`, whether it already existed, was
newly created, or was updated.

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/graph/api/group-post-groups)
