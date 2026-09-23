function _New-FabricWorkspaceRecord {
    <#
    .SYNOPSIS
        Creates the empty per-workspace record used by Invoke-FabricSetup and Get-FabricTopologyState.
    .DESCRIPTION
        Both the provisioning orchestrator and the read-only topology inspector build the same
        addressable "Workspaces" model (one record per workspace type x environment). This factory
        keeps that record schema in one place so the two functions cannot drift — the property set
        and order here define what WorkspacesByType.<type>.<environment> looks like.

        Callers add the record to their results list immediately, then enrich it in place:
          - Status  is set to Created / Existing / NotFound / Failed / WhatIf by the caller.
          - Identity / SparkEnvironment are replaced with a details object once resolved, or left $null.
          - GitConnected is set $true once a Git connection is confirmed.
    .PARAMETER Type
        The workspace type name (e.g. "Bronze") — config.workspaces[].type.
    .PARAMETER Environment
        The environment / stage name (e.g. "Dev") — config.environments[].name.
    .PARAMETER Name
        The resolved workspace display name from the naming convention.
    .PARAMETER CapacityName
        The Fabric capacity name for this environment (config.environments[].capacityName).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Type,

        [Parameter(Mandatory)]
        [string]$Environment,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$CapacityName
    )

    [pscustomobject]@{
        Type             = $Type
        Environment      = $Environment
        Name             = $Name
        WorkspaceId      = $null
        CapacityName     = $CapacityName
        Status           = 'Pending'
        GitConnected     = $false
        Identity         = $null
        SparkEnvironment = $null
    }
}
