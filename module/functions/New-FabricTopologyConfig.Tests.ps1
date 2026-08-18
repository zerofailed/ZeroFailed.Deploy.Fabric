#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Base params without any Git config — used for tests that don't need Git
    $script:commonParams = @{
        Project        = 'salesanalytics'
        WorkspaceTypes = @('Bronze', 'Silver', 'Gold', 'Reporting')
        Environments   = @('Dev', 'Test', 'Acceptance', 'Production')
        CapacityMap    = @{ Dev = 'cap-dev'; Test = 'cap-test'; Acceptance = 'cap-acc'; Production = 'cap-prod' }
    }

    # Git params added on top of commonParams for Git-specific tests
    $script:gitParams = @{
        GitProvider        = 'AzureDevOps'
        GitOrganisation    = 'contoso'
        GitProject         = 'SalesAnalytics'
        GitEnvironment     = 'Dev'
        GitWorkspaceConfig = @{
            Bronze = @{ RepositoryName = 'salesanalytics-bronze'; Branch = 'feature/dev' }
            Silver = @{ RepositoryName = 'salesanalytics-silver'; Branch = 'feature/dev' }
            Gold   = @{ RepositoryName = 'salesanalytics-gold';   Branch = 'feature/dev' }
        }
    }
}

Describe 'New-FabricTopologyConfig' {

    It 'returns a config object with correct project name' {
        $config = New-FabricTopologyConfig @script:commonParams
        $config.project | Should -Be 'salesanalytics'
    }

    It 'generates the correct number of environments' {
        $config = New-FabricTopologyConfig @script:commonParams
        $config.environments.Count | Should -Be 4
    }

    It 'generates the correct number of workspaces' {
        $config = New-FabricTopologyConfig @script:commonParams
        $config.workspaces.Count | Should -Be 4
    }

    It 'assigns correct capacity names' {
        $config = New-FabricTopologyConfig @script:commonParams
        $devEnv = $config.environments | Where-Object { $_.name -eq 'Dev' }
        $devEnv.capacityName | Should -Be 'cap-dev'
    }

    It 'enables identity only for specified types' {
        $config = New-FabricTopologyConfig @script:commonParams -EnableIdentity @('Bronze', 'Silver', 'Gold')
        $reportingWs = $config.workspaces | Where-Object { $_.type -eq 'Reporting' }
        $reportingWs.identity.enabled | Should -Be $false

        $bronzeWs = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $bronzeWs.identity.enabled | Should -Be $true
    }

    It 'enables identity for all types by default' {
        $config = New-FabricTopologyConfig @script:commonParams
        $config.workspaces | ForEach-Object {
            $_.identity.enabled | Should -Be $true
        }
    }

    It 'enables monitoring only for specified types' {
        $config = New-FabricTopologyConfig @script:commonParams -EnableMonitoring @('Bronze', 'Silver')
        $bronzeWs    = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $reportingWs = $config.workspaces | Where-Object { $_.type -eq 'Reporting' }
        $bronzeWs.monitoring.enabled    | Should -Be $true
        $reportingWs.monitoring.enabled | Should -Be $false
    }

    It 'disables monitoring for all types by default' {
        $config = New-FabricTopologyConfig @script:commonParams
        $config.workspaces | ForEach-Object {
            $_.monitoring.enabled | Should -Be $false
        }
    }

    It 'normalises project name by replacing invalid chars with hyphens, preserving casing' {
        $config = New-FabricTopologyConfig @script:commonParams -Project 'Sales Analytics!'
        $config.project | Should -Be 'Sales-Analytics-'
    }

    It 'throws if CapacityMap is missing an environment entry' {
        $params = $script:commonParams.Clone()
        $params.CapacityMap = @{ Dev = 'cap-dev' }  # missing Test, Acceptance, Production
        { New-FabricTopologyConfig @params } | Should -Throw
    }

    It 'writes JSON to OutputPath when specified' {
        $outFile = Join-Path $TestDrive 'topology.json'
        New-FabricTopologyConfig @script:commonParams -OutputPath $outFile | Out-Null
        Test-Path $outFile | Should -Be $true
        $json = Get-Content $outFile -Raw | ConvertFrom-Json
        $json.project | Should -Be 'salesanalytics'
    }
}

