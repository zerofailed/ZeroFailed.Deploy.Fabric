#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    $script:testConfig = [pscustomobject]@{
        project          = 'salesanalytics'
        namingConvention = [pscustomobject]@{
            template                = '{project}-{type} [{env}]'
            environmentNameTemplate = '{project}-{type} Env'
            maxLength               = 64
            typeShortCodes          = [pscustomobject]@{
                Bronze    = 'Bronze'
                Reporting = 'Report'
            }
            envShortCodes           = [pscustomobject]@{
                Dev        = 'DEV'
                Production = 'PROD'
            }
        }
        environments     = @(
            [pscustomobject]@{ name = 'Dev';        shortCode = 'DEV';  capacityName = 'cap-dev' }
            [pscustomobject]@{ name = 'Production'; shortCode = 'PROD'; capacityName = 'cap-prod' }
        )
        workspaces       = @(
            [pscustomobject]@{ id = 'Bronze'; type = 'Bronze'    }
            [pscustomobject]@{ id = 'Report'; type = 'Reporting' }
        )
    }
}

Describe '_Resolve-EnvironmentName' {

    It 'builds the name from project and type, independent of the stage' {
        $dev  = & (Get-Module ZeroFailed.Deploy.Fabric) { _Resolve-EnvironmentName -Config $args[0] -WorkspaceId 'Bronze' -EnvironmentName 'Dev' } $script:testConfig
        $prod = & (Get-Module ZeroFailed.Deploy.Fabric) { _Resolve-EnvironmentName -Config $args[0] -WorkspaceId 'Bronze' -EnvironmentName 'Production' } $script:testConfig
        $dev  | Should -Be 'salesanalytics-Bronze Env'
        $prod | Should -Be 'salesanalytics-Bronze Env'   # same across stages
    }

    It 'uses the workspace type short code, not the full type name' {
        $name = & (Get-Module ZeroFailed.Deploy.Fabric) { _Resolve-EnvironmentName -Config $args[0] -WorkspaceId 'Report' -EnvironmentName 'Dev' } $script:testConfig
        $name | Should -Be 'salesanalytics-Report Env'
    }

    It 'defaults to the {project} - {type} - Env template when none is set on the config' {
        $cfg = $script:testConfig | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $cfg.namingConvention.PSObject.Properties.Remove('environmentNameTemplate')
        $name = & (Get-Module ZeroFailed.Deploy.Fabric) { _Resolve-EnvironmentName -Config $args[0] -WorkspaceId 'Bronze' } $cfg
        $name | Should -Be 'salesanalytics-Bronze Env'
    }

    It 'still resolves a legacy {workspace} template using the stage-specific workspace name' {
        $cfg = $script:testConfig | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $cfg.namingConvention.environmentNameTemplate = '{workspace} Env'
        $name = & (Get-Module ZeroFailed.Deploy.Fabric) { _Resolve-EnvironmentName -Config $args[0] -WorkspaceId 'Bronze' -EnvironmentName 'Dev' } $cfg
        $name | Should -Be 'salesanalytics-Bronze [DEV] Env'
    }

    It 'throws when a legacy {workspace} template is used without an environment name' {
        $cfg = $script:testConfig | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $cfg.namingConvention.environmentNameTemplate = '{workspace} Env'
        { & (Get-Module ZeroFailed.Deploy.Fabric) { _Resolve-EnvironmentName -Config $args[0] -WorkspaceId 'Bronze' } $cfg } |
            Should -Throw
    }

    It 'throws for an unknown workspace id' {
        { & (Get-Module ZeroFailed.Deploy.Fabric) { _Resolve-EnvironmentName -Config $args[0] -WorkspaceId 'nope' -EnvironmentName 'Dev' } $script:testConfig } |
            Should -Throw
    }
}
