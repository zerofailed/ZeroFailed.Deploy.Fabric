#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    function New-TestConfig {
        [pscustomobject]@{
            project          = 'THX'
            namingConvention = [pscustomobject]@{
                template                = '{project}-{type} [{env}]'
                environmentNameTemplate = '{project}-{type} Env'
                maxLength               = 64
                typeShortCodes          = [pscustomobject]@{ DataPrep = 'DataPrep'; Reporting = 'Report' }
                envShortCodes           = [pscustomobject]@{ DEV = 'DEV' }
            }
            environments     = @(
                [pscustomobject]@{ name = 'DEV'; shortCode = 'DEV'; capacityName = 'cap' }
            )
            workspaces       = @(
                [pscustomobject]@{ id = 'DataPrep'; type = 'DataPrep'; environment = [pscustomobject]@{ enabled = $true } }
                [pscustomobject]@{ id = 'Report';   type = 'Reporting'; environment = [pscustomobject]@{ enabled = $false } }
            )
        }
    }

    $script:deployParams = @{
        Stage            = 'DEV'
        PackageName      = 'mypackage'
        PackageVersion   = '1.4.2'
        FeedOrganisation = 'contoso'
        FeedProject      = 'Analytics'
        FeedName         = 'fabric-python'
        FeedToken        = 'tok'
    }
}

