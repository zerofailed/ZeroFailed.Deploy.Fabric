# <copyright file="Get-AzureAdDirectoryObject.Tests.ps1" company="Endjin Limited">
# Copyright (c) Endjin Limited. All rights reserved.
# </copyright>

#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe "Get-AzureAdDirectoryObject Tests" {

    BeforeAll {
        # Setup some mock AzureAD objects
        $mockGroup = @{
            ObjectId = '5c21a713-c12c-4592-807e-e45b1adc8634'
            DisplayName = 'Mock Group'
        }
        $mockServicePrincipal = @{
            ObjectId = '308d6796-5639-49da-a0b4-17e37de6e4de'
            ApplicationId = 'c6c60257-7088-41b0-a8b3-6cdfe22c4855'
            DisplayName = 'Mock Service Principal'
        }
        $mockUser = @{
            ObjectId = '5f3c6343-88e8-4888-afcd-2a7acfaa7fc7'
            DisplayName = 'Mock User'
            UserPrincipalName = 'mock.user@nowhere.org'
        }

        Mock Write-Verbose {} -ModuleName ZeroFailed.Deploy.Fabric
        Mock Write-Warning {} -ModuleName ZeroFailed.Deploy.Fabric

        # Mock the real cmdlets that the SUT's nested lookup helpers (_groupById, _groupByName,
        # etc.) call internally. Pester's -ModuleName mock intercepts calls made from nested
        # function bodies too, since they still resolve unqualified command names through the
        # enclosing module's scope - so the nested helpers themselves don't need to be (and,
        # being declared inside their parent function's body, can't be) mocked directly.
        #
        # ObjectId-based lookups throw on no match; DisplayName/ApplicationId/UserPrincipalName
        # lookups return $null on no match - matching the real Az cmdlets' documented behaviour
        # (see the comments in Get-AzureAdDirectoryObject.ps1).

        Mock Get-AzADGroup { $global:methodUsed = "ObjectId"; $mockGroup } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId -eq $mockGroup.ObjectId }
        Mock Get-AzADGroup { throw "not found" } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId -and $ObjectId -ne $mockGroup.ObjectId }
        Mock Get-AzADGroup { $global:methodUsed = "DisplayName"; $mockGroup } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName -eq $mockGroup.DisplayName }
        Mock Get-AzADGroup {} -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName -and $DisplayName -ne $mockGroup.DisplayName }

        Mock Get-AzADServicePrincipal { $global:methodUsed = "ApplicationId"; $mockServicePrincipal } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ApplicationId -eq $mockServicePrincipal.ApplicationId }
        Mock Get-AzADServicePrincipal {} -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ApplicationId -and $ApplicationId -ne $mockServicePrincipal.ApplicationId }
        Mock Get-AzADServicePrincipal { $global:methodUsed = "ObjectId"; $mockServicePrincipal } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId -eq $mockServicePrincipal.ObjectId }
        Mock Get-AzADServicePrincipal { throw "not found" } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId -and $ObjectId -ne $mockServicePrincipal.ObjectId }
        Mock Get-AzADServicePrincipal { $global:methodUsed = "DisplayName"; $mockServicePrincipal } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName -eq $mockServicePrincipal.DisplayName }
        Mock Get-AzADServicePrincipal {} -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName -and $DisplayName -ne $mockServicePrincipal.DisplayName }

        Mock Get-AzADUser { $global:methodUsed = "ObjectId"; $mockUser } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId -eq $mockUser.ObjectId }
        Mock Get-AzADUser { throw "not found" } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId -and $ObjectId -ne $mockUser.ObjectId }
        Mock Get-AzADUser { $global:methodUsed = "DisplayName"; $mockUser } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName -eq $mockUser.DisplayName }
        Mock Get-AzADUser {} -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName -and $DisplayName -ne $mockUser.DisplayName }
        Mock Get-AzADUser { $global:methodUsed = "UserPrincipalName"; $mockUser } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $UserPrincipalName -eq $mockUser.UserPrincipalName }
        Mock Get-AzADUser {} -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $UserPrincipalName -and $UserPrincipalName -ne $mockUser.UserPrincipalName }
    }

    Context "Finding a group" {

        Context "Searching by ObjectId" {

            It "should return the group" {
                $global:methodUsed = $null
                $res = Get-AzureAdDirectoryObject -Criterion $mockGroup.ObjectId

                $methodUsed | Should -Be "ObjectId"
                $res.DisplayName | Should -Be $mockGroup.DisplayName

                Should -Invoke Get-AzADGroup -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADServicePrincipal -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ApplicationId }
                Should -Invoke Get-AzADServicePrincipal -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADUser -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADGroup -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADServicePrincipal -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADUser -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
            }
        }

        Context "Searching by DisplayName" {

            It "should return the group" {
                $global:methodUsed = $null
                $res = Get-AzureAdDirectoryObject -Criterion $mockGroup.DisplayName

                $methodUsed | Should -Be "DisplayName"
                $res.ObjectId | Should -Be $mockGroup.ObjectId

                Should -Invoke Get-AzADGroup -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADServicePrincipal -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ApplicationId }
                Should -Invoke Get-AzADServicePrincipal -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADUser -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADGroup -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADServicePrincipal -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADUser -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
            }
        }
    }

    Context "Finding a service principal" {

        Context "Searching by ObjectId" {

            It "should return the service principal" {
                $global:methodUsed = $null
                $res = Get-AzureAdDirectoryObject -Criterion $mockServicePrincipal.ObjectId

                $methodUsed | Should -Be "ObjectId"
                $res.DisplayName | Should -Be $mockServicePrincipal.DisplayName

                Should -Invoke Get-AzADGroup -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADServicePrincipal -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ApplicationId }
                Should -Invoke Get-AzADServicePrincipal -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADUser -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADGroup -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADServicePrincipal -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADUser -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
            }
        }

        Context "Searching by ApplicationId" {

            It "should return the service principal" {
                $global:methodUsed = $null
                $res = Get-AzureAdDirectoryObject -Criterion $mockServicePrincipal.ApplicationId

                $methodUsed | Should -Be "ApplicationId"
                $res.DisplayName | Should -Be $mockServicePrincipal.DisplayName

                Should -Invoke Get-AzADGroup -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADServicePrincipal -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ApplicationId }
                Should -Invoke Get-AzADServicePrincipal -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADUser -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADGroup -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADServicePrincipal -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADUser -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
            }
        }

        Context "Searching by DisplayName" {

            It "should return the service principal" {
                $global:methodUsed = $null
                $res = Get-AzureAdDirectoryObject -Criterion $mockServicePrincipal.DisplayName

                $methodUsed | Should -Be "DisplayName"
                $res.ObjectId | Should -Be $mockServicePrincipal.ObjectId

                Should -Invoke Get-AzADGroup -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADServicePrincipal -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ApplicationId }
                Should -Invoke Get-AzADServicePrincipal -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADUser -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADGroup -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADServicePrincipal -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADUser -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
            }
        }
    }

    Context "Finding a user" {

        Context "Searching by ObjectId" {

            It "should return the user" {
                $global:methodUsed = $null
                $res = Get-AzureAdDirectoryObject -Criterion $mockUser.ObjectId

                $methodUsed | Should -Be "ObjectId"
                $res.DisplayName | Should -Be $mockUser.DisplayName

                Should -Invoke Get-AzADGroup -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADServicePrincipal -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ApplicationId }
                Should -Invoke Get-AzADServicePrincipal -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADUser -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADGroup -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADServicePrincipal -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADUser -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
            }
        }

        Context "Searching by DisplayName" {

            It "should return the user" {
                $global:methodUsed = $null
                $res = Get-AzureAdDirectoryObject -Criterion $mockUser.DisplayName

                $methodUsed | Should -Be "DisplayName"
                $res.ObjectId | Should -Be $mockUser.ObjectId

                Should -Invoke Get-AzADGroup -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADServicePrincipal -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADServicePrincipal -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADUser -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADGroup -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADServicePrincipal -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADUser -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
            }
        }

        Context "Searching by UPN" {

            It "should return the user" {
                $global:methodUsed = $null
                $res = Get-AzureAdDirectoryObject -Criterion $mockUser.UserPrincipalName

                $methodUsed | Should -Be "UserPrincipalName"
                $res.ObjectId | Should -Be $mockUser.ObjectId

                Should -Invoke Get-AzADGroup -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADServicePrincipal -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADUser -Times 0 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ObjectId }
                Should -Invoke Get-AzADGroup -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADServicePrincipal -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
                Should -Invoke Get-AzADUser -Times 1 -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $DisplayName }
            }
        }
    }
}
