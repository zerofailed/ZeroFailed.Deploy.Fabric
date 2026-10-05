function _Get-FabricManagedPrivateEndpoint {
    <#
    .SYNOPSIS
        Finds a workspace's managed private endpoint by name.
    .DESCRIPTION
        Lists the workspace's managed private endpoints, following continuation tokens, and returns the
        one with the given name, or $null when there is none.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID.
    .PARAMETER Name
        The managed private endpoint name.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Token
    )

    $nextUri = "workspaces/$WorkspaceId/managedPrivateEndpoints"
    do {
        $page  = _Invoke-FabricRestMethod -Method GET -RelativeUri $nextUri -Token $Token -ErrorAction Stop
        $items = if ($page -and $page.PSObject.Properties.Name -contains 'value') { @($page.value) } else { @() }
        $match = $items | Where-Object { $_.name -eq $Name } | Select-Object -First 1
        if ($match) { return $match }

        # continuationToken is only present when more pages remain. Guard the access so it does
        # not throw under Set-StrictMode (as enforced by the ZeroFailed build harness).
        $continuationToken = if ($page -and $page.PSObject.Properties.Name -contains 'continuationToken') { $page.continuationToken } else { $null }
        $nextUri = if ($continuationToken) { "workspaces/$WorkspaceId/managedPrivateEndpoints?continuationToken=$continuationToken" } else { $null }
    } while ($nextUri)

    return $null
}
