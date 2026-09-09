#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    function New-Rec ($type, $env) {
        [pscustomobject]@{ Type = $type; Environment = $env; WorkspaceId = "ws-$type-$env" }
    }
}

Describe '_ConvertTo-FabricWorkspaceIndex' {

    It 'nests records by type then environment' {
        $records = @(
            New-Rec 'Bronze' 'Dev'
            New-Rec 'Bronze' 'Test'
            New-Rec 'Gold'   'Dev'
        )

        $index = & (Get-Module ZeroFailed.Deploy.Fabric) { param($r) _ConvertTo-FabricWorkspaceIndex -Workspace $r } $records

        $index.Keys                      | Should -Be @('Bronze', 'Gold')
        $index['Bronze'].Keys            | Should -Be @('Dev', 'Test')
        $index['Bronze']['Dev'].WorkspaceId  | Should -Be 'ws-Bronze-Dev'
        $index['Gold']['Dev'].WorkspaceId    | Should -Be 'ws-Gold-Dev'
    }

    It 'keeps the same record object instances (no copy)' {
        $rec = New-Rec 'Bronze' 'Dev'
        $index = & (Get-Module ZeroFailed.Deploy.Fabric) { param($r) _ConvertTo-FabricWorkspaceIndex -Workspace $r } @($rec)

        [object]::ReferenceEquals($rec, $index['Bronze']['Dev']) | Should -BeTrue
    }

    It 'returns an empty ordered dictionary for an empty input' {
        $index = & (Get-Module ZeroFailed.Deploy.Fabric) { _ConvertTo-FabricWorkspaceIndex -Workspace @() }
        $index                     | Should -BeOfType ([System.Collections.Specialized.OrderedDictionary])
        $index.Count               | Should -Be 0
    }

    It 'preserves first-seen type and environment order' {
        $records = @(
            New-Rec 'Gold'   'Prod'
            New-Rec 'Bronze' 'Test'
            New-Rec 'Gold'   'Dev'
            New-Rec 'Bronze' 'Dev'
        )
        $index = & (Get-Module ZeroFailed.Deploy.Fabric) { param($r) _ConvertTo-FabricWorkspaceIndex -Workspace $r } $records

        $index.Keys           | Should -Be @('Gold', 'Bronze')
        $index['Gold'].Keys   | Should -Be @('Prod', 'Dev')
        $index['Bronze'].Keys | Should -Be @('Test', 'Dev')
    }
}
