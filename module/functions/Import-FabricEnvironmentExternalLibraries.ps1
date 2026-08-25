function Import-FabricEnvironmentExternalLibraries {
    <#
    .SYNOPSIS
        Imports the external (public) libraries of a Fabric environment from an environment.yml.
    .DESCRIPTION
        Uploads an environment.yml describing public PyPI/conda packages to the environment's staging
        area via POST /workspaces/{id}/environments/{id}/staging/libraries/importExternalLibraries.
        The call OVERRIDES the whole external library list, so the supplied document is the complete
        desired set — stale external libraries are removed automatically on the next publish.

        Like custom library uploads, this stages only; the environment must be published (see
        Publish-FabricEnvironment) for the changes to take effect. The document is sent as the raw
        request body via _Invoke-FabricFileUpload, which also gives it retry-on-5xx behaviour.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID that contains the environment.
    .PARAMETER EnvironmentId
        The Fabric environment GUID to import into.
    .PARAMETER EnvironmentYml
        The environment.yml content (as a string) listing the public libraries.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .EXAMPLE
        Import-FabricEnvironmentExternalLibraries -WorkspaceId $ws.id -EnvironmentId $env.id `
            -EnvironmentYml $yml -Token $token

        Replaces the environment's staged external libraries with those declared in $yml.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$EnvironmentId,

        [Parameter(Mandatory)]
        [string]$EnvironmentYml,

        [Parameter(Mandatory)]
        [string]$Token
    )

    if (-not $PSCmdlet.ShouldProcess($EnvironmentId, 'Import external libraries (environment.yml)')) {
        return @{
            EnvironmentId = $EnvironmentId
            Action        = 'whatif'
        }
    }

    Write-Verbose "Importing external libraries into environment '$EnvironmentId'..."

    # The API reads the request body as an environment.yml file, so stage it to a temp file and let
    # _Invoke-FabricFileUpload stream it (octet-stream + retry). A .yml suffix keeps the sent name sane.
    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "fabric-environment-$([guid]::NewGuid()).yml"
    try {
        # Write UTF-8 without BOM — a BOM can trip YAML parsers.
        [System.IO.File]::WriteAllText($tempFile, $EnvironmentYml, [System.Text.UTF8Encoding]::new($false))

        _Invoke-FabricFileUpload `
            -RelativeUri "workspaces/$WorkspaceId/environments/$EnvironmentId/staging/libraries/importExternalLibraries" `
            -FilePath    $tempFile `
            -Token       $Token `
            -ErrorAction Stop | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
    }

    return @{
        EnvironmentId = $EnvironmentId
        Action        = 'Imported'
    }
}
