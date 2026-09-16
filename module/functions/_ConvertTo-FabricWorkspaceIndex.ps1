function _ConvertTo-FabricWorkspaceIndex {
    <#
    .SYNOPSIS
        Builds the nested WorkspacesByType index from a flat list of per-workspace records.
    .DESCRIPTION
        Both Invoke-FabricSetup and Get-FabricTopologyState expose the same per-workspace model as a
        flat 'Workspaces' list plus a nested 'WorkspacesByType.<type>.<environment>' view. This
        synthesises the nested view from the flat list once, at the end of the run, so the two views
        always hold the *same* record objects and cannot drift.

        The returned structure is an ordered dictionary of ordered dictionaries; the leaf values are
        the exact record objects passed in (not copies), so mutating one view is visible via the other.
    .PARAMETER Workspace
        The flat list of records (as produced by _New-FabricWorkspaceRecord and enriched by the caller).
        Each must carry .Type and .Environment.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [pscustomobject[]]$Workspace
    )

    $index = [ordered]@{}
    foreach ($rec in $Workspace) {
        if (-not $index.Contains($rec.Type)) {
            $index[$rec.Type] = [ordered]@{}
        }
        $index[$rec.Type][$rec.Environment] = $rec
    }

    $index
}
