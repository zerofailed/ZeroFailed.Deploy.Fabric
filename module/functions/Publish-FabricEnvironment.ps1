function Publish-FabricEnvironment {
    <#
    .SYNOPSIS
        Publishes a Fabric environment's staging changes, waiting for the long-running operation.
    .DESCRIPTION
        Promotes the environment's staging state (uploaded libraries, settings) to published via
        POST /workspaces/{id}/environments/{id}/staging/publish. Publishing is a long-running
        operation (HTTP 202) that typically takes several minutes; the default timeout is raised
        accordingly.

        Idempotent: if the API reports there are no pending staging changes to publish, this is
        treated as success (there is nothing to do), so re-runs after an unchanged deployment do
        not fail.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID that contains the environment.
    .PARAMETER EnvironmentId
        The Fabric environment GUID to publish.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .PARAMETER TimeoutSeconds
        Maximum seconds to wait for the publish LRO to complete. Default: 600.
    .EXAMPLE
        Publish-FabricEnvironment -WorkspaceId $ws.id -EnvironmentId $env.id -Token $token

        Publishes the environment and blocks until the operation completes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$EnvironmentId,

        [Parameter(Mandatory)]
        [string]$Token,

        [int]$TimeoutSeconds = 600
    )

    if ($PSCmdlet.ShouldProcess($EnvironmentId, 'Publish Fabric environment')) {
        Write-Verbose "Publishing environment '$EnvironmentId' (timeout ${TimeoutSeconds}s)..."

        try {
            _Invoke-FabricRestMethod -Method POST `
                -RelativeUri    "workspaces/$WorkspaceId/environments/$EnvironmentId/staging/publish" `
                -Token          $Token `
                -TimeoutSeconds $TimeoutSeconds `
                -ErrorAction    Stop | Out-Null

            return @{
                EnvironmentId = $EnvironmentId
                Action        = 'Published'
            }
        }
        catch {
            # No pending staging changes is not an error — the environment is already up to date.
            if ("$_" -match 'NoStagingChanges' -or "$_" -match 'no changes' -or "$_" -match 'nothing to publish' -or "$_" -match 'no pending') {
                Write-Verbose "Environment '$EnvironmentId' has no pending staging changes. Skipping publish."
                return @{
                    EnvironmentId = $EnvironmentId
                    Action        = 'Skipped'
                }
            }
            throw "Failed to publish environment '$EnvironmentId': $_"
        }
    }
    else {
        return @{
            EnvironmentId = $EnvironmentId
            Action        = 'whatif'
        }
    }
}
