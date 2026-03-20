$here = $PSScriptRoot
Get-ChildItem -Path (Join-Path $here 'functions') -Filter '*.ps1' -Recurse |
    Where-Object { $_.Name -notlike '*.Tests.ps1' } |
    ForEach-Object { . $_.FullName }

$functionsToExport = Get-ChildItem -Path (Join-Path $here 'functions') -Filter '*.ps1' -Recurse |
    Where-Object { $_.Name -notlike '*.Tests.ps1' -and $_.BaseName -notlike '_*' } |
    ForEach-Object { $_.BaseName }

$aliasName = 'ZeroFailed.Deploy.Fabric.tasks'
$aliasTarget = Join-Path $here 'tasks/fabric.tasks.ps1'
Set-Alias -Name $aliasName -Value $aliasTarget -Scope Global

Export-ModuleMember -Function $functionsToExport -Alias $aliasName
