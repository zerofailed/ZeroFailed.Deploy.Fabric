function New-FabricWorkspace {
    <#
    .SYNOPSIS
        Creates a Fabric workspace idempotently (skips creation if it already exists).
    .DESCRIPTION
        Checks whether a workspace with the given display name already exists and returns it if so.
        Otherwise resolves the capacity by name and creates the workspace via the Fabric REST API
        (POST /workspaces), returning the created object.

        Uses the module's own bearer-token REST path (not MicrosoftFabricMgmt) for a consistent
        identity, clean error propagation, and StrictMode safety. A WorkspaceNameAlreadyExists
        (HTTP 409) conflict is treated idempotently: the existing workspace is resolved and returned.
    .PARAMETER DisplayName
        The display name for the workspace.
    .PARAMETER CapacityName
        The Fabric capacity to assign to the workspace.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .EXAMPLE
        New-FabricWorkspace -DisplayName 'SalesAnalytics-ETL [DEV]' -CapacityName 'cap-dev' -Token $token

        Creates the workspace on the cap-dev capacity, or returns it if it already exists.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string]$CapacityName,

        [Parameter(Mandatory)]
        [string]$Token
    )

    # Idempotency check
    $existing = Test-FabricWorkspaceExists -DisplayName $DisplayName -Token $Token
    if ($existing) {
        Write-Verbose "Workspace '$DisplayName' already exists (id: $($existing.id)). Skipping creation."
        return $existing
    }

    if ($PSCmdlet.ShouldProcess($DisplayName, 'Create Fabric workspace')) {
        Write-Verbose "Creating workspace '$DisplayName' on capacity '$CapacityName'..."

        # Resolve the capacity id by display name (paginated, StrictMode-safe).
        $capacityId = $null
        $nextUri    = 'capacities'
        do {
            $page = _Invoke-FabricRestMethod -Method GET -RelativeUri $nextUri -Token $Token -ErrorAction Stop
            $cap  = $page.value | Where-Object { $_.displayName -eq $CapacityName } | Select-Object -First 1
            if ($cap) {
                $capacityId = $cap.id
                break
            }
            $continuationToken = if ($page.PSObject.Properties.Name -contains 'continuationToken') { $page.continuationToken } else { $null }
            $nextUri = if ($continuationToken) { "capacities?continuationToken=$continuationToken" } else { $null }
        } while ($nextUri)

        if (-not $capacityId) {
            throw "Capacity '$CapacityName' not found."
        }

        try {
            $workspace = _Invoke-FabricRestMethod -Method POST `
                -RelativeUri 'workspaces' `
                -Body        @{ displayName = $DisplayName; capacityId = $capacityId } `
                -Token       $Token `
                -ErrorAction Stop

            Write-Verbose "Workspace '$DisplayName' created (id: $($workspace.id))."
            return $workspace
        }
        catch {
            # A 409 / WorkspaceNameAlreadyExists means the workspace already exists. Resolve and
            # return it for idempotency. If it cannot be resolved, the deploying identity can see
            # the name is taken but not the workspace itself — surface that clearly.
            if ("$_" -match 'WorkspaceNameAlreadyExists' -or "$_" -match '\b409\b' -or "$_" -match 'Conflict') {
                Write-Verbose "Workspace '$DisplayName' already exists (per API conflict). Resolving existing workspace."
                $existing = Test-FabricWorkspaceExists -DisplayName $DisplayName -Token $Token
                if ($existing) {
                    return $existing
                }
                throw "Workspace '$DisplayName' already exists but is not visible to the deploying identity. Ensure the service principal/user running the deployment is an Admin or Member of the existing workspace so it is returned by 'GET /workspaces'."
            }
            throw "Failed to create workspace '$DisplayName': $_"
        }
    }
    else {
        return [pscustomobject]@{ id = 'whatif-id'; displayName = $DisplayName }
    }
}
