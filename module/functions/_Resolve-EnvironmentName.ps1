function _Resolve-EnvironmentName {
    <#
    .SYNOPSIS
        Resolves a Fabric Spark Environment display name from the naming convention template.
    .DESCRIPTION
        Applies the config's environmentNameTemplate using codes exactly as defined in the config
        short-code maps. The default template is '{project}-{type} Env', which is deliberately
        environment-independent — the Dev/Test/Prod stage is not part of the environment name, since
        each stage's Spark Environment lives in its own workspace and there is no name clash.

        Supported tokens:
          {project} — the config project name
          {type}    — the workspace type short code (as used in workspace names)
          {workspace} — the full, stage-specific workspace name (for backward compatibility with the
                        legacy '{workspace} Env' template; requires -EnvironmentName)
    .PARAMETER Config
        The topology config object produced by New-FabricTopologyConfig.
    .PARAMETER WorkspaceId
        The workspace id (e.g. "bronze") from config.workspaces.
    .PARAMETER EnvironmentName
        The environment/stage name (e.g. "Dev") as defined in config.environments. Only used when
        the template contains the {workspace} token.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config,

        [Parameter(Mandatory)]
        [string]$WorkspaceId,

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

    $template = if ($nc.PSObject.Properties.Name -contains 'environmentNameTemplate' -and $nc.environmentNameTemplate) {
        $nc.environmentNameTemplate
    }
    else { '{project}-{type} Env' }

    $name = $template `
        -replace '\{project\}', $Config.project `
        -replace '\{type\}',    $typeCode

    # Backward compatibility: the legacy template used {workspace} (the full, stage-specific name).
    if ($name -match '\{workspace\}') {
        if (-not $EnvironmentName) {
            throw "Environment name template '$template' uses {workspace} but no -EnvironmentName was supplied."
        }
        $wsName = _Resolve-WorkspaceName -Config $Config -WorkspaceId $WorkspaceId -EnvironmentName $EnvironmentName
        $name = $name -replace '\{workspace\}', $wsName
    }

    # Validate — no unresolved tokens
    if ($name -match '\{[^}]+\}') {
        throw "Unresolved token in environment name: '$name'."
    }

    return $name.Trim()
}
