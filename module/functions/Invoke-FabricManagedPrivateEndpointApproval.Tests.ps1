#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Assert-PrivateEndpointConnectionApproval comes from the ZeroFailed.Deploy.Azure extension, which
    # is not installed for these tests. Stand in a module of the same name so the call resolves.
    if (Get-Module ZeroFailed.Deploy.Azure) { Remove-Module ZeroFailed.Deploy.Azure -Force }
    New-Module -Name ZeroFailed.Deploy.Azure {
        function Assert-PrivateEndpointConnectionApproval {
            [CmdletBinding(SupportsShouldProcess)]
            param (
                [string]$PrivateLinkResourceId,
                [string]$PrivateEndpointNameLike,
                [string]$Description,
                [int]$TimeoutSeconds,
                [int]$PollIntervalSeconds
            )
            @{ Status = 'Approved'; Action = 'Approved' }
        }
        Export-ModuleMember -Function Assert-PrivateEndpointConnectionApproval
    } | Import-Module

    function New-TestConfig {
        [pscustomobject]@{
            environments = @(
                [pscustomobject]@{ name = 'Dev';  shortCode = 'DEV';  capacityName = 'cap-dev' }
                [pscustomobject]@{ name = 'Test'; shortCode = 'TEST'; capacityName = 'cap-test' }
            )
            workspaces   = @(
                [pscustomobject]@{
                    id = 'bronze'; type = 'Bronze'
                    managedPrivateEndpoints = [pscustomobject]@{
                        Dev  = [pscustomobject]@{
                            subscriptionId = '11111111-1111-1111-1111-111111111111'
                            resources      = @([pscustomobject]@{ resourceName = 'kv-dev'; resourceGroup = 'rg-dev'; resourceType = 'KeyVault'; subResourceType = 'vault' })
                        }
                        Test = [pscustomobject]@{
                            subscriptionId = '22222222-2222-2222-2222-222222222222'
                            resources      = @([pscustomobject]@{ resourceName = 'kv-test'; resourceGroup = 'rg-test'; resourceType = 'KeyVault'; subResourceType = 'vault' })
                        }
                    }
                }
            )
        }
    }

    function New-TestEndpoint {
        param ([string]$Name = 'kv-dev.vault', [string]$ProvisioningState = 'Succeeded', [string]$ConnectionStatus = 'Pending')
        $endpoint = [pscustomobject]@{ id = 'mpe-1'; name = $Name; provisioningState = $ProvisioningState }
        if ($ConnectionStatus) {
            $endpoint | Add-Member -NotePropertyName connectionState -NotePropertyValue ([pscustomobject]@{ status = $ConnectionStatus })
        }
        $endpoint
    }
}

AfterAll {
    if (Get-Module ZeroFailed.Deploy.Azure) { Remove-Module ZeroFailed.Deploy.Azure -Force }
}

