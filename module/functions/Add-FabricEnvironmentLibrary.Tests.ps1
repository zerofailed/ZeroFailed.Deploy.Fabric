#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Add-FabricEnvironmentLibrary' {

    It 'uploads to the staging libraries endpoint' {
        Mock _Invoke-FabricFileUpload { } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Add-FabricEnvironmentLibrary -WorkspaceId 'ws-1' -EnvironmentId 'env-1' `
            -FilePath '/tmp/mypackage-1.4.2-py3-none-any.whl' -Token 'tok'

        $result.Action | Should -Be 'Uploaded'
        $result.FileName | Should -Be 'mypackage-1.4.2-py3-none-any.whl'
        Should -Invoke _Invoke-FabricFileUpload -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $RelativeUri -eq 'workspaces/ws-1/environments/env-1/staging/libraries' -and
            $FilePath -eq '/tmp/mypackage-1.4.2-py3-none-any.whl'
        }
    }

    It 'does not upload and returns a whatif action under -WhatIf' {
        Mock _Invoke-FabricFileUpload { } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Add-FabricEnvironmentLibrary -WorkspaceId 'ws-1' -EnvironmentId 'env-1' `
            -FilePath '/tmp/pkg.whl' -Token 'tok' -WhatIf

        $result.Action | Should -Be 'whatif'
        Should -Invoke _Invoke-FabricFileUpload -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }
}
