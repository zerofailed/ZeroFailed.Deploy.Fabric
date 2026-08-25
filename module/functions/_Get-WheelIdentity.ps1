function _Get-WheelIdentity {
    <#
    .SYNOPSIS
        Parses a wheel file name into its distribution name and version.
    .DESCRIPTION
        A wheel file name follows PEP 427: {name}-{version}(-{build})?-{python}-{abi}-{platform}.whl.
        Neither the distribution name nor the version may contain a hyphen, so the first two
        hyphen-separated segments are the name and version. Returns the raw name, the version, and
        the PEP 503 normalised name (lower-cased, runs of -_. collapsed to a single -) used for
        matching against PyPI and for pinning in environment.yml.
    .PARAMETER FileName
        The wheel file name (base name, with or without directory), e.g.
        'charset_normalizer-3.5.1-cp311-cp311-manylinux2014_x86_64.whl'.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$FileName
    )

    $base = [System.IO.Path]::GetFileName($FileName)
    if ($base -notmatch '\.whl$') {
        throw "Not a wheel file name: $FileName"
    }

    $stem  = $base -replace '\.whl$', ''
    $parts = $stem.Split('-')
    if ($parts.Count -lt 2) {
        throw "Cannot parse distribution name/version from wheel file name: $FileName"
    }

    $name    = $parts[0]
    $version = $parts[1]

    [pscustomobject]@{
        Name           = $name
        Version        = $version
        NormalizedName = ($name -replace '[-_.]+', '-').ToLower()
    }
}
