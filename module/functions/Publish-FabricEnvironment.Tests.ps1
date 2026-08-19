#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Publish-FabricEnvironment' {

    It 'posts to the staging publish endpoint and passes the timeout through' {
        Mock _Invoke-FabricRestMethod { } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Publish-FabricEnvironment -WorkspaceId 'ws-1' -EnvironmentId 'env-1' -Token 'tok' -TimeoutSeconds 900

        $result.Action | Should -Be 'Published'
        Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $Method -eq 'POST' -and
            $RelativeUri -eq 'workspaces/ws-1/environments/env-1/staging/publish' -and
            $TimeoutSeconds -eq 900
        }
    }

    It 'treats "no pending changes" as an idempotent skip' {
        Mock _Invoke-FabricRestMethod {
            throw 'Fabric API error 400 on POST : NoStagingChanges - There are no changes to publish.'
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Publish-FabricEnvironment -WorkspaceId 'ws-1' -EnvironmentId 'env-1' -Token 'tok'
        $result.Action | Should -Be 'Skipped'
    }

    It 'rethrows other publish failures' {
        Mock _Invoke-FabricRestMethod {
            throw 'Fabric API error 500 on POST : InternalError'
        } -ModuleName ZeroFailed.Deploy.Fabric

        { Publish-FabricEnvironment -WorkspaceId 'ws-1' -EnvironmentId 'env-1' -Token 'tok' } |
            Should -Throw '*Failed to publish environment*'
    }

    It 'returns a whatif action under -WhatIf' {
        Mock _Invoke-FabricRestMethod { } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Publish-FabricEnvironment -WorkspaceId 'ws-1' -EnvironmentId 'env-1' -Token 'tok' -WhatIf
        $result.Action | Should -Be 'whatif'
        Should -Invoke _Invoke-FabricRestMethod -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }
}
