# <copyright file="Assert-AzureAdGroupMembership.Tests.ps1" company="Endjin Limited">
# Copyright (c) Endjin Limited. All rights reserved.
# </copyright>

#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe "Assert-AzureAdGroupMembership Tests" {

    BeforeAll {
        $mockDuplicateGroups = @(
            @{Id="00000000-0000-0000-0000-000000000000"; DisplayName="a-common-group-name"; SecurityEnabled=$true}
            @{Id="11111111-1111-1111-1111-111111111111"; DisplayName="a-common-group-name"; SecurityEnabled=$true}
        )

        $mockGroup = @{
            Id = "7c408c06-b467-4fd5-96e2-bc9cbc1bd4ee"
            DisplayName = "some-group"
            SecurityEnabled = $true
        }
        $mockGroupMembers = @(
            @{Id = "6cea30de-a493-42b7-9855-2d9a343eca8f"}
            @{Id = "9871e647-e493-4596-84d7-8bbbe8e90447"}
        )

        # Builds the value returned by the mocked Invoke-AzRestMethod for the beta
        # groups/{id}/members call, which the real (nested, unmockable) _getGroupMembers ->
        # _HandleRestError chain runs against for real.
        #
        # The response has to be a real Microsoft.Azure.Commands.Profile.Models.PSHttpResponse:
        # _HandleRestError declares its pipeline parameter with that exact type, and PowerShell
        # won't bind a plain [pscustomobject] to it. The type has no usable public constructor,
        # so build an uninitialized instance and set its (writable) StatusCode/Content properties.
        #
        # NOTE: this is a plain helper (no Mock call inside it), unlike a wrapper that calls
        # Mock itself - Pester's test-scope detection for a -ModuleName mock breaks when Mock is
        # invoked through an extra function-call layer, silently registering the behaviour where
        # It can't find it. Every `Mock Invoke-AzRestMethod ...` below is therefore written out
        # inline in each It block rather than going through a shared helper.
        function New-MockGroupMembersResponse {
            param([array] $Members)

            $response = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject(
                [Microsoft.Azure.Commands.Profile.Models.PSHttpResponse])
            $response.StatusCode = 200
            $response.Content = (@{ value = @($Members) } | ConvertTo-Json -Depth 5)
            $response
        }
    }

    Context "Group does not exist" {

        It "should throw an exception" {
            Mock Get-AzADGroup {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock Get-AzureAdDirectoryObject {} -ModuleName ZeroFailed.Deploy.Fabric

            $mockGroupName = "nonexistent-group"
            { Assert-AzureAdGroupMembership -Name $mockGroupName -RequiredMembers @("user@nowwhere.org") } |
                Should -Throw "The specified group could not be found: DisplayName=$mockGroupName"

            Should -Invoke Get-AzureAdDirectoryObject -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
        }
    }

    Context "Multiple groups found" {

        It "should throw an exception" {
            Mock Get-AzADGroup { $mockDuplicateGroups } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Get-AzureAdDirectoryObject {} -ModuleName ZeroFailed.Deploy.Fabric

            { Assert-AzureAdGroupMembership -Name "a-common-group-name" -RequiredMembers @("user@nowwhere.org") } |
                Should -Throw "Found multiple matching groups: ObjectId=$($mockDuplicateGroups[0].Id); ObjectId=$($mockDuplicateGroups[1].Id);"

            Should -Invoke Get-AzureAdDirectoryObject -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
        }
    }

    Context "Required members are already in the group (one member)" {

        It "should not try to update the group" {
            Mock Get-AzADGroup { $mockGroup } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Invoke-AzRestMethod {
                New-MockGroupMembersResponse -Members @($mockGroupMembers[0])
            } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Uri.ToString() -like "*/members" }
            Mock Get-AzureAdDirectoryObject { $mockGroupMembers[0] } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Add-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock Remove-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric

            Assert-AzureAdGroupMembership `
                -Name $mockGroup.DisplayName `
                -RequiredMembers @($mockGroupMembers[0].Id)

            Should -Invoke Get-AzureAdDirectoryObject -Times 1 -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Add-AzADGroupMember -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Remove-AzADGroupMember -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
        }
    }

    Context "Required members are already in the group (multiple members)" {

        It "should not try to update the group" {
            Mock Get-AzADGroup { $mockGroup } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Invoke-AzRestMethod {
                New-MockGroupMembersResponse -Members $mockGroupMembers
            } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Uri.ToString() -like "*/members" }
            Mock Get-AzureAdDirectoryObject { $mockGroupMembers[0] } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq $mockGroupMembers[0].Id }
            Mock Get-AzureAdDirectoryObject { $mockGroupMembers[1] } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq $mockGroupMembers[1].Id }
            Mock Add-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock Remove-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric

            Assert-AzureAdGroupMembership `
                -Name $mockGroup.DisplayName `
                -RequiredMembers ($mockGroupMembers | Select-Object -ExpandProperty Id)

            Should -Invoke Get-AzureAdDirectoryObject -Times 2 -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Add-AzADGroupMember -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Remove-AzADGroupMember -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
        }
    }

    Context "Missing single member" {

        It "should add the missing member to the group" {
            Mock Get-AzADGroup { $mockGroup } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Invoke-AzRestMethod {
                New-MockGroupMembersResponse -Members @($mockGroupMembers[0])
            } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Uri.ToString() -like "*/members" }
            Mock Get-AzureAdDirectoryObject { $mockGroupMembers[0] } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq $mockGroupMembers[0].Id }
            Mock Get-AzureAdDirectoryObject { $mockGroupMembers[1] } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq $mockGroupMembers[1].Id }
            Mock Add-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock Remove-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric

            Assert-AzureAdGroupMembership `
                -Name $mockGroup.DisplayName `
                -RequiredMembers ($mockGroupMembers | Select-Object -ExpandProperty Id)

            Should -Invoke Get-AzureAdDirectoryObject -Times 2 -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Add-AzADGroupMember -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $MemberObjectId -eq $mockGroupMembers[1].Id }
            Should -Invoke Remove-AzADGroupMember -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
        }
    }

    Context "Missing multiple members" {

        It "should add the missing member to the group" {
            Mock Get-AzADGroup { $mockGroup } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Invoke-AzRestMethod {
                New-MockGroupMembersResponse -Members @()
            } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Uri.ToString() -like "*/members" }
            Mock Get-AzureAdDirectoryObject { $mockGroupMembers[0] } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq $mockGroupMembers[0].Id }
            Mock Get-AzureAdDirectoryObject { $mockGroupMembers[1] } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq $mockGroupMembers[1].Id }
            Mock Add-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock Remove-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric

            Assert-AzureAdGroupMembership `
                -Name $mockGroup.DisplayName `
                -RequiredMembers ($mockGroupMembers | Select-Object -ExpandProperty Id)

            Should -Invoke Get-AzureAdDirectoryObject -Times 2 -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Add-AzADGroupMember -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $MemberObjectId -eq $mockGroupMembers[0].Id }
            Should -Invoke Add-AzADGroupMember -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $MemberObjectId -eq $mockGroupMembers[1].Id }
            Should -Invoke Remove-AzADGroupMember -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
        }
    }

    Context "Additional members are already in the group (Non-Strict)" {

        It "should not try to update the group" {
            Mock Get-AzADGroup { $mockGroup } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Invoke-AzRestMethod {
                New-MockGroupMembersResponse -Members $mockGroupMembers
            } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Uri.ToString() -like "*/members" }
            Mock Get-AzureAdDirectoryObject { $mockGroupMembers[0] } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Add-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock Remove-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric

            Assert-AzureAdGroupMembership `
                -Name $mockGroup.DisplayName `
                -RequiredMembers @($mockGroupMembers[0].Id)

            Should -Invoke Add-AzADGroupMember -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Remove-AzADGroupMember -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
        }
    }

    Context "Additional members are already in the group (Strict)" {

        It "should remove extraneous members" {
            Mock Get-AzADGroup { $mockGroup } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Invoke-AzRestMethod {
                New-MockGroupMembersResponse -Members $mockGroupMembers
            } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Uri.ToString() -like "*/members" }
            Mock Get-AzureAdDirectoryObject { $mockGroupMembers[0] } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Add-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock Remove-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric

            Assert-AzureAdGroupMembership `
                -Name "nonexistent-group" `
                -RequiredMembers @($mockGroupMembers[0].Id) `
                -StrictMode $true

            Should -Invoke Add-AzADGroupMember -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Remove-AzADGroupMember -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $MemberObjectId -eq $mockGroupMembers[1].Id }
        }
    }

    Context "Adding and removing group members (Strict)" {

        It "should remove extraneous members" {
            $mockExistingMembers = $mockGroupMembers + @{Id = ([guid]::Empty).Guid.ToString()}
            $requiredMembers = $mockGroupMembers

            Mock Get-AzADGroup { $mockGroup } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Invoke-AzRestMethod {
                New-MockGroupMembersResponse -Members @($mockExistingMembers[0], $mockExistingMembers[2])
            } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Uri.ToString() -like "*/members" }
            Mock Get-AzureAdDirectoryObject { $mockExistingMembers[0] } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq $mockExistingMembers[0].Id }
            Mock Get-AzureAdDirectoryObject { $mockExistingMembers[1] } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq $mockExistingMembers[1].Id }
            Mock Get-AzureAdDirectoryObject { $mockExistingMembers[2] } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq $mockExistingMembers[2].Id }
            # We need to return a group this time, so we still have a group object for the subsequent call Remove-AzADGroupMember
            Mock Add-AzADGroupMember { $mockGroup } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Remove-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric

            Assert-AzureAdGroupMembership `
                -Name $mockGroup.DisplayName `
                -RequiredMembers ($requiredMembers | Select-Object -ExpandProperty Id) `
                -StrictMode $true

            Should -Invoke Get-AzureAdDirectoryObject -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq $mockExistingMembers[0].Id }
            Should -Invoke Get-AzureAdDirectoryObject -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq $mockExistingMembers[1].Id }
            Should -Invoke Add-AzADGroupMember -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $MemberObjectId -eq $mockExistingMembers[1].Id }
            Should -Invoke Remove-AzADGroupMember -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $MemberObjectId -eq $mockExistingMembers[2].Id }
        }
    }

    Context "Adding an invalid member" {

        It "should not add the member, but log a warning instead" {
            Mock Get-AzADGroup { $mockGroup } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Invoke-AzRestMethod {
                New-MockGroupMembersResponse -Members @()
            } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Uri.ToString() -like "*/members" }
            Mock Get-AzureAdDirectoryObject {} -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq [guid]::Empty }
            Mock Add-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock Remove-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock Write-Warning {} -ModuleName ZeroFailed.Deploy.Fabric

            Assert-AzureAdGroupMembership `
                -Name $mockGroup.DisplayName `
                -RequiredMembers @([guid]::Empty)

            Should -Invoke Get-AzureAdDirectoryObject -Times 1 -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Add-AzADGroupMember -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Remove-AzADGroupMember -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Write-Warning -Times 1 -ModuleName ZeroFailed.Deploy.Fabric
        }
    }
}
