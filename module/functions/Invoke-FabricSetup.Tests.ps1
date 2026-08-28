#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # MicrosoftFabricMgmt and Az.Accounts are runtime-only dependencies that are not installed
    # in CI. Invoke-FabricSetup imports MicrosoftFabricMgmt, reads its $script:FabricAuthContext,
    # and calls Get-AzContext. Stand in a dynamic module of the same name so those calls resolve.
    if (Get-Module MicrosoftFabricMgmt) { Remove-Module MicrosoftFabricMgmt -Force }
    New-Module -Name MicrosoftFabricMgmt {
        $script:FabricAuthContext = @{}
        function Get-AzContext { [pscustomobject]@{ Tenant = [pscustomobject]@{ Id = 'stub-tenant' } } }
        Export-ModuleMember -Function Get-AzContext
    } | Import-Module

    function New-TestConfig {
        [pscustomobject]@{
            gitEnvironment = 'Dev'
            environments   = @(
                [pscustomobject]@{ name = 'Dev';  capacityName = 'cap-dev' }
                [pscustomobject]@{ name = 'Test'; capacityName = 'cap-test' }
            )
            workspaces     = @(
                [pscustomobject]@{
                    id         = 'bronze'; type = 'Bronze'
                    git        = [pscustomobject]@{ enabled = $true; branch = 'main' }
                    identity   = [pscustomobject]@{ enabled = $true }
                    monitoring = [pscustomobject]@{ enabled = $true }
                    rbac       = [pscustomobject]@{ Dev = @([pscustomobject]@{ principalId = 'g1'; principalType = 'Group'; role = 'Member' }) }
                    pipeline   = [pscustomobject]@{ enabled = $true; roleAssignments = @([pscustomobject]@{ principalId = 'pg1'; principalType = 'Group'; role = 'Admin' }) }
                    environment = [pscustomobject]@{ enabled = $true; setAsWorkspaceDefault = $true; runtimeVersion = '1.3' }
                }
            )
        }
    }
}

AfterAll {
    if (Get-Module MicrosoftFabricMgmt) { Remove-Module MicrosoftFabricMgmt -Force }
}

