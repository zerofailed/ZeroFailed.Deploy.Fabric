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
                [pscustomobject]@{ name = 'Dev';  shortCode = 'DEV';  capacityName = 'cap-dev' }
                [pscustomobject]@{ name = 'Test'; shortCode = 'TEST'; capacityName = 'cap-test' }
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
                    variableLibrary = [pscustomobject]@{ enabled = $true; name = 'Bronze Variables' }
                }
            )
        }
    }
}

AfterAll {
    if (Get-Module MicrosoftFabricMgmt) { Remove-Module MicrosoftFabricMgmt -Force }
}

Describe 'Invoke-FabricSetup' {

    BeforeAll {
        # Many tests deliberately drive the "no deploying identity" and per-step failure-
        # aggregation branches; silence the warnings and non-terminating errors they emit so a
        # passing run stays clean. No test asserts on this output.
        Mock Write-Warning {} -ModuleName ZeroFailed.Deploy.Fabric
        Mock Write-Error   {} -ModuleName ZeroFailed.Deploy.Fabric
    }

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
            Mock Enable-FabricWorkspaceIdentity { @{ WorkspaceName = 'bronze'; WorkspaceId = 'ws-1'; ServicePrincipalObjectId = 'sp-oid'; ApplicationId = 'app-1' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Enable-FabricWorkspaceMonitoring { @{ Enabled = $true } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock New-FabricEnvironment { [pscustomobject]@{ id = 'env-1'; displayName = 'bronze Env' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricWorkspaceDefaultEnvironment { @{ EnvironmentName = 'bronze Env'; Action = 'Set' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock New-FabricVariableLibrary { [pscustomobject]@{ id = 'vl-1'; displayName = $DisplayName } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricVariableLibraryValues { @{ DefinitionAction = 'Updated'; ActiveValueSetAction = 'Set' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Get-FabricWorkspaceIdentity { $null } -ModuleName ZeroFailed.Deploy.Fabric
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
            $r.Failures.Count       | Should -Be 0

            Should -Invoke New-FabricWorkspace      -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Set-FabricGitIntegration -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric  # only the git environment
        }

        It 'does not configure deployment pipelines, even when they are enabled in the config' {
            # Pipelines span every environment, so they are configured by Invoke-FabricDeploymentPipelineSetup.
            $r = Invoke-FabricSetup -Config (New-TestConfig)

            $r.PSObject.Properties.Name | Should -Not -Contain 'Pipelines'
            Should -Invoke Set-FabricDeploymentPipeline               -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Set-FabricDeploymentPipelineRoleAssignment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'grants the deploying identity Admin on each workspace when it can be resolved' {
            Mock _Get-FabricDeploymentIdentity { @{ Id = 'deployer-oid'; Type = 'ServicePrincipal' } } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev'

            # Configured rbac for Dev (1) + deployer Admin (1) + identity Contributor grant (1)
            $r.RoleAssignments.Count | Should -Be 3
            Should -Invoke Set-FabricWorkspaceRoleAssignment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric `
                -ParameterFilter { $PrincipalId -eq 'deployer-oid' -and $Role -eq 'Admin' -and $PrincipalType -eq 'ServicePrincipal' }
        }

        It 'still grants the deploying identity Admin when -SkipRbac is set' {
            Mock _Get-FabricDeploymentIdentity { @{ Id = 'deployer-oid'; Type = 'ServicePrincipal' } } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev' -SkipRbac

            # Configured rbac skipped, but the deployer Admin grant and identity Contributor grant still happen
            $r.RoleAssignments.Count | Should -Be 2
            Should -Invoke Set-FabricWorkspaceRoleAssignment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric `
                -ParameterFilter { $PrincipalId -eq 'deployer-oid' -and $Role -eq 'Admin' }
        }

        It 'grants the workspace identity Contributor on its own workspace after provisioning' {
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev'

            Should -Invoke Set-FabricWorkspaceRoleAssignment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric `
                -ParameterFilter { $PrincipalId -eq 'sp-oid' -and $Role -eq 'Contributor' -and $PrincipalType -eq 'ServicePrincipal' }
            $r.RoleAssignments.Count | Should -Be 2     # rbac (1) + identity Contributor grant (1)
        }

        It 'does not grant the workspace identity a role when the workspace has no identity' {
            Mock Enable-FabricWorkspaceIdentity { $null } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev'

            Should -Invoke Set-FabricWorkspaceRoleAssignment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric `
                -ParameterFilter { $Role -eq 'Contributor' }
        }

        It 'records a non-fatal failure when granting the workspace identity Contributor fails' {
            Mock Set-FabricWorkspaceRoleAssignment {
                if ($Role -eq 'Contributor') { throw 'identity rbac boom' }
                @{ Action = 'Created' }
            } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev'

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

        It 'processes only the environment named in -Environment' {
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev'
            $r.Summary.Created | Should -Be 1
            Should -Invoke New-FabricWorkspace -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'throws when -Environment matches no environment in the config' {
            { Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Nope' } | Should -Throw
        }

        It 'honours the Skip switches' {
            $r = Invoke-FabricSetup -Config (New-TestConfig) -SkipGit -SkipIdentity -SkipMonitoring -SkipEnvironment -SkipVariableLibrary -SkipRbac
            $r.Identities.Count      | Should -Be 0
            $r.Monitoring.Count      | Should -Be 0
            $r.Environments.Count    | Should -Be 0
            $r.VariableLibraries.Count | Should -Be 0
            Should -Invoke New-FabricVariableLibrary     -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            $r.RoleAssignments.Count | Should -Be 0
            Should -Invoke Set-FabricGitIntegration     -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Enable-FabricWorkspaceIdentity -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke New-FabricEnvironment         -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
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
            $r = Invoke-FabricSetup -Config $config -Environment 'Dev'

            $r.Environments.Count | Should -Be 1
            Should -Invoke New-FabricEnvironment                -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Set-FabricWorkspaceDefaultEnvironment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'skips environment provisioning when the workspace has it disabled' {
            $config = New-TestConfig
            $config.workspaces[0].environment.enabled = $false
            $r = Invoke-FabricSetup -Config $config -Environment 'Dev'

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
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev'

            $r.Environments.Count | Should -Be 0
            ($r.Failures.Step) | Should -Contain 'Environment'
        }

        It 'provisions a variable library with the same name in each environment' {
            $r = Invoke-FabricSetup -Config (New-TestConfig)

            $r.VariableLibraries.Count | Should -Be 2     # 1 workspace x 2 environments
            ($r.VariableLibraries.VariableLibraryName | Sort-Object -Unique) | Should -Be 'Bronze Variables'
            $r.VariableLibraries[0].VariableLibraryId | Should -Be 'vl-1'
            Should -Invoke New-FabricVariableLibrary -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric `
                -ParameterFilter { $WorkspaceId -eq 'ws-1' -and $DisplayName -eq 'Bronze Variables' }
        }

        It 'uses the default variable library name when the variableLibrary block has no name' {
            $config = New-TestConfig
            $config.workspaces[0].variableLibrary.PSObject.Properties.Remove('name')
            $r = Invoke-FabricSetup -Config $config -Environment 'Dev'

            $r.VariableLibraries[0].VariableLibraryName | Should -Be 'DefaultVariableLibrary'
            Should -Invoke New-FabricVariableLibrary -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric `
                -ParameterFilter { $DisplayName -eq 'DefaultVariableLibrary' }
        }

        It 'skips variable library provisioning when the workspace has it disabled' {
            $config = New-TestConfig
            $config.workspaces[0].variableLibrary.enabled = $false
            $r = Invoke-FabricSetup -Config $config -Environment 'Dev'

            $r.VariableLibraries.Count | Should -Be 0
            Should -Invoke New-FabricVariableLibrary -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'skips variable library provisioning for an older config without a variableLibrary block' {
            $config = New-TestConfig
            $config.workspaces[0].PSObject.Properties.Remove('variableLibrary')
            $r = Invoke-FabricSetup -Config $config -Environment 'Dev'

            $r.VariableLibraries.Count | Should -Be 0
            $r.Failures.Count          | Should -Be 0
            Should -Invoke New-FabricVariableLibrary -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'only provisions the variable library in the configured stages' {
            $config = New-TestConfig
            $config.workspaces[0].variableLibrary | Add-Member -NotePropertyName stages -NotePropertyValue @('Test')
            $r = Invoke-FabricSetup -Config $config

            $r.VariableLibraries.Count | Should -Be 1
            Should -Invoke New-FabricVariableLibrary -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'does not set default values unless defaultValues is enabled' {
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev'

            $r.VariableLibraries[0].DefaultValues | Should -BeNullOrEmpty
            Should -Invoke Set-FabricVariableLibraryValues -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'sets the default values in a value set named by the stage short code' {
            $config = New-TestConfig
            $config.workspaces[0].variableLibrary | Add-Member -NotePropertyName defaultValues -NotePropertyValue $true
            $r = Invoke-FabricSetup -Config $config -Environment 'Dev'

            $r.VariableLibraries[0].DefaultValues.DefinitionAction | Should -Be 'Updated'
            $workspaceName = $r.VariableLibraries[0].WorkspaceName
            Should -Invoke Set-FabricVariableLibraryValues -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
                $WorkspaceId -eq 'ws-1' -and $VariableLibraryId -eq 'vl-1' -and $VariableLibraryName -eq 'Bronze Variables' -and
                $ValueSetName -eq 'DEV' -and
                ($Values.Keys -join ',') -eq 'workspace_name,workspace_id,workspace_identity_name,workspace_identity_id' -and
                $Values.workspace_name -eq $workspaceName -and $Values.workspace_id -eq 'ws-1' -and
                $Values.workspace_identity_name -eq $workspaceName -and $Values.workspace_identity_id -eq 'app-1'
            }
            # The identity provisioned in this run is used — no extra lookup.
            Should -Invoke _Get-FabricWorkspaceIdentity -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'reads the identity off the workspace when identity provisioning is skipped' {
            Mock _Get-FabricWorkspaceIdentity { [pscustomobject]@{ applicationId = 'app-existing'; servicePrincipalId = 'sp-existing' } } -ModuleName ZeroFailed.Deploy.Fabric
            $config = New-TestConfig
            $config.workspaces[0].variableLibrary | Add-Member -NotePropertyName defaultValues -NotePropertyValue $true
            Invoke-FabricSetup -Config $config -Environment 'Dev' -SkipIdentity | Out-Null

            Should -Invoke Set-FabricVariableLibraryValues -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
                $Values.workspace_identity_id -eq 'app-existing'
            }
        }

        It 'sets empty identity values when the workspace has no identity' {
            $config = New-TestConfig
            $config.workspaces[0].variableLibrary | Add-Member -NotePropertyName defaultValues -NotePropertyValue $true
            Invoke-FabricSetup -Config $config -Environment 'Dev' -SkipIdentity | Out-Null

            Should -Invoke Set-FabricVariableLibraryValues -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
                $Values.workspace_identity_name -eq '' -and $Values.workspace_identity_id -eq ''
            }
        }

        It 'names the value set after the environment when the config has no short codes' {
            $config = New-TestConfig
            $config.environments[0].PSObject.Properties.Remove('shortCode')
            $config.workspaces[0].variableLibrary | Add-Member -NotePropertyName defaultValues -NotePropertyValue $true
            Invoke-FabricSetup -Config $config -Environment 'Dev' | Out-Null

            Should -Invoke Set-FabricVariableLibraryValues -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $ValueSetName -eq 'Dev' }
        }

        It 'records a non-fatal failure when setting default values throws, keeping the library' {
            Mock Set-FabricVariableLibraryValues { throw 'values boom' } -ModuleName ZeroFailed.Deploy.Fabric
            $config = New-TestConfig
            $config.workspaces[0].variableLibrary | Add-Member -NotePropertyName defaultValues -NotePropertyValue $true
            $r = Invoke-FabricSetup -Config $config -Environment 'Dev'

            $r.VariableLibraries.Count | Should -Be 1
            ($r.Failures.Step) | Should -Contain 'VariableLibraryValues'
        }

        It 'records a non-fatal failure when variable library provisioning throws' {
            Mock New-FabricVariableLibrary { throw 'variable library boom' } -ModuleName ZeroFailed.Deploy.Fabric
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev'

            $r.VariableLibraries.Count | Should -Be 0
            ($r.Failures.Step) | Should -Contain 'VariableLibrary'
            $r.Environments.Count | Should -Be 2     # later/earlier steps unaffected
        }

        It 'refreshes the token when it is near expiry' {
            Mock _Test-FabricTokenExpiry { $true } -ModuleName ZeroFailed.Deploy.Fabric
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev'
            $r.Summary.Created | Should -Be 1
            # initial acquisition + at least one refresh
            Should -Invoke _Get-FabricAuthToken -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'records a fatal failure and continues when workspace creation throws' {
            Mock New-FabricWorkspace { throw 'capacity not found' } -ModuleName ZeroFailed.Deploy.Fabric
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev'
            $r.Summary.Failed | Should -Be 1
            $r.Failures[0].Step | Should -Be 'Workspace'
        }

        It 'records non-fatal failures for each provisioning step and still completes' {
            Mock Set-FabricGitIntegration          { throw 'git boom' }        -ModuleName ZeroFailed.Deploy.Fabric
            Mock Enable-FabricWorkspaceIdentity    { throw 'identity boom' }   -ModuleName ZeroFailed.Deploy.Fabric
            Mock Enable-FabricWorkspaceMonitoring  { throw 'monitoring boom' } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricWorkspaceRoleAssignment { throw 'rbac boom' }       -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev'
            ($r.Failures.Step | Sort-Object -Unique) | Should -Be @('Git', 'Identity', 'Monitoring', 'RoleAssignment')
        }

        It 'loads the topology config from a JSON file via -ConfigPath' {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) "topology-$([guid]::NewGuid()).json"
            (New-TestConfig) | ConvertTo-Json -Depth 20 | Set-Content -Path $tmp
            try {
                $r = Invoke-FabricSetup -ConfigPath $tmp -Environment 'Dev'
                $r.Summary.Created | Should -Be 1
            }
            finally {
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'workspace model' {

        BeforeEach {
            Mock Import-Module {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Get-FabricAuthToken { @{ Token = 'tok'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1) } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Get-FabricDeploymentIdentity { $null } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Test-FabricTokenExpiry { $false } -ModuleName ZeroFailed.Deploy.Fabric
            # Resolve to a stable, distinct name per type x environment so records are addressable.
            Mock _Resolve-WorkspaceName { "$WorkspaceId [$EnvironmentName]" } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Resolve-EnvironmentName { 'bronze Env' } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Test-FabricWorkspaceExists { $null } -ModuleName ZeroFailed.Deploy.Fabric
            Mock New-FabricWorkspace { [pscustomobject]@{ id = "ws-$($DisplayName -replace '[^a-zA-Z]', '')" } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricGitIntegration {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock Enable-FabricWorkspaceIdentity { @{ WorkspaceName = $WorkspaceName; WorkspaceId = $WorkspaceId; ServicePrincipalObjectId = 'sp-oid'; ApplicationId = 'app-id' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Enable-FabricWorkspaceMonitoring { @{ Enabled = $true } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock New-FabricEnvironment { [pscustomobject]@{ id = 'env-1'; displayName = 'bronze Env' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricWorkspaceDefaultEnvironment { @{ EnvironmentName = 'bronze Env'; Action = 'Set' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricWorkspaceRoleAssignment { @{ Action = 'Created' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricDeploymentPipeline { @{ Action = 'Created'; PipelineId = 'pipe-1'; PipelineName = 'bronze-pipeline' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricDeploymentPipelineRoleAssignment { @{ Action = 'Created' } } -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'produces a flat Workspaces list and a nested WorkspacesByType index of the same records' {
            $r = Invoke-FabricSetup -Config (New-TestConfig)

            $r.Workspaces.Count | Should -Be 2
            $r.WorkspacesByType.Bronze.Dev.WorkspaceId  | Should -Be 'ws-bronzeDev'
            $r.WorkspacesByType.Bronze.Test.WorkspaceId | Should -Be 'ws-bronzeTest'
            $r.WorkspacesByType.Bronze.Dev.Status       | Should -Be 'Created'
            $r.WorkspacesByType.Bronze.Dev.Name         | Should -Be 'bronze [Dev]'

            # Same object reference in both views.
            $flatDev = $r.Workspaces | Where-Object { $_.Environment -eq 'Dev' }
            [object]::ReferenceEquals($flatDev, $r.WorkspacesByType.Bronze.Dev) | Should -BeTrue
        }

        It 'captures the identity principal / application id and the Spark environment id on the record' {
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev'
            $rec = $r.WorkspacesByType.Bronze.Dev

            $rec.Identity.PrincipalId              | Should -Be 'sp-oid'
            $rec.Identity.ApplicationId            | Should -Be 'app-id'
            $rec.SparkEnvironment.Id               | Should -Be 'env-1'
            $rec.SparkEnvironment.IsWorkspaceDefault | Should -BeTrue
            $rec.GitConnected                      | Should -BeTrue
        }

        It 'marks a pre-existing workspace as Existing and records its id' {
            Mock Test-FabricWorkspaceExists { [pscustomobject]@{ id = 'existing-ws' } } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev'
            $r.WorkspacesByType.Bronze.Dev.Status      | Should -Be 'Existing'
            $r.WorkspacesByType.Bronze.Dev.WorkspaceId | Should -Be 'existing-ws'
        }

        It 'keeps a Failed record with a null WorkspaceId when workspace creation throws' {
            Mock New-FabricWorkspace { throw 'capacity not found' } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev'
            $r.Workspaces.Count                        | Should -Be 1
            $r.WorkspacesByType.Bronze.Dev.Status      | Should -Be 'Failed'
            $r.WorkspacesByType.Bronze.Dev.WorkspaceId | Should -BeNullOrEmpty
        }

        It 'marks records WhatIf under -WhatIf' {
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev' -WhatIf
            $r.WorkspacesByType.Bronze.Dev.Status | Should -Be 'WhatIf'
        }

        It 'leaves Identity and SparkEnvironment null when those steps are skipped, keeping the record' {
            $r = Invoke-FabricSetup -Config (New-TestConfig) -Environment 'Dev' -SkipIdentity -SkipEnvironment
            $rec = $r.WorkspacesByType.Bronze.Dev

            $rec.Status           | Should -Be 'Created'
            $rec.Identity         | Should -BeNullOrEmpty
            $rec.SparkEnvironment | Should -BeNullOrEmpty
        }

        It 'survives a ConvertTo-Json | ConvertFrom-Json round-trip' {
            $r = Invoke-FabricSetup -Config (New-TestConfig)
            $rt = $r | ConvertTo-Json -Depth 10 | ConvertFrom-Json

            $rt.Workspaces.Count                        | Should -Be 2
            $rt.WorkspacesByType.Bronze.Dev.WorkspaceId | Should -Be 'ws-bronzeDEV'
            $rt.WorkspacesByType.Bronze.Dev.Identity.PrincipalId | Should -Be 'sp-oid'
        }
    }
}
