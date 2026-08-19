#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'ZeroFailed.Deploy.Fabric module' {

    It 'imports without error' {
        { Import-Module (Join-Path $PSScriptRoot 'ZeroFailed.Deploy.Fabric.psd1') -Force -ErrorAction Stop } |
            Should -Not -Throw
    }

    It 'exports all expected public functions' {
        $exported = Get-Command -Module ZeroFailed.Deploy.Fabric | Select-Object -ExpandProperty Name
        $expectedFunctions = @(
            'Enable-FabricWorkspaceIdentity'
            'Invoke-FabricSetup'
            'New-FabricTopologyConfig'
            'New-FabricWorkspace'
            'Set-FabricGitIntegration'
            'Test-FabricWorkspaceExists'
            'Invoke-FabricPythonLibraryDeploy'
            'Add-FabricEnvironmentLibrary'
            'Remove-FabricEnvironmentLibrary'
            'Publish-FabricEnvironment'
            'Get-FabricEnvironmentLibraries'
            'Save-FabricLibraryPackage'
        )
        foreach ($fn in $expectedFunctions) {
            $exported | Should -Contain $fn
        }
    }

    It 'does not export private functions' {
        $exported = Get-Command -Module ZeroFailed.Deploy.Fabric | Select-Object -ExpandProperty Name
        $exported | Where-Object { $_ -like '_*' } | Should -BeNullOrEmpty
    }

    It 'exports the tasks alias' {
        $alias = Get-Alias -Name 'ZeroFailed.Deploy.Fabric.tasks' -ErrorAction SilentlyContinue
        $alias | Should -Not -BeNullOrEmpty
    }

    It 'manifest ModuleVersion is a valid semantic version' {
        $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ZeroFailed.Deploy.Fabric.psd1')
        $manifest.ModuleVersion | Should -Match '^\d+\.\d+\.\d+'
    }
}
