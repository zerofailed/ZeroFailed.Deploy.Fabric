#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Set-FabricGitIntegration' {

    BeforeAll {
        $script:gitConfig = [pscustomobject]@{
            enabled          = $true
            provider         = 'AzureDevOps'
            organisationName = 'contoso'
            projectName      = 'MyProject'
            repositoryName   = 'my-repo'
            rootFolder       = 'fabric'
            branch           = 'main'
        }
    }

    It 'does not call REST API when -WhatIf is specified' {
        Mock _Invoke-FabricRestMethod { throw 'should not be called' } -ModuleName ZeroFailed.Deploy.Fabric

        { Set-FabricGitIntegration -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -GitConfig $script:gitConfig -Branch 'main' -Token 'tok' -WhatIf } |
            Should -Not -Throw
    }

    It 'treats WorkspaceAlreadyConnectedToGit error as non-fatal' {
        Mock _Invoke-FabricRestMethod { throw 'WorkspaceAlreadyConnectedToGit' } -ModuleName ZeroFailed.Deploy.Fabric

        { Set-FabricGitIntegration -WorkspaceId 'ws-id' -WorkspaceName 'my-ws' -GitConfig $script:gitConfig -Branch 'main' -Token 'tok' } |
            Should -Not -Throw
    }
}
