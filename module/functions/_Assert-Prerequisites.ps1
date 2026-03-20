function _Assert-Prerequisites {
    <#
    .SYNOPSIS
        Validates that required tools and modules are available before provisioning.
    #>
    [CmdletBinding()]
    param()

    Write-Verbose 'Checking prerequisites...'

    # Az PowerShell module
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        throw "Az.Accounts PowerShell module is not installed. Run: Install-Module Az -Scope CurrentUser"
    }

    # MicrosoftFabricMgmt module
    if (-not (Get-Module -ListAvailable -Name MicrosoftFabricMgmt)) {
        throw "MicrosoftFabricMgmt PowerShell module is not installed. Run: Install-Module MicrosoftFabricMgmt -Scope CurrentUser"
    }

    Write-Verbose 'All prerequisites satisfied.'
}
