function Test-FabricWorkspaceExists {
    <#
    .SYNOPSIS
        Checks whether a Fabric workspace with the given display name already exists.
    .DESCRIPTION
        Lists the Fabric workspaces via the REST API and returns the one whose displayName matches
        exactly, or $null when none match. Uses the same bearer-token REST path as the rest of the
        module (rather than MicrosoftFabricMgmt's Get-FabricWorkspace, whose lookup under the
        injected auth context proved unreliable and caused non-idempotent creation). Paginates
        across continuation tokens and is safe under Set-StrictMode.
    .PARAMETER DisplayName
        The workspace display name to search for.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .EXAMPLE
        Test-FabricWorkspaceExists -DisplayName 'SalesAnalytics-ETL [DEV]' -Token $token

        Returns the workspace object if it exists, otherwise $null.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string]$Token
    )

    $nextUri = 'workspaces'
    do {
        $page  = _Invoke-FabricRestMethod -Method GET -RelativeUri $nextUri -Token $Token -ErrorAction Stop
        $match = $page.value | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
        if ($match) {
            return $match
        }

        # continuationToken is only present when more pages remain. Guard the access so it does
        # not throw under Set-StrictMode (as enforced by the ZeroFailed build harness).
        $continuationToken = if ($page.PSObject.Properties.Name -contains 'continuationToken') { $page.continuationToken } else { $null }
        $nextUri = if ($continuationToken) { "workspaces?continuationToken=$continuationToken" } else { $null }
    } while ($nextUri)

    return $null
}
