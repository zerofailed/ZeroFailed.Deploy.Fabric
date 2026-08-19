function Enable-FabricWorkspaceIdentity {
    <#
    .SYNOPSIS
        Provisions a Workspace Identity (managed identity) for a Fabric workspace.
    .DESCRIPTION
        Uses the MicrosoftFabricMgmt module to provision a workspace identity. Waits for the
        asynchronous provisioning operation to complete using the module's LRO tracking functions
        before returning the service principal details.

        Idempotent: if the identity is already provisioned, Add-FabricWorkspaceIdentity returns
        an empty response (the module silently swallows the 409/200-no-op from the API). In that
        case the existing identity is read back from the workspace itself (GET /workspaces/{id}
        exposes a workspaceIdentity block), so re-runs report the same service principal details
        as the first run. Returns $null only when the workspace genuinely has no identity.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID.
    .PARAMETER WorkspaceName
        Display name used in log messages and the returned report entry.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .EXAMPLE
        Enable-FabricWorkspaceIdentity -WorkspaceId $ws.id -WorkspaceName 'SalesAnalytics-ETL [DEV]' -Token $token

        Provisions a workspace identity and returns its service principal details.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$WorkspaceName,

        [Parameter(Mandatory)]
        [string]$Token
    )

    if ($PSCmdlet.ShouldProcess($WorkspaceName, 'Enable Workspace Identity')) {
        Write-Host "Provisioning Workspace Identity for '$WorkspaceName' (workspaceId: $WorkspaceId)..."
        $operationInfo = Add-FabricWorkspaceIdentity -WorkspaceId $WorkspaceId -ErrorAction Stop -WarningAction SilentlyContinue

        # Add-FabricWorkspaceIdentity catches all errors internally without rethrowing.
        # When the identity is already provisioned the API returns 200/409 with an empty or
        # error body; the module swallows the error and returns $null or an empty array.
        $isEmptyResponse = ($null -eq $operationInfo) -or ($operationInfo -is [array] -and $operationInfo.Count -eq 0)

        $identity = $null

        if ($isEmptyResponse) {
            # Already provisioned. provisionIdentity tells us nothing about the existing identity,
            # so read it off the workspace instead: GET /workspaces/{id} returns a workspaceIdentity
            # block for any workspace that has one. This keeps re-runs reporting the same SP details
            # as the first run, so callers can still act on the identity (e.g. assign it a role).
            Write-Verbose "Workspace identity for '$WorkspaceName' is already provisioned (provisionIdentity returned no operation). Reading the existing identity from the workspace..."

            $workspace = _Invoke-FabricRestMethod -Method GET `
                -RelativeUri "workspaces/$WorkspaceId" `
                -Token $Token `
                -ErrorAction Stop

            # workspaceIdentity is absent when the workspace has no identity. Guard the access so
            # it does not throw under Set-StrictMode (as enforced by the ZeroFailed build harness).
            $identity = if ($workspace.PSObject.Properties.Name -contains 'workspaceIdentity') { $workspace.workspaceIdentity } else { $null }

            if (-not $identity -or -not $identity.servicePrincipalId) {
                Write-Verbose "No workspace identity found on '$WorkspaceName'. Skipping identity report entry."
                return $null
            }
        }
        else {
            # Normalise: Invoke-FabricAPIRequest wraps 200 responses in a ToArray() array.
            $firstItem = if ($operationInfo -is [array]) { $operationInfo[0] } else { $operationInfo }

            if ($firstItem.OperationId) {
                # 202 Accepted — asynchronous provisioning started
                Write-Verbose "Identity provisioning accepted (operationId: $($firstItem.OperationId)). Waiting for completion..."
                $operationStatus = Get-FabricLongRunningOperation `
                    -operationId $firstItem.OperationId `
                    -location    $firstItem.Location `
                    -ErrorAction Stop

                if ($operationStatus.status -notin @('Succeeded', 'Completed')) {
                    throw "Identity provisioning operation ended with status '$($operationStatus.status)' for '$WorkspaceName'."
                }

                $identityResult = Get-FabricLongRunningOperationResult `
                    -operationId $firstItem.OperationId `
                    -ErrorAction Stop

                # The module returns results as an array via List.ToArray()
                $identity = if ($identityResult -is [array]) { $identityResult[0] } else { $identityResult }
            }
            elseif ($firstItem.servicePrincipalId) {
                # 200 with identity data — already provisioned, API returned existing details
                $identity = $firstItem
            }
        }

        if (-not $identity -or -not $identity.servicePrincipalId) {
            throw "Workspace identity for '$WorkspaceName' could not be retrieved after provisioning."
        }

        Write-Verbose "Workspace Identity ready for '$WorkspaceName' (SP: $($identity.servicePrincipalId))."

        return @{
            WorkspaceName            = $WorkspaceName
            WorkspaceId              = $WorkspaceId
            ServicePrincipalObjectId = $identity.servicePrincipalId
            ApplicationId            = $identity.applicationId
        }
    }
    else {
        return @{
            WorkspaceName            = $WorkspaceName
            WorkspaceId              = $WorkspaceId
            ServicePrincipalObjectId = 'whatif-sp-object-id'
            ApplicationId            = 'whatif-app-id'
        }
    }
}
