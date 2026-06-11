function Test-FabricWorkspaceExists {
    <#
    .SYNOPSIS
        Checks whether a Fabric workspace with the given display name already exists.
    .DESCRIPTION
        Queries the Fabric workspaces for one matching the given display name and returns it if
        found. Returns $null when no matching workspace exists.
    .PARAMETER DisplayName
        The workspace display name to search for.
    .EXAMPLE
        Test-FabricWorkspaceExists -DisplayName 'SalesAnalytics-ETL [DEV]'

        Returns the workspace object if it exists, otherwise $null.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    try {
        $workspace = Get-FabricWorkspace -WorkspaceName $DisplayName -ErrorAction SilentlyContinue
        return $workspace
    }
    catch {
        # Module returns an error when not found in some versions
        return $null
    }
}
