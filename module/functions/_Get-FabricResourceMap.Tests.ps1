#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe '_Get-FabricWorkspaceMap' {

    It 'returns a displayName -> workspace object hashtable' {
        Mock _Invoke-FabricRestMethod {
            [pscustomobject]@{ value = @(
                [pscustomobject]@{ id = 'a'; displayName = 'sa-Bronze [DEV]' }
                [pscustomobject]@{ id = 'b'; displayName = 'sa-Bronze [TEST]' }
            ) }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $map = & (Get-Module ZeroFailed.Deploy.Fabric) { _Get-FabricWorkspaceMap -Token 'tok' }

        $map                          | Should -BeOfType ([hashtable])
        $map['sa-Bronze [DEV]'].id    | Should -Be 'a'
        $map['sa-Bronze [TEST]'].id   | Should -Be 'b'
        $map.Count                    | Should -Be 2
    }

    It 'follows the continuation token across pages' {
        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri)
            if ($RelativeUri -eq 'workspaces') {
                return [pscustomobject]@{
                    value             = @([pscustomobject]@{ id = 'p1'; displayName = 'page-one' })
                    continuationToken = 'tok-2'
                }
            }
            return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'p2'; displayName = 'page-two' }) }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $map = & (Get-Module ZeroFailed.Deploy.Fabric) { _Get-FabricWorkspaceMap -Token 'tok' }

        $map['page-one'].id | Should -Be 'p1'
        $map['page-two'].id | Should -Be 'p2'
        Should -Invoke _Invoke-FabricRestMethod -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'does not throw under StrictMode when continuationToken is omitted' {
        InModuleScope ZeroFailed.Deploy.Fabric {
            Set-StrictMode -Version Latest
            Mock _Invoke-FabricRestMethod {
                [pscustomobject]@{ value = @([pscustomobject]@{ id = 'x'; displayName = 'ws' }) }
            }
            $map = _Get-FabricWorkspaceMap -Token 'tok'
            $map['ws'].id | Should -Be 'x'
        }
    }
}

Describe '_Get-FabricDeploymentPipelineMap' {

    It 'returns a displayName -> pipeline object hashtable and follows pagination' {
        Mock _Invoke-FabricRestMethod {
            param($Method, $RelativeUri)
            if ($RelativeUri -eq 'deploymentPipelines') {
                return [pscustomobject]@{
                    value             = @([pscustomobject]@{ id = 'pipe-1'; displayName = 'sa-Bronze Pipeline' })
                    continuationToken = 'next'
                }
            }
            return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'pipe-2'; displayName = 'sa-Gold Pipeline' }) }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $map = & (Get-Module ZeroFailed.Deploy.Fabric) { _Get-FabricDeploymentPipelineMap -Token 'tok' }

        $map['sa-Bronze Pipeline'].id | Should -Be 'pipe-1'
        $map['sa-Gold Pipeline'].id   | Should -Be 'pipe-2'
        Should -Invoke _Invoke-FabricRestMethod -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }
}