Describe 'New-FabricTopologyConfig — Git configuration' {

    It 'disables Git for all workspaces when GitWorkspaceConfig is not provided' {
        $config = New-FabricTopologyConfig @script:commonParams
        $config.workspaces | ForEach-Object {
            $_.git.enabled | Should -Be $false
        }
        $config.gitEnvironment | Should -BeNullOrEmpty
    }

    It 'enables Git only for workspace types listed in GitWorkspaceConfig' {
        $config = New-FabricTopologyConfig @script:commonParams @script:gitParams
        $bronzeWs    = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $reportingWs = $config.workspaces | Where-Object { $_.type -eq 'Reporting' }
        $bronzeWs.git.enabled    | Should -Be $true
        $reportingWs.git.enabled | Should -Be $false
    }

    It 'stores the correct gitEnvironment in the top-level config' {
        $config = New-FabricTopologyConfig @script:commonParams @script:gitParams
        $config.gitEnvironment | Should -Be 'Dev'
    }

    It 'stores gitEnvironment as null when GitWorkspaceConfig is not provided' {
        $config = New-FabricTopologyConfig @script:commonParams
        $config.gitEnvironment | Should -BeNullOrEmpty
    }

    It 'stores correct repositoryName and branch from GitWorkspaceConfig' {
        $config = New-FabricTopologyConfig @script:commonParams @script:gitParams
        $bronzeWs = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $bronzeWs.git.repositoryName | Should -Be 'salesanalytics-bronze'
        $bronzeWs.git.branch         | Should -Be 'feature/dev'
    }

    It 'defaults rootFolder to fabric when not specified in GitWorkspaceConfig' {
        $config = New-FabricTopologyConfig @script:commonParams @script:gitParams
        $bronzeWs = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $bronzeWs.git.rootFolder | Should -Be 'fabric'
    }

    It 'uses rootFolder from GitWorkspaceConfig when specified' {
        $params = @{
            GitProvider        = 'AzureDevOps'
            GitOrganisation    = 'contoso'
            GitProject         = 'SalesAnalytics'
            GitEnvironment     = 'Dev'
            GitWorkspaceConfig = @{
                Gold = @{ RepositoryName = 'salesanalytics-gold'; RootFolder = 'gold-data' }
            }
        }
        $config = New-FabricTopologyConfig @script:commonParams @params
        $goldWs = $config.workspaces | Where-Object { $_.type -eq 'Gold' }
        $goldWs.git.rootFolder | Should -Be 'gold-data'
    }

    It 'defaults branch to main when not specified in GitWorkspaceConfig' {
        $params = @{
            GitProvider        = 'AzureDevOps'
            GitOrganisation    = 'contoso'
            GitProject         = 'SalesAnalytics'
            GitEnvironment     = 'Dev'
            GitWorkspaceConfig = @{
                Gold = @{ RepositoryName = 'salesanalytics-gold' }
            }
        }
        $config = New-FabricTopologyConfig @script:commonParams @params
        $goldWs = $config.workspaces | Where-Object { $_.type -eq 'Gold' }
        $goldWs.git.branch | Should -Be 'main'
    }

    It 'uses ownerName for GitHub provider' {
        $params = @{
            GitProvider        = 'GitHub'
            GitOrganisation    = 'contoso'
            GitEnvironment     = 'Dev'
            GitWorkspaceConfig = @{
                Bronze = @{ RepositoryName = 'salesanalytics-bronze' }
            }
        }
        $config = New-FabricTopologyConfig @script:commonParams @params
        $bronzeWs = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $bronzeWs.git.ownerName | Should -Be 'contoso'
    }

    It 'sets gitEnvironment to null when GitEnvironment is empty string' {
        $params = @{
            GitProvider        = 'AzureDevOps'
            GitOrganisation    = 'contoso'
            GitProject         = 'SalesAnalytics'
            GitEnvironment     = ''
            GitWorkspaceConfig = @{
                Bronze = @{ RepositoryName = 'salesanalytics-bronze' }
            }
        }
        $config = New-FabricTopologyConfig @script:commonParams @params
        $bronzeWs = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $bronzeWs.git.enabled  | Should -Be $false
        $config.gitEnvironment | Should -BeNullOrEmpty
    }

    It 'throws if GitWorkspaceConfig is provided without GitProvider' {
        $params = $script:commonParams.Clone()
        $params.GitOrganisation    = 'contoso'
        $params.GitProject         = 'SalesAnalytics'
        $params.GitWorkspaceConfig = @{ Bronze = @{ RepositoryName = 'repo' } }
        { New-FabricTopologyConfig @params } | Should -Throw
    }

    It 'throws if GitWorkspaceConfig is provided without GitOrganisation' {
        $params = $script:commonParams.Clone()
        $params.GitProvider        = 'AzureDevOps'
        $params.GitProject         = 'SalesAnalytics'
        $params.GitWorkspaceConfig = @{ Bronze = @{ RepositoryName = 'repo' } }
        { New-FabricTopologyConfig @params } | Should -Throw
    }

    It 'throws if AzureDevOps provider is used without GitProject' {
        $params = $script:commonParams.Clone()
        $params.GitProvider        = 'AzureDevOps'
        $params.GitOrganisation    = 'contoso'
        $params.GitWorkspaceConfig = @{ Bronze = @{ RepositoryName = 'repo' } }
        { New-FabricTopologyConfig @params } | Should -Throw
    }

    It 'throws if GitEnvironment is not in the Environments list' {
        $params = $script:commonParams.Clone()
        $params.GitProvider        = 'AzureDevOps'
        $params.GitOrganisation    = 'contoso'
        $params.GitProject         = 'SalesAnalytics'
        $params.GitEnvironment     = 'Staging'
        $params.GitWorkspaceConfig = @{ Bronze = @{ RepositoryName = 'repo' } }
        { New-FabricTopologyConfig @params } | Should -Throw
    }

    It 'throws if GitWorkspaceConfig references a type not in WorkspaceTypes' {
        $params = $script:commonParams.Clone()
        $params.GitProvider        = 'AzureDevOps'
        $params.GitOrganisation    = 'contoso'
        $params.GitProject         = 'SalesAnalytics'
        $params.GitWorkspaceConfig = @{ DataScience = @{ RepositoryName = 'repo' } }
        { New-FabricTopologyConfig @params } | Should -Throw
    }

    It 'throws if a GitWorkspaceConfig entry is missing RepositoryName' {
        $params = $script:commonParams.Clone()
        $params.GitProvider        = 'AzureDevOps'
        $params.GitOrganisation    = 'contoso'
        $params.GitProject         = 'SalesAnalytics'
        $params.GitWorkspaceConfig = @{ Bronze = @{ RootFolder = 'bronze' } }
        { New-FabricTopologyConfig @params } | Should -Throw
    }
}

