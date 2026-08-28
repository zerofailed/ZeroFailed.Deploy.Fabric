function _Invoke-FabricFileUpload {
    <#
    .SYNOPSIS
        Uploads a file to the Fabric REST API as a raw octet-stream body, with retry on transient failures.
    .DESCRIPTION
        The JSON-oriented _Invoke-FabricRestMethod wrapper cannot upload binary library files. The
        GA "Upload custom library" API takes the library name in the URL path and the file's raw
        bytes as the request body with Content-Type 'application/octet-stream' — NOT a
        multipart/form-data body. (The older multipart 'staging/libraries' endpoint is deprecated
        as of 2026-08-31 and returns a generic 400 UnknownError.) This helper streams the file via
        Invoke-RestMethod -InFile so the whole file becomes the body.

        The staging-upload endpoint intermittently returns 5xx (typically
        EnvironmentInternalServerError) on larger library files, and often succeeds on a retry. The
        response's own isRetriable flag is unreliable for this, so the retry decision is made by
        status code: 5xx and 429 are retried with exponential backoff (honouring Retry-After when
        present); other 4xx are deterministic client errors and fail immediately.
    .PARAMETER RelativeUri
        URI relative to https://api.fabric.microsoft.com/v1, including the URL-encoded library name,
        e.g. "workspaces/{id}/environments/{id}/staging/libraries/mypackage.whl".
    .PARAMETER FilePath
        Path to the file whose raw bytes are sent as the request body.
    .PARAMETER Token
        Bearer token string from _Get-FabricAuthToken.
    .PARAMETER TimeoutSec
        Per-attempt request timeout in seconds. Default: 600.
    .PARAMETER MaxAttempts
        Maximum number of attempts (initial try + retries) for transient failures. Default: 4.
    .PARAMETER RetryBaseDelaySec
        Base delay for exponential backoff between retries (delay = base * 2^(attempt-1)). Default: 5.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RelativeUri,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Token,

        [int]$TimeoutSec = 600,

        [ValidateRange(1, 10)]
        [int]$MaxAttempts = 4,

        [ValidateRange(0, 300)]
        [int]$RetryBaseDelaySec = 5
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "File not found: $FilePath"
    }

    $baseUrl  = 'https://api.fabric.microsoft.com/v1'
    $uri      = "$baseUrl/$($RelativeUri.TrimStart('/'))"
    $headers  = @{ Authorization = "Bearer $Token" }
    $fileName = [System.IO.Path]::GetFileName($FilePath)

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Write-Debug "UPLOAD POST $uri ($fileName) attempt $attempt/$MaxAttempts"
            # -InFile streams the file's raw bytes as the request body; the GA upload API expects the
            # library name in the URL (already in $RelativeUri) and the content as octet-stream.
            return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers `
                -InFile $FilePath -ContentType 'application/octet-stream' `
                -TimeoutSec $TimeoutSec -ErrorAction Stop
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

            $message = "Fabric API error $statusCode on POST $uri : $content"

            # Only 5xx (transient server-side failure) and 429 (throttling) are worth retrying; any
            # other 4xx is a deterministic client error, so surface it straight away.
            $isTransient = ($statusCode -ge 500) -or ($statusCode -eq 429)
            if (-not $isTransient -or $attempt -eq $MaxAttempts) {
                throw $message
            }

            # Exponential backoff, overridden by a Retry-After header (429/503) when the server sends one.
            $delay = $RetryBaseDelaySec * [math]::Pow(2, $attempt - 1)
            $retryAfter = $_.Exception.Response.Headers.RetryAfter.Delta.TotalSeconds
            if ($retryAfter -and $retryAfter -gt 0) { $delay = $retryAfter }

            Write-Warning "Upload of '$fileName' failed (attempt $attempt/$MaxAttempts): $message. Retrying in $delay s..."
            Start-Sleep -Seconds $delay
        }
        catch {
            # Non-HTTP failures (connection reset, client-side timeout) are usually transient too.
            if ($attempt -eq $MaxAttempts) {
                throw "Upload of '$fileName' to $uri failed after $MaxAttempts attempt(s): $($_.Exception.Message)"
            }

            $delay = $RetryBaseDelaySec * [math]::Pow(2, $attempt - 1)
            Write-Warning "Upload of '$fileName' errored (attempt $attempt/$MaxAttempts): $($_.Exception.Message). Retrying in $delay s..."
            Start-Sleep -Seconds $delay
        }
    }
}
