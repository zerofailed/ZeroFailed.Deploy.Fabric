function _Resolve-FabricEnvironment {
    <#
    .SYNOPSIS
        Returns an existing Fabric environment in a workspace by display name, or $null.
    .DESCRIPTION
        Queries GET /workspaces/{id}/environments and returns the first environment whose
        displayName matches. Paginates via continuationToken (StrictMode-safe) so environments
        beyond the first page are found.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID.
    .PARAMETER DisplayName
        The environment display name to match.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$WorkspaceId,
        [Parameter(Mandatory)] [string]$DisplayName,
        [Parameter(Mandatory)] [string]$Token
    )

    $nextUri = "workspaces/$WorkspaceId/environments"
    do {
        $page  = _Invoke-FabricRestMethod -Method GET -RelativeUri $nextUri -Token $Token -ErrorAction Stop
        $match = $page.value | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
        if ($match) {
            return $match
        }
        $continuationToken = if ($page.PSObject.Properties.Name -contains 'continuationToken') { $page.continuationToken } else { $null }
        $nextUri = if ($continuationToken) { "workspaces/$WorkspaceId/environments?continuationToken=$continuationToken" } else { $null }
    } while ($nextUri)

    return $null
}