Describe 'Config shape validation' {

    It 'namingConvention contains expected type short codes' {
        $config = New-FabricTopologyConfig `
            -Project       'test' `
            -WorkspaceTypes @('Bronze', 'ETL') `
            -Environments  @('Dev') `
            -CapacityMap   @{ Dev = 'cap-dev' }

        $config.namingConvention.typeShortCodes.Bronze | Should -Be 'Bronze'
        $config.namingConvention.typeShortCodes.ETL    | Should -Be 'ETL'
        $config.namingConvention.envShortCodes.Dev     | Should -Be 'DEV'
        $config.namingConvention.maxLength             | Should -Be 64
    }
}

Describe 'New-FabricTopologyConfig — custom workspace types and environments' {

    It 'accepts workspace type and environment names outside the built-in lists' {
        $config = New-FabricTopologyConfig `
            -Project        'test' `
            -WorkspaceTypes @('Lakehouse', 'Warehouse') `
            -Environments   @('Sandbox', 'Staging') `
            -CapacityMap    @{ Sandbox = 'cap-sandbox'; Staging = 'cap-staging' }

        $config.workspaces.Count   | Should -Be 2
        $config.environments.Count | Should -Be 2
        ($config.workspaces | Where-Object { $_.type -eq 'Lakehouse' }) | Should -Not -BeNullOrEmpty
    }

    It 'generates an uppercased, whitespace-stripped short code for a custom environment' {
        $config = New-FabricTopologyConfig `
            -Project        'test' `
            -WorkspaceTypes @('Lakehouse') `
            -Environments   @('Pre Prod') `
            -CapacityMap    @{ 'Pre Prod' = 'cap-preprod' }

        $config.namingConvention.envShortCodes.'Pre Prod' | Should -Be 'PREPROD'
    }

    It 'generates a whitespace-stripped, case-preserved short code for a custom workspace type' {
        $config = New-FabricTopologyConfig `
            -Project        'test' `
            -WorkspaceTypes @('Data Science') `
            -Environments   @('Dev') `
            -CapacityMap    @{ Dev = 'cap-dev' }

        $config.namingConvention.typeShortCodes.'Data Science' | Should -Be 'DataScience'
    }

    It 'still applies built-in short codes for known names alongside custom ones' {
        $config = New-FabricTopologyConfig `
            -Project        'test' `
            -WorkspaceTypes @('Reporting', 'Lakehouse') `
            -Environments   @('Production', 'Sandbox') `
            -CapacityMap    @{ Production = 'cap-prod'; Sandbox = 'cap-sandbox' }

        $config.namingConvention.typeShortCodes.Reporting | Should -Be 'Report'
        $config.namingConvention.typeShortCodes.Lakehouse | Should -Be 'Lakehouse'
        $config.namingConvention.envShortCodes.Production | Should -Be 'PROD'
        $config.namingConvention.envShortCodes.Sandbox    | Should -Be 'SANDBOX'
    }

    It 'honours -TypeShortCodes and -EnvShortCodes overrides above defaults and fallbacks' {
        $config = New-FabricTopologyConfig `
            -Project        'test' `
            -WorkspaceTypes @('Reporting', 'Lakehouse') `
            -Environments   @('Production', 'Sandbox') `
            -CapacityMap    @{ Production = 'cap-prod'; Sandbox = 'cap-sandbox' } `
            -TypeShortCodes @{ Reporting = 'RPT'; Lakehouse = 'LH' } `
            -EnvShortCodes  @{ Production = 'LIVE'; Sandbox = 'SBX' }

        $config.namingConvention.typeShortCodes.Reporting | Should -Be 'RPT'
        $config.namingConvention.typeShortCodes.Lakehouse | Should -Be 'LH'
        $config.namingConvention.envShortCodes.Production | Should -Be 'LIVE'
        $config.namingConvention.envShortCodes.Sandbox    | Should -Be 'SBX'
    }
}

