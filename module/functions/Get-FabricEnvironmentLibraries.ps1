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
    .EXAMPLE
        Get-FabricEnvironmentLibraries -WorkspaceId $ws.id -EnvironmentId $env.id -Token $token

        Returns the published custom library file names, e.g. @('mypackage-1.4.2-py3-none-any.whl').
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

        [switch]$Staging
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

    $custom = if ($response.PSObject.Properties.Name -contains 'customLibraries') { $response.customLibraries } else { $null }
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
