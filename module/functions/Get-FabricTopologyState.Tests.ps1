#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Real config — the resolvers are pure string logic, so no mocking needed.
    # Resolves to: workspaces 'sa-Bronze [DEV]' / 'sa-Bronze [TEST]', environment 'sa-Bronze Env',
    # pipeline 'sa-Bronze Pipeline', gitEnvironment 'Dev'.
    $script:config = New-FabricTopologyConfig `
        -Project            'sa' `
        -WorkspaceTypes     @('Bronze') `
        -Environments       @('Dev', 'Test') `
        -CapacityMap        @{ Dev = 'cap-dev'; Test = 'cap-test' } `
        -GitProvider        'AzureDevOps' `
        -GitOrganisation    'o' `
        -GitProject         'p' `
        -GitEnvironment     'Dev' `
        -GitWorkspaceConfig @{ Bronze = @{ RepositoryName = 'r' } } `
        -EnableIdentity     @('Bronze') `
        -EnablePipelines    @('Bronze') `
        -EnableEnvironments @('Bronze') `
        -SetEnvironmentAsDefault
}

Describe 'Get-FabricTopologyState' {

    BeforeAll {
        # Many tests deliberately drive the non-fatal per-lookup failure branches; silence the
        # warnings they emit so a passing run stays clean. No test asserts on this output.
        Mock Write-Warning {} -ModuleName ZeroFailed.Deploy.Fabric
    }

    BeforeEach {
        Mock _Get-FabricAuthToken { @{ Token = 'tok'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1) } } -ModuleName ZeroFailed.Deploy.Fabric
        Mock _Test-FabricTokenExpiry { $false } -ModuleName ZeroFailed.Deploy.Fabric
        Mock _Resolve-FabricEnvironment { [pscustomobject]@{ id = 'env-1'; displayName = $DisplayName } } -ModuleName ZeroFailed.Deploy.Fabric

        Mock _Invoke-FabricRestMethod {
            param($RelativeUri)
            switch -Wildcard ($RelativeUri) {
                'workspaces' {
                    return [pscustomobject]@{ value = @(
                        [pscustomobject]@{ id = 'ws-dev';  displayName = 'sa-Bronze [DEV]' }
                        [pscustomobject]@{ id = 'ws-test'; displayName = 'sa-Bronze [TEST]' }
                    ) }
                }
                'deploymentPipelines' {
                    return [pscustomobject]@{ value = @(
                        [pscustomobject]@{ id = 'pipe-1'; displayName = 'sa-Bronze Pipeline' }
                    ) }
                }
                'workspaces/ws-dev' {
                    return [pscustomobject]@{ id = 'ws-dev'; workspaceIdentity = [pscustomobject]@{ servicePrincipalId = 'sp-oid'; applicationId = 'app-id' } }
                }
                'workspaces/ws-test' {
                    return [pscustomobject]@{ id = 'ws-test'; workspaceIdentity = [pscustomobject]@{ servicePrincipalId = 'sp-oid-2'; applicationId = 'app-id-2' } }
                }
                'workspaces/*/git/connection' {
                    return [pscustomobject]@{ gitConnectionState = 'ConnectedAndInitialized' }
                }
                'workspaces/*/spark/settings' {
                    return [pscustomobject]@{ environment = [pscustomobject]@{ name = 'sa-Bronze Env' } }
                }
                'deploymentPipelines/pipe-1/stages' {
                    return [pscustomobject]@{ value = @(
                        [pscustomobject]@{ id = 's1'; order = 0; displayName = 'Dev';  workspaceId = 'ws-dev' }
                        [pscustomobject]@{ id = 's2'; order = 1; displayName = 'Test' }
                    ) }
                }
                default { return $null }
            }
        } -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'builds the full model for existing workspaces' {
        $r = Get-FabricTopologyState -Config $script:config

        $r.Workspaces.Count | Should -Be 2
        $r.Summary.Found    | Should -Be 2
        $r.Summary.Missing  | Should -Be 0
        $r.Summary.Failed   | Should -Be 0

        $dev = $r.WorkspacesByType.Bronze.Dev
        $dev.WorkspaceId                     | Should -Be 'ws-dev'
        $dev.Status                          | Should -Be 'Existing'
        $dev.Name                            | Should -Be 'sa-Bronze [DEV]'
        $dev.Identity.PrincipalId            | Should -Be 'sp-oid'
        $dev.Identity.ApplicationId          | Should -Be 'app-id'
        $dev.SparkEnvironment.Id             | Should -Be 'env-1'
        $dev.SparkEnvironment.Name           | Should -Be 'sa-Bronze Env'
        $dev.SparkEnvironment.IsWorkspaceDefault | Should -BeTrue
        $dev.GitConnected                    | Should -BeTrue

        # Git is only checked in the git environment (Dev).
        $r.WorkspacesByType.Bronze.Test.GitConnected | Should -BeFalse
    }

    It 'indexes the same record objects in both views' {
        $r = Get-FabricTopologyState -Config $script:config
        $flatDev = $r.Workspaces | Where-Object { $_.Environment -eq 'Dev' }
        [object]::ReferenceEquals($flatDev, $r.WorkspacesByType.Bronze.Dev) | Should -BeTrue
    }

    It 'marks an absent workspace NotFound, keeps the record, and counts it Missing' {
        Mock _Invoke-FabricRestMethod {
            param($RelativeUri)
            if ($RelativeUri -eq 'workspaces') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'ws-dev'; displayName = 'sa-Bronze [DEV]' }) }
            }
            if ($RelativeUri -eq 'deploymentPipelines') { return [pscustomobject]@{ value = @() } }
            if ($RelativeUri -eq 'workspaces/ws-dev') { return [pscustomobject]@{ id = 'ws-dev' } }
            if ($RelativeUri -like 'workspaces/*/git/connection') { return [pscustomobject]@{ gitConnectionState = 'NotConnected' } }
            return $null
        } -ModuleName ZeroFailed.Deploy.Fabric

        $r = Get-FabricTopologyState -Config $script:config

        $r.Workspaces.Count                         | Should -Be 2
        $r.WorkspacesByType.Bronze.Test.Status      | Should -Be 'NotFound'
        $r.WorkspacesByType.Bronze.Test.WorkspaceId | Should -BeNullOrEmpty
        $r.Summary.Missing                          | Should -Be 1
        $r.Summary.Found                            | Should -Be 1
    }

    It 'does not look up identity with -SkipIdentity' {
        $r = Get-FabricTopologyState -Config $script:config -SkipIdentity

        Should -Invoke _Invoke-FabricRestMethod -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $RelativeUri -eq 'workspaces/ws-dev' }
        $r.WorkspacesByType.Bronze.Dev.Identity | Should -BeNullOrEmpty
        $r.Identities.Count | Should -Be 0
    }

    It 'does not look up the Spark environment with -SkipEnvironment' {
        $r = Get-FabricTopologyState -Config $script:config -SkipEnvironment

        Should -Invoke _Resolve-FabricEnvironment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        $r.WorkspacesByType.Bronze.Dev.SparkEnvironment | Should -BeNullOrEmpty
        $r.Environments.Count | Should -Be 0
    }

    It 'does not look up the Git connection with -SkipGit' {
        $r = Get-FabricTopologyState -Config $script:config -SkipGit

        Should -Invoke _Invoke-FabricRestMethod -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $RelativeUri -like '*/git/connection' }
        $r.WorkspacesByType.Bronze.Dev.GitConnected | Should -BeFalse
    }

    It 'does not look up pipelines with -SkipPipeline' {
        $r = Get-FabricTopologyState -Config $script:config -SkipPipeline

        Should -Invoke _Invoke-FabricRestMethod -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $RelativeUri -eq 'deploymentPipelines' }
        $r.Pipelines.Count | Should -Be 0
    }

    It 'reports a discovered pipeline with a Stages map from its own stage assignments' {
        $r = Get-FabricTopologyState -Config $script:config

        $r.Pipelines.Count            | Should -Be 1
        $p = $r.Pipelines[0]
        $p.Action                     | Should -Be 'Existing'
        $p.PipelineId                 | Should -Be 'pipe-1'
        $p.WorkspaceType              | Should -Be 'Bronze'
        $p.Stages['Dev']              | Should -Be 'ws-dev'
        $p.Stages['Test']             | Should -BeNullOrEmpty
        $p.StagesAssigned             | Should -Be 1
    }

    It 'reports Action=NotFound for a pipeline that does not exist' {
        Mock _Invoke-FabricRestMethod {
            param($RelativeUri)
            if ($RelativeUri -eq 'workspaces') {
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{ id = 'ws-dev';  displayName = 'sa-Bronze [DEV]' }
                    [pscustomobject]@{ id = 'ws-test'; displayName = 'sa-Bronze [TEST]' }
                ) }
            }
            if ($RelativeUri -eq 'deploymentPipelines') { return [pscustomobject]@{ value = @() } }
            if ($RelativeUri -like 'workspaces/ws-*') { return [pscustomobject]@{ id = 'x' } }
            if ($RelativeUri -like 'workspaces/*/git/connection') { return [pscustomobject]@{ gitConnectionState = 'NotConnected' } }
            return $null
        } -ModuleName ZeroFailed.Deploy.Fabric

        $r = Get-FabricTopologyState -Config $script:config
        $r.Pipelines[0].Action     | Should -Be 'NotFound'
        $r.Pipelines[0].PipelineId | Should -BeNullOrEmpty
        $r.Pipelines[0].Stages.Count | Should -Be 0
        $r.Pipelines[0].StagesAssigned | Should -Be 0
    }

    It 'records a non-fatal failure when a sub-lookup throws, without aborting or changing Status' {
        Mock _Invoke-FabricRestMethod {
            param($RelativeUri)
            if ($RelativeUri -eq 'workspaces') {
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{ id = 'ws-dev';  displayName = 'sa-Bronze [DEV]' }
                    [pscustomobject]@{ id = 'ws-test'; displayName = 'sa-Bronze [TEST]' }
                ) }
            }
            if ($RelativeUri -eq 'deploymentPipelines') { return [pscustomobject]@{ value = @() } }
            if ($RelativeUri -like 'workspaces/*') { throw 'identity boom' }
            return $null
        } -ModuleName ZeroFailed.Deploy.Fabric

        $r = Get-FabricTopologyState -Config $script:config

        ($r.Failures.Step) | Should -Contain 'Identity'
        $r.Summary.Failed  | Should -Be $r.Failures.Count
        $r.Summary.Failed  | Should -BeGreaterThan 0
        $r.WorkspacesByType.Bronze.Dev.Status | Should -Be 'Existing'
    }

    It 'treats a 404 on the Git connection as not-connected, not a failure' {
        Mock _Invoke-FabricRestMethod {
            param($RelativeUri)
            if ($RelativeUri -eq 'workspaces') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'ws-dev'; displayName = 'sa-Bronze [DEV]' }) }
            }
            if ($RelativeUri -eq 'deploymentPipelines') { return [pscustomobject]@{ value = @() } }
            if ($RelativeUri -eq 'workspaces/ws-dev') { return [pscustomobject]@{ id = 'ws-dev' } }
            if ($RelativeUri -like 'workspaces/*/git/connection') { throw 'Fabric API error 404 on GET https://api.fabric.microsoft.com/v1/workspaces/ws-dev/git/connection : WorkspaceNotConnectedToGit' }
            return $null
        } -ModuleName ZeroFailed.Deploy.Fabric

        $r = Get-FabricTopologyState -Config $script:config -Environments @('Dev')
        $r.WorkspacesByType.Bronze.Dev.GitConnected | Should -BeFalse
        $r.Failures.Count | Should -Be 0
    }

    It 'honours the -Environments filter' {
        $r = Get-FabricTopologyState -Config $script:config -Environments @('Dev')

        $r.Workspaces.Count | Should -Be 1
        $r.Summary.Found    | Should -Be 1
        Should -Invoke _Invoke-FabricRestMethod -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $RelativeUri -eq 'workspaces/ws-test' }
    }

    It 'loads the topology config from a JSON file via -ConfigPath' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) "topology-$([guid]::NewGuid()).json"
        ($script:config) | ConvertTo-Json -Depth 20 | Set-Content -Path $tmp
        try {
            $r = Get-FabricTopologyState -ConfigPath $tmp -Environments @('Dev')
            $r.WorkspacesByType.Bronze.Dev.WorkspaceId | Should -Be 'ws-dev'
        }
        finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when -ConfigPath does not exist' {
        { Get-FabricTopologyState -ConfigPath './nope.json' } | Should -Throw
    }

    It 'survives a ConvertTo-Json | ConvertFrom-Json round-trip' {
        $r  = Get-FabricTopologyState -Config $script:config
        $rt = $r | ConvertTo-Json -Depth 10 | ConvertFrom-Json

        $rt.WorkspacesByType.Bronze.Dev.WorkspaceId          | Should -Be 'ws-dev'
        $rt.WorkspacesByType.Bronze.Dev.Identity.PrincipalId | Should -Be 'sp-oid'
        $rt.Workspaces.Count                                 | Should -Be 2
    }

    It 'reports a Found/Missing/Failed summary and leaves the non-derivable lists empty' {
        $r = Get-FabricTopologyState -Config $script:config

        $r.Summary.PSObject.Properties.Name | Should -Be @('Found', 'Missing', 'Failed')
        $r.Monitoring.Count                 | Should -Be 0
        $r.RoleAssignments.Count            | Should -Be 0
        $r.PipelineRoleAssignments.Count    | Should -Be 0
    }

    It 'refreshes the token when it is near expiry' {
        Mock _Test-FabricTokenExpiry { $true } -ModuleName ZeroFailed.Deploy.Fabric
        Get-FabricTopologyState -Config $script:config -Environments @('Dev') | Out-Null
        Should -Invoke _Get-FabricAuthToken -Times 2 -ModuleName ZeroFailed.Deploy.Fabric
    }
}
