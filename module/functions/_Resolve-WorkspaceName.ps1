function _Resolve-WorkspaceName {
    <#
    .SYNOPSIS
        Resolves a workspace name from the naming convention template.
    .DESCRIPTION
        Applies the naming template using codes exactly as defined in the config short-code maps.
        Casing is controlled by the map values — no automatic case transformation is applied.
        Truncates at MaxLength.
    .PARAMETER Config
        The topology config object produced by New-FabricTopologyConfig.
    .PARAMETER WorkspaceId
        The workspace id (e.g. "bronze") from config.workspaces.
    .PARAMETER EnvironmentName
        The full environment name (e.g. "Dev") as defined in config.environments.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config,

        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$EnvironmentName
    )

    $nc = $Config.namingConvention

    # Resolve workspace type short code
    $ws = $Config.workspaces | Where-Object { $_.id -eq $WorkspaceId }
    if (-not $ws) {
        throw "Workspace id '$WorkspaceId' not found in config."
    }
    $typeCode = $nc.typeShortCodes.($ws.type)
    if (-not $typeCode) {
        throw "No short code defined for workspace type '$($ws.type)'."
    }

    # Resolve environment short code
    $env = $Config.environments | Where-Object { $_.name -eq $EnvironmentName }
    if (-not $env) {
        throw "Environment '$EnvironmentName' not found in config."
    }

    # Apply template — codes used as-is; casing is defined in the short-code maps
    $name = $nc.template `
        -replace '\{project\}', $Config.project `
        -replace '\{type\}',    $typeCode `
        -replace '\{env\}',     $env.shortCode

    # Validate — no unresolved tokens
    if ($name -match '\{[^}]+\}') {
        throw "Unresolved token in workspace name: '$name'."
    }

    $name = $name.Trim()

    # Truncate
    $maxLen = $nc.maxLength
    if ($name.Length -gt $maxLen) {
        Write-Warning "Workspace name '$name' exceeds $maxLen chars and will be truncated."
        $name = $name.Substring(0, $maxLen).TrimEnd('-')
    }

    return $name
}
