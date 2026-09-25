#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Calls the private function inside the module, splatting the given parameters.
    function Get-Mpe([hashtable]$Params) {
        & (Get-Module ZeroFailed.Deploy.Fabric) { param($p) _Get-FabricManagedPrivateEndpoint @p } $Params
    }
}

Describe '_Get-FabricManagedPrivateEndpoint' {

    It 'returns the endpoint with the given name' {
        Mock _Invoke-FabricRestMethod {
            [pscustomobject]@{ value = @(
                [pscustomobject]@{ id = 'mpe-1'; name = 'kv-dev.vault' }
                [pscustomobject]@{ id = 'mpe-2'; name = 'stdev.dfs' }
            ) }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $r = Get-Mpe @{ WorkspaceId = 'ws-1'; Name = 'stdev.dfs'; Token = 'tok' }

        $r.id | Should -Be 'mpe-2'
        Should -Invoke _Invoke-FabricRestMethod -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $Method -eq 'GET' -and $RelativeUri -eq 'workspaces/ws-1/managedPrivateEndpoints'
        }
    }

    It 'returns nothing when no endpoint has that name' {
        Mock _Invoke-FabricRestMethod { [pscustomobject]@{ value = @([pscustomobject]@{ id = 'mpe-1'; name = 'kv-dev.vault' }) } } -ModuleName ZeroFailed.Deploy.Fabric

        Get-Mpe @{ WorkspaceId = 'ws-1'; Name = 'missing'; Token = 'tok' } | Should -BeNullOrEmpty
    }

    It 'follows continuation tokens across pages' {
        Mock _Invoke-FabricRestMethod {
            if ($RelativeUri -like '*continuationToken=page2') {
                [pscustomobject]@{ value = @([pscustomobject]@{ id = 'mpe-2'; name = 'stdev.dfs' }) }
            }
            else {
                [pscustomobject]@{ value = @([pscustomobject]@{ id = 'mpe-1'; name = 'kv-dev.vault' }); continuationToken = 'page2' }
            }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $r = Get-Mpe @{ WorkspaceId = 'ws-1'; Name = 'stdev.dfs'; Token = 'tok' }

        $r.id | Should -Be 'mpe-2'
        Should -Invoke _Invoke-FabricRestMethod -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'copes with a response that has no value or continuation token' {
        Mock _Invoke-FabricRestMethod { [pscustomobject]@{} } -ModuleName ZeroFailed.Deploy.Fabric

        Get-Mpe @{ WorkspaceId = 'ws-1'; Name = 'kv-dev.vault'; Token = 'tok' } | Should -BeNullOrEmpty
    }

    It 'propagates API errors' {
        Mock _Invoke-FabricRestMethod { throw 'boom' } -ModuleName ZeroFailed.Deploy.Fabric

        { Get-Mpe @{ WorkspaceId = 'ws-1'; Name = 'kv-dev.vault'; Token = 'tok' } } | Should -Throw '*boom*'
    }
}
