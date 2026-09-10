#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    $script:testConfig = [pscustomobject]@{
        project          = 'salesanalytics'
        namingConvention = [pscustomobject]@{
            template       = '{project}-{type} [{env}]'
            maxLength      = 64
            typeShortCodes = [pscustomobject]@{
                Bronze          = 'Bronze'
                Silver          = 'Silver'
                Gold            = 'Gold'
                ETL             = 'ETL'
                Storage         = 'Storage'
                Reporting       = 'Report'
            }
            envShortCodes  = [pscustomobject]@{
                Dev        = 'DEV'
                Test       = 'TEST'
                Acceptance = 'ACC'
                Production = 'PROD'
            }
        }
        environments     = @(
            [pscustomobject]@{ name = 'Dev';        shortCode = 'DEV';  capacityName = 'cap-dev' }
            [pscustomobject]@{ name = 'Test';       shortCode = 'TEST'; capacityName = 'cap-test' }
            [pscustomobject]@{ name = 'Acceptance'; shortCode = 'ACC';  capacityName = 'cap-acc' }
            [pscustomobject]@{ name = 'Production'; shortCode = 'PROD'; capacityName = 'cap-prod' }
        )
        workspaces       = @(
            [pscustomobject]@{ id = 'bronze'; type = 'Bronze';    identity = [pscustomobject]@{ enabled = $true  } }
            [pscustomobject]@{ id = 'silver'; type = 'Silver';    identity = [pscustomobject]@{ enabled = $true  } }
            [pscustomobject]@{ id = 'gold';   type = 'Gold';      identity = [pscustomobject]@{ enabled = $true  } }
            [pscustomobject]@{ id = 'report'; type = 'Reporting'; identity = [pscustomobject]@{ enabled = $false } }
        )
    }
}

Describe '_Resolve-WorkspaceName' {

    BeforeAll {
        # The over-length-name test deliberately triggers the truncation warning; silence it so a
        # passing run stays clean. No test asserts on this output.
        Mock Write-Warning {} -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'produces correct name: bronze x Dev' {
        $name = & (Get-Module ZeroFailed.Deploy.Fabric) { _Resolve-WorkspaceName -Config $args[0] -WorkspaceId 'bronze' -EnvironmentName 'Dev' } $script:testConfig
        $name | Should -Be 'salesanalytics-Bronze [DEV]'
    }

    It 'produces correct name: report x Production' {
        $name = & (Get-Module ZeroFailed.Deploy.Fabric) { _Resolve-WorkspaceName -Config $args[0] -WorkspaceId 'report' -EnvironmentName 'Production' } $script:testConfig
        $name | Should -Be 'salesanalytics-Report [PROD]'
    }

    It 'produces correct name: gold x Acceptance' {
        $name = & (Get-Module ZeroFailed.Deploy.Fabric) { _Resolve-WorkspaceName -Config $args[0] -WorkspaceId 'gold' -EnvironmentName 'Acceptance' } $script:testConfig
        $name | Should -Be 'salesanalytics-Gold [ACC]'
    }

    It 'uses type and env codes exactly as defined in the short-code maps' {
        $name = & (Get-Module ZeroFailed.Deploy.Fabric) { _Resolve-WorkspaceName -Config $args[0] -WorkspaceId 'bronze' -EnvironmentName 'Dev' } $script:testConfig
        $name | Should -Match '-Bronze \[DEV\]$'
    }

    It 'truncates names longer than maxLength' {
        $longConfig = $script:testConfig | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $longConfig.project = 'a' * 60
        $name = & (Get-Module ZeroFailed.Deploy.Fabric) { _Resolve-WorkspaceName -Config $args[0] -WorkspaceId 'bronze' -EnvironmentName 'Dev' } $longConfig
        $name.Length | Should -BeLessOrEqual 64
    }

    It 'throws for an unknown workspace id' {
        { & (Get-Module ZeroFailed.Deploy.Fabric) {
            _Resolve-WorkspaceName -Config $args[0] -WorkspaceId 'nonexistent' -EnvironmentName 'Dev'
        } $script:testConfig } | Should -Throw
    }

    It 'throws for an unknown environment name' {
        { & (Get-Module ZeroFailed.Deploy.Fabric) {
            _Resolve-WorkspaceName -Config $args[0] -WorkspaceId 'bronze' -EnvironmentName 'Staging'
        } $script:testConfig } | Should -Throw
    }
}
