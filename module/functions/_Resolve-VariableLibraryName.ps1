function _Resolve-VariableLibraryName {
    <#
    .SYNOPSIS
        Resolves a Fabric Variable Library display name, applying the default when none is configured.
    .DESCRIPTION
        Returns the configured name as-is, or 'VariableLibrary' when no name is configured (e.g. an
        older or hand-written config whose variableLibrary block has no name).

        The variable library name is deliberately the same in every environment (stage) — each stage's
        library lives in its own workspace, so there is no name clash, and a stable name lets items
        reference the library consistently as they are promoted between stages.

        The name is validated against Fabric's variable library naming rules: it must start with a
        letter, contain only letters, numbers, underscores, hyphens and spaces, and be no longer than
        256 characters.
    .PARAMETER Name
        The configured variable library name. Null or empty resolves to the default.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Name
    )

    $resolved = if ([string]::IsNullOrWhiteSpace($Name)) { 'VariableLibrary' } else { $Name.Trim() }

    # Validate against Fabric's variable library naming rules.
    if ($resolved -notmatch '^[A-Za-z][A-Za-z0-9_\- ]*$' -or $resolved.Length -gt 256) {
        throw "Variable library name '$resolved' is invalid. It must start with a letter, contain only letters, numbers, underscores, hyphens and spaces, and be no longer than 256 characters."
    }

    return $resolved
}
