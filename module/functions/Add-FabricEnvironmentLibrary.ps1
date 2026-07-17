function Add-FabricEnvironmentLibrary {
    <#
    .SYNOPSIS
        Uploads a single library file (.whl, .tar.gz, .jar, .py) to a Fabric environment's staging area.
    .DESCRIPTION
        Uploads the file to the environment's staging libraries via
        POST /workspaces/{id}/environments/{id}/staging/libraries (multipart/form-data).

        Uploading places the file in staging only — it is not usable by notebooks/jobs until the
        environment is published (see Publish-FabricEnvironment). The maximum file size is 200 MB.

        Re-uploading a file with the same name overwrites the existing staged copy, so this is safe
        to call repeatedly.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID that contains the environment.
    .PARAMETER EnvironmentId
        The Fabric environment GUID to upload the library into.
    .PARAMETER FilePath
        Path to the library file to upload.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .EXAMPLE
        Add-FabricEnvironmentLibrary -WorkspaceId $ws.id -EnvironmentId $env.id `
            -FilePath './dist/mypackage-1.4.2-py3-none-any.whl' -Token $token

        Uploads the wheel into the environment's staging libraries.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$EnvironmentId,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Token
    )

    $fileName = [System.IO.Path]::GetFileName($FilePath)

    if ($PSCmdlet.ShouldProcess($fileName, "Upload library to environment '$EnvironmentId'")) {
        Write-Verbose "Uploading library '$fileName' to environment '$EnvironmentId'..."

        _Invoke-FabricFileUpload `
            -RelativeUri "workspaces/$WorkspaceId/environments/$EnvironmentId/staging/libraries" `
            -FilePath    $FilePath `
            -Token       $Token `
            -ErrorAction Stop | Out-Null

        return @{
            EnvironmentId = $EnvironmentId
            FileName      = $fileName
            Action        = 'Uploaded'
        }
    }
    else {
        return @{
            EnvironmentId = $EnvironmentId
            FileName      = $fileName
            Action        = 'whatif'
        }
    }
}
