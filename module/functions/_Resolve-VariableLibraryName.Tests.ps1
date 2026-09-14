#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    $script:testConfig = [pscustomobject]@{
        project          = 'salesanalytics'
        namingConvention = [pscustomobject]@{
            template                    = '{project}-{type} [{env}]'
            variableLibraryNameTemplate = '{project}-{type} Variables'
            maxLength                   = 64
            typeShortCodes              = [pscustomobject]@{
                Bronze    = 'Bronze'
                Reporting = 'Report'
            }
            envShortCodes               = [pscustomobject]@{
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

    function Resolve-Name($Config, $WorkspaceId) {
        & (Get-Module ZeroFailed.Deploy.Fabric) { _Resolve-VariableLibraryName -Config $args[0] -WorkspaceId $args[1] } $Config $WorkspaceId
    }

    function Copy-TestConfig {
        $script:testConfig | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    }
}

Describe '_Resolve-VariableLibraryName' {

    It 'builds the name from project and type' {
        Resolve-Name $script:testConfig 'Bronze' | Should -Be 'salesanalytics-Bronze Variables'
    }

    It 'uses the workspace type short code, not the full type name' {
        Resolve-Name $script:testConfig 'Report' | Should -Be 'salesanalytics-Report Variables'
    }

    It 'defaults to the {project}-{type} Variables template when none is set on the config' {
        $cfg = Copy-TestConfig
        $cfg.namingConvention.PSObject.Properties.Remove('variableLibraryNameTemplate')
        Resolve-Name $cfg 'Bronze' | Should -Be 'salesanalytics-Bronze Variables'
    }

    It 'honours a custom template' {
        $cfg = Copy-TestConfig
        $cfg.namingConvention.variableLibraryNameTemplate = 'Config_{type}'
        Resolve-Name $cfg 'Bronze' | Should -Be 'Config_Bronze'
    }

    It 'throws when the template uses a stage-specific token' {
        $cfg = Copy-TestConfig
        $cfg.namingConvention.variableLibraryNameTemplate = '{project}-{type} {env}'
        { Resolve-Name $cfg 'Bronze' } | Should -Throw '*Only {project} and {type} are supported*'
    }

    It 'throws when the resolved name does not start with a letter' {
        $cfg = Copy-TestConfig
        $cfg.project = '1sales'
        { Resolve-Name $cfg 'Bronze' } | Should -Throw '*is invalid*'
    }

    It 'throws when the resolved name contains a character Fabric does not allow' {
        $cfg = Copy-TestConfig
        $cfg.namingConvention.variableLibraryNameTemplate = '{project}-{type} [Vars]'
        { Resolve-Name $cfg 'Bronze' } | Should -Throw '*is invalid*'
    }

    It 'throws for an unknown workspace id' {
        { Resolve-Name $script:testConfig 'nope' } | Should -Throw
    }
}
