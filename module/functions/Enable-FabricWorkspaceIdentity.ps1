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
        case the function returns $null — no error is raised, but no identity report entry is
        produced (the SP details are not retrievable via this code path on re-runs).
    .PARAMETER WorkspaceId
        The Fabric workspace GUID.
    .PARAMETER WorkspaceName
        Display name used in log messages and the returned report entry.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .OUTPUTS
        Hashtable: WorkspaceName, WorkspaceId, ServicePrincipalObjectId, ApplicationId.
        Returns $null when the identity is already provisioned (idempotent re-run).
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
        # Treat either as "already provisioned" — return $null so the caller can skip the
        # report entry cleanly without raising a failure.
        $isEmptyResponse = ($null -eq $operationInfo) -or ($operationInfo -is [array] -and $operationInfo.Count -eq 0)
        if ($isEmptyResponse) {
            Write-Verbose "Workspace identity for '$WorkspaceName' is already provisioned (provisionIdentity returned no operation). Skipping identity report entry."
            return $null
        }

        # Normalise: Invoke-FabricAPIRequest wraps 200 responses in a ToArray() array.
        $firstItem = if ($operationInfo -is [array]) { $operationInfo[0] } else { $operationInfo }

        $identity = $null

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
