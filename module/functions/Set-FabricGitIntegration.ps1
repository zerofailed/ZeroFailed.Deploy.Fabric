function Set-FabricGitIntegration {
    <#
    .SYNOPSIS
        Connects a Fabric workspace to a Git repository and initialises the connection.
    .DESCRIPTION
        Uses the Fabric REST API (POST /workspaces/{id}/git/connect then /git/initializeConnection).
        HTTP 400 WorkspaceAlreadyConnectedToGit is treated as a non-fatal idempotency condition.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID.
    .PARAMETER WorkspaceName
        Display name used in log messages.
    .PARAMETER GitConfig
        The git block from the topology config for this workspace.
    .PARAMETER Branch
        The branch name to connect for this environment (resolved from branchMap).
    .PARAMETER Token
        Bearer token string.
    .EXAMPLE
        Set-FabricGitIntegration -WorkspaceId $ws.id -WorkspaceName 'SalesAnalytics-ETL [DEV]' -GitConfig $cfg.git -Branch 'main' -Token $token

        Connects the workspace to the configured Git repository and initialises the connection.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$WorkspaceName,

        [Parameter(Mandatory)]
        [pscustomobject]$GitConfig,

        [Parameter(Mandatory)]
        [string]$Branch,

        [Parameter(Mandatory)]
        [string]$Token
    )

    if ($PSCmdlet.ShouldProcess($WorkspaceName, "Connect Git ($Branch)")) {
        # Build provider-specific git credentials block
        $gitCredentials = if ($GitConfig.provider -eq 'AzureDevOps') {
            @{
                gitProviderType  = 'AzureDevOps'
                organizationName = $GitConfig.organisationName
                projectName      = $GitConfig.projectName
                repositoryName   = $GitConfig.repositoryName
                branchName       = $Branch
                directoryName    = $GitConfig.rootFolder
            }
        }
        else {
            @{
                gitProviderType = 'GitHub'
                ownerName       = $GitConfig.ownerName
                repositoryName  = $GitConfig.repositoryName
                branchName      = $Branch
                directoryName   = $GitConfig.rootFolder
            }
        }

        # POST /workspaces/{id}/git/connect
        Write-Verbose "Connecting workspace '$WorkspaceName' to Git branch '$Branch'..."
        try {
            _Invoke-FabricRestMethod -Method POST `
                -RelativeUri "workspaces/$WorkspaceId/git/connect" `
                -Body @{ gitProviderDetails = $gitCredentials } `
                -Token $Token | Out-Null
        }
        catch {
            if ($_ -match 'WorkspaceAlreadyConnectedToGit') {
                Write-Verbose "Workspace '$WorkspaceName' is already connected to Git. Skipping."
                return
            }
            throw
        }

        # POST /workspaces/{id}/git/initializeConnection
        Write-Verbose "Initialising Git connection for '$WorkspaceName'..."
        try {
            _Invoke-FabricRestMethod -Method POST `
                -RelativeUri "workspaces/$WorkspaceId/git/initializeConnection" `
                -Body @{ initializationStrategy = 'PreferWorkspace' } `
                -Token $Token | Out-Null
        }
        catch {
            if ($_ -match 'WorkspaceAlreadyConnectedToGit') {
                Write-Verbose "Git connection for '$WorkspaceName' already initialised. Skipping."
                return
            }
            throw
        }

        Write-Verbose "Git integration configured for '$WorkspaceName' (branch: $Branch)."
    }
}
