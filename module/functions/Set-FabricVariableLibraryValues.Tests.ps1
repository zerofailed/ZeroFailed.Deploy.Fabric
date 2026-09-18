#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    $script:placeholder = 'PLACEHOLDER - NO VALUE SET ACTIVE'

    # Builds a getDefinition response from a map of part path -> JSON text.
    function New-DefinitionResponse([System.Collections.IDictionary]$Parts) {
        [pscustomobject]@{
            definition = [pscustomobject]@{
                parts = @(
                    foreach ($path in $Parts.Keys) {
                        [pscustomobject]@{
                            path        = $path
                            payload     = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Parts[$path]))
                            payloadType = 'InlineBase64'
                        }
                    }
                )
            }
        }
    }

    # Decodes the parts of an updateDefinition request body into a map of path -> parsed JSON.
    function Get-SentParts($Body) {
        $map = @{}
        foreach ($part in $Body.definition.parts) {
            $map[$part.path] = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part.payload)) | ConvertFrom-Json
        }
        $map
    }

    function Get-SentPayloads($Body) {
        $map = @{}
        foreach ($part in $Body.definition.parts) { $map[$part.path] = $part.payload }
        $map
    }

    # Registers the REST mock: getDefinition returns $Definition, GET returns the library with
    # $ActiveValueSet, and updateDefinition/PATCH bodies are captured into $script:sent.
    function Register-RestMock($Definition, $ActiveValueSet) {
        $script:definitionResponse = $Definition
        $script:activeValueSet     = $ActiveValueSet
        $script:sent               = @{}
        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri, $Body)
            if ($RelativeUri -like '*/getDefinition')    { return $script:definitionResponse }
            if ($RelativeUri -like '*/updateDefinition') { $script:sent.update = $Body; return $null }
            if ($Method -eq 'GET') {
                return [pscustomobject]@{ id = 'vl-1'; properties = [pscustomobject]@{ activeValueSetName = $script:activeValueSet } }
            }
            if ($Method -eq 'PATCH') { $script:sent.patch = $Body; return $null }
        } -ModuleName ZeroFailed.Deploy.Fabric
    }

    $script:params = @{
        WorkspaceId         = 'ws-1'
        WorkspaceName       = 'sales-Bronze [DEV]'
        VariableLibraryId   = 'vl-1'
        VariableLibraryName = 'DefaultVariableLibrary'
        ValueSetName        = 'DEV'
        Values              = [ordered]@{ workspace_name = 'sales-Bronze [DEV]'; workspace_id = 'ws-1' }
        Token               = 'tok'
    }
}

