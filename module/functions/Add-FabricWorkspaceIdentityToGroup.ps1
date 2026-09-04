function Add-FabricWorkspaceIdentityToGroup {
    <#
    .SYNOPSIS
        Adds a Fabric Workspace Identity to an existing Entra security group, idempotently.
    .DESCRIPTION
        Ensures the workspace identity's service principal is a member of a known, existing Entra
        security group — the group used to grant workspace identities their shared downstream
        access (for example, source data that Fabric shortcuts read using the identity).

        Idempotent: the group's current membership is checked first, so an identity that is already
        a member is reported as 'Skipped' rather than re-added. An "already exists" response from
        Entra is also treated as 'Skipped', so concurrent runs do not fail each other.

        Uses the Az.Resources Entra cmdlets (as _Get-FabricDeploymentIdentity does) rather than
        calling Microsoft Graph directly, so the signed-in Az context supplies the credentials and
        no second token has to be managed alongside the Fabric one.

        The group is never created — it must already exist. The caller needs directory permissions
        to read and modify the group's membership (for example Group Owner, or a directory role
        such as Groups Administrator).
    .PARAMETER ServicePrincipalObjectId
        The Entra object ID of the workspace identity's service principal, as returned by
        Enable-FabricWorkspaceIdentity.
    .PARAMETER GroupId
        The Entra object ID of the existing security group to add the identity to.
    .PARAMETER WorkspaceName
        Display name used in log messages and the returned report entry.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID, recorded on the returned report entry.
    .EXAMPLE
        Add-FabricWorkspaceIdentityToGroup -ServicePrincipalObjectId $identity.ServicePrincipalObjectId -GroupId $groupId -WorkspaceName 'SalesAnalytics-ETL [DEV]' -WorkspaceId $ws.id

        Ensures the workspace identity is a member of the given security group.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ServicePrincipalObjectId,

        [Parameter(Mandatory)]
        [string]$GroupId,

        [Parameter(Mandatory)]
        [string]$WorkspaceName,

        [Parameter(Mandatory)]
        [string]$WorkspaceId
    )

    if ($PSCmdlet.ShouldProcess("$WorkspaceName ($ServicePrincipalObjectId)", "Add workspace identity to group '$GroupId'")) {
        Write-Debug "Checking membership of group '$GroupId' for principal '$ServicePrincipalObjectId'..."

        $existing = Get-AzADGroupMember -GroupObjectId $GroupId -ErrorAction Stop |
            Where-Object { $_.Id -eq $ServicePrincipalObjectId } |
            Select-Object -First 1

        $action = $null

        if ($existing) {
            Write-Verbose "Workspace identity for '$WorkspaceName' is already a member of group '$GroupId'. Skipping."
            $action = 'Skipped'
        }
        else {
            Write-Verbose "Adding the workspace identity for '$WorkspaceName' to group '$GroupId'..."
            try {
                Add-AzADGroupMember -TargetGroupObjectId $GroupId -MemberObjectId $ServicePrincipalObjectId -ErrorAction Stop | Out-Null
                Write-Verbose "Workspace identity for '$WorkspaceName' added to group '$GroupId'."
                $action = 'Added'
            }
            catch {
                # A concurrent run may have added the identity between the check above and this
                # call. Entra reports that as a bad request naming the existing reference, which
                # is the outcome we wanted — treat it as a no-op rather than a failure.
                if ($_.Exception.Message -match 'already exist') {
                    Write-Verbose "Workspace identity for '$WorkspaceName' was already added to group '$GroupId' concurrently. Skipping."
                    $action = 'Skipped'
                }
                else {
                    throw
                }
            }
        }

        return @{
            WorkspaceName            = $WorkspaceName
            WorkspaceId              = $WorkspaceId
            ServicePrincipalObjectId = $ServicePrincipalObjectId
            GroupId                  = $GroupId
            Action                   = $action
        }
    }
    else {
        return @{
            WorkspaceName            = $WorkspaceName
            WorkspaceId              = $WorkspaceId
            ServicePrincipalObjectId = $ServicePrincipalObjectId
            GroupId                  = $GroupId
            Action                   = 'WhatIf'
        }
    }
}
