function _Get-FabricWorkspaceMap {
    <#
    .SYNOPSIS
        Returns every Fabric workspace keyed by display name, from a single paginated GET /workspaces.
    .DESCRIPTION
        Get-FabricTopologyState resolves an entire topology (every workspace type x environment) by
        name. Calling Test-FabricWorkspaceExists per combination re-walks GET /workspaces from the
        start for every workspace that does not exist yet — the common "nothing provisioned" case.
        This fetches the list once and returns a { displayName -> workspace object } hashtable so
        each combination is an O(1) lookup.

        Workspace display names are unique tenant-wide (the naming convention guarantees it), so a
        duplicate key is not expected; last-write-wins is harmless if one occurs. Paginates across
        continuation tokens and is safe under Set-StrictMode.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Token
    )

    $map     = @{}
    $nextUri = 'workspaces'
    do {
        $page = _Invoke-FabricRestMethod -Method GET -RelativeUri $nextUri -Token $Token -ErrorAction Stop
        foreach ($ws in $page.value) {
            $map[$ws.displayName] = $ws
        }

        # continuationToken is only present when more pages remain. Guard the access so it does not
        # throw under Set-StrictMode (as enforced by the ZeroFailed build harness).
        $continuationToken = if ($page.PSObject.Properties.Name -contains 'continuationToken') { $page.continuationToken } else { $null }
        $nextUri = if ($continuationToken) { "workspaces?continuationToken=$continuationToken" } else { $null }
    } while ($nextUri)

    return $map
}

function _Get-FabricDeploymentPipelineMap {
    <#
    .SYNOPSIS
        Returns every Fabric deployment pipeline keyed by display name, from a single paginated
        GET /deploymentPipelines.
    .DESCRIPTION
        The read-only counterpart to the per-type paginated search in Set-FabricDeploymentPipeline.
        Get-FabricTopologyState uses it to resolve every pipeline-enabled workspace type's pipeline
        by name in one pass. Paginates across continuation tokens and is safe under Set-StrictMode.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Token
    )

    $map     = @{}
    $nextUri = 'deploymentPipelines'
    do {
        $page = _Invoke-FabricRestMethod -Method GET -RelativeUri $nextUri -Token $Token -ErrorAction Stop
        foreach ($pipeline in $page.value) {
            $map[$pipeline.displayName] = $pipeline
        }

        $continuationToken = if ($page.PSObject.Properties.Name -contains 'continuationToken') { $page.continuationToken } else { $null }
        $nextUri = if ($continuationToken) { "deploymentPipelines?continuationToken=$continuationToken" } else { $null }
    } while ($nextUri)

    return $map
}