Describe 'Set-FabricVariableLibraryValues' {

    It 'makes no API calls under -WhatIf' {
        Register-RestMock (New-DefinitionResponse @{}) $null
        $result = Set-FabricVariableLibraryValues @script:params -WhatIf

        $result.DefinitionAction     | Should -Be 'WhatIf'
        $result.ActiveValueSetAction | Should -Be 'WhatIf'
        Should -Invoke _Invoke-FabricRestMethod -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'populates an empty library: placeholder defaults, a new stage value set, and activates it' {
        Register-RestMock (New-DefinitionResponse ([ordered]@{
            'variables.json' = '{"variables":[]}'
            'settings.json'  = '{"valueSetsOrder":[]}'
            '.platform'      = '{"metadata":{}}'
        })) $null

        $result = Set-FabricVariableLibraryValues @script:params

        $result.DefinitionAction     | Should -Be 'Updated'
        $result.ActiveValueSetAction | Should -Be 'Set'

        $sent = Get-SentParts $script:sent.update
        $sent.Keys | Should -Not -Contain '.platform'
        $sent['variables.json'].variables.name  | Should -Be @('workspace_name', 'workspace_id')
        $sent['variables.json'].variables.type  | Should -Be @('String', 'String')
        $sent['variables.json'].variables.value | Should -Be @($script:placeholder, $script:placeholder)

        $valueSet = $sent['valueSets/DEV.json']
        $valueSet.name | Should -Be 'DEV'
        ($valueSet.variableOverrides | Where-Object name -eq 'workspace_name').value | Should -Be 'sales-Bronze [DEV]'
        ($valueSet.variableOverrides | Where-Object name -eq 'workspace_id').value   | Should -Be 'ws-1'

        $script:sent.patch.properties.activeValueSetName | Should -Be 'DEV'
    }

    It 'preserves other variables, value sets and overrides, and passes unmodified parts through unchanged' {
        $otherValueSet = '{"name":"PROD","variableOverrides":[{"name":"workspace_id","value":"ws-prod"}]}'
        Register-RestMock (New-DefinitionResponse ([ordered]@{
            'variables.json'      = '{"variables":[{"name":"my_var","type":"DateTime","value":"2025-01-20T15:30:00+01:00"}]}'
            'valueSets/DEV.json'  = '{"name":"DEV","variableOverrides":[{"name":"my_var","value":"2026-01-01T00:00:00+01:00"}]}'
            'valueSets/PROD.json' = $otherValueSet
            'settings.json'       = '{"valueSetsOrder":["DEV","PROD"]}'
        })) 'DEV'

        Set-FabricVariableLibraryValues @script:params | Out-Null

        $sent = Get-SentParts $script:sent.update
        $sent['variables.json'].variables.name | Should -Be @('my_var', 'workspace_name', 'workspace_id')
        $sent['valueSets/DEV.json'].variableOverrides.name | Should -Be @('my_var', 'workspace_name', 'workspace_id')

        # Date strings in rewritten parts are not reformatted.
        $payloads = Get-SentPayloads $script:sent.update
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payloads['variables.json'])) | Should -Match '2025-01-20T15:30:00\+01:00'

        # Untouched parts are sent back byte-for-byte.
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payloads['valueSets/PROD.json'])) | Should -Be $otherValueSet
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payloads['settings.json'])) | Should -Be '{"valueSetsOrder":["DEV","PROD"]}'
    }

    It 'resets a default variable whose default value holds a real value back to the placeholder' {
        Register-RestMock (New-DefinitionResponse ([ordered]@{
            'variables.json'     = '{"variables":[{"name":"workspace_name","type":"String","value":"leaked"},{"name":"workspace_id","type":"String","value":"PLACEHOLDER - NO VALUE SET ACTIVE"}]}'
            'valueSets/DEV.json' = '{"name":"DEV","variableOverrides":[{"name":"workspace_name","value":"sales-Bronze [DEV]"},{"name":"workspace_id","value":"ws-1"}]}'
            'settings.json'      = '{}'
        })) 'DEV'

        $result = Set-FabricVariableLibraryValues @script:params
        $result.DefinitionAction | Should -Be 'Updated'
        (Get-SentParts $script:sent.update)['variables.json'].variables.value | Should -Be @($script:placeholder, $script:placeholder)
    }

    It 'updates a stale override in an existing value set' {
        Register-RestMock (New-DefinitionResponse ([ordered]@{
            'variables.json'     = '{"variables":[{"name":"workspace_name","type":"String","value":"PLACEHOLDER - NO VALUE SET ACTIVE"},{"name":"workspace_id","type":"String","value":"PLACEHOLDER - NO VALUE SET ACTIVE"}]}'
            'valueSets/DEV.json' = '{"name":"DEV","variableOverrides":[{"name":"workspace_name","value":"sales-Bronze [DEV]"},{"name":"workspace_id","value":"old-id"}]}'
            'settings.json'      = '{}'
        })) 'DEV'

        Set-FabricVariableLibraryValues @script:params | Out-Null
        $overrides = (Get-SentParts $script:sent.update)['valueSets/DEV.json'].variableOverrides
        ($overrides | Where-Object name -eq 'workspace_id').value | Should -Be 'ws-1'
    }

    It 'skips the update and activation when everything is already up to date' {
        Register-RestMock (New-DefinitionResponse ([ordered]@{
            'variables.json'     = '{"variables":[{"name":"workspace_name","type":"String","value":"PLACEHOLDER - NO VALUE SET ACTIVE"},{"name":"workspace_id","type":"String","value":"PLACEHOLDER - NO VALUE SET ACTIVE"}]}'
            'valueSets/DEV.json' = '{"name":"DEV","variableOverrides":[{"name":"workspace_name","value":"sales-Bronze [DEV]"},{"name":"workspace_id","value":"ws-1"}]}'
            'settings.json'      = '{}'
        })) 'DEV'

        $result = Set-FabricVariableLibraryValues @script:params

        $result.DefinitionAction     | Should -Be 'Skipped'
        $result.ActiveValueSetAction | Should -Be 'Skipped'
        Should -Invoke _Invoke-FabricRestMethod -ParameterFilter { $RelativeUri -like '*/updateDefinition' } -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke _Invoke-FabricRestMethod -ParameterFilter { $Method -eq 'PATCH' } -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'activates the value set when the definition is up to date but another value set is active' {
        Register-RestMock (New-DefinitionResponse ([ordered]@{
            'variables.json'     = '{"variables":[{"name":"workspace_name","type":"String","value":"PLACEHOLDER - NO VALUE SET ACTIVE"},{"name":"workspace_id","type":"String","value":"PLACEHOLDER - NO VALUE SET ACTIVE"}]}'
            'valueSets/DEV.json' = '{"name":"DEV","variableOverrides":[{"name":"workspace_name","value":"sales-Bronze [DEV]"},{"name":"workspace_id","value":"ws-1"}]}'
            'settings.json'      = '{}'
        })) 'OTHER'

        $result = Set-FabricVariableLibraryValues @script:params

        $result.DefinitionAction     | Should -Be 'Skipped'
        $result.ActiveValueSetAction | Should -Be 'Set'
        $script:sent.patch.properties.activeValueSetName | Should -Be 'DEV'
    }

    It 'adds the required parts when the definition has none' {
        Register-RestMock ([pscustomobject]@{ definition = [pscustomobject]@{ parts = @() } }) $null

        Set-FabricVariableLibraryValues @script:params | Out-Null
        (Get-SentParts $script:sent.update).Keys | Sort-Object | Should -Be @('settings.json', 'valueSets/DEV.json', 'variables.json')
    }

    It 'requests the getDefinition LRO result' {
        Register-RestMock (New-DefinitionResponse @{}) $null
        Set-FabricVariableLibraryValues @script:params | Out-Null
        Should -Invoke _Invoke-FabricRestMethod -ModuleName ZeroFailed.Deploy.Fabric -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $RelativeUri -eq 'workspaces/ws-1/variableLibraries/vl-1/getDefinition' -and $ReturnLroResult
        }
    }

    It 'propagates API errors' {
        Mock _Invoke-FabricRestMethod { throw 'Fabric API error 403' } -ModuleName ZeroFailed.Deploy.Fabric
        { Set-FabricVariableLibraryValues @script:params } | Should -Throw '*403*'
    }
}
