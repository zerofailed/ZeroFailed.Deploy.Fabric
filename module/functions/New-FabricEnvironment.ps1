function New-FabricEnvironment {
    <#
    .SYNOPSIS
        Creates a Fabric Spark Environment idempotently (skips creation if it already exists).
    .DESCRIPTION
        Checks whether an environment with the given display name already exists in the workspace
        and returns it if so. Otherwise creates it via the Fabric REST API
        (POST /workspaces/{id}/environments), returning the created object.

        An EnvironmentDisplayNameAlreadyInUse (HTTP 409) conflict is treated idempotently: the
        existing environment is resolved and returned.

        This provisions an empty environment only. Uploading libraries (.whl) and publishing are
        handled by a separate action — creating and referencing an empty environment does not
        require a publish.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID that will contain the environment.
    .PARAMETER DisplayName
        The display name for the environment.
    .PARAMETER Description
        Optional description for the environment.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .EXAMPLE
        New-FabricEnvironment -WorkspaceId $ws.id -DisplayName 'SalesAnalytics-ETL [DEV] Env' -Token $token

        Creates the environment in the workspace, or returns it if it already exists.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$DisplayName,

        [string]$Description,

        [Parameter(Mandatory)]
        [string]$Token
    )

    # Idempotency check — resolve any existing environment by display name.
    $existing = _Resolve-FabricEnvironment -WorkspaceId $WorkspaceId -DisplayName $DisplayName -Token $Token
    if ($existing) {
        Write-Verbose "Environment '$DisplayName' already exists (id: $($existing.id)). Skipping creation."
        return $existing
    }

    if ($PSCmdlet.ShouldProcess($DisplayName, 'Create Fabric environment')) {
        Write-Verbose "Creating environment '$DisplayName' in workspace '$WorkspaceId'..."

        $body = @{ displayName = $DisplayName }
        if ($Description) { $body.description = $Description }

        try {
            $environment = _Invoke-FabricRestMethod -Method POST `
                -RelativeUri "workspaces/$WorkspaceId/environments" `
                -Body        $body `
                -Token       $Token `
                -ErrorAction Stop

            Write-Verbose "Environment '$DisplayName' created (id: $($environment.id))."
            return $environment
        }
        catch {
            # A 409 / name-in-use means the environment already exists. Resolve and return it for
            # idempotency; if it cannot be resolved, surface the original error.
            if ("$_" -match 'AlreadyInUse' -or "$_" -match 'AlreadyExists' -or "$_" -match '\b409\b' -or "$_" -match 'Conflict') {
                Write-Verbose "Environment '$DisplayName' already exists (per API conflict). Resolving existing environment."
                $existing = _Resolve-FabricEnvironment -WorkspaceId $WorkspaceId -DisplayName $DisplayName -Token $Token
                if ($existing) {
                    return $existing
                }
            }
            throw "Failed to create environment '$DisplayName': $_"
        }
    }
    else {
        return [pscustomobject]@{ id = 'whatif-id'; displayName = $DisplayName }
    }
}