Describe 'New-FabricTopologyConfig — RBAC configuration' {

    It 'produces an empty rbac entry per environment when no RoleAssignments are specified' {
        $config = New-FabricTopologyConfig @script:commonParams
        foreach ($ws in $config.workspaces) {
            $ws.rbac | Should -Not -BeNullOrEmpty
            $ws.rbac.Dev | Should -BeNullOrEmpty
        }
    }

    It 'applies a global rule to all workspace types and all environments' {
        $config = New-FabricTopologyConfig @script:commonParams -RoleAssignments @(
            @{ PrincipalId = 'grp-001'; PrincipalType = 'Group'; Role = 'Viewer' }
        )
        foreach ($ws in $config.workspaces) {
            foreach ($envName in @('Dev', 'Test', 'Acceptance', 'Production')) {
                $ws.rbac.$envName | Should -HaveCount 1
                $ws.rbac.$envName[0].principalId | Should -Be 'grp-001'
                $ws.rbac.$envName[0].role        | Should -Be 'Viewer'
            }
        }
    }

    It 'applies a workspace-type-scoped rule only to the specified types' {
        $config = New-FabricTopologyConfig @script:commonParams -RoleAssignments @(
            @{ PrincipalId = 'grp-002'; PrincipalType = 'Group'; Role = 'Contributor'; WorkspaceTypes = @('Bronze') }
        )
        $bronzeWs    = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $reportingWs = $config.workspaces | Where-Object { $_.type -eq 'Reporting' }

        $bronzeWs.rbac.Dev    | Should -HaveCount 1
        $reportingWs.rbac.Dev | Should -HaveCount 0
    }

    It 'applies an environment-scoped rule only to the specified environments' {
        $config = New-FabricTopologyConfig @script:commonParams -RoleAssignments @(
            @{ PrincipalId = 'grp-003'; PrincipalType = 'Group'; Role = 'Admin'; Environments = @('Dev') }
        )
        $bronzeWs = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $bronzeWs.rbac.Dev        | Should -HaveCount 1
        $bronzeWs.rbac.Test       | Should -HaveCount 0
        $bronzeWs.rbac.Production | Should -HaveCount 0
    }

    It 'applies a rule scoped to both workspace type and environment' {
        $config = New-FabricTopologyConfig @script:commonParams -RoleAssignments @(
            @{ PrincipalId = 'grp-004'; PrincipalType = 'User'; Role = 'Member';
               WorkspaceTypes = @('Gold'); Environments = @('Production') }
        )
        $goldWs   = $config.workspaces | Where-Object { $_.type -eq 'Gold' }
        $bronzeWs = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }

        $goldWs.rbac.Production | Should -HaveCount 1
        $goldWs.rbac.Dev        | Should -HaveCount 0
        $bronzeWs.rbac.Production | Should -HaveCount 0
    }

    It 'accumulates multiple rules when both apply' {
        $config = New-FabricTopologyConfig @script:commonParams -RoleAssignments @(
            @{ PrincipalId = 'grp-005'; PrincipalType = 'Group'; Role = 'Viewer' }
            @{ PrincipalId = 'grp-006'; PrincipalType = 'Group'; Role = 'Contributor'; WorkspaceTypes = @('Bronze') }
        )
        $bronzeWs = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $bronzeWs.rbac.Dev | Should -HaveCount 2
    }

    It 'stores principalId, principalType, and role on each resolved entry' {
        $config = New-FabricTopologyConfig @script:commonParams -RoleAssignments @(
            @{ PrincipalId = 'usr-007'; PrincipalType = 'User'; Role = 'Member'; Environments = @('Dev') }
        )
        $bronzeWs = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $entry    = $bronzeWs.rbac.Dev[0]
        $entry.principalId   | Should -Be 'usr-007'
        $entry.principalType | Should -Be 'User'
        $entry.role          | Should -Be 'Member'
    }

    It 'throws when a RoleAssignments entry is missing PrincipalId' {
        { New-FabricTopologyConfig @script:commonParams -RoleAssignments @(
            @{ PrincipalType = 'Group'; Role = 'Viewer' }
        )} | Should -Throw
    }

    It 'throws when a RoleAssignments entry has an invalid PrincipalType' {
        { New-FabricTopologyConfig @script:commonParams -RoleAssignments @(
            @{ PrincipalId = 'grp-x'; PrincipalType = 'Team'; Role = 'Viewer' }
        )} | Should -Throw
    }

    It 'throws when a RoleAssignments entry has an invalid Role' {
        { New-FabricTopologyConfig @script:commonParams -RoleAssignments @(
            @{ PrincipalId = 'grp-x'; PrincipalType = 'Group'; Role = 'Owner' }
        )} | Should -Throw
    }

    It 'throws when WorkspaceTypes references a type not in the topology' {
        { New-FabricTopologyConfig @script:commonParams -RoleAssignments @(
            @{ PrincipalId = 'grp-x'; PrincipalType = 'Group'; Role = 'Viewer'; WorkspaceTypes = @('DataScience') }
        )} | Should -Throw
    }

    It 'throws when Environments references an environment not in the topology' {
        { New-FabricTopologyConfig @script:commonParams -RoleAssignments @(
            @{ PrincipalId = 'grp-x'; PrincipalType = 'Group'; Role = 'Viewer'; Environments = @('Staging') }
        )} | Should -Throw
    }
}

