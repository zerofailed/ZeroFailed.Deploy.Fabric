#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Get-AzADGroupMember/Add-AzADGroupMember come from Az.Resources, which is not installed in CI.
    # Provide stubs so the commands exist and can be mocked from within the module's scope.
    if (Get-Module _AzGroupStub) { Remove-Module _AzGroupStub -Force }
    New-Module -Name _AzGroupStub {
        function Get-AzADGroupMember { param([string]$GroupObjectId, $ErrorAction) }
        function Add-AzADGroupMember { param([string]$TargetGroupObjectId, [string[]]$MemberObjectId, $ErrorAction) }
        Export-ModuleMember -Function Get-AzADGroupMember, Add-AzADGroupMember
    } | Import-Module
}

AfterAll {
    if (Get-Module _AzGroupStub) { Remove-Module _AzGroupStub -Force }
}

Describe 'Add-FabricWorkspaceIdentityToGroup' {

    It 'adds the identity when it is not already a member' {
        Mock Get-AzADGroupMember { @([pscustomobject]@{ Id = 'other-sp' }) } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Add-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric

        $result = Add-FabricWorkspaceIdentityToGroup -ServicePrincipalObjectId 'sp-1' -GroupId 'grp-1' `
            -WorkspaceName 'my-ws' -WorkspaceId 'ws-1'

        $result.Action                   | Should -Be 'Added'
        $result.ServicePrincipalObjectId | Should -Be 'sp-1'
        $result.GroupId                  | Should -Be 'grp-1'
        $result.WorkspaceName            | Should -Be 'my-ws'
        $result.WorkspaceId              | Should -Be 'ws-1'

        Should -Invoke Add-AzADGroupMember -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric `
            -ParameterFilter { $TargetGroupObjectId -eq 'grp-1' -and $MemberObjectId -contains 'sp-1' }
    }

    It 'skips when the identity is already a member' {
        Mock Get-AzADGroupMember { @([pscustomobject]@{ Id = 'sp-1' }) } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Add-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric

        $result = Add-FabricWorkspaceIdentityToGroup -ServicePrincipalObjectId 'sp-1' -GroupId 'grp-1' `
            -WorkspaceName 'my-ws' -WorkspaceId 'ws-1'

        $result.Action | Should -Be 'Skipped'
        Should -Invoke Add-AzADGroupMember -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'handles an empty group' {
        Mock Get-AzADGroupMember { @() } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Add-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric

        $result = Add-FabricWorkspaceIdentityToGroup -ServicePrincipalObjectId 'sp-1' -GroupId 'grp-1' `
            -WorkspaceName 'my-ws' -WorkspaceId 'ws-1'

        $result.Action | Should -Be 'Added'
    }

    It 'treats a concurrent "already exists" response as skipped' {
        # Another run added the identity between the membership check and the add.
        Mock Get-AzADGroupMember { @() } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Add-AzADGroupMember {
            throw "One or more added object references already exist for the following modified properties: 'members'."
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Add-FabricWorkspaceIdentityToGroup -ServicePrincipalObjectId 'sp-1' -GroupId 'grp-1' `
            -WorkspaceName 'my-ws' -WorkspaceId 'ws-1'

        $result.Action | Should -Be 'Skipped'
    }

    It 'rethrows an unexpected failure from the add' {
        Mock Get-AzADGroupMember { @() } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Add-AzADGroupMember { throw 'Insufficient privileges to complete the operation.' } -ModuleName ZeroFailed.Deploy.Fabric

        { Add-FabricWorkspaceIdentityToGroup -ServicePrincipalObjectId 'sp-1' -GroupId 'grp-1' `
            -WorkspaceName 'my-ws' -WorkspaceId 'ws-1' } | Should -Throw '*Insufficient privileges*'
    }

    It 'rethrows when the group membership lookup fails' {
        Mock Get-AzADGroupMember { throw 'Request_ResourceNotFound' } -ModuleName ZeroFailed.Deploy.Fabric

        { Add-FabricWorkspaceIdentityToGroup -ServicePrincipalObjectId 'sp-1' -GroupId 'missing-grp' `
            -WorkspaceName 'my-ws' -WorkspaceId 'ws-1' } | Should -Throw '*Request_ResourceNotFound*'
    }

    It 'returns a WhatIf placeholder and makes no changes when -WhatIf is specified' {
        Mock Get-AzADGroupMember { @() } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Add-AzADGroupMember {} -ModuleName ZeroFailed.Deploy.Fabric

        $result = Add-FabricWorkspaceIdentityToGroup -ServicePrincipalObjectId 'sp-1' -GroupId 'grp-1' `
            -WorkspaceName 'my-ws' -WorkspaceId 'ws-1' -WhatIf

        $result.Action | Should -Be 'WhatIf'
        Should -Invoke Add-AzADGroupMember -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Get-AzADGroupMember -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }
}
