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
                    pipeline   = [pscustomobject]@{ enabled = $true }
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
            Mock _Assert-Prerequisites {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Get-FabricAuthToken { @{ Token = 'tok'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1) } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Test-FabricTokenExpiry { $false } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Resolve-WorkspaceName { "$($args[0])" } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Test-FabricWorkspaceExists { $null } -ModuleName ZeroFailed.Deploy.Fabric
            Mock New-FabricWorkspace { [pscustomobject]@{ id = 'ws-1' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricGitIntegration {} -ModuleName ZeroFailed.Deploy.Fabric
            Mock Enable-FabricWorkspaceIdentity { @{ WorkspaceName = 'bronze' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Enable-FabricWorkspaceMonitoring { @{ Enabled = $true } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricWorkspaceRoleAssignment { @{ Action = 'Created' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Set-FabricDeploymentPipeline { @{ Action = 'Created' } } -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'runs the full pipeline and aggregates results across both environments' {
            $r = Invoke-FabricSetup -Config (New-TestConfig)

            $r.Summary.Created      | Should -Be 2     # bronze in Dev + Test
            $r.Identities.Count     | Should -Be 2
            $r.Monitoring.Count     | Should -Be 2
            $r.RoleAssignments.Count | Should -Be 1     # rbac only configured for Dev
            $r.Pipelines.Count      | Should -Be 1
            $r.Failures.Count       | Should -Be 0

            Should -Invoke New-FabricWorkspace      -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Set-FabricGitIntegration -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric  # only the git environment
            Should -Invoke Set-FabricDeploymentPipeline -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
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
            $r = Invoke-FabricSetup -Config (New-TestConfig) -SkipGit -SkipIdentity -SkipMonitoring -SkipRbac -SkipPipeline
            $r.Identities.Count      | Should -Be 0
            $r.Monitoring.Count      | Should -Be 0
            $r.RoleAssignments.Count | Should -Be 0
            $r.Pipelines.Count       | Should -Be 0
            Should -Invoke Set-FabricGitIntegration     -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Enable-FabricWorkspaceIdentity -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Set-FabricDeploymentPipeline  -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
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
