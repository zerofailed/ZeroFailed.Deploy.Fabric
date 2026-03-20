#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Real config — _Resolve-WorkspaceName is pure string logic, no mocking needed
    $script:config = New-FabricTopologyConfig `
        -Project         'salesanalytics' `
        -WorkspaceTypes  @('Bronze', 'Gold') `
        -Environments    @('Dev', 'Test', 'Production') `
        -CapacityMap     @{ Dev = 'cap-dev'; Test = 'cap-test'; Production = 'cap-prod' } `
        -EnablePipelines @('Bronze')

    # Resolved workspace display names for Bronze
    # salesanalytics-Bronze [DEV], salesanalytics-Bronze [TEST], salesanalytics-Bronze [PROD]
    $script:wsNames = @{
        Dev        = 'salesanalytics-Bronze [DEV]'
        Test       = 'salesanalytics-Bronze [TEST]'
        Production = 'salesanalytics-Bronze [PROD]'
    }
}

Describe 'Set-FabricDeploymentPipeline' {

    It 'returns WhatIf placeholder when -WhatIf is specified' {
        $result = Set-FabricDeploymentPipeline -Config $script:config -WorkspaceType 'Bronze' -Token 'tok' -WhatIf
        $result.Action       | Should -Be 'WhatIf'
        $result.PipelineName | Should -Be 'salesanalytics-Bronze Pipeline'
        $result.WorkspaceType | Should -Be 'Bronze'
    }

    It 'creates pipeline and assigns all stages when no pipeline exists' {
        Mock Test-FabricWorkspaceExists {
            param($DisplayName)
            [pscustomobject]@{ id = "ws-$($DisplayName -replace '.*\[(\w+)\].*', '$1')" }
        } -ModuleName ZeroFailed.Deploy.Fabric

        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri, $Body)
            if ($Method -eq 'GET' -and $RelativeUri -eq 'deploymentPipelines') {
                return [pscustomobject]@{ value = @(); continuationToken = $null }
            }
            if ($Method -eq 'POST' -and $RelativeUri -eq 'deploymentPipelines') {
                return [pscustomobject]@{
                    id     = 'pipeline-001'
                    stages = @(
                        [pscustomobject]@{ id = 'stage-dev';  order = 0; displayName = 'Dev';        workspaceId = $null }
                        [pscustomobject]@{ id = 'stage-test'; order = 1; displayName = 'Test';       workspaceId = $null }
                        [pscustomobject]@{ id = 'stage-prod'; order = 2; displayName = 'Production'; workspaceId = $null }
                    )
                }
            }
            # POST assignWorkspace returns empty body
            return $null
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricDeploymentPipeline -Config $script:config -WorkspaceType 'Bronze' -Token 'tok'
        $result.Action         | Should -Be 'Created'
        $result.PipelineId     | Should -Be 'pipeline-001'
        $result.StagesAssigned | Should -Be 3

        # GET pipelines + POST create + POST assign x3
        Should -Invoke _Invoke-FabricRestMethod -Times 5 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'returns Skipped when pipeline exists and all stages are correctly assigned' {
        Mock Test-FabricWorkspaceExists {
            param($DisplayName)
            [pscustomobject]@{ id = "ws-$($DisplayName -replace '.*\[(\w+)\].*', '$1')" }
        } -ModuleName ZeroFailed.Deploy.Fabric

        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri)
            if ($Method -eq 'GET' -and $RelativeUri -eq 'deploymentPipelines') {
                return [pscustomobject]@{
                    value = @([pscustomobject]@{ id = 'pipeline-001'; displayName = 'salesanalytics-Bronze Pipeline' })
                    continuationToken = $null
                }
            }
            if ($Method -eq 'GET' -and $RelativeUri -match '/stages$') {
                return [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{ id = 'stage-dev';  order = 0; displayName = 'Dev';        workspaceId = 'ws-DEV' }
                        [pscustomobject]@{ id = 'stage-test'; order = 1; displayName = 'Test';       workspaceId = 'ws-TEST' }
                        [pscustomobject]@{ id = 'stage-prod'; order = 2; displayName = 'Production'; workspaceId = 'ws-PROD' }
                    )
                }
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricDeploymentPipeline -Config $script:config -WorkspaceType 'Bronze' -Token 'tok'
        $result.Action         | Should -Be 'Skipped'
        $result.StagesAssigned | Should -Be 0

        Should -Invoke _Invoke-FabricRestMethod -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'assigns missing stage workspace when pipeline exists and a stage is vacant' {
        Mock Test-FabricWorkspaceExists {
            param($DisplayName)
            [pscustomobject]@{ id = "ws-$($DisplayName -replace '.*\[(\w+)\].*', '$1')" }
        } -ModuleName ZeroFailed.Deploy.Fabric

        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri)
            if ($Method -eq 'GET' -and $RelativeUri -eq 'deploymentPipelines') {
                return [pscustomobject]@{
                    value = @([pscustomobject]@{ id = 'pipeline-001'; displayName = 'salesanalytics-Bronze Pipeline' })
                    continuationToken = $null
                }
            }
            if ($Method -eq 'GET' -and $RelativeUri -match '/stages$') {
                return [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{ id = 'stage-dev';  order = 0; displayName = 'Dev';        workspaceId = 'ws-DEV' }
                        [pscustomobject]@{ id = 'stage-test'; order = 1; displayName = 'Test';       workspaceId = $null }
                        [pscustomobject]@{ id = 'stage-prod'; order = 2; displayName = 'Production'; workspaceId = $null }
                    )
                }
            }
            return $null
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricDeploymentPipeline -Config $script:config -WorkspaceType 'Bronze' -Token 'tok'
        $result.Action         | Should -Be 'Updated'
        $result.StagesAssigned | Should -Be 2

        # GET pipelines + GET stages + POST assign x2
        Should -Invoke _Invoke-FabricRestMethod -Times 4 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'skips stage assignment when workspace does not yet exist' {
        Mock Test-FabricWorkspaceExists {
            param($DisplayName)
            if ($DisplayName -eq 'salesanalytics-Bronze [DEV]') {
                return [pscustomobject]@{ id = 'ws-DEV' }
            }
            return $null   # Test and Production workspaces don't exist yet
        } -ModuleName ZeroFailed.Deploy.Fabric

        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri)
            if ($Method -eq 'GET' -and $RelativeUri -eq 'deploymentPipelines') {
                return [pscustomobject]@{ value = @(); continuationToken = $null }
            }
            if ($Method -eq 'POST' -and $RelativeUri -eq 'deploymentPipelines') {
                return [pscustomobject]@{
                    id     = 'pipeline-001'
                    stages = @(
                        [pscustomobject]@{ id = 'stage-dev';  order = 0; displayName = 'Dev';        workspaceId = $null }
                        [pscustomobject]@{ id = 'stage-test'; order = 1; displayName = 'Test';       workspaceId = $null }
                        [pscustomobject]@{ id = 'stage-prod'; order = 2; displayName = 'Production'; workspaceId = $null }
                    )
                }
            }
            return $null
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricDeploymentPipeline -Config $script:config -WorkspaceType 'Bronze' -Token 'tok'
        $result.Action         | Should -Be 'Created'
        $result.StagesAssigned | Should -Be 1  # Only Dev assigned

        # GET pipelines + POST create + POST assign x1 (only Dev)
        Should -Invoke _Invoke-FabricRestMethod -Times 3 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'iterates continuation token to find pipeline on second page' {
        Mock Test-FabricWorkspaceExists { $null } -ModuleName ZeroFailed.Deploy.Fabric

        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri)
            if ($Method -eq 'GET' -and $RelativeUri -eq 'deploymentPipelines') {
                return [pscustomobject]@{
                    value             = @([pscustomobject]@{ id = 'other-001'; displayName = 'Other Pipeline' })
                    continuationToken = 'token-abc'
                }
            }
            if ($Method -eq 'GET' -and $RelativeUri -match 'continuationToken') {
                return [pscustomobject]@{
                    value             = @([pscustomobject]@{ id = 'pipeline-001'; displayName = 'salesanalytics-Bronze Pipeline' })
                    continuationToken = $null
                }
            }
            # GET stages
            return [pscustomobject]@{ value = @() }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricDeploymentPipeline -Config $script:config -WorkspaceType 'Bronze' -Token 'tok'
        $result.PipelineId | Should -Be 'pipeline-001'
        $result.Action     | Should -Be 'Skipped'
    }

    It 'propagates error when pipeline list API call fails' {
        Mock Test-FabricWorkspaceExists { $null } -ModuleName ZeroFailed.Deploy.Fabric
        Mock _Invoke-FabricRestMethod { throw 'API unavailable' } -ModuleName ZeroFailed.Deploy.Fabric

        { Set-FabricDeploymentPipeline -Config $script:config -WorkspaceType 'Bronze' -Token 'tok' } |
            Should -Throw
    }

    It 'returns correct report fields' {
        Mock Test-FabricWorkspaceExists { $null } -ModuleName ZeroFailed.Deploy.Fabric

        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') {
                return [pscustomobject]@{
                    value = @([pscustomobject]@{ id = 'pipeline-999'; displayName = 'salesanalytics-Bronze Pipeline' })
                    continuationToken = $null
                }
            }
            return [pscustomobject]@{ value = @() }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricDeploymentPipeline -Config $script:config -WorkspaceType 'Bronze' -Token 'tok'
        $result.PipelineName  | Should -Be 'salesanalytics-Bronze Pipeline'
        $result.PipelineId    | Should -Be 'pipeline-999'
        $result.WorkspaceType | Should -Be 'Bronze'
    }
}
