#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Save-FabricLibraryPackage' {

    BeforeEach {
        $script:dest = Join-Path ([System.IO.Path]::GetTempPath()) "fabpkg-$([guid]::NewGuid())"
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:dest) { Remove-Item -LiteralPath $script:dest -Recurse -Force }
    }

    It 'invokes pip download with the package, version, dest and authenticated feed index' {
        Mock _Invoke-PipDownload {
            # Simulate pip populating the destination.
            Set-Content -LiteralPath (Join-Path $Arguments[($Arguments.IndexOf('--dest') + 1)] 'mypackage-1.4.2-py3-none-any.whl') -Value 'x'
            Set-Content -LiteralPath (Join-Path $Arguments[($Arguments.IndexOf('--dest') + 1)] 'dep-2.0-py3-none-any.whl') -Value 'x'
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Save-FabricLibraryPackage -PackageName 'mypackage' -PackageVersion '1.4.2' `
            -FeedOrganisation 'contoso' -FeedProject 'Analytics' -FeedName 'fabric-python' `
            -FeedToken 'secrettoken' -DestinationPath $script:dest

        $result | Should -HaveCount 2
        $result.Name | Should -Contain 'mypackage-1.4.2-py3-none-any.whl'

        Should -Invoke _Invoke-PipDownload -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            ($Arguments -contains 'download') -and
            ($Arguments -contains 'mypackage==1.4.2') -and
            ($Arguments -contains '--dest') -and
            ($Arguments -join ' ') -match 'https://build:secrettoken@pkgs.dev.azure.com/contoso/Analytics/_packaging/fabric-python/pypi/simple/'
        }
    }

    It 'resolves wheels for the target Fabric runtime, not the build agent' {
        Mock _Invoke-PipDownload {
            Set-Content -LiteralPath (Join-Path $Arguments[($Arguments.IndexOf('--dest') + 1)] 'pkg-1.0-py3-none-any.whl') -Value 'x'
        } -ModuleName ZeroFailed.Deploy.Fabric

        Save-FabricLibraryPackage -PackageName 'pkg' -PackageVersion '1.0' `
            -FeedOrganisation 'o' -FeedProject 'p' -FeedName 'f' -FeedToken 't' -DestinationPath $script:dest | Out-Null

        # Defaults target Fabric runtime 1.3 (Python 3.11) on manylinux. --only-binary=:all: is
        # mandatory whenever --platform/--abi are used.
        Should -Invoke _Invoke-PipDownload -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            ($Arguments -contains '--only-binary') -and ($Arguments -contains ':all:') -and
            ($Arguments[($Arguments.IndexOf('--python-version') + 1)] -eq '3.11') -and
            ($Arguments[($Arguments.IndexOf('--abi') + 1)] -eq 'cp311') -and
            ($Arguments[($Arguments.IndexOf('--implementation') + 1)] -eq 'cp') -and
            ($Arguments[($Arguments.IndexOf('--platform') + 1)] -eq 'manylinux2014_x86_64')
        }
    }

    It 'derives the CPython ABI tag from an overridden target python version' {
        Mock _Invoke-PipDownload {
            Set-Content -LiteralPath (Join-Path $Arguments[($Arguments.IndexOf('--dest') + 1)] 'pkg-1.0-py3-none-any.whl') -Value 'x'
        } -ModuleName ZeroFailed.Deploy.Fabric

        Save-FabricLibraryPackage -PackageName 'pkg' -PackageVersion '1.0' `
            -FeedOrganisation 'o' -FeedProject 'p' -FeedName 'f' -FeedToken 't' -DestinationPath $script:dest `
            -TargetPythonVersion '3.10' -TargetPlatform 'manylinux_2_28_x86_64' | Out-Null

        Should -Invoke _Invoke-PipDownload -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            ($Arguments[($Arguments.IndexOf('--python-version') + 1)] -eq '3.10') -and
            ($Arguments[($Arguments.IndexOf('--abi') + 1)] -eq 'cp310') -and
            ($Arguments[($Arguments.IndexOf('--platform') + 1)] -eq 'manylinux_2_28_x86_64')
        }
    }

    It 'passes a constraints file through to pip as a resolved path' {
        Mock _Invoke-PipDownload {
            Set-Content -LiteralPath (Join-Path $Arguments[($Arguments.IndexOf('--dest') + 1)] 'pkg-1.0-py3-none-any.whl') -Value 'x'
        } -ModuleName ZeroFailed.Deploy.Fabric

        $constraints = Join-Path ([System.IO.Path]::GetTempPath()) "constraints-$([guid]::NewGuid()).txt"
        Set-Content -LiteralPath $constraints -Value 'cryptography==42.0.2'

        try {
            Save-FabricLibraryPackage -PackageName 'pkg' -PackageVersion '1.0' `
                -FeedOrganisation 'o' -FeedProject 'p' -FeedName 'f' -FeedToken 't' -DestinationPath $script:dest `
                -ConstraintsPath $constraints | Out-Null

            Should -Invoke _Invoke-PipDownload -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
                $Arguments[($Arguments.IndexOf('--constraint') + 1)] -eq (Resolve-Path -LiteralPath $constraints).ProviderPath
            }
        }
        finally {
            Remove-Item -LiteralPath $constraints -Force
        }
    }

    It 'omits --constraint when no constraints file is supplied' {
        Mock _Invoke-PipDownload {
            Set-Content -LiteralPath (Join-Path $Arguments[($Arguments.IndexOf('--dest') + 1)] 'pkg-1.0-py3-none-any.whl') -Value 'x'
        } -ModuleName ZeroFailed.Deploy.Fabric

        Save-FabricLibraryPackage -PackageName 'pkg' -PackageVersion '1.0' `
            -FeedOrganisation 'o' -FeedProject 'p' -FeedName 'f' -FeedToken 't' -DestinationPath $script:dest | Out-Null

        Should -Invoke _Invoke-PipDownload -Times 1 -Exactly -ModuleName ZeroFailed.Deploy.Fabric -ParameterFilter {
            $Arguments -notcontains '--constraint'
        }
    }

    It 'throws when the constraints file does not exist' {
        Mock _Invoke-PipDownload { } -ModuleName ZeroFailed.Deploy.Fabric

        { Save-FabricLibraryPackage -PackageName 'pkg' -PackageVersion '1.0' `
            -FeedOrganisation 'o' -FeedProject 'p' -FeedName 'f' -FeedToken 't' -DestinationPath $script:dest `
            -ConstraintsPath (Join-Path $script:dest 'nope.txt') } | Should -Throw '*Constraints file not found*'

        Should -Invoke _Invoke-PipDownload -Times 0 -Exactly -ModuleName ZeroFailed.Deploy.Fabric
    }

    It 'rejects a malformed target python version' {
        { Save-FabricLibraryPackage -PackageName 'pkg' -PackageVersion '1.0' `
            -FeedOrganisation 'o' -FeedProject 'p' -FeedName 'f' -FeedToken 't' -DestinationPath $script:dest `
            -TargetPythonVersion 'py311' } | Should -Throw
    }

    It 'creates the destination directory when missing' {
        Mock _Invoke-PipDownload {
            Set-Content -LiteralPath (Join-Path $Arguments[($Arguments.IndexOf('--dest') + 1)] 'pkg-1.0-py3-none-any.whl') -Value 'x'
        } -ModuleName ZeroFailed.Deploy.Fabric

        Test-Path -LiteralPath $script:dest | Should -BeFalse
        Save-FabricLibraryPackage -PackageName 'pkg' -PackageVersion '1.0' `
            -FeedOrganisation 'o' -FeedProject 'p' -FeedName 'f' -FeedToken 't' -DestinationPath $script:dest | Out-Null
        Test-Path -LiteralPath $script:dest | Should -BeTrue
    }

    It 'returns only FileInfo objects even if the pip shim leaks output' {
        # Regression: pip's 'Collecting ...' stdout used to reach the success stream, so callers
        # received Strings whose .FullName was empty ("Cannot bind argument to parameter FilePath").
        Mock _Invoke-PipDownload {
            Write-Output 'Collecting edap-data-validation'
            Write-Output 'Saved ./edap.whl'
            Set-Content -LiteralPath (Join-Path $Arguments[($Arguments.IndexOf('--dest') + 1)] 'edap-0.1.23-py3-none-any.whl') -Value 'x'
        } -ModuleName ZeroFailed.Deploy.Fabric

        $result = Save-FabricLibraryPackage -PackageName 'edap' -PackageVersion '0.1.23' `
            -FeedOrganisation 'o' -FeedProject 'p' -FeedName 'f' -FeedToken 't' -DestinationPath $script:dest

        @($result) | Should -HaveCount 1
        @($result)[0] | Should -BeOfType [System.IO.FileInfo]
        @($result)[0].FullName | Should -Not -BeNullOrEmpty
        @($result).FullName | ForEach-Object { $_ | Should -Not -BeNullOrEmpty }
    }

    It 'throws when pip produces no package files' {
        Mock _Invoke-PipDownload { } -ModuleName ZeroFailed.Deploy.Fabric

        { Save-FabricLibraryPackage -PackageName 'pkg' -PackageVersion '1.0' `
            -FeedOrganisation 'o' -FeedProject 'p' -FeedName 'f' -FeedToken 't' -DestinationPath $script:dest } |
            Should -Throw '*no package files were found*'
    }

    It 'propagates a pip failure' {
        Mock _Invoke-PipDownload { throw 'pip download failed with exit code 1.' } -ModuleName ZeroFailed.Deploy.Fabric

        { Save-FabricLibraryPackage -PackageName 'pkg' -PackageVersion '1.0' `
            -FeedOrganisation 'o' -FeedProject 'p' -FeedName 'f' -FeedToken 't' -DestinationPath $script:dest } |
            Should -Throw '*pip download failed*'
    }
}
