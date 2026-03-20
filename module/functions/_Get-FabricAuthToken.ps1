function _Get-FabricAuthToken {
    <#
    .SYNOPSIS
        Retrieves a bearer token for the Microsoft Fabric REST API via Get-AzAccessToken.
    .OUTPUTS
        A hashtable with keys: Token (string), ExpiresOn (DateTimeOffset).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $resourceUrl = 'https://analysis.windows.net/powerbi/api'

    try {
        $tokenObj = Get-AzAccessToken -ResourceUrl $resourceUrl -AsSecureString -ErrorAction Stop -WarningAction SilentlyContinue
    }
    catch {
        throw "Failed to acquire Fabric access token. Ensure you are logged in with Connect-AzAccount. Error: $_"
    }

    $plainToken = [System.Net.NetworkCredential]::new('', $tokenObj.Token).Password

    return @{
        Token     = $plainToken
        ExpiresOn = $tokenObj.ExpiresOn
    }
}

function _Test-FabricTokenExpiry {
    <#
    .SYNOPSIS
        Returns $true if the token has fewer than 5 minutes remaining.
    .PARAMETER TokenInfo
        Hashtable returned by _Get-FabricAuthToken.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TokenInfo
    )

    $remaining = $TokenInfo.ExpiresOn - [DateTimeOffset]::UtcNow
    return ($remaining.TotalMinutes -lt 5)
}
