@{
    RootModule        = 'ZeroFailed.Deploy.Fabric.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'Endjineers (Endjin Limited)'
    CompanyName       = 'Endjin Limited'
    Description       = 'ZeroFailed extension module for provisioning Microsoft Fabric workspaces across DTAP environments.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    RequiredModules   = @('MicrosoftFabricMgmt')
    FunctionsToExport = '*'
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('Fabric', 'Microsoft', 'DTAP', 'Provisioning', 'ZeroFailed')
            ProjectUri = 'https://github.com/zerofailed/ZeroFailed.Deploy.Fabric'
        }
    }
}
