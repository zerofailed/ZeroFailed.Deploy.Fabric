function _Resolve-ManagedPrivateEndpointName {
    <#
    .SYNOPSIS
        Resolves a managed private endpoint name from the naming convention template.
    .DESCRIPTION
        Applies the config's managedPrivateEndpointNameTemplate using codes exactly as defined in the
        config short-code maps. The default template is '{project}-{type}-{name}-{env}' — for example
        'SalesAnalytics-ETL-KeyVault-DEV'. Unlike a Spark Environment name, the stage is part of the
        name: each stage's endpoint targets that stage's resource, so the name says which one it is.

        Supported tokens:
          {project} — the config project name
          {type}    — the workspace type short code (as used in workspace names)
          {name}    — the endpoint's logical name from the topology (e.g. 'KeyVault')
          {env}     — the environment short code (as used in workspace names)

        Characters other than letters, digits, hyphens and underscores (such as the spaces a custom
        short code can contain) are replaced with hyphens.

        Throws rather than truncating a name longer than Fabric's 64-character limit: the name is how
        an existing endpoint is found on re-runs, so a shortened name could collide with another
        endpoint's.
    .PARAMETER Config
        The topology config object produced by New-FabricTopologyConfig.
    .PARAMETER WorkspaceId
        The workspace id (e.g. "bronze") from config.workspaces.
    .PARAMETER EnvironmentName
        The full environment name (e.g. "Dev") as defined in config.environments.
    .PARAMETER EndpointName
        The endpoint's logical name from the topology config (e.g. "KeyVault").
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config,

        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$EnvironmentName,

        [Parameter(Mandatory)]
        [string]$EndpointName
    )

    $maxLength = 64
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

    # Configs generated before managed private endpoints were supported have no template.
    $template = if ($nc.PSObject.Properties.Name -contains 'managedPrivateEndpointNameTemplate' -and $nc.managedPrivateEndpointNameTemplate) {
        $nc.managedPrivateEndpointNameTemplate
    }
    else { '{project}-{type}-{name}-{env}' }

    $name = $template `
        -replace '\{project\}', $Config.project `
        -replace '\{type\}',    $typeCode `
        -replace '\{name\}',    $EndpointName `
        -replace '\{env\}',     $env.shortCode

    # Validate — no unresolved tokens (checked before the character clean-up removes the braces)
    if ($name -match '\{[^}]+\}') {
        throw "Unresolved token in managed private endpoint name: '$name'."
    }

    $name = ($name -replace '[^A-Za-z0-9_-]', '-' -replace '-{2,}', '-').Trim('-')

    if ($name.Length -gt $maxLength) {
        throw "Managed private endpoint name '$name' is $($name.Length) characters, over Fabric's $maxLength-character limit. Shorten the endpoint's Name, the short codes, or the managedPrivateEndpointNameTemplate."
    }

    return $name
}
