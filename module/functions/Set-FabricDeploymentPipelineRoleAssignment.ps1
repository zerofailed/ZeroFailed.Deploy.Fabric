function Set-FabricDeploymentPipelineRoleAssignment {
    <#
    .SYNOPSIS
        Applies a single role assignment to a Fabric deployment pipeline idempotently.
    .DESCRIPTION
        Checks the current role assignments on a deployment pipeline, then:
          - Skips if the principal already holds the role (idempotent)
          - Creates the assignment via POST if the principal has no current assignment
        Supports Entra Group, User, and Service Principal object IDs.

        Fabric deployment pipelines only support the 'Admin' role, so an existing principal
        already holds the only available role and the assignment is skipped.
    .PARAMETER PipelineId
        The Fabric deployment pipeline GUID.
    .PARAMETER PipelineName
        Display name used in log messages and the returned report entry.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .PARAMETER PrincipalId
        The Entra object ID of the group, user, or service principal to assign.
    .PARAMETER PrincipalType
        The type of principal: Group, User, or ServicePrincipal.
    .PARAMETER Role
        The deployment pipeline role to assign. Only 'Admin' is supported. Defaults to 'Admin'.
    .EXAMPLE
        Set-FabricDeploymentPipelineRoleAssignment -PipelineId $pipe.id -PipelineName 'SalesAnalytics-Bronze Pipeline' -PrincipalId $groupId -PrincipalType 'Group' -Token $token

        Ensures the given Entra group holds the Admin role on the deployment pipeline, applying the change idempotently.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$PipelineId,

        [Parameter(Mandatory)]
        [string]$PipelineName,

        [Parameter(Mandatory)]
        [string]$Token,

        [Parameter(Mandatory)]
        [string]$PrincipalId,

        [Parameter(Mandatory)]
        [ValidateSet('Group', 'User', 'ServicePrincipal')]
        [string]$PrincipalType,

        [ValidateSet('Admin')]
        [string]$Role = 'Admin'
    )

    if ($PSCmdlet.ShouldProcess("$PipelineName ($PrincipalId)", "Assign role '$Role'")) {
        Write-Debug "Fetching role assignments for deployment pipeline '$PipelineName' ($PipelineId)..."

        $response = _Invoke-FabricRestMethod -Method GET `
            -RelativeUri "deploymentPipelines/$PipelineId/roleAssignments" `
            -Token $Token `
            -ErrorAction Stop

        $existing = $response.value | Where-Object { $_.principal.id -eq $PrincipalId }

        $action = $null

        if ($existing) {
            Write-Verbose "Principal '$PrincipalId' already has role '$Role' on deployment pipeline '$PipelineName'. Skipping."
            $action = 'Skipped'
        }
        else {
            Write-Verbose "Assigning role '$Role' to principal '$PrincipalId' ($PrincipalType) on deployment pipeline '$PipelineName'..."
            _Invoke-FabricRestMethod -Method POST `
                -RelativeUri "deploymentPipelines/$PipelineId/roleAssignments" `
                -Body @{
                    principal = @{ id = $PrincipalId; type = $PrincipalType }
                    role      = $Role
                } `
                -Token $Token `
                -ErrorAction Stop | Out-Null
            Write-Verbose "Role '$Role' assigned to principal '$PrincipalId' on deployment pipeline '$PipelineName'."
            $action = 'Created'
        }

        return @{
            PipelineName  = $PipelineName
            PipelineId    = $PipelineId
            PrincipalId   = $PrincipalId
            PrincipalType = $PrincipalType
            Role          = $Role
            Action        = $action
        }
    }
    else {
        return @{
            PipelineName  = $PipelineName
            PipelineId    = $PipelineId
            PrincipalId   = $PrincipalId
            PrincipalType = $PrincipalType
            Role          = $Role
            Action        = 'WhatIf'
        }
    }
}
