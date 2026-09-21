function _Get-FabricWorkspaceIdentity {
    <#
    .SYNOPSIS
        Returns a Fabric workspace's identity (applicationId, servicePrincipalId), or $null.
    .DESCRIPTION
        Reads GET /workspaces/{id}, which exposes a workspaceIdentity block for any workspace that has
        a workspace identity. Returns $null when the workspace has none. StrictMode-safe.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$WorkspaceId,
        [Parameter(Mandatory)] [string]$Token
    )

    $workspace = _Invoke-FabricRestMethod -Method GET -RelativeUri "workspaces/$WorkspaceId" -Token $Token -ErrorAction Stop

    $identity = if ($workspace.PSObject.Properties.Name -contains 'workspaceIdentity') { $workspace.workspaceIdentity } else { $null }
    if (-not $identity -or -not ($identity.PSObject.Properties.Name -contains 'applicationId') -or -not $identity.applicationId) {
        return $null
    }

    return $identity
}
