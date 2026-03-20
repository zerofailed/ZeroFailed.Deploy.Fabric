function Test-FabricWorkspaceExists {
    <#
    .SYNOPSIS
        Checks whether a Fabric workspace with the given display name already exists.
    .PARAMETER DisplayName
        The workspace display name to search for.
    .OUTPUTS
        The workspace object if found, or $null if not found.
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
