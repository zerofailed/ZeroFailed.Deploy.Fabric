#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Import-FabricEnvironmentExternalLibraries' {

    It 'posts the yml to the importExternalLibraries endpoint' {
        $script:sentContent = $null
        Mock _Invoke-FabricFileUpload {
            $script:sentContent = Get-Content -LiteralPath $FilePath -Raw
        } -ModuleName ZeroFailed.Deploy.Fabric

        $yml = "name: env`ndependencies:`n  - pip:`n    - deltalake==1.6.2`n"
        $result = Import-FabricEnvironmentExternalLibraries -WorkspaceId 'ws-1' -EnvironmentId 'env-1' `
            -EnvironmentYml $yml -Token 'tok'

        $result.Action | Should -Be 'Imported'
        Should -Invoke _Invoke-FabricFileUpload -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $RelativeUri -eq 'workspaces/ws-1/environments/env-1/staging/libraries/importExternalLibraries'
        }
        $script:sentContent | Should -Match 'deltalake==1\.6\.2'
    }

    It 'cleans up the temp file after upload' {
        $script:capturedPath = $null
        Mock _Invoke-FabricFileUpload { $script:capturedPath = $FilePath } -ModuleName ZeroFailed.Deploy.Fabric

        Import-FabricEnvironmentExternalLibraries -WorkspaceId 'ws-1' -EnvironmentId 'env-1' `
            -EnvironmentYml 'name: env' -Token 'tok' | Out-Null

        $script:capturedPath | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $script:capturedPath | Should -BeFalse
    }

    It 'does not call the API under -WhatIf' {
        Mock _Invoke-FabricFileUpload { } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Import-FabricEnvironmentExternalLibraries -WorkspaceId 'ws-1' -EnvironmentId 'env-1' `
            -EnvironmentYml 'name: env' -Token 'tok' -WhatIf

        $result.Action | Should -Be 'whatif'
        Should -Invoke _Invoke-FabricFileUpload -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }
}
