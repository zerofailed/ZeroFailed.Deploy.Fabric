function Enable-FabricWorkspaceMonitoring {
    <#
    .SYNOPSIS
        Verifies that workspace monitoring has been provisioned for a Fabric workspace.
    .DESCRIPTION
        Checks whether the Monitoring Eventhouse already exists in the workspace by querying the
        workspace items list. Returns success if found (idempotent).

        NOTE: There is no public Fabric REST API to provision the Monitoring Eventhouse
        programmatically. It must be created via the Fabric portal before running provisioning:
        Workspace Settings → Monitoring → +Eventhouse.

        If monitoring has not yet been set up this function throws a clear, actionable error.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID.
    .PARAMETER WorkspaceName
        Display name used in log messages and the returned report entry.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .EXAMPLE
        Enable-FabricWorkspaceMonitoring -WorkspaceId $ws.id -WorkspaceName 'SalesAnalytics-ETL [DEV]' -Token $token

        Verifies that the Monitoring Eventhouse exists for the workspace and returns a report entry.
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

    if ($PSCmdlet.ShouldProcess($WorkspaceName, 'Verify Workspace Monitoring')) {
        Write-Debug "Checking monitoring items for workspace '$WorkspaceName' ($WorkspaceId)..."

        $itemsResponse = _Invoke-FabricRestMethod -Method GET `
            -RelativeUri "workspaces/$WorkspaceId/items" `
            -Token $Token `
            -ErrorAction Stop

        $items = if ($itemsResponse.value) { $itemsResponse.value } else { @($itemsResponse) }

        $monitoringEventhouse = $items | Where-Object {
            $_.type -eq 'Eventhouse' -and $_.displayName -match 'monitoring'
        }

        if ($monitoringEventhouse) {
            Write-Verbose "Monitoring Eventhouse found for workspace '$WorkspaceName'. Monitoring is active."
        }
        else {
            throw (
                "Workspace monitoring has not been set up for '$WorkspaceName'. " +
                "Please enable it manually via the Fabric portal " +
                "(Workspace Settings -> Monitoring -> +Eventhouse) before running provisioning."
            )
        }

        return @{
            WorkspaceName = $WorkspaceName
            WorkspaceId   = $WorkspaceId
            Enabled       = $true
        }
    }
    else {
        return @{
            WorkspaceName = $WorkspaceName
            WorkspaceId   = $WorkspaceId
            Enabled       = 'whatif'
        }
    }
}
