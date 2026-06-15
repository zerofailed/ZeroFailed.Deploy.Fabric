function New-FabricWorkspace {
    <#
    .SYNOPSIS
        Creates a Fabric workspace idempotently (skips creation if it already exists).
    .DESCRIPTION
        Checks whether a workspace with the given display name already exists and returns it if so.
        Otherwise creates a new workspace on the specified capacity and returns the created object.
    .PARAMETER DisplayName
        The display name for the workspace.
    .PARAMETER CapacityName
        The Fabric capacity to assign to the workspace.
    .PARAMETER Token
        Bearer token string for the Fabric REST API, used for the idempotency lookup.
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

        try {
            $capacity = MicrosoftFabricMgmt\Get-FabricCapacity -CapacityName $CapacityName -ErrorAction Stop
            if (-not $capacity) {
                throw "Capacity '$CapacityName' not found."
            }

            $workspace = MicrosoftFabricMgmt\New-FabricWorkspace `
                -WorkspaceName $DisplayName `
                -CapacityId    $capacity.id `
                -ErrorAction Stop

            Write-Verbose "Workspace '$DisplayName' created (id: $($workspace.id))."
            return $workspace
        }
        catch {
            # Tolerate the case where the workspace already exists (idempotency guarantee even if
            # the pre-flight lookup missed it). Fabric returns HTTP 409 / WorkspaceNameAlreadyExists.
            if ("$_" -match 'WorkspaceNameAlreadyExists' -or "$_" -match '\b409\b' -or "$_" -match 'Conflict') {
                Write-Verbose "Workspace '$DisplayName' already exists (per API conflict). Resolving existing workspace."
                $existing = Test-FabricWorkspaceExists -DisplayName $DisplayName -Token $Token
                if ($existing) {
                    return $existing
                }
            }
            throw "Failed to create workspace '$DisplayName': $_"
        }
    }
    else {
        return [pscustomobject]@{ id = 'whatif-id'; displayName = $DisplayName }
    }
}
