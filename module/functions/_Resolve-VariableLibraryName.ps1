function _Resolve-VariableLibraryName {
    <#
    .SYNOPSIS
        Resolves a Fabric Variable Library display name from the naming convention template.
    .DESCRIPTION
        Applies the config's variableLibraryNameTemplate using codes exactly as defined in the config
        short-code maps. The default template is '{project}-{type} Variables'.

        The variable library name is deliberately the same in every environment (stage) — each stage's
        library lives in its own workspace, so there is no name clash, and a stable name lets items
        reference the library consistently as they are promoted between stages. Only the
        stage-independent tokens are therefore supported:
          {project} — the config project name
          {type}    — the workspace type short code (as used in workspace names)

        The resolved name is validated against Fabric's variable library naming rules: it must start
        with a letter, contain only letters, numbers, underscores, hyphens and spaces, and be no longer
        than 256 characters.
    .PARAMETER Config
        The topology config object produced by New-FabricTopologyConfig.
    .PARAMETER WorkspaceId
        The workspace id (e.g. "Bronze") from config.workspaces.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config,

        [Parameter(Mandatory)]
        [string]$WorkspaceId
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

    $template = if ($nc.PSObject.Properties.Name -contains 'variableLibraryNameTemplate' -and $nc.variableLibraryNameTemplate) {
        $nc.variableLibraryNameTemplate
    }
    else { '{project}-{type} Variables' }

    $name = ($template `
        -replace '\{project\}', $Config.project `
        -replace '\{type\}',    $typeCode).Trim()

    # Validate — no unresolved tokens. {env}/{workspace} are rejected here because the name must not vary by stage.
    if ($name -match '\{[^}]+\}') {
        throw "Unresolved token in variable library name '$name'. Only {project} and {type} are supported — the variable library name is the same in every environment."
    }

    # Validate against Fabric's variable library naming rules.
    if ($name -notmatch '^[A-Za-z][A-Za-z0-9_\- ]*$' -or $name.Length -gt 256) {
        throw "Variable library name '$name' is invalid. It must start with a letter, contain only letters, numbers, underscores, hyphens and spaces, and be no longer than 256 characters."
    }

    return $name
}
