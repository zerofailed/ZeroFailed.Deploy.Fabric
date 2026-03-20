$zerofailedExtensions = @(
    @{
        Name          = 'ZeroFailed.Build.PowerShell'
        GitRepository = 'https://github.com/zerofailed/ZeroFailed.Build.PowerShell.git'
        GitRef        = 'main'
    }
)

. ZeroFailed.tasks -ZfPath $here/.zf

$PesterTestsDir            = "$here/module"
$PesterCodeCoveragePaths   = @("$here/module/functions")
$PowerShellModulesToPublish = @(
    @{
        ModulePath        = "$here/module/ZeroFailed.Deploy.Fabric.psd1"
        FunctionsToExport = @('*')
        CmdletsToExport   = @()
        AliasesToExport   = @()
    }
)
$PSMarkdownDocsFlattenOutputPath = $true
$PSMarkdownDocsOutputPath        = './docs/functions'
$PSMarkdownDocsIncludeModulePage = $false

task . FullBuild
