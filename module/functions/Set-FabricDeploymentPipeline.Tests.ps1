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

    It 'returns a Stages map of environment -> workspace id' {
        Mock Test-FabricWorkspaceExists {
            param($DisplayName)
            [pscustomobject]@{ id = "ws-$($DisplayName -replace '.*\[(\w+)\].*', '$1')" }
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
                        [pscustomobject]@{ id = 'stage-dev';  order = 0; displayName = 'Dev' }
                        [pscustomobject]@{ id = 'stage-test'; order = 1; displayName = 'Test' }
                        [pscustomobject]@{ id = 'stage-prod'; order = 2; displayName = 'Production' }
                    )
                }
            }
            return $null
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricDeploymentPipeline -Config $script:config -WorkspaceType 'Bronze' -Token 'tok'
        ($result.Stages.Keys -join ',')  | Should -Be 'Dev,Test,Production'
        $result.Stages['Dev']            | Should -Be 'ws-DEV'
        $result.Stages['Production']     | Should -Be 'ws-PROD'
    }

    Context 'with caller-supplied workspace ids (-KnownWorkspaceIds)' {

        It 'uses the supplied ids and makes no workspace lookups when every environment is covered' {
            Mock Test-FabricWorkspaceExists { throw 'Test-FabricWorkspaceExists should not be called' } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Resolve-WorkspaceName { throw '_Resolve-WorkspaceName should not be called' } -ModuleName ZeroFailed.Deploy.Fabric

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

            $known = @{ Dev = 'ws-DEV'; Test = 'ws-TEST'; Production = 'ws-PROD' }
            $result = Set-FabricDeploymentPipeline -Config $script:config -WorkspaceType 'Bronze' -Token 'tok' -KnownWorkspaceIds $known

            $result.Action         | Should -Be 'Created'
            $result.StagesAssigned | Should -Be 3
            $result.Stages['Dev']  | Should -Be 'ws-DEV'
            Should -Invoke Test-FabricWorkspaceExists -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke _Resolve-WorkspaceName     -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'falls back to a live lookup only for environments not in the map' {
            Mock Test-FabricWorkspaceExists {
                param($DisplayName)
                [pscustomobject]@{ id = "ws-$($DisplayName -replace '.*\[(\w+)\].*', '$1')" }
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
                            [pscustomobject]@{ id = 'stage-dev';  order = 0; displayName = 'Dev' }
                            [pscustomobject]@{ id = 'stage-test'; order = 1; displayName = 'Test' }
                            [pscustomobject]@{ id = 'stage-prod'; order = 2; displayName = 'Production' }
                        )
                    }
                }
                return $null
            } -ModuleName ZeroFailed.Deploy.Fabric

            $result = Set-FabricDeploymentPipeline -Config $script:config -WorkspaceType 'Bronze' -Token 'tok' -KnownWorkspaceIds @{ Dev = 'ws-DEV' }

            $result.Stages['Dev']  | Should -Be 'ws-DEV'
            $result.Stages['Test'] | Should -Be 'ws-TEST'
            # Only Test + Production are looked up; Dev came from the map.
            Should -Invoke Test-FabricWorkspaceExists -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'builds the Stages map from the supplied ids under -WhatIf without any API calls' {
            Mock Test-FabricWorkspaceExists { throw 'should not be called' } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Invoke-FabricRestMethod  { throw 'should not be called' } -ModuleName ZeroFailed.Deploy.Fabric

            $result = Set-FabricDeploymentPipeline -Config $script:config -WorkspaceType 'Bronze' -Token 'tok' `
                -KnownWorkspaceIds @{ Dev = 'ws-DEV' } -WhatIf

            $result.Action         | Should -Be 'WhatIf'
            $result.Stages['Dev']  | Should -Be 'ws-DEV'
            $result.Stages['Test'] | Should -BeNullOrEmpty
            Should -Invoke Test-FabricWorkspaceExists -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }
    }
}

Describe 'Set-FabricDeploymentPipeline — StrictMode safety' {

    # The ZeroFailed build harness (e.g. in Azure DevOps) runs under Set-StrictMode, where
    # accessing a property the API omitted throws "The property X cannot be found on this object".
    # The real Fabric API omits 'continuationToken' on the last page and 'workspaceId' on
    # unassigned stages. InModuleScope runs in the module's session state so StrictMode applies
    # to the function under test, reproducing the ADO condition.
    It 'completes when responses omit continuationToken and stage workspaceId' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            Set-StrictMode -Version Latest

            $cfg = New-FabricTopologyConfig `
                -Project         'salesanalytics' `
                -WorkspaceTypes  @('Bronze') `
                -Environments    @('Dev', 'Test', 'Production') `
                -CapacityMap     @{ Dev = 'cap-dev'; Test = 'cap-test'; Production = 'cap-prod' } `
                -EnablePipelines @('Bronze')

            Mock Test-FabricWorkspaceExists {
                param($DisplayName)
                [pscustomobject]@{ id = "ws-$($DisplayName -replace '.*\[(\w+)\].*', '$1')" }
            }

            Mock _Invoke-FabricRestMethod {
                param($Method, $RelativeUri)
                if ($Method -eq 'GET' -and $RelativeUri -eq 'deploymentPipelines') {
                    # Single/last page — API omits continuationToken entirely
                    return [pscustomobject]@{ value = @() }
                }
                if ($Method -eq 'POST' -and $RelativeUri -eq 'deploymentPipelines') {
                    # Freshly created stages carry no workspaceId property at all
                    return [pscustomobject]@{
                        id     = 'pipeline-001'
                        stages = @(
                            [pscustomobject]@{ id = 'stage-dev';  order = 0; displayName = 'Dev' }
                            [pscustomobject]@{ id = 'stage-test'; order = 1; displayName = 'Test' }
                            [pscustomobject]@{ id = 'stage-prod'; order = 2; displayName = 'Production' }
                        )
                    }
                }
                return $null
            }

            $result = Set-FabricDeploymentPipeline -Config $cfg -WorkspaceType 'Bronze' -Token 'tok'
            $result.Action         | Should -Be 'Created'
            $result.StagesAssigned | Should -Be 3
        }
    }
}