Describe 'New-FabricTopologyConfig — Pipeline configuration' {

    It 'disables pipelines for all types by default' {
        $config = New-FabricTopologyConfig @script:commonParams
        $config.workspaces | ForEach-Object {
            $_.pipeline.enabled | Should -Be $false
        }
    }

    It 'enables pipelines only for specified types' {
        $config = New-FabricTopologyConfig @script:commonParams -EnablePipelines @('Bronze', 'Gold')
        $bronzeWs    = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $silverWs    = $config.workspaces | Where-Object { $_.type -eq 'Silver' }
        $goldWs      = $config.workspaces | Where-Object { $_.type -eq 'Gold' }
        $reportingWs = $config.workspaces | Where-Object { $_.type -eq 'Reporting' }

        $bronzeWs.pipeline.enabled    | Should -Be $true
        $goldWs.pipeline.enabled      | Should -Be $true
        $silverWs.pipeline.enabled    | Should -Be $false
        $reportingWs.pipeline.enabled | Should -Be $false
    }

    It 'enables pipeline for a single type' {
        $config = New-FabricTopologyConfig @script:commonParams -EnablePipelines @('Reporting')
        $reportingWs = $config.workspaces | Where-Object { $_.type -eq 'Reporting' }
        $bronzeWs    = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }

        $reportingWs.pipeline.enabled | Should -Be $true
        $bronzeWs.pipeline.enabled    | Should -Be $false
    }
}

