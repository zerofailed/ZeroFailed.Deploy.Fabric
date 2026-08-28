function _ConvertTo-FabricEnvironmentYml {
    <#
    .SYNOPSIS
        Builds a Fabric environment.yml body pinning a set of public PyPI packages.
    .DESCRIPTION
        Fabric's "Import external libraries" API takes a conda-style environment.yml whose PyPI
        packages live under a 'pip:' entry of the dependencies list. This produces exactly that from
        a list of {NormalizedName, Version} objects, one pinned 'name==version' per package. PyPI is
        always searched by Fabric, so no channels/index entries are needed. Packages are emitted in
        a stable (sorted) order so the generated document is deterministic.

        Only the 'dependencies' section is emitted. Fabric's portal environment.yml validator accepts
        only 'channels' and 'dependencies' sections and rejects anything else (e.g. a conda 'name:'
        field) with "please remove the unsupported contents" — which blocks the public libraries from
        rendering in the UI even though the publish API accepts the document.
    .PARAMETER Package
        Objects with NormalizedName and Version properties (as produced by _Get-WheelIdentity).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [pscustomobject[]]$Package
    )

    $pins = @($Package | ForEach-Object { "$($_.NormalizedName)==$($_.Version)" } | Sort-Object -Unique)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('dependencies:')
    $lines.Add('  - pip:')
    foreach ($pin in $pins) {
        $lines.Add("    - $pin")
    }

    # Trailing newline keeps the document POSIX-clean; join with LF regardless of host OS.
    return ($lines -join "`n") + "`n"
}
