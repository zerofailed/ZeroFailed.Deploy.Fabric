#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    $script:deployParams = @{
        WorkspaceName    = 'THX-DataPrep [DEV]'
        EnvironmentName  = 'THX-DataPrep Env'
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
        Mock Import-FabricEnvironmentExternalLibraries { @{ EnvironmentId = $EnvironmentId; Action = 'Imported' } } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Publish-FabricEnvironment { @{ EnvironmentId = $EnvironmentId; Action = 'Published' } } -ModuleName ZeroFailed.Deploy.Fabric
        # Default: classify every downloaded package as private (feed-only), so the base cases upload
        # them all as custom libraries. Individual tests override this to exercise the public split.
        Mock _Test-PackageOnPyPI { $false } -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'deploys into the named workspace and environment' {
        $result = Invoke-FabricPythonLibraryDeploy @script:deployParams

        $result.Action | Should -Be 'Published'
        $result.WorkspaceName | Should -Be 'THX-DataPrep [DEV]'
        $result.EnvironmentName | Should -Be 'THX-DataPrep Env'
        $result.EnvironmentId | Should -Be 'env-1'
        Should -Invoke Test-FabricWorkspaceExists -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $DisplayName -eq 'THX-DataPrep [DEV]'
        }
        Should -Invoke _Resolve-FabricEnvironment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $WorkspaceId -eq 'ws-1' -and $DisplayName -eq 'THX-DataPrep Env'
        }
        Should -Invoke Save-FabricLibraryPackage -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Publish-FabricEnvironment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'uploads every downloaded file to the environment' {
        Invoke-FabricPythonLibraryDeploy @script:deployParams | Out-Null
        Should -Invoke Add-FabricEnvironmentLibrary -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'passes the Fabric runtime target through to the download by default' {
        Invoke-FabricPythonLibraryDeploy @script:deployParams | Out-Null
        Should -Invoke Save-FabricLibraryPackage -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $TargetPythonVersion -eq '3.11' -and $TargetPlatform -eq 'manylinux2014_x86_64'
        }
    }

    It 'passes an overridden runtime target through to the download' {
        Invoke-FabricPythonLibraryDeploy @script:deployParams -TargetPythonVersion '3.10' | Out-Null
        Should -Invoke Save-FabricLibraryPackage -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $TargetPythonVersion -eq '3.10'
        }
    }

    It 'passes a constraints file through to the download' {
        $constraints = Join-Path ([System.IO.Path]::GetTempPath()) "constraints-$([guid]::NewGuid()).txt"
        Set-Content -LiteralPath $constraints -Value 'cryptography==42.0.2'

        try {
            Invoke-FabricPythonLibraryDeploy @script:deployParams -ConstraintsPath $constraints | Out-Null
            Should -Invoke Save-FabricLibraryPackage -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
                $ConstraintsPath -eq $constraints
            }
        }
        finally {
            Remove-Item -LiteralPath $constraints -Force
        }
    }

    It 'fails before authenticating when the constraints file is missing' {
        { Invoke-FabricPythonLibraryDeploy @script:deployParams `
            -ConstraintsPath '/does/not/exist/constraints.txt' } | Should -Throw '*Constraints file not found*'

        Should -Invoke Save-FabricLibraryPackage -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'clears down staged libraries that are not part of the desired set' {
        Mock Get-FabricEnvironmentLibraries {
            if ($Staging) { @('mypackage-1.4.1-py3-none-any.whl', 'oldDep-1.0-py3-none-any.whl') } else { @() }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Invoke-FabricPythonLibraryDeploy @script:deployParams

        $result.Removed | Should -HaveCount 2
        Should -Invoke Remove-FabricEnvironmentLibrary -Times 2 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Remove-FabricEnvironmentLibrary -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $LibraryName -eq 'mypackage-1.4.1-py3-none-any.whl'
        }
    }

    It 'leaves staged libraries that are part of the desired set to be overwritten' {
        Mock Get-FabricEnvironmentLibraries {
            if ($Staging) { @('mypackage-1.4.2-py3-none-any.whl', 'stale-9.9-py3-none-any.whl') } else { @() }
        } -ModuleName ZeroFailed.Deploy.Fabric

        Invoke-FabricPythonLibraryDeploy @script:deployParams | Out-Null

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

        $result = Invoke-FabricPythonLibraryDeploy @script:deployParams

        $result.Action | Should -Be 'Published'
        Should -Invoke Publish-FabricEnvironment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'skips upload and publish when all files are already published' {
        Mock Get-FabricEnvironmentLibraries {
            if ($External) { @() } else { @('mypackage-1.4.2-py3-none-any.whl', 'dep-2.0-py3-none-any.whl') }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Invoke-FabricPythonLibraryDeploy @script:deployParams

        $result.Action | Should -Be 'Skipped'
        Should -Invoke Add-FabricEnvironmentLibrary -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Publish-FabricEnvironment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 're-publishes already-published files when -Force is set' {
        Mock Get-FabricEnvironmentLibraries {
            @('mypackage-1.4.2-py3-none-any.whl', 'dep-2.0-py3-none-any.whl')
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Invoke-FabricPythonLibraryDeploy @script:deployParams -Force

        $result.Action | Should -Be 'Published'
        Should -Invoke Publish-FabricEnvironment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'throws before downloading when the workspace does not exist' {
        Mock Test-FabricWorkspaceExists { $null } -ModuleName ZeroFailed.Deploy.Fabric

        { Invoke-FabricPythonLibraryDeploy @script:deployParams } |
            Should -Throw "*Workspace 'THX-DataPrep ``[DEV``]' does not exist*"

        Should -Invoke Save-FabricLibraryPackage -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Publish-FabricEnvironment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'throws before downloading when the environment does not exist in the workspace' {
        Mock _Resolve-FabricEnvironment { $null } -ModuleName ZeroFailed.Deploy.Fabric

        { Invoke-FabricPythonLibraryDeploy @script:deployParams } |
            Should -Throw "*Environment 'THX-DataPrep Env' does not exist*"

        Should -Invoke Save-FabricLibraryPackage -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Publish-FabricEnvironment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'uses existing files under -SkipDownload without calling pip' {
        $staging = Join-Path ([System.IO.Path]::GetTempPath()) "fabskip-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $staging 'mypackage-1.4.2-py3-none-any.whl') -Value 'x'
        try {
            $result = Invoke-FabricPythonLibraryDeploy @script:deployParams -SkipDownload -StagingPath $staging
            $result.Action | Should -Be 'Published'
            Should -Invoke Save-FabricLibraryPackage -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
            Should -Invoke Add-FabricEnvironmentLibrary -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        }
        finally {
            Remove-Item -LiteralPath $staging -Recurse -Force
        }
    }

    It 'uploads only private wheels as custom libraries and declares public ones in environment.yml' {
        Mock _Test-PackageOnPyPI { $Name -eq 'deltalake' } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Save-FabricLibraryPackage {
            @(
                [pscustomobject]@{ Name = 'mypackage-1.4.2-py3-none-any.whl'; FullName = '/tmp/mypackage-1.4.2-py3-none-any.whl' }
                [pscustomobject]@{ Name = 'deltalake-1.6.2-cp310-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl'; FullName = '/tmp/deltalake.whl' }
            )
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Invoke-FabricPythonLibraryDeploy @script:deployParams

        # Only the private wheel is uploaded as a custom library.
        Should -Invoke Add-FabricEnvironmentLibrary -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $FilePath -eq '/tmp/mypackage-1.4.2-py3-none-any.whl'
        }
        Should -Invoke Add-FabricEnvironmentLibrary -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $FilePath -eq '/tmp/deltalake.whl'
        }
        # The public wheel is declared in environment.yml instead.
        Should -Invoke Import-FabricEnvironmentExternalLibraries -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $EnvironmentYml -match 'deltalake==1\.6\.2'
        }
        $result.ExternalLibraries | Should -Contain 'deltalake==1.6.2'
        $result.Files | Should -Contain 'mypackage-1.4.2-py3-none-any.whl'
    }

    It 'uses -PrivatePackageName to classify without querying PyPI' {
        Mock Save-FabricLibraryPackage {
            @(
                [pscustomobject]@{ Name = 'mypackage-1.4.2-py3-none-any.whl'; FullName = '/tmp/mypackage-1.4.2-py3-none-any.whl' }
                [pscustomobject]@{ Name = 'deltalake-1.6.2-cp310-abi3-manylinux2014_x86_64.whl'; FullName = '/tmp/deltalake.whl' }
            )
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Invoke-FabricPythonLibraryDeploy @script:deployParams -PrivatePackageName 'mypackage'

        Should -Invoke _Test-PackageOnPyPI -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Add-FabricEnvironmentLibrary -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $FilePath -eq '/tmp/mypackage-1.4.2-py3-none-any.whl'
        }
        $result.ExternalLibraries | Should -Contain 'deltalake==1.6.2'
    }

    It 'skips when both the custom and external published sets already match' {
        Mock _Test-PackageOnPyPI { $Name -eq 'deltalake' } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Save-FabricLibraryPackage {
            @(
                [pscustomobject]@{ Name = 'mypackage-1.4.2-py3-none-any.whl'; FullName = '/tmp/mypackage-1.4.2-py3-none-any.whl' }
                [pscustomobject]@{ Name = 'deltalake-1.6.2-cp310-abi3-manylinux2014_x86_64.whl'; FullName = '/tmp/deltalake.whl' }
            )
        } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Get-FabricEnvironmentLibraries {
            if ($External) { @('deltalake==1.6.2') }
            elseif ($Staging) { @() }
            else { @('mypackage-1.4.2-py3-none-any.whl') }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Invoke-FabricPythonLibraryDeploy @script:deployParams

        $result.Action | Should -Be 'Skipped'
        Should -Invoke Import-FabricEnvironmentExternalLibraries -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Publish-FabricEnvironment -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'redeploys when the external set has drifted even if the custom set matches' {
        Mock _Test-PackageOnPyPI { $Name -eq 'deltalake' } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Save-FabricLibraryPackage {
            @(
                [pscustomobject]@{ Name = 'mypackage-1.4.2-py3-none-any.whl'; FullName = '/tmp/mypackage-1.4.2-py3-none-any.whl' }
                [pscustomobject]@{ Name = 'deltalake-1.6.2-cp310-abi3-manylinux2014_x86_64.whl'; FullName = '/tmp/deltalake.whl' }
            )
        } -ModuleName ZeroFailed.Deploy.Fabric
        Mock Get-FabricEnvironmentLibraries {
            if ($External) { @('deltalake==1.6.1') }   # a different version is published
            elseif ($Staging) { @() }
            else { @('mypackage-1.4.2-py3-none-any.whl') }
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Invoke-FabricPythonLibraryDeploy @script:deployParams

        $result.Action | Should -Be 'Published'
        Should -Invoke Import-FabricEnvironmentExternalLibraries -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
        Should -Invoke Publish-FabricEnvironment -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }
}