Describe 'New-FabricTopologyConfig — Pipeline role assignments' {

    It 'produces an empty pipeline roleAssignments array when none are specified' {
        $config = New-FabricTopologyConfig @script:commonParams
        $config.workspaces | ForEach-Object {
            $_.pipeline.roleAssignments | Should -HaveCount 0
        }
    }

    It 'applies a pipeline role assignment to all pipeline-enabled workspace types by default' {
        $config = New-FabricTopologyConfig @script:commonParams `
            -EnablePipelines @('Bronze', 'Silver', 'Gold', 'Reporting') `
            -PipelineRoleAssignments @(
                @{ PrincipalId = 'grp-001'; PrincipalType = 'Group' }
            )
        $config.workspaces | ForEach-Object {
            $_.pipeline.roleAssignments | Should -HaveCount 1
            $_.pipeline.roleAssignments[0].principalId | Should -Be 'grp-001'
            $_.pipeline.roleAssignments[0].role        | Should -Be 'Admin'
        }
    }

    It 'omits pipeline role assignments for a type whose pipeline is not enabled' {
        $config = New-FabricTopologyConfig @script:commonParams `
            -EnablePipelines @('Bronze') `
            -PipelineRoleAssignments @(
                @{ PrincipalId = 'grp-001'; PrincipalType = 'Group' }
            )
        $bronzeWs    = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $reportingWs = $config.workspaces | Where-Object { $_.type -eq 'Reporting' }
        $bronzeWs.pipeline.roleAssignments    | Should -HaveCount 1
        $reportingWs.pipeline.enabled         | Should -Be $false
        $reportingWs.pipeline.roleAssignments | Should -HaveCount 0
    }

    It 'defaults the role to Admin when omitted' {
        $config = New-FabricTopologyConfig @script:commonParams `
            -EnablePipelines @('Bronze') `
            -PipelineRoleAssignments @(
                @{ PrincipalId = 'usr-001'; PrincipalType = 'User' }
            )
        $bronzeWs = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $bronzeWs.pipeline.roleAssignments[0].role          | Should -Be 'Admin'
        $bronzeWs.pipeline.roleAssignments[0].principalType | Should -Be 'User'
    }

    It 'scopes a pipeline role assignment to specific workspace types' {
        $config = New-FabricTopologyConfig @script:commonParams `
            -EnablePipelines @('Bronze', 'Reporting') `
            -PipelineRoleAssignments @(
                @{ PrincipalId = 'grp-001'; PrincipalType = 'Group'; WorkspaceTypes = @('Bronze') }
            )
        $bronzeWs    = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $reportingWs = $config.workspaces | Where-Object { $_.type -eq 'Reporting' }
        $bronzeWs.pipeline.roleAssignments    | Should -HaveCount 1
        $reportingWs.pipeline.roleAssignments | Should -HaveCount 0
    }

    It 'applies multiple pipeline role assignments to a single type' {
        $config = New-FabricTopologyConfig @script:commonParams `
            -EnablePipelines @('Bronze') `
            -PipelineRoleAssignments @(
                @{ PrincipalId = 'grp-001'; PrincipalType = 'Group';  WorkspaceTypes = @('Bronze') }
                @{ PrincipalId = 'sp-001';  PrincipalType = 'ServicePrincipal'; WorkspaceTypes = @('Bronze') }
            )
        $bronzeWs = $config.workspaces | Where-Object { $_.type -eq 'Bronze' }
        $bronzeWs.pipeline.roleAssignments | Should -HaveCount 2
    }

    It 'throws when a PipelineRoleAssignments entry is missing PrincipalId' {
        { New-FabricTopologyConfig @script:commonParams -PipelineRoleAssignments @(
            @{ PrincipalType = 'Group' }
        ) } | Should -Throw
    }

    It 'throws when a PipelineRoleAssignments entry has an invalid PrincipalType' {
        { New-FabricTopologyConfig @script:commonParams -PipelineRoleAssignments @(
            @{ PrincipalId = 'grp-001'; PrincipalType = 'Robot' }
        ) } | Should -Throw
    }

    It 'throws when a PipelineRoleAssignments entry specifies a non-Admin role' {
        { New-FabricTopologyConfig @script:commonParams -PipelineRoleAssignments @(
            @{ PrincipalId = 'grp-001'; PrincipalType = 'Group'; Role = 'Viewer' }
        ) } | Should -Throw
    }

    It 'throws when a PipelineRoleAssignments entry references an unknown workspace type' {
        { New-FabricTopologyConfig @script:commonParams -PipelineRoleAssignments @(
            @{ PrincipalId = 'grp-001'; PrincipalType = 'Group'; WorkspaceTypes = @('Platinum') }
        ) } | Should -Throw
    }
}
