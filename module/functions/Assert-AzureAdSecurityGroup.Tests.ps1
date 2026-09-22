# <copyright file="Assert-AzureAdSecurityGroup.Tests.ps1" company="Endjin Limited">
# Copyright (c) Endjin Limited. All rights reserved.
# </copyright>

#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe "Assert-AzureAdSecurityGroup Tests" {

    BeforeAll {
        Mock Write-Host {} -ModuleName ZeroFailed.Deploy.Fabric
    }

    Context "Group does not exist" {

        BeforeAll {
            $baseMockGroup = @{
                DisplayName = 'testgroup'
                MailNickname = 'testgroup@nowhere.org'
                Description = 'just a test group'
            }
            $mockCreatedGroup = $baseMockGroup.Clone() + @{
                id = (New-Guid).Guid
                mailEnabled = $false
                securityEnabled = $true
            }

            Mock Get-AzADGroup {} -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
            Mock Get-AzADGroup { $mockCreatedGroup } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
            Mock Invoke-AzRestMethod { @{StatusCode = 200; Content = ($mockCreatedGroup | ConvertTo-Json)} } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "POST" -and $Uri.ToString().EndsWith("/groups") }
        }

        Context "No group owners specified" {

            BeforeAll {
                $testGroup = $baseMockGroup.Clone() + @{
                    OwnersToAssignOnCreation = @()
                    StrictMode = $false
                }
                Mock Get-AzureAdDirectoryObject {} -ModuleName ZeroFailed.Deploy.Fabric
            }
            BeforeEach {
                $res = Assert-AzureAdSecurityGroup @testGroup
            }

            It "should return the new group" {
                $res.DisplayName | Should -Be $testGroup.DisplayName
                $res.securityEnabled | Should -Be $true
                Should -Invoke Get-AzADGroup -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId -eq $mockCreatedGroup.id }
            }
            It "should create the group" {
                Should -Invoke Get-AzureAdDirectoryObject -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "PATCH" }
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "GET" -and $Uri.ToString() -like "*/owners" }
                Should -Invoke Invoke-AzRestMethod -Times 1 -ModuleName ZeroFailed.Deploy.Fabric `
                    -ParameterFilter {
                        $Method -eq "POST" -and `
                        $Uri.ToString() -eq "https://graph.microsoft.com/v1.0/groups" -and `
                        $Payload -notmatch "owners"
                    }
            }
        }

        Context "Group owner specified" {

            BeforeAll {
                $testGroup = $baseMockGroup.Clone() + @{
                    OwnersToAssignOnCreation = @("someone@nowhere.org")
                    StrictMode = $false
                }
                $mockOwners = @( @{ id = [guid]::NewGuid().ToString() } )
                Mock Get-AzureAdDirectoryObject { $mockOwners } -ModuleName ZeroFailed.Deploy.Fabric
            }
            BeforeEach {
                $res = Assert-AzureAdSecurityGroup @testGroup
            }

            It "should return the new group" {
                $res.DisplayName | Should -Be $testGroup.DisplayName
                $res.securityEnabled | Should -Be $true
                Should -Invoke Get-AzADGroup -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId -eq $mockCreatedGroup.id }
            }
            It "should create the group with the specified owner" {
                Should -Invoke Get-AzureAdDirectoryObject -Times 1 -ModuleName ZeroFailed.Deploy.Fabric
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "PATCH" }
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "GET" -and $Uri.ToString() -like "*/owners" }
                Should -Invoke Invoke-AzRestMethod -Times 1 -ModuleName ZeroFailed.Deploy.Fabric `
                    -ParameterFilter {
                        $Method -eq "POST" -and `
                        $Uri.ToString() -eq "https://graph.microsoft.com/v1.0/groups" -and `
                        $Payload -match $mockOwners.id
                    }
            }
        }

        Context "Multiple group owners specified" {

            BeforeAll {
                $testGroup = $baseMockGroup.Clone() + @{
                    OwnersToAssignOnCreation = @("someone@nowhere.org","MyServicePrincipal")
                    StrictMode = $false
                }
                $mockOwnerObjectIds = @(
                    @{ id = [guid]::NewGuid().ToString() }
                    @{ id = [guid]::NewGuid().ToString() }
                )

                Mock Get-AzureAdDirectoryObject { $mockOwnerObjectIds[0] } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq "someone@nowhere.org" }
                Mock Get-AzureAdDirectoryObject { $mockOwnerObjectIds[1] } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq "MyServicePrincipal" }
            }
            BeforeEach {
                $res = Assert-AzureAdSecurityGroup @testGroup
            }

            It "should return the new group" {
                $res.DisplayName | Should -Be $testGroup.DisplayName
                $res.securityEnabled | Should -Be $true
                Should -Invoke Get-AzADGroup -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId -eq $mockCreatedGroup.id }
            }
            It "should create the group specifying all the required owners" {
                Should -Invoke Get-AzureAdDirectoryObject -Times 2 -ModuleName ZeroFailed.Deploy.Fabric
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "PATCH" }
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "GET" -and $Uri.ToString() -like "*/owners" }
                Should -Invoke Invoke-AzRestMethod -Times 1 -ModuleName ZeroFailed.Deploy.Fabric `
                    -ParameterFilter {
                        $Method -eq "POST" -and `
                        $Uri.ToString() -eq "https://graph.microsoft.com/v1.0/groups" -and `
                        $Payload -match $mockOwnerObjectIds[0].id -and `
                        $Payload -match $mockOwnerObjectIds[1].id
                    }
            }
        }

        # Added to catch a previous bug
        Context "Invalid group owners specified - multiple empty string owners" {

            BeforeAll {
                $testGroup = $baseMockGroup.Clone() + @{
                    OwnersToAssignOnCreation = @("","")
                    StrictMode = $false
                }
                $mockOwnerObjectIds = @( [guid]::NewGuid().ToString(), [guid]::NewGuid().ToString() )

                Mock Get-AzureAdDirectoryObject { $mockOwnerObjectIds[0] } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq "someone@nowhere.org" }
                Mock Get-AzureAdDirectoryObject { $mockOwnerObjectIds[1] } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Criterion -eq "MyServicePrincipal" }
            }
            BeforeEach {
                $res = Assert-AzureAdSecurityGroup @testGroup
            }

            It "should return the new group" {
                $res.DisplayName | Should -Be $testGroup.DisplayName
                $res.securityEnabled | Should -Be $true
                Should -Invoke Get-AzADGroup -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId -eq $mockCreatedGroup.id }
            }
            It "should create the group with no owners" {
                Should -Invoke Get-AzureAdDirectoryObject -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "PATCH" }
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "GET" -and $Uri.ToString() -like "*/owners" }
                Should -Invoke Invoke-AzRestMethod -Times 1 -ModuleName ZeroFailed.Deploy.Fabric `
                    -ParameterFilter { `
                        $Method -eq "POST" -and `
                        $Uri.ToString() -eq "https://graph.microsoft.com/v1.0/groups" -and `
                        $Payload -notmatch 'owners@odata.bind'
                    }
            }
        }
    }

    Context "Group already exists" {

        BeforeAll {
            $groupObjectId = '00000000-0000-0000-0000-000000000000'
            $baseMockGroup = @{
                DisplayName = 'testgroup'
                MailNickname = 'testgroup@nowhere.org'
                Description = 'just a test group'
            }
            $mockExistingGroup = $baseMockGroup.Clone() + @{
                id = $groupObjectId
                mailEnabled = $false
                securityEnabled = $true
            }
            $mockExistingOwners = @( @{ id = [guid]::NewGuid().ToString(); displayName = "fake-existing-owner" } )
            $mockOwners = @( @{ id = [guid]::NewGuid().ToString(); displayName = "fake-owner" } )

            Mock Get-AzADGroup { $mockExistingGroup } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
            Mock Invoke-AzRestMethod { @{StatusCode = 200; Content = "{ `"value`": [ $($mockExistingOwners | ConvertTo-Json -Compress) ] }" } } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "GET" -and $Uri.ToString().EndsWith("/owners") }
            Mock Invoke-AzRestMethod { @{StatusCode = 200 } } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "PATCH" -and $Uri.ToString().EndsWith("/$groupObjectId") }
            Mock Get-AzureAdDirectoryObject { $mockOwners } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Write-Warning {} -ModuleName ZeroFailed.Deploy.Fabric
        }

        Context "Up-to-date group with no specified owners" {

            BeforeAll {
                $testGroup = $baseMockGroup.Clone() + @{
                    OwnersToAssignOnCreation = @()
                    StrictMode = $false
                }
                Mock Get-AzADGroup { $mockExistingGroup } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
            }
            BeforeEach {
                $res = Assert-AzureAdSecurityGroup @testGroup
            }

            It "should return the new group" {
                $res.DisplayName | Should -Be $testGroup.DisplayName
                $res.Description | Should -Be $testGroup.Description
                Should -Invoke Get-AzADGroup -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
            }
            It "should not update the group" {
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "POST" }
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric `
                    -ParameterFilter { $Method -eq "GET" -and $Uri.ToString().EndsWith("/owners") }
                Should -Invoke Get-AzureAdDirectoryObject -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric `
                    -ParameterFilter { $Method -eq "PATCH" -and $Uri.ToString().EndsWith("/$groupObjectId") }
            }
            It "should log no warnings that the owners cannot be updated" {
                Should -Invoke Write-Warning -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
            }
        }

        Context "Outdated group with no specified owners (StrictMode=false)" {

            BeforeAll {
                $updatedGroupDesc = 'just a test group with a different description'
                $mockUpdatedGroup = $mockExistingGroup.Clone()
                $mockUpdatedGroup.Description = $updatedGroupDesc
                Mock Get-AzADGroup { $mockUpdatedGroup } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }

                $testGroup = $baseMockGroup.Clone()
                $testGroup.Remove("Description")
                $testGroup += @{
                    Description = $updatedGroupDesc
                    OwnersToAssignOnCreation = @()
                    StrictMode = $false
                }
            }
            BeforeEach {
                $res = Assert-AzureAdSecurityGroup @testGroup
            }

            It "should return the existing group" {
                $res.DisplayName | Should -Be $testGroup.DisplayName
                $res.Description | Should -Be $mockExistingGroup.Description
                Should -Invoke Get-AzADGroup -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
            }
            It "should not update the group" {
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "POST" }
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "GET" -and $Uri.ToString() -eq "https://graph.microsoft.com/beta/groups/$groupObjectId/owners" }
                Should -Invoke Get-AzureAdDirectoryObject -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "PATCH" -and $Uri.ToString() -eq "https://graph.microsoft.com/v1.0/groups/$groupObjectId" }
            }
            It "should log no warnings that the owners cannot be updated" {
                Should -Invoke Write-Warning -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
            }
        }

        Context "Outdated group with no specified owners (StrictMode=true)" {

            BeforeAll {
                $updatedGroupDesc = 'just a test group with a different description'
                $mockUpdatedGroup = $mockExistingGroup.Clone()
                $mockUpdatedGroup.Description = $updatedGroupDesc
                Mock Get-AzADGroup { $mockUpdatedGroup } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }

                $testGroup = $baseMockGroup.Clone()
                $testGroup.Remove("Description")
                $testGroup += @{
                    Description = $updatedGroupDesc
                    OwnersToAssignOnCreation = @()
                    StrictMode = $true
                }
            }
            BeforeEach {
                $res = Assert-AzureAdSecurityGroup @testGroup
            }

            It "should return the updated group" {
                $res.DisplayName | Should -Be $testGroup.DisplayName
                $res.Description | Should -Be $updatedGroupDesc
                Should -Invoke Get-AzADGroup -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId -eq $groupObjectId }
            }
            It "should update the group" {
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "POST" }
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "GET" -and $Uri.ToString() -eq "https://graph.microsoft.com/beta/groups/$groupObjectId/owners" }
                Should -Invoke Get-AzureAdDirectoryObject -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
                Should -Invoke Invoke-AzRestMethod -Times 1 -ModuleName ZeroFailed.Deploy.Fabric `
                    -ParameterFilter {
                        $Method -eq "PATCH" -and `
                        $Uri.ToString() -eq "https://graph.microsoft.com/v1.0/groups/$groupObjectId" -and `
                        $Payload -notmatch "owners" -and $Payload -match $updatedGroupDesc
                    }
            }
            It "should log no warnings that the owners cannot be updated" {
                Should -Invoke Write-Warning -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
            }
        }

        Context "Up-to-date group with up-to-date owners specified" {

            BeforeAll {
                Mock Invoke-AzRestMethod { @{StatusCode = 200; Content = "{ `"value`": [ $($mockExistingOwners | ConvertTo-Json -Compress) ] }" } } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "GET" -and $Uri.ToString().EndsWith("/owners") }
                Mock Get-AzureAdDirectoryObject { $mockExistingOwners } -ModuleName ZeroFailed.Deploy.Fabric

                $testGroup = $baseMockGroup.Clone() + @{
                    OwnersToAssignOnCreation = @('fake-existing-owner')
                    StrictMode = $false
                }
            }
            BeforeEach {
                $res = Assert-AzureAdSecurityGroup @testGroup
            }

            It "should return the existing group" {
                $res.DisplayName | Should -Be $mockExistingGroup.DisplayName
                $res.mailEnabled | Should -Be $mockExistingGroup.mailEnabled
                Should -Invoke Get-AzADGroup -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
            }
            It "should not update the group" {
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "POST" }
                Should -Invoke Invoke-AzRestMethod -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "GET" -and $Uri.ToString() -eq "https://graph.microsoft.com/beta/groups/$groupObjectId/owners" }
                Should -Invoke Get-AzureAdDirectoryObject -Times 1 -ModuleName ZeroFailed.Deploy.Fabric
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "PATCH" -and $Uri.ToString() -eq "https://graph.microsoft.com/v1.0/groups/$groupObjectId" }
            }
            It "should log no warnings that the owners cannot be updated" {
                Should -Invoke Write-Warning -Times 0 -ModuleName ZeroFailed.Deploy.Fabric
            }
        }

        Context "Up-to-date group with additional owner specified" {

            BeforeAll {
                $testGroup = $baseMockGroup.Clone() + @{
                    OwnersToAssignOnCreation = @('new-owner@nowhere.com')
                    StrictMode = $false
                }
            }
            BeforeEach {
                $res = Assert-AzureAdSecurityGroup @testGroup
            }

            It "should return the existing group" {
                $res.DisplayName | Should -Be $mockExistingGroup.DisplayName
                $res.mailEnabled | Should -Be $mockExistingGroup.mailEnabled
                Should -Invoke Get-AzADGroup -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
            }
            It "should not update the group" {
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "POST" }
                Should -Invoke Invoke-AzRestMethod -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "GET" -and $Uri.ToString() -eq "https://graph.microsoft.com/beta/groups/$groupObjectId/owners" }
                Should -Invoke Get-AzureAdDirectoryObject -Times 1 -ModuleName ZeroFailed.Deploy.Fabric
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "PATCH" -and $Uri.ToString() -eq "https://graph.microsoft.com/v1.0/groups/$groupObjectId" }
            }
            It "should log a warning that the owners cannot be updated" {
                Should -Invoke Write-Warning -Times 1 -ModuleName ZeroFailed.Deploy.Fabric
            }
        }

        Context "Outdated group with additional owner specified (StrictMode=false)" {

            BeforeAll {
                $updatedGroupDesc = 'just a test group with a different description'
                $mockUpdatedGroup = $mockExistingGroup.Clone()
                $mockUpdatedGroup.Description = $updatedGroupDesc
                Mock Get-AzADGroup { $mockUpdatedGroup } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }

                $testGroup = $baseMockGroup.Clone()
                $testGroup.Remove("Description")
                $testGroup += @{
                    Description = $updatedGroupDesc
                    OwnersToAssignOnCreation = @('new-owner@nowhere.com')
                    StrictMode = $false
                }
            }
            BeforeEach {
                $res = Assert-AzureAdSecurityGroup @testGroup
            }

            It "should return the existing group" {
                $res.DisplayName | Should -Be $mockExistingGroup.DisplayName
                $res.mailEnabled | Should -Be $mockExistingGroup.mailEnabled
                Should -Invoke Get-AzADGroup -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
            }
            It "should not update the group" {
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "POST" }
                Should -Invoke Invoke-AzRestMethod -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "GET" -and $Uri.ToString() -eq "https://graph.microsoft.com/beta/groups/$groupObjectId/owners" }
                Should -Invoke Get-AzureAdDirectoryObject -Times 1 -ModuleName ZeroFailed.Deploy.Fabric
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "PATCH" -and $Uri.ToString() -eq "https://graph.microsoft.com/v1.0/groups/$groupObjectId" }
            }
            It "should log a warning that the owners cannot be updated" {
                Should -Invoke Write-Warning -Times 1 -ModuleName ZeroFailed.Deploy.Fabric
            }
        }

        Context "Outdated group with additional owner specified (StrictMode=true)" {

            BeforeAll {
                $updatedGroupDesc = 'just a test group with a different description'
                $mockUpdatedGroup = $mockExistingGroup.Clone()
                $mockUpdatedGroup.Description = $updatedGroupDesc
                Mock Get-AzADGroup { $mockUpdatedGroup } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }

                $testGroup = $baseMockGroup.Clone()
                $testGroup.Remove("Description")
                $testGroup += @{
                    Description = $updatedGroupDesc
                    OwnersToAssignOnCreation = @('new-owner@nowhere.com')
                    StrictMode = $true
                }
            }
            BeforeEach {
                $res = Assert-AzureAdSecurityGroup @testGroup
            }

            It "should return the updated group" {
                $res.DisplayName | Should -Be $testGroup.DisplayName
                $res.Description | Should -Be $updatedGroupDesc
                Should -Invoke Get-AzADGroup -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId -eq $groupObjectId }
            }
            It "should update the group" {
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "POST" }
                Should -Invoke Invoke-AzRestMethod -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "GET" -and $Uri.ToString() -eq "https://graph.microsoft.com/beta/groups/$groupObjectId/owners" }
                Should -Invoke Get-AzureAdDirectoryObject -Times 1 -ModuleName ZeroFailed.Deploy.Fabric
                Should -Invoke Invoke-AzRestMethod -Times 1 -ModuleName ZeroFailed.Deploy.Fabric `
                    -ParameterFilter {
                        $Method -eq "PATCH" -and `
                        $Uri.ToString() -eq "https://graph.microsoft.com/v1.0/groups/$groupObjectId" -and `
                        $Payload -notmatch "owners" -and $Payload -match $updatedGroupDesc
                    }
            }
            It "should log a warning that the owners cannot be updated" {
                Should -Invoke Write-Warning -Times 1 -ModuleName ZeroFailed.Deploy.Fabric
            }
        }

        Context "Backwards-compatible handling of StrictMode" {

            BeforeAll {
                $testGroup = $baseMockGroup.Clone() + @{
                    OwnersToAssignOnCreation = @('MyServicePrincipal')
                    # Omit the StrictMode parameter to simulate a consumer of an earlier version, before it was added
                }
            }
            BeforeEach {
                $res = Assert-AzureAdSecurityGroup @testGroup
            }

            It "should return the existing group" {
                $res.DisplayName | Should -Be $mockExistingGroup.DisplayName
                $res.mailEnabled | Should -Be $mockExistingGroup.mailEnabled
                Should -Invoke Get-AzADGroup -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
            }
            It "should not update the group and warn the owners cannot be updated" {
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "POST" }
                Should -Invoke Invoke-AzRestMethod -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "GET" -and $Uri.ToString() -eq "https://graph.microsoft.com/beta/groups/$groupObjectId/owners" }
                Should -Invoke Get-AzureAdDirectoryObject -Times 1 -ModuleName ZeroFailed.Deploy.Fabric
                Should -Invoke Write-Warning -Times 1 -ModuleName ZeroFailed.Deploy.Fabric
                Should -Invoke Invoke-AzRestMethod -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq "PATCH" -and $Uri.ToString() -eq "https://graph.microsoft.com/v1.0/groups/$groupObjectId" }
            }
            It "should log a warning that the owners cannot be updated" {
                Should -Invoke Write-Warning -Times 1 -ModuleName ZeroFailed.Deploy.Fabric
            }
        }
    }
}
