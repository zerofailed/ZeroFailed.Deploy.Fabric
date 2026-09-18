function Set-FabricVariableLibraryValues {
    <#
    .SYNOPSIS
        Sets variables and a stage value set on a Fabric Variable Library, preserving everything else.
    .DESCRIPTION
        Merges the given variables into an existing variable library:
          1. Each variable is added as a String variable if missing. Its default value (the library's
             default value set) is always -DefaultValue — a placeholder, never a real value.
          2. The value set named -ValueSetName is created if missing, and its overrides for the given
             variables are set to the supplied values.
          3. That value set is made the library's active value set.

        All other variables, value sets and overrides are left unchanged. The definition is read with
        getDefinition and written back in full with updateDefinition (which replaces the whole
        definition) — and only when something has changed. Parts that are not modified are written
        back byte-for-byte. The active value set is only updated when it differs.
    .PARAMETER WorkspaceId
        The Fabric workspace GUID containing the variable library.
    .PARAMETER WorkspaceName
        Display name used in log messages and the returned report entry.
    .PARAMETER VariableLibraryId
        The variable library GUID.
    .PARAMETER VariableLibraryName
        Display name used in log messages and the returned report entry.
    .PARAMETER ValueSetName
        Name of the value set to create/update and activate, e.g. the stage short code 'DEV'.
    .PARAMETER Values
        Dictionary of variable name to value, set as overrides in the value set.
    .PARAMETER DefaultValue
        Default value (default value set) for each variable. Default: 'PLACEHOLDER - NO VALUE SET ACTIVE'.
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .EXAMPLE
        Set-FabricVariableLibraryValues -WorkspaceId $ws.id -WorkspaceName 'SalesAnalytics-ETL [DEV]' `
            -VariableLibraryId $library.id -VariableLibraryName 'DefaultVariableLibrary' `
            -ValueSetName 'DEV' -Values ([ordered]@{ workspace_id = $ws.id }) -Token $token

        Adds workspace_id (default value: the placeholder), sets it to the workspace id in the DEV
        value set, and activates the DEV value set.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceId,

        [Parameter(Mandatory)]
        [string]$WorkspaceName,

        [Parameter(Mandatory)]
        [string]$VariableLibraryId,

        [Parameter(Mandatory)]
        [string]$VariableLibraryName,

        [Parameter(Mandatory)]
        [string]$ValueSetName,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Values,

        [string]$DefaultValue = 'PLACEHOLDER - NO VALUE SET ACTIVE',

        [Parameter(Mandatory)]
        [string]$Token
    )

    $report = @{
        WorkspaceName        = $WorkspaceName
        WorkspaceId          = $WorkspaceId
        VariableLibraryName  = $VariableLibraryName
        ValueSetName         = $ValueSetName
        Variables            = @($Values.Keys)
        DefinitionAction     = 'WhatIf'
        ActiveValueSetAction = 'WhatIf'
    }

    if (-not $PSCmdlet.ShouldProcess("$VariableLibraryName ($WorkspaceName)", "Set variables and activate value set '$ValueSetName'")) {
        return $report
    }

    $libraryUri = "workspaces/$WorkspaceId/variableLibraries/$VariableLibraryId"

    # --- Read the current definition ---
    $response = _Invoke-FabricRestMethod -Method POST -RelativeUri "$libraryUri/getDefinition" -Token $Token -ReturnLroResult -ErrorAction Stop
    $definition = if ($response -and $response.PSObject.Properties.Name -contains 'definition') { $response.definition } else { $null }
    $existingParts = if ($definition -and $definition.PSObject.Properties.Name -contains 'parts') { @($definition.parts) } else { @() }

    # Keep date strings as strings when decoding (PowerShell 7.5+), so DateTime variable values are
    # not reformatted if their part is rewritten.
    $fromJsonParams = @{ AsHashtable = $true }
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $fromJsonParams.DateKind = 'String' }

    # Only variables.json and value sets are decoded; only parts marked Modified are re-encoded, so
    # everything else is written back byte-for-byte. The optional .platform part is dropped —
    # metadata is not being updated (no updateMetadata).
    $parts = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($part in $existingParts) {
        if ($part.path -eq '.platform') { continue }
        $content = if ($part.path -eq 'variables.json' -or $part.path -match '^valueSets?/') {
            [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part.payload)) | ConvertFrom-Json @fromJsonParams
        }
        else { $null }
        $parts.Add(@{ Path = $part.path; Payload = $part.payload; Content = $content; Modified = $false })
    }

    # --- variables.json: ensure each variable exists as a String with the placeholder default ---
    $variablesPart = $parts | Where-Object { $_.Path -eq 'variables.json' } | Select-Object -First 1
    if (-not $variablesPart) {
        $variablesPart = @{
            Path     = 'variables.json'
            Modified = $true
            Content  = [ordered]@{
                '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/variableLibrary/definition/variables/1.0.0/schema.json'
                variables = @()
            }
        }
        $parts.Add($variablesPart)
    }
    $variables = [System.Collections.Generic.List[object]]::new()
    foreach ($variable in @($variablesPart.Content.variables)) { if ($variable) { $variables.Add($variable) } }

    foreach ($name in $Values.Keys) {
        $variable = $variables | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if (-not $variable) {
            $variables.Add([ordered]@{ name = $name; type = 'String'; value = $DefaultValue })
            $variablesPart.Modified = $true
        }
        elseif ($variable.type -ne 'String' -or $variable.value -cne $DefaultValue) {
            $variable.type  = 'String'
            $variable.value = $DefaultValue
            $variablesPart.Modified = $true
        }
    }
    $variablesPart.Content.variables = $variables.ToArray()

    # --- valueSets/<name>.json: ensure the value set exists and overrides each variable ---
    $valueSetPart = $parts |
        Where-Object { $_.Path -match '^valueSets?/' -and $_.Content -and $_.Content.name -eq $ValueSetName } |
        Select-Object -First 1
    if (-not $valueSetPart) {
        $valueSetPart = @{
            Path     = "valueSets/$ValueSetName.json"
            Modified = $true
            Content  = [ordered]@{
                '$schema'         = 'https://developer.microsoft.com/json-schemas/fabric/item/variableLibrary/definition/valueSet/1.0.0/schema.json'
                name              = $ValueSetName
                variableOverrides = @()
            }
        }
        $parts.Add($valueSetPart)
        Write-Verbose "Value set '$ValueSetName' does not exist in '$VariableLibraryName' — creating it."
    }
    $overrides = [System.Collections.Generic.List[object]]::new()
    $existingOverrides = if ($valueSetPart.Content.Contains('variableOverrides')) { @($valueSetPart.Content.variableOverrides) } else { @() }
    foreach ($override in $existingOverrides) { if ($override) { $overrides.Add($override) } }

    foreach ($name in $Values.Keys) {
        $value    = [string]$Values[$name]
        $override = $overrides | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if (-not $override) {
            $overrides.Add([ordered]@{ name = $name; value = $value })
            $valueSetPart.Modified = $true
        }
        elseif ($override.value -cne $value) {
            $override.value = $value
            $valueSetPart.Modified = $true
        }
    }
    $valueSetPart.Content.variableOverrides = $overrides.ToArray()

    # --- settings.json is a required part; add an empty one if missing (Fabric orders value sets) ---
    if (-not ($parts | Where-Object { $_.Path -eq 'settings.json' })) {
        $parts.Add(@{
            Path     = 'settings.json'
            Modified = $true
            Content  = [ordered]@{
                '$schema'      = 'https://developer.microsoft.com/json-schemas/fabric/item/variableLibrary/definition/settings/1.0.0/schema.json'
                valueSetsOrder = @()
            }
        })
    }

    # --- Write the definition back (in full) only when something changed ---
    if ($parts | Where-Object { $_.Modified }) {
        Write-Verbose "Updating the definition of variable library '$VariableLibraryName' in '$WorkspaceName'..."
        $body = @{
            definition = @{
                parts = @(
                    foreach ($part in $parts) {
                        $payload = if ($part.Modified) {
                            [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($part.Content | ConvertTo-Json -Depth 20)))
                        }
                        else { $part.Payload }
                        @{ path = $part.Path; payload = $payload; payloadType = 'InlineBase64' }
                    }
                )
            }
        }
        _Invoke-FabricRestMethod -Method POST -RelativeUri "$libraryUri/updateDefinition" -Body $body -Token $Token -ErrorAction Stop | Out-Null
        $report.DefinitionAction = 'Updated'
    }
    else {
        Write-Verbose "Variables and value set '$ValueSetName' in '$VariableLibraryName' are already up to date."
        $report.DefinitionAction = 'Skipped'
    }

    # --- Activate the value set ---
    $library    = _Invoke-FabricRestMethod -Method GET -RelativeUri $libraryUri -Token $Token -ErrorAction Stop
    $properties = if ($library.PSObject.Properties.Name -contains 'properties') { $library.properties } else { $null }
    $activeName = if ($properties -and $properties.PSObject.Properties.Name -contains 'activeValueSetName') { $properties.activeValueSetName } else { $null }

    if ($activeName -eq $ValueSetName) {
        $report.ActiveValueSetAction = 'Skipped'
    }
    else {
        Write-Verbose "Activating value set '$ValueSetName' on '$VariableLibraryName' (was: '$activeName')..."
        _Invoke-FabricRestMethod -Method PATCH -RelativeUri $libraryUri `
            -Body        @{ properties = @{ activeValueSetName = $ValueSetName } } `
            -Token       $Token `
            -ErrorAction Stop | Out-Null
        $report.ActiveValueSetAction = 'Set'
    }

    return $report
}