Describe 'Invoke-FabricSetup' {

    Context 'input validation' {
        It 'throws when ConfigPath does not exist' {
            { Invoke-FabricSetup -ConfigPath './nonexistent.json' } | Should -Throw
        }
    }

    Context 'orchestration' {

        BeforeEach {
            Mock Import-Module {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Get-FabricAuthToken { @{ Token = 'tok'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1) } } -ModuleName ZeroFailed.Deploy.Fabric
            # Default: deploying identity cannot be determined (overridden in the dedicated tests).
            Mock _Get-FabricDeploymentIdentity { $null } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Test-FabricTokenExpiry { $false } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Resolve-WorkspaceName { "$($args[0])" } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Resolve-EnvironmentName { 'bronze Env' } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Test-FabricWorkspaceExists { $null } -ModuleName ZeroFailed.Deploy.Fabric
            Mock New-FabricWorkspace { [pscustomobject]@{ id = 'ws-1' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricGitIntegration {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock Enable-FabricWorkspaceIdentity { @{ WorkspaceName = 'bronze'; ServicePrincipalObjectId = 'sp-oid' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Enable-FabricWorkspaceMonitoring { @{ Enabled = $true } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock New-FabricEnvironment { [pscustomobject]@{ id = 'env-1'; displayName = 'bronze Env' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricWorkspaceDefaultEnvironment { @{ EnvironmentName = 'bronze Env'; Action = 'Set' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricWorkspaceRoleAssignment { @{ Action = 'Created' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricDeploymentPipeline { @{ Action = 'Created'; PipelineId = 'pipe-1'; PipelineName = 'bronze-pipeline' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricDeploymentPipelineRoleAssignment { @{ Action = 'Created' } } -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'runs the full pipeline and aggregates results across both environments' {
            $r = Invoke-FabricSetup -Config (New-TestConfig)

            $r.Summary.Created      | Should -Be 2     # bronze in Dev + Test
            $r.Identities.Count     | Should -Be 2
            $r.Monitoring.Count     | Should -Be 2
            $r.RoleAssignments.Count | Should -Be 3     # rbac only configured for Dev (1) + identity Contributor grant in Dev + Test (2)
            $r.Pipelines.Count      | Should -Be 1
            $r.PipelineRoleAssignments.Count | Should -Be 1
            $r.Failures.Count       | Should -Be 0

            Should -Invoke New-FabricWorkspace      -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Set-FabricGitIntegration -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric  # only the git environment
            Should -Invoke Set-FabricDeploymentPipeline -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Set-FabricDeploymentPipelineRoleAssignment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'grants the deploying identity Admin on each workspace when it can be resolved' {
            Mock _Get-FabricDeploymentIdentity { @{ Id = 'deployer-oid'; Type = 'ServicePrincipal' } } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environments @('Dev')

            # Configured rbac for Dev (1) + deployer Admin (1) + identity Contributor grant (1)
            $r.RoleAssignments.Count | Should -Be 3
            Should -Invoke Set-FabricWorkspaceRoleAssignment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric `
                -ParameterFilter { $PrincipalId -eq 'deployer-oid' -and $Role -eq 'Admin' -and $PrincipalType -eq 'ServicePrincipal' }
        }

        It 'still grants the deploying identity Admin when -SkipRbac is set' {
            Mock _Get-FabricDeploymentIdentity { @{ Id = 'deployer-oid'; Type = 'ServicePrincipal' } } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environments @('Dev') -SkipRbac

            # Configured rbac skipped, but the deployer Admin grant and identity Contributor grant still happen
            $r.RoleAssignments.Count | Should -Be 2
            Should -Invoke Set-FabricWorkspaceRoleAssignment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric `
                -ParameterFilter { $PrincipalId -eq 'deployer-oid' -and $Role -eq 'Admin' }
        }

        It 'grants the workspace identity Contributor on its own workspace after provisioning' {
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environments @('Dev')

            Should -Invoke Set-FabricWorkspaceRoleAssignment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric `
                -ParameterFilter { $PrincipalId -eq 'sp-oid' -and $Role -eq 'Contributor' -and $PrincipalType -eq 'ServicePrincipal' }
            $r.RoleAssignments.Count | Should -Be 2     # rbac (1) + identity Contributor grant (1)
        }

        It 'does not grant the workspace identity a role when the workspace has no identity' {
            Mock Enable-FabricWorkspaceIdentity { $null } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environments @('Dev')

            Should -Invoke Set-FabricWorkspaceRoleAssignment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric `
                -ParameterFilter { $Role -eq 'Contributor' }
        }

        It 'records a non-fatal failure when granting the workspace identity Contributor fails' {
            Mock Set-FabricWorkspaceRoleAssignment {
                if ($Role -eq 'Contributor') { throw 'identity rbac boom' }
                @{ Action = 'Created' }
            } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environments @('Dev')

            ($r.Failures.Step) | Should -Contain 'IdentityRoleAssignment'
            $r.Identities.Count | Should -Be 1     # identity provisioning itself still succeeded
        }

        It 'counts an existing workspace as skipped rather than created' {
            Mock Test-FabricWorkspaceExists { [pscustomobject]@{ id = 'existing-ws' } } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricSetup -Config (New-TestConfig)
            $r.Summary.Created | Should -Be 0
            $r.Summary.Skipped | Should -Be 2
            Should -Invoke New-FabricWorkspace -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'processes only the environments named in -Environments' {
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environments @('Dev')
            $r.Summary.Created | Should -Be 1
            Should -Invoke New-FabricWorkspace -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'throws when -Environments matches no environment in the config' {
            { Invoke-FabricSetup -Config (New-TestConfig) -Environments @('Nope') } | Should -Throw
        }

        It 'honours the Skip switches' {
            $r = Invoke-FabricSetup -Config (New-TestConfig) -SkipGit -SkipIdentity -SkipMonitoring -SkipEnvironment -SkipRbac -SkipPipeline
            $r.Identities.Count      | Should -Be 0
            $r.Monitoring.Count      | Should -Be 0
            $r.Environments.Count    | Should -Be 0
            $r.RoleAssignments.Count | Should -Be 0
            $r.Pipelines.Count       | Should -Be 0
            $r.PipelineRoleAssignments.Count | Should -Be 0
            Should -Invoke Set-FabricGitIntegration     -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Enable-FabricWorkspaceIdentity -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke New-FabricEnvironment         -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Set-FabricDeploymentPipeline  -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Set-FabricDeploymentPipelineRoleAssignment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'provisions an environment and sets it as workspace default for each environment' {
            $r = Invoke-FabricSetup -Config (New-TestConfig)

            # 1 workspace x 2 environments; each iteration records a create + a set-default entry.
            $r.Environments.Count | Should -Be 4
            Should -Invoke New-FabricEnvironment                -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Set-FabricWorkspaceDefaultEnvironment -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'does not set a workspace default when setAsWorkspaceDefault is false' {
            $config = New-TestConfig
            $config.workspaces[0].environment.setAsWorkspaceDefault = $false
            $r = Invoke-FabricSetup -Config $config -Environments @('Dev')

            $r.Environments.Count | Should -Be 1
            Should -Invoke New-FabricEnvironment                -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Set-FabricWorkspaceDefaultEnvironment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'skips environment provisioning when the workspace has it disabled' {
            $config = New-TestConfig
            $config.workspaces[0].environment.enabled = $false
            $r = Invoke-FabricSetup -Config $config -Environments @('Dev')

            $r.Environments.Count | Should -Be 0
            Should -Invoke New-FabricEnvironment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'provisions an environment only in the stages configured for the workspace type' {
            $config = New-TestConfig
            # Scope the Spark Environment to Dev only, even though the config spans Dev + Test.
            $config.workspaces[0].environment | Add-Member -NotePropertyName stages -NotePropertyValue @('Dev') -Force
            $r = Invoke-FabricSetup -Config $config

            # Only Dev provisions (create + set-default); Test is skipped. Without scoping this
            # would be invoked twice (once per environment).
            $r.Environments.Count | Should -Be 2
            Should -Invoke New-FabricEnvironment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'records a non-fatal failure when environment provisioning throws' {
            Mock New-FabricEnvironment { throw 'env boom' } -ModuleName ZeroFailed.Deploy.Fabric
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environments @('Dev')

            $r.Environments.Count | Should -Be 0
            ($r.Failures.Step) | Should -Contain 'Environment'
        }

        It 'configures the pipeline but skips pipeline role assignments with -SkipPipelineRbac' {
            $r = Invoke-FabricSetup -Config (New-TestConfig) -SkipPipelineRbac
            $r.Pipelines.Count               | Should -Be 1
            $r.PipelineRoleAssignments.Count | Should -Be 0
            Should -Invoke Set-FabricDeploymentPipeline               -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Set-FabricDeploymentPipelineRoleAssignment  -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'records a non-fatal failure when a pipeline role assignment throws' {
            Mock Set-FabricDeploymentPipelineRoleAssignment { throw 'pipeline rbac boom' } -ModuleName ZeroFailed.Deploy.Fabric
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environments @('Dev')
            $r.PipelineRoleAssignments.Count | Should -Be 0
            ($r.Failures.Step) | Should -Contain 'PipelineRoleAssignment'
        }

        It 'does not attempt pipeline role assignments when the pipeline setup fails' {
            Mock Set-FabricDeploymentPipeline { throw 'pipeline boom' } -ModuleName ZeroFailed.Deploy.Fabric
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environments @('Dev')
            $r.PipelineRoleAssignments.Count | Should -Be 0
            Should -Invoke Set-FabricDeploymentPipelineRoleAssignment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'refreshes the token when it is near expiry' {
            Mock _Test-FabricTokenExpiry { $true } -ModuleName ZeroFailed.Deploy.Fabric
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environments @('Dev')
            $r.Summary.Created | Should -Be 1
            # initial acquisition + at least one refresh
            Should -Invoke _Get-FabricAuthToken -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'records a fatal failure and continues when workspace creation throws' {
            Mock New-FabricWorkspace { throw 'capacity not found' } -ModuleName ZeroFailed.Deploy.Fabric
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environments @('Dev')
            $r.Summary.Failed | Should -Be 1
            $r.Failures[0].Step | Should -Be 'Workspace'
        }

        It 'records non-fatal failures for each provisioning step and still completes' {
            Mock Set-FabricGitIntegration          { throw 'git boom' }        -ModuleName ZeroFailed.Deploy.Fabric
            Mock Enable-FabricWorkspaceIdentity    { throw 'identity boom' }   -ModuleName ZeroFailed.Deploy.Fabric
            Mock Enable-FabricWorkspaceMonitoring  { throw 'monitoring boom' } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricWorkspaceRoleAssignment { throw 'rbac boom' }       -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricDeploymentPipeline      { throw 'pipeline boom' }   -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environments @('Dev')
            ($r.Failures.Step | Sort-Object -Unique) | Should -Be @('Git', 'Identity', 'Monitoring', 'Pipeline', 'RoleAssignment')
        }

        It 'loads the topology config from a JSON file via -ConfigPath' {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) "topology-$([guid]::NewGuid()).json"
            (New-TestConfig) | ConvertTo-Json -Depth 20 | Set-Content -Path $tmp
            try {
                $r = Invoke-FabricSetup -ConfigPath $tmp -Environments @('Dev')
                $r.Summary.Created | Should -Be 1
            }
            finally {
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
