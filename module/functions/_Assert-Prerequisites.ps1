function _Assert-Prerequisites {
    <#
    .SYNOPSIS
        Validates that required tools and modules are available before provisioning.
    .DESCRIPTION
        Runtime guard called by Invoke-FabricSetup itself, independent of ZeroFailed.DevOps.Common's
        'RequiredPowerShellModules' / 'setupModules' mechanism (used by the 'ensureFabricModules'
        task in fabric.tasks.ps1 to install these same modules at build time). That mechanism only
        runs as part of the ZeroFailed InvokeBuild task graph, so it does not help a caller that
        invokes Invoke-FabricSetup directly (e.g. from a script, notebook, or outside a ZeroFailed
        build). This function fills that gap with a fast, explicit check independent of how
        Invoke-FabricSetup was invoked.
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
