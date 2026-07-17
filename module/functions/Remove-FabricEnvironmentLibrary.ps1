function Remove-FabricEnvironmentLibrary {
    <#
    .SYNOPSIS
        Removes a single custom library file from a Fabric environment's staging area.
    .DESCRIPTION
        Deletes the file from the environment's staging libraries via
        DELETE /workspaces/{id}/environments/{id}/staging/libraries?libraryToDelete={name}.

        Staging starts as a copy of the published libraries, so removing a file from staging and
        then publishing (see Publish-FabricEnvironment) is how a published library is retired.
        Until the publish happens the library remains usable by notebooks/jobs.

        A 404 (the library is not staged) is treated as success so this is safe to call repeatedly.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID that contains the environment.
    .PARAMETER EnvironmentId
        The Fabric environment GUID to remove the library from.
    .PARAMETER LibraryName
        The library file name to remove, e.g. 'mypackage-1.4.2-py3-none-any.whl'.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .EXAMPLE
        Remove-FabricEnvironmentLibrary -WorkspaceId $ws.id -EnvironmentId $env.id `
            -LibraryName 'mypackage-1.4.1-py3-none-any.whl' -Token $token

        Removes the stale wheel from the environment's staging libraries.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$EnvironmentId,

        [Parameter(Mandatory)]
        [string]$LibraryName,

        [Parameter(Mandatory)]
        [string]$Token
    )

    if ($PSCmdlet.ShouldProcess($LibraryName, "Remove library from environment '$EnvironmentId'")) {
        Write-Verbose "Removing library '$LibraryName' from environment '$EnvironmentId'..."

        $relativeUri = "workspaces/$WorkspaceId/environments/$EnvironmentId/staging/libraries" +
                       "?libraryToDelete=$([uri]::EscapeDataString($LibraryName))"

        try {
            _Invoke-FabricRestMethod -Method DELETE -RelativeUri $relativeUri -Token $Token -ErrorAction Stop | Out-Null
        }
        catch {
            # Not staged — nothing to remove.
            if ("$_" -match '\b404\b' -or "$_" -match 'NotFound') {
                return @{
                    EnvironmentId = $EnvironmentId
                    FileName      = $LibraryName
                    Action        = 'NotFound'
                }
            }
            throw
        }

        return @{
            EnvironmentId = $EnvironmentId
            FileName      = $LibraryName
            Action        = 'Removed'
        }
    }
    else {
        return @{
            EnvironmentId = $EnvironmentId
            FileName      = $LibraryName
            Action        = 'whatif'
        }
    }
}
