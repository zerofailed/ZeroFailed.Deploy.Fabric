#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'New-FabricEnvironment' {

    It 'returns existing environment without creating when it already exists' {
        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri)
            if ($Method -eq 'GET') {
                return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'env-existing'; displayName = 'my-env' }) }
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = New-FabricEnvironment -WorkspaceId 'ws-1' -DisplayName 'my-env' -Token 'tok'
        $result.id | Should -Be 'env-existing'
        Should -Invoke _Invoke-FabricRestMethod -ParameterFilter { $Method -eq 'POST' } -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'returns WhatIf placeholder when -WhatIf is specified and environment does not exist' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = New-FabricEnvironment -WorkspaceId 'ws-1' -DisplayName 'new-env' -Token 'tok' -WhatIf
        $result.id | Should -Be 'whatif-id'
        $result.displayName | Should -Be 'new-env'
    }

    It 'creates the environment via POST when it does not exist' {
        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri)
            if ($Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
            if ($Method -eq 'POST' -and $RelativeUri -eq 'workspaces/ws-1/environments') {
                return [pscustomobject]@{ id = 'env-new'; displayName = 'new-env' }
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = New-FabricEnvironment -WorkspaceId 'ws-1' -DisplayName 'new-env' -Token 'tok'
        $result.id | Should -Be 'env-new'
        Should -Invoke _Invoke-FabricRestMethod -ParameterFilter { $Method -eq 'POST' } -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'includes the description in the POST body when provided' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
            if ($Method -eq 'POST') { return [pscustomobject]@{ id = 'env-new'; displayName = 'new-env' } }
        } -ModuleName ZeroFailed.Deploy.Fabric

        New-FabricEnvironment -WorkspaceId 'ws-1' -DisplayName 'new-env' -Description 'desc' -Token 'tok' | Out-Null
        Should -Invoke _Invoke-FabricRestMethod -ParameterFilter {
            $Method -eq 'POST' -and $Body.description -eq 'desc' -and $Body.displayName -eq 'new-env'
        } -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    Context 'idempotency on 409 conflict' {

        BeforeEach {
            InModuleScope ZeroFailed.Deploy.Fabric { $script:nfeLookups = 0 }
        }

        It 'resolves and returns the existing environment when creation reports a conflict' {
            Mock _Invoke-FabricRestMethod {
                param($Method, $RelativeUri)
                if ($Method -eq 'GET') {
                    $script:nfeLookups++
                    if ($script:nfeLookups -eq 1) { return [pscustomobject]@{ value = @() } }
                    return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'env-existing'; displayName = 'dup' }) }
                }
                if ($Method -eq 'POST') {
                    throw 'Fabric API error 409 on POST https://api.fabric.microsoft.com/v1/workspaces/ws-1/environments : EnvironmentDisplayNameAlreadyInUse'
                }
            } -ModuleName ZeroFailed.Deploy.Fabric

            $result = New-FabricEnvironment -WorkspaceId 'ws-1' -DisplayName 'dup' -Token 'tok'
            $result.id | Should -Be 'env-existing'
        }
    }

    It 'rethrows non-conflict creation errors' {
        Mock _Invoke-FabricRestMethod {
            param($Method)
            if ($Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
            if ($Method -eq 'POST') { throw 'Fabric API error 500 on POST : InternalError' }
        } -ModuleName ZeroFailed.Deploy.Fabric

        { New-FabricEnvironment -WorkspaceId 'ws-1' -DisplayName 'doomed' -Token 'tok' } |
            Should -Throw '*Failed to create environment*'
    }
}
