function _Get-FabricDeploymentIdentity {
    <#
    .SYNOPSIS
        Resolves the Entra object id and principal type of the identity running the deployment.
    .DESCRIPTION
        Mirrors the ZeroFailed.Deploy.Azure 'getDeploymentIdentity' pattern: reads the signed-in
        principal from Get-AzContext, then resolves its Entra object id:
          - Service principals / federated (ClientAssertion) identities via Get-AzADServicePrincipal
            -ApplicationId (Get-AzContext exposes the app/client id, not the object id Fabric needs).
          - Users via Get-AzADUser -UserPrincipalName, falling back to the object id embedded in the
            context's HomeAccountId for guest users.

        Works both in Azure DevOps (where the wrapper pipeline signs in as the service principal) and
        locally (signed-in user). Best-effort: returns $null with a warning if it cannot be resolved
        (e.g. Az.Resources unavailable or insufficient directory permissions).
    .OUTPUTS
        A hashtable with keys: Id (Entra object id), Type ('ServicePrincipal' or 'User'); or $null.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $account = (Get-AzContext -ErrorAction Stop).Account
    }
    catch {
        Write-Warning "Could not read the Az context to determine the deploying identity: $_"
        return $null
    }

    if (-not $account -or -not $account.Id) {
        Write-Warning "No signed-in Az account found; cannot determine the deploying identity."
        return $null
    }

    try {
        if ($account.Type -in @('ServicePrincipal', 'ClientAssertion')) {
            # Get-AzContext exposes the application (client) id for service principals; resolve the
            # service principal's object id, which is what Fabric role assignments require.
            $objectId = (Get-AzADServicePrincipal -ApplicationId $account.Id -ErrorAction Stop).Id
            if ($objectId) {
                return @{ Id = $objectId; Type = 'ServicePrincipal' }
            }
        }
        else {
            $objectId = (Get-AzADUser -UserPrincipalName $account.Id -ErrorAction SilentlyContinue).Id
            if (-not $objectId -and
                $account.ExtendedProperties -and
                $account.ExtendedProperties.ContainsKey('HomeAccountId')) {
                # HomeAccountId is "<objectId>.<tenantId>"; the leading segment is the object id.
                $objectId = $account.ExtendedProperties['HomeAccountId'].Split('.')[0]
            }
            if ($objectId) {
                return @{ Id = $objectId; Type = 'User' }
            }
        }
    }
    catch {
        Write-Warning "Failed to resolve the deploying identity's object id: $_"
        return $null
    }

    Write-Warning "Could not resolve the deploying identity's object id from the Az context."
    return $null
}
