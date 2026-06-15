function _Invoke-FabricRestMethod {
    <#
    .SYNOPSIS
        Wrapper around Invoke-RestMethod for the Fabric REST API with LRO polling support.
    .DESCRIPTION
        Sends a REST request to the Fabric API. If the response is HTTP 202 (Accepted),
        polls the Location header until the operation completes or times out.
    .PARAMETER Method
        HTTP method: GET, POST, PATCH, DELETE.
    .PARAMETER RelativeUri
        URI relative to https://api.fabric.microsoft.com/v1, e.g. "workspaces/{id}/git/connect".
    .PARAMETER Body
        Optional request body (will be serialised to JSON).
    .PARAMETER Token
        Bearer token string from _Get-FabricAuthToken.
    .PARAMETER PollingIntervalSeconds
        Seconds between LRO poll attempts. Default: 5.
    .PARAMETER TimeoutSeconds
        Maximum seconds to wait for LRO completion. Default: 300.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE', 'PUT')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$RelativeUri,

        [object]$Body,

        [Parameter(Mandatory)]
        [string]$Token,

        [int]$PollingIntervalSeconds = 5,
        [int]$TimeoutSeconds         = 300
    )

    $baseUrl = 'https://api.fabric.microsoft.com/v1'
    $uri     = "$baseUrl/$($RelativeUri.TrimStart('/'))"

    $headers = @{
        Authorization  = "Bearer $Token"
        'Content-Type' = 'application/json'
    }

    $invokeParams = @{
        Method      = $Method
        Uri         = $uri
        Headers     = $headers
        ErrorAction = 'Stop'
    }

    if ($Body) {
        $invokeParams.Body = ($Body | ConvertTo-Json -Depth 20 -Compress)
    }

    Write-Debug "REST $Method $uri"

    try {
        $response = Invoke-RestMethod @invokeParams -ResponseHeadersVariable responseHeaders -StatusCodeVariable statusCode
    }
    catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        $statusCode = [int]$_.Exception.Response.StatusCode
        $content    = $_.ErrorDetails.Message
        throw "Fabric API error $statusCode on $Method $uri : $content"
    }

    # Handle LRO (HTTP 202)
    if ($statusCode -eq 202) {
        $locationUrl = $responseHeaders['Location'] | Select-Object -First 1
        if (-not $locationUrl) {
            Write-Warning "HTTP 202 received but no Location header — treating as success."
            return $response
        }

        Write-Debug "LRO started. Polling: $locationUrl"
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

        while ([DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Seconds $PollingIntervalSeconds

            try {
                $pollResponse = Invoke-RestMethod -Method GET -Uri $locationUrl -Headers $headers `
                    -ErrorAction Stop -StatusCodeVariable pollStatus
            }
            catch [Microsoft.PowerShell.Commands.HttpResponseException] {
                throw "LRO poll failed on $locationUrl : $($_.ErrorDetails.Message)"
            }

            # Guard optional property access so it does not throw under Set-StrictMode.
            $status          = if ($pollResponse.PSObject.Properties.Name -contains 'status')          { $pollResponse.status }          else { $null }
            $operationStatus = if ($pollResponse.PSObject.Properties.Name -contains 'operationStatus') { $pollResponse.operationStatus } else { $null }
            $opStatus        = if ($status) { $status } elseif ($operationStatus) { $operationStatus } else { 'Running' }
            Write-Debug "LRO status: $opStatus"

            if ($opStatus -in @('Succeeded', 'Completed')) {
                return $pollResponse
            }
            elseif ($opStatus -in @('Failed', 'Canceled')) {
                $errObj = if ($pollResponse.PSObject.Properties.Name -contains 'error') { $pollResponse.error } else { $null }
                $errMsg = if ($errObj -and $errObj.PSObject.Properties.Name -contains 'message') { $errObj.message } else { 'Unknown LRO failure' }
                throw "LRO operation failed with status '$opStatus': $errMsg"
            }
        }

        throw "LRO timed out after $TimeoutSeconds seconds: $locationUrl"
    }

    return $response
}
