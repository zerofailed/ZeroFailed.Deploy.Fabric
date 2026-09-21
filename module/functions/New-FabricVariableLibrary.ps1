function New-FabricVariableLibrary {
    <#
    .SYNOPSIS
        Creates a Fabric Variable Library idempotently (never modifies one that already exists).
    .DESCRIPTION
        Checks whether a variable library with the given display name already exists in the workspace
        and returns it unchanged if so — its variables, value sets and active value set are never
        overwritten or modified. Otherwise creates an empty variable library via the Fabric REST API
        (POST /workspaces/{id}/variableLibraries), returning the created object.

        An ItemDisplayNameAlreadyInUse (HTTP 409) conflict is treated idempotently: the existing
        variable library is resolved and returned.

        This provisions an empty library only — no definition is supplied, so no variables or value
        sets are populated.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID that will contain the variable library.
    .PARAMETER DisplayName
        The display name for the variable library.
    .PARAMETER Description
        Optional description for the variable library.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .EXAMPLE
        New-FabricVariableLibrary -WorkspaceId $ws.id -DisplayName 'SalesAnalytics-ETL Variables' -Token $token

        Creates the variable library in the workspace, or returns it unchanged if it already exists.
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

    # Idempotency check — resolve any existing variable library by display name and leave it untouched.
    $existing = _Resolve-FabricVariableLibrary -WorkspaceId $WorkspaceId -DisplayName $DisplayName -Token $Token
    if ($existing) {
        Write-Verbose "Variable library '$DisplayName' already exists (id: $($existing.id)). Leaving it unchanged."
        return $existing
    }

    if ($PSCmdlet.ShouldProcess($DisplayName, 'Create Fabric variable library')) {
        Write-Verbose "Creating variable library '$DisplayName' in workspace '$WorkspaceId'..."

        $body = @{ displayName = $DisplayName }
        if ($Description) { $body.description = $Description }

        try {
            $library = _Invoke-FabricRestMethod -Method POST `
                -RelativeUri "workspaces/$WorkspaceId/variableLibraries" `
                -Body        $body `
                -Token       $Token `
                -ErrorAction Stop

            # When creation runs as a long-running operation (HTTP 202), the response is the operation
            # state rather than the item, so resolve the created library by name.
            if (-not ($library -and $library.PSObject.Properties.Name -contains 'id')) {
                $library = _Resolve-FabricVariableLibrary -WorkspaceId $WorkspaceId -DisplayName $DisplayName -Token $Token
                if (-not $library) {
                    throw "Variable library '$DisplayName' could not be found after creation."
                }
            }

            Write-Verbose "Variable library '$DisplayName' created (id: $($library.id))."
            return $library
        }
        catch {
            # A 409 / name-in-use means the library already exists. Resolve and return it for
            # idempotency; if it cannot be resolved, surface the original error.
            if ("$_" -match 'AlreadyInUse' -or "$_" -match 'AlreadyExists' -or "$_" -match '\b409\b' -or "$_" -match 'Conflict') {
                Write-Verbose "Variable library '$DisplayName' already exists (per API conflict). Resolving existing variable library."
                $existing = _Resolve-FabricVariableLibrary -WorkspaceId $WorkspaceId -DisplayName $DisplayName -Token $Token
                if ($existing) {
                    return $existing
                }
            }
            throw "Failed to create variable library '$DisplayName': $_"
        }
    }
    else {
        return [pscustomobject]@{ id = 'whatif-id'; displayName = $DisplayName }
    }
}
