function _Resolve-FabricVariableLibrary {
    <#
    .SYNOPSIS
        Returns an existing Fabric variable library in a workspace by display name, or $null.
    .DESCRIPTION
        Queries GET /workspaces/{id}/variableLibraries and returns the first variable library whose
        displayName matches. Paginates via continuationToken (StrictMode-safe) so libraries beyond the
        first page are found. Fabric variable library names are not case sensitive, so the match is
        case-insensitive.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID.
    .PARAMETER DisplayName
        The variable library display name to match.
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

    $nextUri = "workspaces/$WorkspaceId/variableLibraries"
    do {
        $page  = _Invoke-FabricRestMethod -Method GET -RelativeUri $nextUri -Token $Token -ErrorAction Stop
        $match = $page.value | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
        if ($match) {
            return $match
        }
        $continuationToken = if ($page.PSObject.Properties.Name -contains 'continuationToken') { $page.continuationToken } else { $null }
        $nextUri = if ($continuationToken) { "workspaces/$WorkspaceId/variableLibraries?continuationToken=$continuationToken" } else { $null }
    } while ($nextUri)

    return $null
}