Describe 'Invoke-FabricManagedPrivateEndpointApproval' {

    Context 'without the ZeroFailed.Deploy.Azure extension' {

        BeforeEach {
            Mock _Get-FabricAuthToken { @{ Token = 'tok'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1) } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Test-FabricTokenExpiry { $false } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Resolve-WorkspaceName { 'bronze [DEV]' } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Test-FabricWorkspaceExists { [pscustomobject]@{ id = 'ws-1' } } -ModuleName ZeroFailed.Deploy.Fabric
            # Simulate the extension not being loaded: its command cannot be found.
            Mock Get-Command { $null } -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Name -eq 'Assert-PrivateEndpointConnectionApproval' }
        }

        It 'throws a helpful error when there are endpoints to approve' {
            { Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev' } |
                Should -Throw '*requires the ZeroFailed.Deploy.Azure extension*'
        }

        It 'does nothing when the topology has no managed private endpoints' {
            $config = New-TestConfig
            $config.workspaces[0].PSObject.Properties.Remove('managedPrivateEndpoints')

            $r = Invoke-FabricManagedPrivateEndpointApproval -Config $config

            $r.Approvals.Count | Should -Be 0
            $r.Summary.Failed  | Should -Be 0
        }
    }

    Context 'input validation' {
        It 'throws when ConfigPath does not exist' {
            { Invoke-FabricManagedPrivateEndpointApproval -ConfigPath './nonexistent.json' } | Should -Throw '*not found*'
        }

        It 'throws when -Environment matches no environment in the config' {
            { Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Nope' } | Should -Throw "*Environment 'Nope' not found*"
        }
    }

    Context 'approval' {

        BeforeEach {
            Mock _Get-FabricAuthToken { @{ Token = 'tok'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1) } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Test-FabricTokenExpiry { $false } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Resolve-WorkspaceName { 'bronze [DEV]' } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Test-FabricWorkspaceExists { [pscustomobject]@{ id = 'ws-1' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock _Get-FabricManagedPrivateEndpoint { New-TestEndpoint } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Assert-PrivateEndpointConnectionApproval { @{ Status = 'Approved'; Action = 'Approved' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Start-Sleep {} -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'approves the connection for each configured endpoint, in every environment' {
            $r = Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig)

            $r.Summary.Approved | Should -Be 2
            $r.Summary.Failed   | Should -Be 0
            $r.Approvals.Count  | Should -Be 2
            Should -Invoke Assert-PrivateEndpointConnectionApproval -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'approves on the resolved target resource, matching the workspace id and endpoint name' {
            Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev' | Out-Null

            Should -Invoke Assert-PrivateEndpointConnectionApproval -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
                $PrivateLinkResourceId -eq '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-dev/providers/Microsoft.KeyVault/vaults/kv-dev' -and
                $PrivateEndpointNameLike -eq '*ws-1*kv-dev.vault' -and
                $Description -eq "Approved for Fabric workspace 'bronze [DEV]'"
            }
        }

        It 'uses a custom endpoint name pattern' {
            Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev' -EndpointNamePattern '{name}.{workspaceId}' | Out-Null

            Should -Invoke Assert-PrivateEndpointConnectionApproval -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
                $PrivateEndpointNameLike -eq 'kv-dev.vault.ws-1'
            }
        }

        It 'passes the timeout and poll interval through' {
            Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev' -TimeoutSeconds 120 -PollIntervalSeconds 5 | Out-Null

            Should -Invoke Assert-PrivateEndpointConnectionApproval -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
                $TimeoutSeconds -eq 120 -and $PollIntervalSeconds -eq 5
            }
        }

        It 'skips an endpoint whose connection is already approved' {
            Mock _Get-FabricManagedPrivateEndpoint { New-TestEndpoint -ConnectionStatus 'Approved' } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev'

            $r.Summary.Skipped        | Should -Be 1
            $r.Approvals[0].Action    | Should -Be 'Skipped'
            Should -Invoke Assert-PrivateEndpointConnectionApproval -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'handles an endpoint that has no connection state yet' {
            Mock _Get-FabricManagedPrivateEndpoint { New-TestEndpoint -ConnectionStatus '' } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev'

            $r.Summary.Approved | Should -Be 1
        }

        It 'waits for an endpoint that is still provisioning' {
            $script:lookups = 0
            Mock _Get-FabricManagedPrivateEndpoint {
                $script:lookups++
                New-TestEndpoint -ProvisioningState $(if ($script:lookups -ge 3) { 'Succeeded' } else { 'Provisioning' })
            } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev' -PollIntervalSeconds 5

            $r.Summary.Approved | Should -Be 1
            Should -Invoke Start-Sleep -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Seconds -eq 5 }
        }

        It 'records a failure when the endpoint is still provisioning at the timeout' {
            Mock _Get-FabricManagedPrivateEndpoint { New-TestEndpoint -ProvisioningState 'Provisioning' } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev' -TimeoutSeconds 30 -PollIntervalSeconds 10 -WarningAction SilentlyContinue

            $r.Summary.Failed    | Should -Be 1
            ($r.Failures.Step)   | Should -Contain 'ManagedPrivateEndpointApproval'
            ($r.Failures.Error)  | Should -BeLike '*still provisioning*'
            Should -Invoke Assert-PrivateEndpointConnectionApproval -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'records a failure when the endpoint failed to provision' {
            Mock _Get-FabricManagedPrivateEndpoint { New-TestEndpoint -ProvisioningState 'Failed' } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev' -WarningAction SilentlyContinue

            $r.Summary.Failed   | Should -Be 1
            ($r.Failures.Error) | Should -BeLike '*failed to provision*'
        }

        It 'records a failure when the endpoint does not exist on the workspace' {
            Mock _Get-FabricManagedPrivateEndpoint { $null } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev' -WarningAction SilentlyContinue

            $r.Summary.Failed   | Should -Be 1
            ($r.Failures.Error) | Should -BeLike '*was not found on workspace*'
        }

        It 'records a failure when the workspace does not exist' {
            Mock Test-FabricWorkspaceExists { $null } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev' -WarningAction SilentlyContinue

            $r.Summary.Failed  | Should -Be 1
            ($r.Failures.Step) | Should -Contain 'Workspace'
            Should -Invoke _Get-FabricManagedPrivateEndpoint -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'records a failure when the connection is not approved, and warns' {
            Mock Assert-PrivateEndpointConnectionApproval { @{ Status = 'Rejected'; Action = 'None' } } -ModuleName ZeroFailed.Deploy.Fabric
            Mock Write-Warning {} -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev'

            $r.Summary.Failed   | Should -Be 1
            ($r.Failures.Error) | Should -BeLike "*status 'Rejected'*"
            Should -Invoke Write-Warning -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Message -like '*remain pending*' }
        }

        It 'records a failure when approval throws, e.g. for missing permissions' {
            Mock Assert-PrivateEndpointConnectionApproval { throw 'does not have authorization to perform action' } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev' -WarningAction SilentlyContinue

            $r.Summary.Failed   | Should -Be 1
            ($r.Failures.Error) | Should -BeLike '*authorization*'
        }

        It 'throws at the end when -FailOnError is set and an endpoint could not be approved' {
            Mock Assert-PrivateEndpointConnectionApproval { throw 'nope' } -ModuleName ZeroFailed.Deploy.Fabric

            { Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev' -FailOnError -WarningAction SilentlyContinue } |
                Should -Throw '*could not be approved*'
        }

        It 'does not approve anything when -WhatIf is set' {
            Mock Assert-PrivateEndpointConnectionApproval { @{ Status = 'Pending'; Action = 'WhatIf' } } -ModuleName ZeroFailed.Deploy.Fabric

            $r = Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev' -WhatIf

            $r.Summary.Failed      | Should -Be 0
            $r.Approvals[0].Action | Should -Be 'WhatIf'
        }

        It 'processes only the environment named in -Environment' {
            Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Test' | Out-Null

            Should -Invoke Assert-PrivateEndpointConnectionApproval -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
                $PrivateLinkResourceId -like '*/vaults/kv-test'
            }
        }

        It 'ignores workspaces with no endpoints configured for the environment' {
            $config = New-TestConfig
            $config.workspaces[0].managedPrivateEndpoints.Test.resources = @()

            $r = Invoke-FabricManagedPrivateEndpointApproval -Config $config

            $r.Approvals.Count | Should -Be 1
        }

        It 'defaults to a 300 second timeout' {
            Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev' | Out-Null

            Should -Invoke Assert-PrivateEndpointConnectionApproval -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
                $TimeoutSeconds -eq 300
            }
        }

        It 'ignores a config that predates managed private endpoints' {
            $config = New-TestConfig
            $config.workspaces[0].PSObject.Properties.Remove('managedPrivateEndpoints')

            $r = Invoke-FabricManagedPrivateEndpointApproval -Config $config

            $r.Approvals.Count | Should -Be 0
            $r.Summary.Failed  | Should -Be 0
        }

        It 'accepts the endpoint block as the ordered dictionary New-FabricTopologyConfig produces in memory' {
            $config = New-TestConfig
            $block  = $config.workspaces[0].managedPrivateEndpoints
            $config.workspaces[0].managedPrivateEndpoints = [ordered]@{ Dev = $block.Dev; Test = $block.Test }

            $r = Invoke-FabricManagedPrivateEndpointApproval -Config $config

            $r.Summary.Approved | Should -Be 2
        }

        It 'refreshes the token when it is near expiry' {
            Mock _Test-FabricTokenExpiry { $true } -ModuleName ZeroFailed.Deploy.Fabric

            Invoke-FabricManagedPrivateEndpointApproval -Config (New-TestConfig) -Environment 'Dev' | Out-Null

            Should -Invoke _Get-FabricAuthToken -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'loads the topology config from a JSON file via -ConfigPath' {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) "topology-$([guid]::NewGuid()).json"
            try {
                New-TestConfig | ConvertTo-Json -Depth 20 | Set-Content -Path $tmp

                $r = Invoke-FabricManagedPrivateEndpointApproval -ConfigPath $tmp -Environment 'Dev'

                $r.Summary.Approved | Should -Be 1
            }
            finally {
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
