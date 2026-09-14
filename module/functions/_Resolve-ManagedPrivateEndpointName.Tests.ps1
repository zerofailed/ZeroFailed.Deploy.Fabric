#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    $script:testConfig = [pscustomobject]@{
        project          = 'salesanalytics'
        namingConvention = [pscustomobject]@{
            template                           = '{project}-{type} [{env}]'
            managedPrivateEndpointNameTemplate = '{project}-{type}-{name}-{env}'
            maxLength                          = 64
            typeShortCodes                     = [pscustomobject]@{
                Bronze    = 'Bronze'
                Reporting = 'Report'
                DataPrep  = 'Data Prep'
            }
            envShortCodes                      = [pscustomobject]@{
                Dev        = 'DEV'
                Production = 'PROD'
            }
        }
        environments     = @(
            [pscustomobject]@{ name = 'Dev';        shortCode = 'DEV';  capacityName = 'cap-dev' }
            [pscustomobject]@{ name = 'Production'; shortCode = 'PROD'; capacityName = 'cap-prod' }
        )
        workspaces       = @(
            [pscustomobject]@{ id = 'Bronze';   type = 'Bronze'    }
            [pscustomobject]@{ id = 'Report';   type = 'Reporting' }
            [pscustomobject]@{ id = 'DataPrep'; type = 'DataPrep'  }
        )
    }

    function Resolve-MpeName([pscustomobject]$Config, [string]$WorkspaceId, [string]$EnvironmentName, [string]$EndpointName) {
        & (Get-Module ZeroFailed.Deploy.Fabric) {
            param($c, $w, $e, $n)
            _Resolve-ManagedPrivateEndpointName -Config $c -WorkspaceId $w -EnvironmentName $e -EndpointName $n
        } $Config $WorkspaceId $EnvironmentName $EndpointName
    }

    function Copy-TestConfig {
        $script:testConfig | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    }
}

Describe '_Resolve-ManagedPrivateEndpointName' {

    It 'builds the name from project, type, endpoint name and stage' {
        Resolve-MpeName $script:testConfig 'Bronze' 'Dev' 'KeyVault' | Should -Be 'salesanalytics-Bronze-KeyVault-DEV'
    }

    It 'changes with the stage, since each stage targets its own resource' {
        Resolve-MpeName $script:testConfig 'Bronze' 'Production' 'KeyVault' | Should -Be 'salesanalytics-Bronze-KeyVault-PROD'
    }

    It 'uses the workspace type short code, not the full type name' {
        Resolve-MpeName $script:testConfig 'Report' 'Dev' 'Storage-Blob' | Should -Be 'salesanalytics-Report-Storage-Blob-DEV'
    }

    It 'honours a custom template' {
        $cfg = Copy-TestConfig
        $cfg.namingConvention.managedPrivateEndpointNameTemplate = '{name}_{env}'
        Resolve-MpeName $cfg 'Bronze' 'Dev' 'KeyVault' | Should -Be 'KeyVault_DEV'
    }

    It 'defaults the template for a config that predates managed private endpoints' {
        $cfg = Copy-TestConfig
        $cfg.namingConvention.PSObject.Properties.Remove('managedPrivateEndpointNameTemplate')
        Resolve-MpeName $cfg 'Bronze' 'Dev' 'KeyVault' | Should -Be 'salesanalytics-Bronze-KeyVault-DEV'
    }

    It 'replaces characters that are not valid in an endpoint name' {
        # The 'Data Prep' short code contains a space
        Resolve-MpeName $script:testConfig 'DataPrep' 'Dev' 'KeyVault' | Should -Be 'salesanalytics-Data-Prep-KeyVault-DEV'
    }

    It 'throws rather than truncating a name over 64 characters' {
        { Resolve-MpeName $script:testConfig 'Bronze' 'Dev' ('x' * 60) } | Should -Throw '*64-character limit*'
    }

    It 'throws on an unresolved token' {
        $cfg = Copy-TestConfig
        $cfg.namingConvention.managedPrivateEndpointNameTemplate = '{project}-{region}-{name}'
        { Resolve-MpeName $cfg 'Bronze' 'Dev' 'KeyVault' } | Should -Throw '*Unresolved token*'
    }

    It 'throws for an unknown workspace id' {
        { Resolve-MpeName $script:testConfig 'nope' 'Dev' 'KeyVault' } | Should -Throw
    }

    It 'throws for an unknown environment' {
        { Resolve-MpeName $script:testConfig 'Bronze' 'Staging' 'KeyVault' } | Should -Throw
    }
}