Describe 'Invoke-FabricPythonLibraryDeploy' {

    BeforeEach {
        Mock _Get-FabricAuthToken { @{ Token = 'tok'; ExpiresOn = [datetimeoffset]::UtcNow.AddHours(1) } } -ModuleName ZeroFailed.Deploy.Fabric
        Mock _Test-FabricTokenExpiry { $false } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Save-FabricLibraryPackage {
            @(
                [pscustomobject]@{ Name = 'mypackage-1.4.2-py3-none-any.whl'; FullName = '/tmp/mypackage-1.4.2-py3-none-any.whl' }
                [pscustomobject]@{ Name = 'dep-2.0-py3-none-any.whl';         FullName = '/tmp/dep-2.0-py3-none-any.whl' }
            )
        } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Test-FabricWorkspaceExists { [pscustomobject]@{ id = 'ws-1'; displayName = $DisplayName } } -ModuleName ZeroFailed.Deploy.Fabric
        Mock _Resolve-FabricEnvironment { [pscustomobject]@{ id = 'env-1'; displayName = $DisplayName } } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Get-FabricEnvironmentLibraries { @() } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Add-FabricEnvironmentLibrary { @{ Action = 'Uploaded' } } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Remove-FabricEnvironmentLibrary { @{ FileName = $LibraryName; Action = 'Removed' } } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Publish-FabricEnvironment { @{ EnvironmentId = $EnvironmentId; Action = 'Published' } } -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'deploys only to workspaces with a Spark Environment enabled' {
        $config = New-TestConfig
        $result = Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams

        $result.Summary.Deployed | Should -Be 1
        $result.Deployed[0].WorkspaceName | Should -Be 'THX-DataPrep [DEV]'
        $result.Deployed[0].EnvironmentName | Should -Be 'THX-DataPrep Env'
        Should -Invoke Publish-FabricEnvironment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'excludes a workspace whose Spark Environment is not configured for the stage' {
        $config = New-TestConfig
        # DataPrep has an environment, but only in a stage other than the one being deployed.
        $config.workspaces[0].environment | Add-Member -NotePropertyName stages -NotePropertyValue @('PROD') -Force

        $result = Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams

        $result.Summary.Deployed | Should -Be 0
        Should -Invoke Save-FabricLibraryPackage -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Publish-FabricEnvironment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'includes a workspace whose Spark Environment stages contain the deployed stage' {
        $config = New-TestConfig
        $config.workspaces[0].environment | Add-Member -NotePropertyName stages -NotePropertyValue @('DEV') -Force

        $result = Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams

        $result.Summary.Deployed | Should -Be 1
        Should -Invoke Publish-FabricEnvironment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'downloads the package only once regardless of target count' {
        $config = New-TestConfig
        # Enable the second workspace too.
        $config.workspaces[1].environment.enabled = $true

        Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams | Out-Null

        Should -Invoke Save-FabricLibraryPackage -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Publish-FabricEnvironment -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'uploads every downloaded file to the environment' {
        $config = New-TestConfig
        Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams | Out-Null
        Should -Invoke Add-FabricEnvironmentLibrary -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'passes the Fabric runtime target through to the download by default' {
        $config = New-TestConfig
        Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams | Out-Null
        Should -Invoke Save-FabricLibraryPackage -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $TargetPythonVersion -eq '3.11' -and $TargetPlatform -eq 'manylinux2014_x86_64'
        }
    }

    It 'passes an overridden runtime target through to the download' {
        $config = New-TestConfig
        Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams -TargetPythonVersion '3.10' | Out-Null
        Should -Invoke Save-FabricLibraryPackage -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $TargetPythonVersion -eq '3.10'
        }
    }

    It 'passes a constraints file through to the download' {
        $config = New-TestConfig
        $constraints = Join-Path ([System.IO.Path]::GetTempPath()) "constraints-$([guid]::NewGuid()).txt"
        Set-Content -LiteralPath $constraints -Value 'cryptography==42.0.2'

        try {
            Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams -ConstraintsPath $constraints | Out-Null
            Should -Invoke Save-FabricLibraryPackage -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
                $ConstraintsPath -eq $constraints
            }
        }
        finally {
            Remove-Item -LiteralPath $constraints -Force
        }
    }

    It 'fails before authenticating when the constraints file is missing' {
        $config = New-TestConfig
        { Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams `
            -ConstraintsPath '/does/not/exist/constraints.txt' } | Should -Throw '*Constraints file not found*'

        Should -Invoke Save-FabricLibraryPackage -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'clears down staged libraries that are not part of the desired set' {
        Mock Get-FabricEnvironmentLibraries {
            if ($Staging) { @('mypackage-1.4.1-py3-none-any.whl', 'oldDep-1.0-py3-none-any.whl') } else { @() }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $config = New-TestConfig
        $result = Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams

        $result.Deployed[0].Removed | Should -HaveCount 2
        Should -Invoke Remove-FabricEnvironmentLibrary -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Remove-FabricEnvironmentLibrary -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $LibraryName -eq 'mypackage-1.4.1-py3-none-any.whl'
        }
    }

    It 'leaves staged libraries that are part of the desired set to be overwritten' {
        Mock Get-FabricEnvironmentLibraries {
            if ($Staging) { @('mypackage-1.4.2-py3-none-any.whl', 'stale-9.9-py3-none-any.whl') } else { @() }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $config = New-TestConfig
        Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams | Out-Null

        Should -Invoke Remove-FabricEnvironmentLibrary -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $LibraryName -eq 'stale-9.9-py3-none-any.whl'
        }
        Should -Invoke Add-FabricEnvironmentLibrary -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'deploys rather than skips when a stale version is published alongside the desired files' {
        Mock Get-FabricEnvironmentLibraries {
            if ($Staging) { @() }
            else { @('mypackage-1.4.2-py3-none-any.whl', 'dep-2.0-py3-none-any.whl', 'mypackage-1.4.1-py3-none-any.whl') }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $config = New-TestConfig
        $result = Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams

        $result.Summary.Skipped | Should -Be 0
        $result.Summary.Deployed | Should -Be 1
        Should -Invoke Publish-FabricEnvironment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'skips upload and publish when all files are already published' {
        Mock Get-FabricEnvironmentLibraries {
            @('mypackage-1.4.2-py3-none-any.whl', 'dep-2.0-py3-none-any.whl')
        } -ModuleName ZeroFailed.Deploy.Fabric

        $config = New-TestConfig
        $result = Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams

        $result.Summary.Skipped | Should -Be 1
        $result.Summary.Deployed | Should -Be 0
        Should -Invoke Add-FabricEnvironmentLibrary -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Publish-FabricEnvironment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 're-publishes already-published files when -Force is set' {
        Mock Get-FabricEnvironmentLibraries {
            @('mypackage-1.4.2-py3-none-any.whl', 'dep-2.0-py3-none-any.whl')
        } -ModuleName ZeroFailed.Deploy.Fabric

        $config = New-TestConfig
        $result = Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams -Force

        $result.Summary.Deployed | Should -Be 1
        Should -Invoke Publish-FabricEnvironment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'records a non-fatal failure when the workspace does not exist' {
        Mock Test-FabricWorkspaceExists { $null } -ModuleName ZeroFailed.Deploy.Fabric

        $config = New-TestConfig
        $result = Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams -ErrorAction SilentlyContinue

        $result.Summary.Failed | Should -Be 1
        $result.Failures[0].Error | Should -BeLike '*does not exist*'
        Should -Invoke Publish-FabricEnvironment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'throws when the stage is not in the config' {
        $config = New-TestConfig
        { Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams -Stage 'NOPE' } |
            Should -Throw "*Stage 'NOPE' not found*"
    }

    It 'uses existing files under -SkipDownload without calling pip' {
        $staging = Join-Path ([System.IO.Path]::GetTempPath()) "fabskip-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $staging 'mypackage-1.4.2-py3-none-any.whl') -Value 'x'
        try {
            $config = New-TestConfig
            $result = Invoke-FabricPythonLibraryDeploy -Config $config @script:deployParams -SkipDownload -StagingPath $staging
            $result.Summary.Deployed | Should -Be 1
            Should -Invoke Save-FabricLibraryPackage -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Add-FabricEnvironmentLibrary -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }
        finally {
            Remove-Item -LiteralPath $staging -Recurse -Force
        }
    }
}
