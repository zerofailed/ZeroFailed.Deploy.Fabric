#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'New-FabricVariableLibrary' {

    It 'returns the existing variable library without creating or modifying it when it already exists' {
        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri)
            if ($Method -eq 'GET') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'vl-existing'; displayName = 'my-vars' }) }
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = New-FabricVariableLibrary -WorkspaceId 'ws-1' -DisplayName 'my-vars' -Token 'tok'
        $result.id | Should -Be 'vl-existing'
        # Only the lookup happens — no create, update or definition calls.
        Should -Invoke _Invoke-FabricRestMethod -ParameterFilter { $Method -ne 'GET' } -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'returns WhatIf placeholder when -WhatIf is specified and the variable library does not exist' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = New-FabricVariableLibrary -WorkspaceId 'ws-1' -DisplayName 'new-vars' -Token 'tok' -WhatIf
        $result.id | Should -Be 'whatif-id'
        $result.displayName | Should -Be 'new-vars'
        Should -Invoke _Invoke-FabricRestMethod -ParameterFilter { $Method -eq 'POST' } -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'creates an empty variable library via POST when it does not exist' {
        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri)
            if ($Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
            if ($Method -eq 'POST' -and $RelativeUri -eq 'workspaces/ws-1/variableLibraries') {
                return [pscustomobject]@{ id = 'vl-new'; displayName = 'new-vars' }
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = New-FabricVariableLibrary -WorkspaceId 'ws-1' -DisplayName 'new-vars' -Token 'tok'
        $result.id | Should -Be 'vl-new'
        # No definition is supplied, so no variables or value sets are populated.
        Should -Invoke _Invoke-FabricRestMethod -ParameterFilter {
            $Method -eq 'POST' -and $Body.displayName -eq 'new-vars' -and -not $Body.ContainsKey('definition')
        } -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'includes the description in the POST body when provided' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
            if ($Method -eq 'POST') { return [pscustomobject]@{ id = 'vl-new'; displayName = 'new-vars' } }
        } -ModuleName ZeroFailed.Deploy.Fabric

        New-FabricVariableLibrary -WorkspaceId 'ws-1' -DisplayName 'new-vars' -Description 'desc' -Token 'tok' | Out-Null
        Should -Invoke _Invoke-FabricRestMethod -ParameterFilter {
            $Method -eq 'POST' -and $Body.description -eq 'desc'
        } -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    Context 'lookups after creation' {

        BeforeEach {
            InModuleScope ZeroFailed.Deploy.Fabric { $script:nfvlLookups = 0 }
        }

        It 'resolves the created variable library by name when creation runs as a long-running operation' {
            Mock _Invoke-FabricRestMethod {
                param($Method)
                if ($Method -eq 'GET') {
                    $script:nfvlLookups++
                    if ($script:nfvlLookups -eq 1) { return [pscustomobject]@{ value = @() } }
                    return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'vl-lro'; displayName = 'lro-vars' }) }
                }
                # LRO poll response: operation state, not the item.
                if ($Method -eq 'POST') { return [pscustomobject]@{ status = 'Succeeded' } }
            } -ModuleName ZeroFailed.Deploy.Fabric

            $result = New-FabricVariableLibrary -WorkspaceId 'ws-1' -DisplayName 'lro-vars' -Token 'tok'
            $result.id | Should -Be 'vl-lro'
        }

        It 'resolves and returns the existing variable library when creation reports a conflict' {
            Mock _Invoke-FabricRestMethod {
                param($Method)
                if ($Method -eq 'GET') {
                    $script:nfvlLookups++
                    if ($script:nfvlLookups -eq 1) { return [pscustomobject]@{ value = @() } }
                    return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'vl-existing'; displayName = 'dup' }) }
                }
                if ($Method -eq 'POST') {
                    throw 'Fabric API error 409 on POST https://api.fabric.microsoft.com/v1/workspaces/ws-1/variableLibraries : ItemDisplayNameAlreadyInUse'
                }
            } -ModuleName ZeroFailed.Deploy.Fabric

            $result = New-FabricVariableLibrary -WorkspaceId 'ws-1' -DisplayName 'dup' -Token 'tok'
            $result.id | Should -Be 'vl-existing'
        }
    }

    It 'rethrows non-conflict creation errors' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
            if ($Method -eq 'POST') { throw 'Fabric API error 500 on POST : InternalError' }
        } -ModuleName ZeroFailed.Deploy.Fabric

        { New-FabricVariableLibrary -WorkspaceId 'ws-1' -DisplayName 'doomed' -Token 'tok' } |
            Should -Throw '*Failed to create variable library*'
    }
}
