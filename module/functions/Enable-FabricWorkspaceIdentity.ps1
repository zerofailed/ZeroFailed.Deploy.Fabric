function Enable-FabricWorkspaceIdentity {
    <#
    .SYNOPSIS
        Provisions a Workspace Identity (managed identity) for a Fabric workspace.
    .DESCRIPTION
        Checks whether an identity already exists via the Fabric REST API, then uses the
        MicrosoftFabricMgmt module to provision one if needed. Waits for the asynchronous
        provisioning operation to complete using the module's LRO tracking functions before
        returning the service principal details.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID.
    .PARAMETER WorkspaceName
        Display name used in log messages and the returned report entry.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .OUTPUTS
        Hashtable: WorkspaceName, WorkspaceId, ServicePrincipalObjectId, ApplicationId.
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
        # Check if identity already exists
        Write-Debug "Checking existing identity for workspace '$WorkspaceName' ($WorkspaceId)..."
        $existingIdentity = $null
        try {
            $existingIdentity = _Invoke-FabricRestMethod -Method GET `
                -RelativeUri "workspaces/$WorkspaceId/managedIdentity" `
                -Token $Token
        }
        catch {
            # No identity yet or endpoint unavailable — proceed to provision
            Write-Debug "Could not check existing identity for '$WorkspaceName': $_"
        }

        $identity = $null

        if ($existingIdentity -and $existingIdentity.servicePrincipalId) {
            Write-Verbose "Workspace '$WorkspaceName' already has an identity. Skipping provisioning."
            $identity = $existingIdentity
        }
        else {
            # Provision via MicrosoftFabricMgmt module.
            # Add-FabricWorkspaceIdentity returns an operation-tracking object when the API
            # responds 202 (async). We use the module's LRO functions to wait for completion
            # and retrieve the provisioned identity details.
            Write-Host "Provisioning Workspace Identity for '$WorkspaceName' (workspaceId: $WorkspaceId)..."
            $operationInfo = Add-FabricWorkspaceIdentity -WorkspaceId $WorkspaceId -ErrorAction Stop -WarningAction SilentlyContinue

            if ($operationInfo -and $operationInfo.OperationId) {
                Write-Verbose "Identity provisioning accepted (operationId: $($operationInfo.OperationId)). Waiting for completion..."
                $operationStatus = Get-FabricLongRunningOperation `
                    -operationId $operationInfo.OperationId `
                    -location    $operationInfo.Location `
                    -ErrorAction Stop

                if ($operationStatus.status -notin @('Succeeded', 'Completed')) {
                    throw "Identity provisioning operation ended with status '$($operationStatus.status)' for '$WorkspaceName'."
                }

                $identityResult = Get-FabricLongRunningOperationResult `
                    -operationId $operationInfo.OperationId `
                    -ErrorAction Stop

                # The module returns results as an array via List.ToArray()
                $identity = if ($identityResult -is [array]) { $identityResult[0] } else { $identityResult }
            }
            elseif ($operationInfo -and $operationInfo.servicePrincipalId) {
                # Synchronous completion — operation info is the identity itself
                $identity = $operationInfo
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
