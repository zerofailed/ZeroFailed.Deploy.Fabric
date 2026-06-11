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
    .EXAMPLE
        New-FabricWorkspace -DisplayName 'SalesAnalytics-ETL [DEV]' -CapacityName 'cap-dev'

        Creates the workspace on the cap-dev capacity, or returns it if it already exists.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string]$CapacityName
    )

    # Idempotency check
    $existing = Test-FabricWorkspaceExists -DisplayName $DisplayName
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
            throw "Failed to create workspace '$DisplayName': $_"
        }
    }
    else {
        return [pscustomobject]@{ id = 'whatif-id'; displayName = $DisplayName }
    }
}
