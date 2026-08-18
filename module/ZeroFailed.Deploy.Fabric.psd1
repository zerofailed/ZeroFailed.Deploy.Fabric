@{
    RootModule        = 'ZeroFailed.Deploy.Fabric.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'Endjineers (Endjin Limited)'
    CompanyName       = 'Endjin Limited'
    Description       = 'ZeroFailed extension module for provisioning Microsoft Fabric workspaces across DTAP environments.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    # RequiredModules intentionally left empty. Runtime dependencies (MicrosoftFabricMgmt,
    # Az.Accounts) are installed via ZeroFailed.DevOps.Common's RequiredPowerShellModules
    # mechanism (see the 'ensureFabricModules' task) and imported on demand within the
    # functions that need them, so they are not required at module-import time (e.g. for docs).
    RequiredModules = @()
    FunctionsToExport = '*'
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('Fabric', 'Microsoft', 'DTAP', 'Provisioning', 'ZeroFailed')
            ProjectUri = 'https://github.com/zerofailed/ZeroFailed.Deploy.Fabric'
        }

        # ZeroFailed metadata
        ZeroFailed = @{
            ExtensionDependencies = @(
                @{
                    # Assume latest stable version
                    Name          = 'ZeroFailed.Deploy.Common'
                    GitRepository = 'https://github.com/zerofailed/ZeroFailed.Deploy.Common'
                    Process       = 'tasks/deploy.process.ps1'
                }
                @{
                    # Provides the 'setupModules' task and 'RequiredPowerShellModules' property
                    # used by the 'ensureFabricModules' task to install Az.Accounts, Az.Resources
                    # and MicrosoftFabricMgmt. Assume latest stable version.
                    Name          = 'ZeroFailed.DevOps.Common'
                    GitRepository = 'https://github.com/zerofailed/ZeroFailed.DevOps.Common'
                }
            )
        }
    }
}
