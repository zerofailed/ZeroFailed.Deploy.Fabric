function Get-FabricEnvironmentLibraries {
    <#
    .SYNOPSIS
        Returns the custom library file names configured on a Fabric environment.
    .DESCRIPTION
        Reads the environment's libraries and returns the flat set of custom library file names
        (wheel, py, jar and tar files). Reads the published libraries via
        GET /workspaces/{id}/environments/{id}/libraries, or the staging libraries via
        GET .../staging/libraries when -Staging is specified.

        The returned names are used to decide, idempotently, whether a desired set of files is
        already deployed (so upload and the expensive publish can be skipped). Safe under
        Set-StrictMode — all optional properties are guarded. A 404 (no libraries yet) returns an
        empty array.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID that contains the environment.
    .PARAMETER EnvironmentId
        The Fabric environment GUID to query.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .PARAMETER Staging
        Query the staging libraries instead of the published libraries.
    .PARAMETER External
        Return the external (public) libraries as normalised 'name==version' tokens instead of the
        custom library file names. Used to compare the declared environment.yml set idempotently.
    .EXAMPLE
        Get-FabricEnvironmentLibraries -WorkspaceId $ws.id -EnvironmentId $env.id -Token $token

        Returns the published custom library file names, e.g. @('mypackage-1.4.2-py3-none-any.whl').
    .EXAMPLE
        Get-FabricEnvironmentLibraries -WorkspaceId $ws.id -EnvironmentId $env.id -Token $token -External

        Returns the published external libraries, e.g. @('deltalake==1.6.2', 'pyarrow==20.0.0').
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$EnvironmentId,

        [Parameter(Mandatory)]
        [string]$Token,

        [switch]$Staging,

        [switch]$External
    )

    $relativeUri = if ($Staging) {
        "workspaces/$WorkspaceId/environments/$EnvironmentId/staging/libraries"
    }
    else {
        "workspaces/$WorkspaceId/environments/$EnvironmentId/libraries"
    }

    try {
        $response = _Invoke-FabricRestMethod -Method GET -RelativeUri $relativeUri -Token $Token -ErrorAction Stop
    }
    catch {
        # No libraries have been configured yet — treat as an empty set rather than an error.
        if ("$_" -match '\b404\b' -or "$_" -match 'NotFound' -or "$_" -match 'EnvironmentLibrariesNotFound') {
            return @()
        }
        throw
    }

    # PEP 503 name normalisation so 'pydantic_core' and 'pydantic-core' compare equal across the
    # environment.yml we send and whatever Fabric returns.
    $normalize = { param($n) ($n -replace '[-_.]+', '-').ToLower() }

    # Two response contracts exist. The preview/beta shape (default until 2026-08-31) groups custom
    # library file names under 'customLibraries' and lists external libraries in 'environmentYml';
    # the GA shape returns a flat 'libraries' list of { name, libraryType, version } where custom
    # files carry libraryType 'Custom' and external packages libraryType 'External'. Handle both so
    # this keeps working across the contract flip.
    if ($External) {
        # Beta shape: the external libraries live in the environmentYml document — pull every pinned
        # 'name==version' token out of it, whatever the exact indentation/nesting.
        if ($response.PSObject.Properties.Name -contains 'environmentYml' -and $response.environmentYml) {
            $tokens = foreach ($m in [regex]::Matches($response.environmentYml, '(?m)^\s*-\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*==\s*([^\s#]+)\s*$')) {
                "$(& $normalize $m.Groups[1].Value)==$($m.Groups[2].Value)"
            }
            return @($tokens)
        }

        # GA shape: external entries carry name + version directly.
        if ($response.PSObject.Properties.Name -contains 'libraries' -and $response.libraries) {
            $tokens = foreach ($lib in $response.libraries) {
                if ($lib.PSObject.Properties.Name -contains 'libraryType' -and $lib.libraryType -eq 'External') {
                    if ($lib.PSObject.Properties.Name -contains 'version' -and $lib.version) {
                        "$(& $normalize $lib.name)==$($lib.version)"
                    }
                    else {
                        & $normalize $lib.name
                    }
                }
            }
            return @($tokens)
        }

        return @()
    }

    if ($response.PSObject.Properties.Name -contains 'customLibraries') {
        $custom = $response.customLibraries
        if (-not $custom) {
            return @()
        }

        # Collect every custom library file collection into a single flat name list (StrictMode-safe).
        $names = foreach ($prop in @('wheelFiles', 'pyFiles', 'jarFiles', 'rTarFiles')) {
            if ($custom.PSObject.Properties.Name -contains $prop -and $custom.$prop) {
                $custom.$prop
            }
        }

        return @($names)
    }

    if ($response.PSObject.Properties.Name -contains 'libraries' -and $response.libraries) {
        $names = foreach ($lib in $response.libraries) {
            if ($lib.PSObject.Properties.Name -contains 'libraryType' -and $lib.libraryType -eq 'Custom') {
                $lib.name
            }
        }

        return @($names)
    }

    return @()
}
