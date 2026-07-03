function Set-FabricWorkspaceDefaultEnvironment {
    <#
    .SYNOPSIS
        Sets a Fabric environment as the workspace default (idempotent).
    .DESCRIPTION
        Configures the workspace Spark settings so that notebooks and Spark job definitions using
        "Workspace default" inherit the given environment's compute and library configuration.

        The environment is referenced by display name (an empty string clears the default).
        Uses PATCH /workspaces/{id}/spark/settings; the caller must have the workspace Admin role.

        Idempotent: reads the current Spark settings first and skips the PATCH if the default
        environment is already set to the requested name.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID.
    .PARAMETER WorkspaceName
        Display name used in log messages and the returned report entry.
    .PARAMETER EnvironmentName
        Display name of the environment to set as the workspace default.
    .PARAMETER RuntimeVersion
        Spark runtime version for the default environment. Default: 1.3.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .EXAMPLE
        Set-FabricWorkspaceDefaultEnvironment -WorkspaceId $ws.id -WorkspaceName 'SalesAnalytics-ETL [DEV]' `
            -EnvironmentName 'SalesAnalytics-ETL [DEV] Env' -Token $token

        Sets the environment as the workspace default, or reports Skipped if already set.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$WorkspaceName,

        [Parameter(Mandatory)]
        [string]$EnvironmentName,

        [string]$RuntimeVersion = '1.3',

        [Parameter(Mandatory)]
        [string]$Token
    )

    if ($PSCmdlet.ShouldProcess($WorkspaceName, "Set default environment '$EnvironmentName'")) {

        # Idempotency: skip the PATCH if the default is already the requested environment.
        $current = _Invoke-FabricRestMethod -Method GET `
            -RelativeUri "workspaces/$WorkspaceId/spark/settings" `
            -Token $Token `
            -ErrorAction Stop

        $currentEnv = if ($current.PSObject.Properties.Name -contains 'environment') { $current.environment } else { $null }
        $currentName = if ($currentEnv -and $currentEnv.PSObject.Properties.Name -contains 'name') { $currentEnv.name } else { $null }

        if ($currentName -eq $EnvironmentName) {
            Write-Verbose "Default environment for '$WorkspaceName' is already '$EnvironmentName'. Skipping."
            return @{
                WorkspaceName   = $WorkspaceName
                WorkspaceId     = $WorkspaceId
                EnvironmentName = $EnvironmentName
                Action          = 'Skipped'
            }
        }

        Write-Verbose "Setting default environment for '$WorkspaceName' to '$EnvironmentName' (runtime $RuntimeVersion)..."
        _Invoke-FabricRestMethod -Method PATCH `
            -RelativeUri "workspaces/$WorkspaceId/spark/settings" `
            -Body        @{ environment = @{ name = $EnvironmentName; runtimeVersion = $RuntimeVersion } } `
            -Token       $Token `
            -ErrorAction Stop | Out-Null

        return @{
            WorkspaceName   = $WorkspaceName
            WorkspaceId     = $WorkspaceId
            EnvironmentName = $EnvironmentName
            Action          = 'Set'
        }
    }
    else {
        return @{
            WorkspaceName   = $WorkspaceName
            WorkspaceId     = $WorkspaceId
            EnvironmentName = $EnvironmentName
            Action          = 'whatif'
        }
    }
}
