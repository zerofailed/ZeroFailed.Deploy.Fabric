---
document type: cmdlet
external help file: ZeroFailed.Deploy.Fabric-Help.xml
HelpUri: https://learn.microsoft.com/graph/api/group-list-members
Locale: en-US
Module Name: ZeroFailed.Deploy.Fabric
ms.date: 09/21/2026
PlatyPS schema version: 2024-05-01
title: Assert-AzureAdGroupMembership
---

# Assert-AzureAdGroupMembership

## SYNOPSIS

Configures the membership of an AzureAD group.

## SYNTAX

### ByName

```
Assert-AzureAdGroupMembership -Name <string> [-RequiredMembers <string[]>] [-GroupType <string>]
 [-StrictMode <bool>] [<CommonParameters>]
```

### ByObjectId

```
Assert-AzureAdGroupMembership -ObjectId <string> [-RequiredMembers <string[]>] [-GroupType <string>]
 [-StrictMode <bool>] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Uses Azure PowerShell to manage AzureAD group membership.

## EXAMPLES

### EXAMPLE 1

Assert-AzureAdGroupMembership -Name "MyGroup" -RequiredMembers @("MyOtherGroup", "MyUser", "MyServicePrincipal")
Assert-AzureAdGroupMembership -Name "MyGroup" -RequiredMembers @("MyOtherGroup", "MyUser@nowhere.org", "be2a6313-cb3a-45ad-a70f-cbac2a8c565f")
Assert-AzureAdGroupMembership -Name "MyGroup" -RequiredMembers @("f7f0545c-82b5-4008-bebf-f73fb1d5a7f8", "MyUser@nowhere.org", "be2a6313-cb3a-45ad-a70f-cbac2a8c565f")

## PARAMETERS

### -GroupType

The type of group to manage: 'Security' or 'Distribution'.
Used to disambiguate when a group
with a matching Name/ObjectId exists as both a security and a distribution group.
Defaults to
'Security'.

```yaml
Type: System.String
DefaultValue: Security
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

### -Name

The display name of the group.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ByName
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ObjectId

The objectId of the group.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ByObjectId
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RequiredMembers

The list of AzureAD objects that should be members of the group.
These can be specified using
'DisplayName', 'ObjectId', 'ApplicationId' or 'UserPrincipalName'.

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

### -StrictMode

When true, existing group members not specified in the 'RequiredMembers' parameters will be removed from the group.

```yaml
Type: System.Boolean
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

## NOTES

## RELATED LINKS

- [](https://learn.microsoft.com/graph/api/group-list-members)
