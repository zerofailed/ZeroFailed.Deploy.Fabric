function _Test-PackageOnPyPI {
    <#
    .SYNOPSIS
        Returns $true when the given package version is published on public PyPI.
    .DESCRIPTION
        Used to classify a downloaded wheel as public (resolvable from PyPI, so it can be declared
        as an external library in environment.yml) or private (feed-only, so it must be uploaded as
        a custom library). Queries the PyPI JSON API for the exact name+version: a 200 means public,
        a 404 means it is not on PyPI at that version. Any other failure (network, throttling) is
        re-thrown rather than being guessed at, so a transient error can't silently misclassify a
        public package as private (which would try to upload a large wheel and hit the size limit).
    .PARAMETER Name
        The (normalised) distribution name, e.g. 'charset-normalizer'.
    .PARAMETER Version
        The exact version, e.g. '3.5.1'.
    .PARAMETER TimeoutSec
        Per-request timeout. Default: 30.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Version,

        [int]$TimeoutSec = 30
    )

    $uri = "https://pypi.org/pypi/$([uri]::EscapeDataString($Name))/$([uri]::EscapeDataString($Version))/json"

    try {
        Invoke-RestMethod -Method Get -Uri $uri -TimeoutSec $TimeoutSec -ErrorAction Stop | Out-Null
        return $true
    }
    catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        if ([int]$_.Exception.Response.StatusCode -eq 404) {
            return $false
        }
        throw "PyPI lookup for '$Name==$Version' failed: $($_.Exception.Message)"
    }
}
