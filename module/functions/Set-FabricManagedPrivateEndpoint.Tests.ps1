#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Shared parameters used across most tests
    $script:baseParams = @{
        WorkspaceId                 = 'ws-001'
        WorkspaceName               = 'my-ws'
        Token                       = 'tok'
        Name                        = 'sales-ETL-KeyVault-DEV'
        TargetPrivateLinkResourceId = '/subscriptions/sub-1/resourceGroups/rg-dev/providers/Microsoft.KeyVault/vaults/kv-dev'
        TargetSubresourceType       = 'vault'
    }
}

Describe 'Set-FabricManagedPrivateEndpoint' {

    It 'returns a WhatIf entry and makes no API calls when -WhatIf is specified' {
        Mock _Invoke-FabricRestMethod {} -ModuleName ZeroFailed.Deploy.Fabric

        $result = Set-FabricManagedPrivateEndpoint @script:baseParams -WhatIf
        $result.Action                      | Should -Be 'WhatIf'
        $result.Name                        | Should -Be 'sales-ETL-KeyVault-DEV'
        $result.TargetPrivateLinkResourceId | Should -Be $script:baseParams.TargetPrivateLinkResourceId
        Should -Invoke _Invoke-FabricRestMethod -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    Context 'creating' {

        BeforeEach {
            Mock _Invoke-FabricRestMethod {
                param($Method)
                if ($Method -eq 'GET') {
                    return [pscustomobject]@{
                        value = @([pscustomobject]@{
                            id                          = 'other'
                            name                        = 'some-other-mpe'
                            targetPrivateLinkResourceId = '/subscriptions/x/resourceGroups/y/providers/Microsoft.Storage/storageAccounts/z'
                        })
                    }
                }
                return [pscustomobject]@{ id = 'mpe-001'; name = 'sales-ETL-KeyVault-DEV'; provisioningState = 'Provisioning' }
            } -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'creates the endpoint via POST when none with the name exists' {
            $result = Set-FabricManagedPrivateEndpoint @script:baseParams -WarningAction SilentlyContinue
            $result.Action            | Should -Be 'Created'
            $result.EndpointId        | Should -Be 'mpe-001'
            $result.ProvisioningState | Should -Be 'Provisioning'
            $result.ConnectionStatus  | Should -BeNullOrEmpty

            Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
                $Method -eq 'POST' -and
                $RelativeUri -eq 'workspaces/ws-001/managedPrivateEndpoints' -and
                $Body.name -eq 'sales-ETL-KeyVault-DEV' -and
                $Body.targetPrivateLinkResourceId -like '*/vaults/kv-dev' -and
                $Body.targetSubresourceType -eq 'vault'
            }
        }

        It 'omits optional fields from the request body when they are not supplied' {
            $params = $script:baseParams.Clone()
            $params.Remove('TargetSubresourceType')
            Set-FabricManagedPrivateEndpoint @params -WarningAction SilentlyContinue | Out-Null

            Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
                $Method -eq 'POST' -and
                -not $Body.ContainsKey('targetSubresourceType') -and
                -not $Body.ContainsKey('requestMessage') -and
                -not $Body.ContainsKey('targetFQDNs')
            }
        }

        It 'includes the request message and FQDNs in the request body when supplied' {
            Set-FabricManagedPrivateEndpoint @script:baseParams -RequestMessage 'Please approve' `
                -TargetFQDNs @('a.example.com', 'b.example.com') -WarningAction SilentlyContinue | Out-Null

            Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
                $Method -eq 'POST' -and
                $Body.requestMessage -eq 'Please approve' -and
                @($Body.targetFQDNs).Count -eq 2
            }
        }

        It 'warns that the new endpoint needs approving before it can be used' {
            Set-FabricManagedPrivateEndpoint @script:baseParams -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
            "$warnings" | Should -Match 'approves its private endpoint connection'
        }

        It 'propagates an error from creating the endpoint' {
            Mock _Invoke-FabricRestMethod {
                param($Method)
                if ($Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
                throw 'POST failed'
            } -ModuleName ZeroFailed.Deploy.Fabric

            { Set-FabricManagedPrivateEndpoint @script:baseParams } | Should -Throw '*POST failed*'
        }
    }

    Context 'an endpoint with the name already exists' {

        It 'skips when it already targets the same resource, ignoring resource ID casing' {
            Mock _Invoke-FabricRestMethod {
                [pscustomobject]@{
                    value = @([pscustomobject]@{
                        id                          = 'mpe-003'
                        name                        = 'sales-ETL-KeyVault-DEV'
                        targetPrivateLinkResourceId = '/subscriptions/sub-1/resourcegroups/RG-DEV/providers/Microsoft.KeyVault/vaults/kv-dev'
                        targetSubresourceType       = 'vault'
                        provisioningState           = 'Succeeded'
                        connectionState             = [pscustomobject]@{ status = 'Approved'; description = 'Endpoint approved' }
                    })
                }
            } -ModuleName ZeroFailed.Deploy.Fabric

            $result = Set-FabricManagedPrivateEndpoint @script:baseParams -WarningVariable warnings
            $result.Action            | Should -Be 'Skipped'
            $result.EndpointId        | Should -Be 'mpe-003'
            $result.ProvisioningState | Should -Be 'Succeeded'
            $result.ConnectionStatus  | Should -Be 'Approved'
            $warnings                 | Should -BeNullOrEmpty
            Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }

        It 'warns while the existing endpoint is still awaiting approval' {
            Mock _Invoke-FabricRestMethod {
                [pscustomobject]@{
                    value = @([pscustomobject]@{
                        id                          = 'mpe-004'
                        name                        = 'sales-ETL-KeyVault-DEV'
                        targetPrivateLinkResourceId = '/subscriptions/sub-1/resourceGroups/rg-dev/providers/Microsoft.KeyVault/vaults/kv-dev'
                        targetSubresourceType       = 'vault'
                        provisioningState           = 'Succeeded'
                        connectionState             = [pscustomobject]@{ status = 'Pending' }
                    })
                }
            } -ModuleName ZeroFailed.Deploy.Fabric

            $result = Set-FabricManagedPrivateEndpoint @script:baseParams -WarningVariable warnings -WarningAction SilentlyContinue
            $result.Action           | Should -Be 'Skipped'
            $result.ConnectionStatus | Should -Be 'Pending'
            "$warnings"              | Should -Match "connection status 'Pending'"
        }

        It 'warns when the existing endpoint failed to provision' {
            Mock _Invoke-FabricRestMethod {
                [pscustomobject]@{
                    value = @([pscustomobject]@{
                        id                          = 'mpe-005'
                        name                        = 'sales-ETL-KeyVault-DEV'
                        targetPrivateLinkResourceId = '/subscriptions/sub-1/resourceGroups/rg-dev/providers/Microsoft.KeyVault/vaults/kv-dev'
                        provisioningState           = 'Failed'
                    })
                }
            } -ModuleName ZeroFailed.Deploy.Fabric

            Set-FabricManagedPrivateEndpoint @script:baseParams -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
            "$warnings" | Should -Match 'failed to provision'
        }

        It 'throws, without creating anything, when it targets a different resource' {
            Mock _Invoke-FabricRestMethod {
                [pscustomobject]@{
                    value = @([pscustomobject]@{
                        id                          = 'mpe-006'
                        name                        = 'sales-ETL-KeyVault-DEV'
                        targetPrivateLinkResourceId = '/subscriptions/sub-1/resourceGroups/rg-prod/providers/Microsoft.KeyVault/vaults/kv-prod'
                        targetSubresourceType       = 'vault'
                    })
                }
            } -ModuleName ZeroFailed.Deploy.Fabric

            { Set-FabricManagedPrivateEndpoint @script:baseParams } | Should -Throw '*cannot update a managed private endpoint in place*'
            Should -Invoke _Invoke-FabricRestMethod -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter { $Method -eq 'POST' }
        }

        It 'throws when it targets a different sub-resource' {
            Mock _Invoke-FabricRestMethod {
                [pscustomobject]@{
                    value = @([pscustomobject]@{
                        id                          = 'mpe-007'
                        name                        = 'sales-ETL-KeyVault-DEV'
                        targetPrivateLinkResourceId = '/subscriptions/sub-1/resourceGroups/rg-dev/providers/Microsoft.KeyVault/vaults/kv-dev'
                        targetSubresourceType       = 'blob'
                    })
                }
            } -ModuleName ZeroFailed.Deploy.Fabric

            { Set-FabricManagedPrivateEndpoint @script:baseParams } | Should -Throw '*cannot update a managed private endpoint in place*'
        }

        It 'follows the continuation token to find it on a later page' {
            Mock _Invoke-FabricRestMethod {
                param($Method, $RelativeUri)
                if ($RelativeUri -eq 'workspaces/ws-001/managedPrivateEndpoints') {
                    return [pscustomobject]@{
                        value             = @([pscustomobject]@{ id = 'p1'; name = 'page-one-mpe'; targetPrivateLinkResourceId = '/x' })
                        continuationToken = 'tok-2'
                    }
                }
                return [pscustomobject]@{
                    value = @([pscustomobject]@{
                        id                          = 'p2'
                        name                        = 'sales-ETL-KeyVault-DEV'
                        targetPrivateLinkResourceId = '/subscriptions/sub-1/resourceGroups/rg-dev/providers/Microsoft.KeyVault/vaults/kv-dev'
                        targetSubresourceType       = 'vault'
                        provisioningState           = 'Succeeded'
                        connectionState             = [pscustomobject]@{ status = 'Approved' }
                    })
                }
            } -ModuleName ZeroFailed.Deploy.Fabric

            $result = Set-FabricManagedPrivateEndpoint @script:baseParams
            $result.Action     | Should -Be 'Skipped'
            $result.EndpointId | Should -Be 'p2'
            Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric `
                -ParameterFilter { $RelativeUri -eq 'workspaces/ws-001/managedPrivateEndpoints?continuationToken=tok-2' }
        }
    }

    It 'does not throw under StrictMode when optional response fields are absent' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            Set-StrictMode -Version Latest
            Mock _Invoke-FabricRestMethod {
                param($Method)
                # The last/only list page omits continuationToken; a new endpoint has no connectionState yet.
                if ($Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
                return [pscustomobject]@{ id = 'mpe-008'; name = 'n'; provisioningState = 'Provisioning' }
            }

            $result = Set-FabricManagedPrivateEndpoint -WorkspaceId 'ws' -WorkspaceName 'ws' -Token 'tok' -Name 'n' `
                -TargetPrivateLinkResourceId '/subscriptions/s/resourceGroups/r/providers/Microsoft.KeyVault/vaults/v' `
                -WarningAction SilentlyContinue
            $result.Action           | Should -Be 'Created'
            $result.ConnectionStatus | Should -BeNullOrEmpty
        }
    }

    It 'propagates an error from listing endpoints' {
        Mock _Invoke-FabricRestMethod { throw 'API error' } -ModuleName ZeroFailed.Deploy.Fabric
        { Set-FabricManagedPrivateEndpoint @script:baseParams } | Should -Throw '*API error*'
    }

    It 'rejects a name longer than Fabric allows' {
        $params = $script:baseParams.Clone()
        $params.Name = 'x' * 65
        { Set-FabricManagedPrivateEndpoint @params -WhatIf } | Should -Throw
    }

    It 'rejects a request message longer than Fabric allows' {
        { Set-FabricManagedPrivateEndpoint @script:baseParams -RequestMessage ('x' * 141) -WhatIf } | Should -Throw
    }
}
