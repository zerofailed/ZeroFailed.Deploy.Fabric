function _Invoke-FabricFileUpload {
    <#
    .SYNOPSIS
        Uploads a file to the Fabric REST API using multipart/form-data.
    .DESCRIPTION
        The JSON-oriented _Invoke-FabricRestMethod wrapper cannot upload binary library files, which
        the Fabric environment staging-libraries endpoint requires as a multipart/form-data request
        with a single 'file' part. This helper streams the file via Invoke-RestMethod -Form (PS7),
        which builds the multipart body and boundary automatically — the Content-Type header must
        NOT be set manually or the boundary will not match and the API rejects the request.
    .PARAMETER RelativeUri
        URI relative to https://api.fabric.microsoft.com/v1, e.g.
        "workspaces/{id}/environments/{id}/staging/libraries".
    .PARAMETER FilePath
        Path to the file to upload. The multipart part name is 'file'; the sent filename is the
        file's base name.
    .PARAMETER Token
        Bearer token string from _Get-FabricAuthToken.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RelativeUri,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Token
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "File not found: $FilePath"
    }

    $baseUrl = 'https://api.fabric.microsoft.com/v1'
    $uri     = "$baseUrl/$($RelativeUri.TrimStart('/'))"

    # Only the Authorization header — Invoke-RestMethod -Form generates the multipart Content-Type
    # (including the boundary) itself. Supplying 'file' as a FileInfo streams the content and sets
    # the part's filename to the base name.
    $headers = @{ Authorization = "Bearer $Token" }

    Write-Debug "UPLOAD POST $uri ($([System.IO.Path]::GetFileName($FilePath)))"

    try {
        return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers `
            -Form @{ file = Get-Item -LiteralPath $FilePath } `
            -ErrorAction Stop
    }
    catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        $statusCode = [int]$_.Exception.Response.StatusCode
        $content    = $_.ErrorDetails.Message

        # ErrorDetails.Message is sometimes empty; fall back to the response body, then the reason
        # phrase / exception message, so the real Fabric errorCode is never silently lost.
        if ([string]::IsNullOrWhiteSpace($content)) {
            try {
                $respContent = $_.Exception.Response.Content
                if ($respContent) {
                    $content = $respContent.ReadAsStringAsync().GetAwaiter().GetResult()
                }
            }
            catch { }
        }
        if ([string]::IsNullOrWhiteSpace($content)) {
            $reason  = $_.Exception.Response.ReasonPhrase
            $content = if (-not [string]::IsNullOrWhiteSpace($reason)) { $reason } else { $_.Exception.Message }
        }

        throw "Fabric API error $statusCode on POST $uri : $content"
    }
}
