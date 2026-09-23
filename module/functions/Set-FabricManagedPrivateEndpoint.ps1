function Set-FabricManagedPrivateEndpoint {
    <#
    .SYNOPSIS
        Ensures a managed private endpoint exists in a Fabric workspace, idempotently.
    .DESCRIPTION
        Lists the workspace's managed private endpoints (following continuation tokens), then:
          - Creates the endpoint via POST if none with that name exists
          - Skips if an endpoint with that name already targets the same resource and sub-resource
          - Throws if an endpoint with that name targets a different resource or sub-resource

        Fabric has no API to update a managed private endpoint, so a changed target can only be
        applied by deleting and re-creating the endpoint. That is deliberately left to a person:
        deleting an endpoint drops its approved private link connection, and the replacement has to
        be approved again.

        Creating an endpoint only sends a private link connection request to the target resource. Its
        owner must approve the request (Azure portal -> the resource -> Networking -> Private endpoint
        connections) before the endpoint can be used. The returned ConnectionStatus reports the
        approval state, and a warning is written while the endpoint is not yet usable.

        Requires the workspace Admin role, and a workspace on a Fabric capacity that supports managed
        private endpoints.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID.
    .PARAMETER WorkspaceName
        Display name used in log messages and the returned report entry.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .PARAMETER Name
        The managed private endpoint name (at most 64 characters). Invoke-FabricSetup names the
        endpoint after its target resource.
    .PARAMETER TargetPrivateLinkResourceId
        Azure resource ID of the private link resource to connect to, e.g. a Key Vault or storage account.
    .PARAMETER TargetSubresourceType
        The private link sub-resource to connect to, e.g. 'vault' for Key Vault, or 'blob' or 'dfs' for
        a storage account. Storage needs a separate endpoint for each sub-resource that is used.
    .PARAMETER RequestMessage
        Message shown to the target resource's owner with the approval request (at most 140 characters).
    .PARAMETER TargetFQDNs
        Fully qualified domain names to associate with the endpoint (at most 20), for resource types
        that need them, such as Azure API Management.
    .EXAMPLE
        Set-FabricManagedPrivateEndpoint -WorkspaceId $ws.id -WorkspaceName 'SalesAnalytics-ETL [DEV]' -Token $token -Name 'kv-sales-dev.vault' -TargetPrivateLinkResourceId '/subscriptions/{id}/resourceGroups/rg-sales-dev/providers/Microsoft.KeyVault/vaults/kv-sales-dev' -TargetSubresourceType 'vault'

        Ensures the workspace has a managed private endpoint to the Dev Key Vault, creating it if it is absent.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$WorkspaceName,

        [Parameter(Mandatory)]
        [string]$Token,

        [Parameter(Mandatory)]
        [ValidateLength(1, 64)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$TargetPrivateLinkResourceId,

        [string]$TargetSubresourceType,

        [ValidateLength(0, 140)]
        [string]$RequestMessage,

        [ValidateCount(0, 20)]
        [string[]]$TargetFQDNs
    )

    if ($PSCmdlet.ShouldProcess("$WorkspaceName ($Name)", "Ensure managed private endpoint to '$TargetPrivateLinkResourceId'")) {
        Write-Debug "Fetching managed private endpoints for workspace '$WorkspaceName' ($WorkspaceId)..."

        $existing = _Get-FabricManagedPrivateEndpoint -WorkspaceId $WorkspaceId -Name $Name -Token $Token

        if ($existing) {
            $existingProps       = $existing.PSObject.Properties.Name
            $existingTarget      = if ($existingProps -contains 'targetPrivateLinkResourceId') { $existing.targetPrivateLinkResourceId } else { $null }
            $existingSubresource = if ($existingProps -contains 'targetSubresourceType') { $existing.targetSubresourceType } else { $null }

            # Azure resource IDs are case-insensitive, as is PowerShell's -ne on strings.
            $targetDrifted      = $existingTarget -ne $TargetPrivateLinkResourceId
            $subresourceDrifted = $TargetSubresourceType -and $existingSubresource -and ($existingSubresource -ne $TargetSubresourceType)

            if ($targetDrifted -or $subresourceDrifted) {
                throw (
                    "Managed private endpoint '$Name' on '$WorkspaceName' already exists but targets " +
                    "'$existingTarget' ($existingSubresource) rather than '$TargetPrivateLinkResourceId' ($TargetSubresourceType). " +
                    "Fabric cannot update a managed private endpoint in place: delete it from the workspace's " +
                    "network security settings, then re-run provisioning to re-create it (the new connection will need approving again)."
                )
            }

            Write-Verbose "Managed private endpoint '$Name' already exists on '$WorkspaceName' with the expected target. Skipping."
            $endpoint = $existing
            $action   = 'Skipped'
        }
        else {
            Write-Verbose "Creating managed private endpoint '$Name' on '$WorkspaceName' to '$TargetPrivateLinkResourceId'..."

            $body = @{
                name                        = $Name
                targetPrivateLinkResourceId = $TargetPrivateLinkResourceId
            }
            if ($TargetSubresourceType) { $body.targetSubresourceType = $TargetSubresourceType }
            if ($RequestMessage)        { $body.requestMessage        = $RequestMessage }
            if ($TargetFQDNs)           { $body.targetFQDNs           = @($TargetFQDNs) }

            $endpoint = _Invoke-FabricRestMethod -Method POST `
                -RelativeUri "workspaces/$WorkspaceId/managedPrivateEndpoints" `
                -Body $body `
                -Token $Token `
                -ErrorAction Stop
            $action = 'Created'
        }

        $endpointProps     = if ($endpoint) { $endpoint.PSObject.Properties.Name } else { @() }
        $endpointId        = if ($endpointProps -contains 'id') { $endpoint.id } else { $null }
        $provisioningState = if ($endpointProps -contains 'provisioningState') { $endpoint.provisioningState } else { $null }
        # A newly created endpoint has no connectionState until its request reaches the target resource.
        $connectionState   = if ($endpointProps -contains 'connectionState') { $endpoint.connectionState } else { $null }
        $connectionStatus  = if ($connectionState -and $connectionState.PSObject.Properties.Name -contains 'status') { $connectionState.status } else { $null }

        # The endpoint is unusable until its connection is approved on the target resource. Surface
        # that on every run until it is, since it needs someone to act outside this pipeline.
        if ($provisioningState -eq 'Failed') {
            Write-Warning "Managed private endpoint '$Name' on '$WorkspaceName' failed to provision. Delete it and re-run provisioning; if it fails again, raise a Fabric support request."
        }
        elseif ($action -eq 'Created') {
            Write-Warning "Managed private endpoint '$Name' requested on '$WorkspaceName'. It cannot be used until the owner of '$TargetPrivateLinkResourceId' approves its private endpoint connection."
        }
        elseif ($connectionStatus -and $connectionStatus -ne 'Approved') {
            Write-Warning "Managed private endpoint '$Name' on '$WorkspaceName' has connection status '$connectionStatus'. It cannot be used until its private endpoint connection to '$TargetPrivateLinkResourceId' is approved."
        }

        return @{
            WorkspaceName               = $WorkspaceName
            WorkspaceId                 = $WorkspaceId
            Name                        = $Name
            EndpointId                  = $endpointId
            TargetPrivateLinkResourceId = $TargetPrivateLinkResourceId
            TargetSubresourceType       = $TargetSubresourceType
            ProvisioningState           = $provisioningState
            ConnectionStatus            = $connectionStatus
            Action                      = $action
        }
    }
    else {
        return @{
            WorkspaceName               = $WorkspaceName
            WorkspaceId                 = $WorkspaceId
            Name                        = $Name
            EndpointId                  = $null
            TargetPrivateLinkResourceId = $TargetPrivateLinkResourceId
            TargetSubresourceType       = $TargetSubresourceType
            ProvisioningState           = $null
            ConnectionStatus            = $null
            Action                      = 'WhatIf'
        }
    }
}
