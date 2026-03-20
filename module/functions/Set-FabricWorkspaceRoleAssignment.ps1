function Set-FabricWorkspaceRoleAssignment {
    <#
    .SYNOPSIS
        Applies a single RBAC role assignment to a Fabric workspace idempotently.
    .DESCRIPTION
        Checks the current role assignments on a workspace, then:
          - Skips if the principal already holds the target role (idempotent)
          - Updates the role via PATCH if the principal exists with a different role
          - Creates the assignment via POST if the principal has no current assignment
        Supports Entra Group, User, and Service Principal object IDs.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID.
    .PARAMETER WorkspaceName
        Display name used in log messages and the returned report entry.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .PARAMETER PrincipalId
        The Entra object ID of the group, user, or service principal to assign.
    .PARAMETER PrincipalType
        The type of principal: Group, User, or ServicePrincipal.
    .PARAMETER Role
        The workspace role to assign: Admin, Contributor, Member, or Viewer.
    .OUTPUTS
        Hashtable: WorkspaceName, WorkspaceId, PrincipalId, PrincipalType, Role, Action.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$WorkspaceName,

        [Parameter(Mandatory)]
        [string]$Token,

        [Parameter(Mandatory)]
        [string]$PrincipalId,

        [Parameter(Mandatory)]
        [ValidateSet('Group', 'User', 'ServicePrincipal')]
        [string]$PrincipalType,

        [Parameter(Mandatory)]
        [ValidateSet('Admin', 'Contributor', 'Member', 'Viewer')]
        [string]$Role
    )

    if ($PSCmdlet.ShouldProcess("$WorkspaceName ($PrincipalId)", "Assign role '$Role'")) {
        Write-Debug "Fetching role assignments for workspace '$WorkspaceName' ($WorkspaceId)..."

        $response = _Invoke-FabricRestMethod -Method GET `
            -RelativeUri "workspaces/$WorkspaceId/roleAssignments" `
            -Token $Token `
            -ErrorAction Stop

        $existing = $response.value | Where-Object { $_.principal.id -eq $PrincipalId }

        $action = $null

        if ($existing) {
            if ($existing.role -eq $Role) {
                Write-Verbose "Principal '$PrincipalId' already has role '$Role' on workspace '$WorkspaceName'. Skipping."
                $action = 'Skipped'
            }
            else {
                Write-Verbose "Principal '$PrincipalId' has role '$($existing.role)' — updating to '$Role' on workspace '$WorkspaceName'..."
                _Invoke-FabricRestMethod -Method PATCH `
                    -RelativeUri "workspaces/$WorkspaceId/roleAssignments/$($existing.id)" `
                    -Body @{ role = $Role } `
                    -Token $Token `
                    -ErrorAction Stop | Out-Null
                Write-Verbose "Role updated to '$Role' for principal '$PrincipalId' on workspace '$WorkspaceName'."
                $action = 'Updated'
            }
        }
        else {
            Write-Verbose "Assigning role '$Role' to principal '$PrincipalId' ($PrincipalType) on workspace '$WorkspaceName'..."
            _Invoke-FabricRestMethod -Method POST `
                -RelativeUri "workspaces/$WorkspaceId/roleAssignments" `
                -Body @{
                    principal = @{ id = $PrincipalId; type = $PrincipalType }
                    role      = $Role
                } `
                -Token $Token `
                -ErrorAction Stop | Out-Null
            Write-Verbose "Role '$Role' assigned to principal '$PrincipalId' on workspace '$WorkspaceName'."
            $action = 'Created'
        }

        return @{
            WorkspaceName = $WorkspaceName
            WorkspaceId   = $WorkspaceId
            PrincipalId   = $PrincipalId
            PrincipalType = $PrincipalType
            Role          = $Role
            Action        = $action
        }
    }
    else {
        return @{
            WorkspaceName = $WorkspaceName
            WorkspaceId   = $WorkspaceId
            PrincipalId   = $PrincipalId
            PrincipalType = $PrincipalType
            Role          = $Role
            Action        = 'WhatIf'
        }
    }
}
