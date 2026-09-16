#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    function New-TestConfig {
        [pscustomobject]@{
            project      = 'salesanalytics'
            environments = @(
                [pscustomobject]@{ name = 'Dev';  capacityName = 'cap-dev' }
                [pscustomobject]@{ name = 'Test'; capacityName = 'cap-test' }
            )
            workspaces   = @(
                [pscustomobject]@{
                    id       = 'Bronze'; type = 'Bronze'
                    pipeline = [pscustomobject]@{
                        enabled         = $true
                        roleAssignments = @(
                            [pscustomobject]@{ principalId = 'pg1'; principalType = 'Group'; role = 'Admin' }
                            [pscustomobject]@{ principalId = 'sp1'; principalType = 'ServicePrincipal'; role = 'Admin' }
                        )
                    }
                }
                [pscustomobject]@{
                    id       = 'Gold'; type = 'Gold'
                    pipeline = [pscustomobject]@{ enabled = $true; roleAssignments = @() }
                }
                [pscustomobject]@{
                    id       = 'Report'; type = 'Reporting'
                    pipeline = [pscustomobject]@{ enabled = $false; roleAssignments = @() }
                }
            )
        }
    }
}

Describe 'Invoke-FabricDeploymentPipelineSetup' {

    Context 'input validation' {
        It 'throws when ConfigPath does not exist' {
            { Invoke-FabricDeploymentPipelineSetup -ConfigPath './nonexistent.json' } | Should -Throw
        }
    }

    Context 'orchestration' {

        BeforeEach {
            Mock _Get-FabricAuthToken { @{ Token = 'tok'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1) } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Test-FabricTokenExpiry { $false } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricDeploymentPipeline {
                @{ Action = 'Created'; PipelineId = "pipe-$WorkspaceType"; PipelineName = "$WorkspaceType Pipeline"; WorkspaceType = $WorkspaceType }
            } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricDeploymentPipelineRoleAssignment { @{ Action = 'Created'; PipelineId = $PipelineId; PrincipalId = $PrincipalId } } -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'configures a pipeline for each pipeline-enabled workspace type and applies its role assignments' {
            $r = Invoke-FabricDeploymentPipelineSetup -Config (New-TestConfig)

            $r.Summary.Created               | Should -Be 2
            $r.Pipelines.Count               | Should -Be 2
            $r.PipelineRoleAssignments.Count | Should -Be 2     # both configured for Bronze; none for Gold
            $r.Failures.Count                | Should -Be 0

            Should -Invoke Set-FabricDeploymentPipeline -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $WorkspaceType -eq 'Bronze' }
            Should -Invoke Set-FabricDeploymentPipeline -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $WorkspaceType -eq 'Gold' }
            Should -Invoke Set-FabricDeploymentPipeline -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $WorkspaceType -eq 'Reporting' }
            Should -Invoke Set-FabricDeploymentPipelineRoleAssignment -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $PipelineId -eq 'pipe-Bronze' }
        }

        It 'summarises pipelines by action' {
            Mock Set-FabricDeploymentPipeline {
                $action = if ($WorkspaceType -eq 'Bronze') { 'Updated' } else { 'Skipped' }
                @{ Action = $action; PipelineId = "pipe-$WorkspaceType"; PipelineName = "$WorkspaceType Pipeline" }
            } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricDeploymentPipelineSetup -Config (New-TestConfig)

            $r.Summary.Created | Should -Be 0
            $r.Summary.Updated | Should -Be 1
            $r.Summary.Skipped | Should -Be 1
            $r.Summary.Failed  | Should -Be 0
        }

        It 'does not count WhatIf pipelines in the summary' {
            Mock Set-FabricDeploymentPipeline {
                @{ Action = 'WhatIf'; PipelineId = 'whatif-pipeline-id'; PipelineName = "$WorkspaceType Pipeline" }
            } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricDeploymentPipelineSetup -Config (New-TestConfig) -WhatIf

            $r.Pipelines.Count | Should -Be 2
            ($r.Summary.Created + $r.Summary.Updated + $r.Summary.Skipped + $r.Summary.Failed) | Should -Be 0
        }

        It 'configures the pipelines but skips pipeline role assignments with -SkipPipelineRbac' {
            $r = Invoke-FabricDeploymentPipelineSetup -Config (New-TestConfig) -SkipPipelineRbac

            $r.Pipelines.Count               | Should -Be 2
            $r.PipelineRoleAssignments.Count | Should -Be 0
            Should -Invoke Set-FabricDeploymentPipelineRoleAssignment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'records a failure, skips its role assignments and continues with other types when pipeline setup throws' {
            Mock Set-FabricDeploymentPipeline {
                if ($WorkspaceType -eq 'Bronze') { throw 'workspace(s) not found' }
                @{ Action = 'Created'; PipelineId = "pipe-$WorkspaceType"; PipelineName = "$WorkspaceType Pipeline" }
            } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricDeploymentPipelineSetup -Config (New-TestConfig) -WarningAction SilentlyContinue

            $r.Summary.Failed            | Should -Be 1
            $r.Summary.Created           | Should -Be 1     # Gold still configured
            $r.Failures.Count            | Should -Be 1
            $r.Failures[0].Step          | Should -Be 'Pipeline'
            $r.Failures[0].WorkspaceType | Should -Be 'Bronze'
            Should -Invoke Set-FabricDeploymentPipelineRoleAssignment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'records a non-fatal failure when a pipeline role assignment throws' {
            Mock Set-FabricDeploymentPipelineRoleAssignment {
                if ($PrincipalId -eq 'pg1') { throw 'pipeline rbac boom' }
                @{ Action = 'Created' }
            } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricDeploymentPipelineSetup -Config (New-TestConfig) -WarningAction SilentlyContinue

            $r.PipelineRoleAssignments.Count | Should -Be 1     # the other principal is still assigned
            $r.Summary.Failed                | Should -Be 0     # the pipeline itself succeeded
            $r.Failures.Count                | Should -Be 1
            $r.Failures[0].Step              | Should -Be 'PipelineRoleAssignment'
        }

        It 'warns and does nothing when no workspace type has pipelines enabled' {
            $config = New-TestConfig
            foreach ($ws in $config.workspaces) { $ws.pipeline.enabled = $false }

            $r = Invoke-FabricDeploymentPipelineSetup -Config $config -WarningVariable warnings -WarningAction SilentlyContinue

            $r.Pipelines.Count | Should -Be 0
            $warnings          | Should -Not -BeNullOrEmpty
            Should -Invoke Set-FabricDeploymentPipeline -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'refreshes the token when it is near expiry' {
            Mock _Test-FabricTokenExpiry { $true } -ModuleName ZeroFailed.Deploy.Fabric

            Invoke-FabricDeploymentPipelineSetup -Config (New-TestConfig) | Out-Null

            # initial acquisition + a refresh before each of the two pipeline-enabled types
            Should -Invoke _Get-FabricAuthToken -Times 3 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'loads the topology config from a JSON file via -ConfigPath' {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) "topology-$([guid]::NewGuid()).json"
            (New-TestConfig) | ConvertTo-Json -Depth 20 | Set-Content -Path $tmp
            try {
                $r = Invoke-FabricDeploymentPipelineSetup -ConfigPath $tmp
                $r.Pipelines.Count               | Should -Be 2
                $r.PipelineRoleAssignments.Count | Should -Be 2
            }
            finally {
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
