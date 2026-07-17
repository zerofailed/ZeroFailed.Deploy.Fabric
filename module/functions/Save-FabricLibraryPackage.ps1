function Save-FabricLibraryPackage {
    <#
    .SYNOPSIS
        Downloads a Python package and its full dependency closure from an Azure Artifacts feed.
    .DESCRIPTION
        Runs 'pip download' against an Azure DevOps Artifacts feed to fetch the named package at the
        given version, plus every transitive dependency, into a destination directory. pip resolves
        the dependency graph from the package metadata in the feed — no dependency list is required.

        Dependencies not present in the feed are resolved from the -ExtraIndexUrl (PyPI by default),
        which relies on the feed being configured with upstream sources or the build agent having
        outbound access to PyPI.

        Wheels are resolved for the *target* Fabric Spark runtime, not for the build agent. Without
        this, pip would select wheels matching the agent's interpreter (e.g. a cp312 wheel on a
        Python 3.12 agent), and any dependency with a compiled C extension would fail to import
        inside Fabric. Fabric runtime 1.2 runs Python 3.10; runtime 1.3 runs Python 3.11.

        Because pip cannot build an sdist for a foreign platform, cross-targeting requires
        --only-binary=:all:. A dependency that publishes no wheel for the target therefore fails the
        download rather than silently shipping something unusable.

        The feed is authenticated with a bearer token / PAT embedded in the index URL as the
        password of a 'build' user. The URL is never logged. Returns the FileInfo objects for the
        downloaded wheel files, ready to hand to Add-FabricEnvironmentLibrary.
    .PARAMETER PackageName
        The package (distribution) name to download, e.g. 'mycompany.dataprep'.
    .PARAMETER PackageVersion
        The exact package version to download, e.g. '1.4.2'.
    .PARAMETER FeedOrganisation
        The Azure DevOps organisation that hosts the Artifacts feed.
    .PARAMETER FeedProject
        The Azure DevOps project that hosts the Artifacts feed.
    .PARAMETER FeedName
        The Azure Artifacts feed name.
    .PARAMETER FeedToken
        Bearer token / PAT with Feed Reader access (e.g. the pipeline's System.AccessToken).
    .PARAMETER DestinationPath
        Directory to download the packages into. Created if it does not exist.
    .PARAMETER ConstraintsPath
        Path to a pip constraints file pinning versions in the dependency closure. Supplied by the
        calling repo (like the topology config), not carried in this module. Omitted by default,
        in which case pip resolves versions itself.
    .PARAMETER ExtraIndexUrl
        Secondary package index used for dependencies not in the feed. Default: PyPI.
    .PARAMETER PythonExecutable
        The python executable to use. Default: 'python'.
    .PARAMETER TargetPythonVersion
        The Python version of the target Fabric Spark runtime that wheels are resolved for.
        Default: '3.11' (Fabric runtime 1.3). Use '3.10' for runtime 1.2.
    .PARAMETER TargetPlatform
        The platform tag wheels are resolved for. Default: 'manylinux2014_x86_64'.
        Platform-independent ('any') wheels are always eligible regardless of this value.
    .EXAMPLE
        Save-FabricLibraryPackage -PackageName 'mycompany.dataprep' -PackageVersion '1.4.2' `
            -FeedOrganisation 'contoso' -FeedProject 'Analytics' -FeedName 'fabric-python' `
            -FeedToken $env:SYSTEM_ACCESSTOKEN -DestinationPath './.artefacts'

        Downloads the wheel and all dependency wheels into ./.artefacts and returns them.
    .EXAMPLE
        Save-FabricLibraryPackage ... -TargetPythonVersion '3.10'

        Resolves wheels for Fabric Spark runtime 1.2 (Python 3.10) instead of the 1.3 default.
    .EXAMPLE
        Save-FabricLibraryPackage ... -ConstraintsPath './fabric/constraints.txt'

        Pins transitive dependency versions to those listed in the constraints file.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [string]$PackageVersion,

        [Parameter(Mandatory)]
        [string]$FeedOrganisation,

        [Parameter(Mandatory)]
        [string]$FeedProject,

        [Parameter(Mandatory)]
        [string]$FeedName,

        [Parameter(Mandatory)]
        [string]$FeedToken,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [string]$ConstraintsPath,

        [string]$ExtraIndexUrl = 'https://pypi.org/simple',

        [string]$PythonExecutable = 'python',

        [ValidatePattern('^\d+\.\d+$')]
        [string]$TargetPythonVersion = '3.11',

        [ValidateNotNullOrEmpty()]
        [string]$TargetPlatform = 'manylinux2014_x86_64'
    )

    if (-not (Test-Path -LiteralPath $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    # Fail fast on a missing constraints file. pip treats one as an error too, but only after the
    # feed round-trip, and the message doesn't say which caller supplied the path.
    if ($ConstraintsPath) {
        if (-not (Test-Path -LiteralPath $ConstraintsPath -PathType Leaf)) {
            throw "Constraints file not found: $ConstraintsPath"
        }
        # pip runs with the caller's working directory; resolve so a relative path is unambiguous.
        $ConstraintsPath = (Resolve-Path -LiteralPath $ConstraintsPath).ProviderPath
    }

    # Authenticated PyPI-format index for the Azure Artifacts feed. The token is the password of a
    # 'build' user; kept out of all logging (only the redacted host is written to verbose output).
    $feedHost  = "pkgs.dev.azure.com/$FeedOrganisation/$FeedProject/_packaging/$FeedName/pypi/simple/"
    $indexUrl  = "https://build:$FeedToken@$feedHost"

    # CPython ABI tag for the target runtime, e.g. '3.11' -> 'cp311'.
    $targetAbi = 'cp' + ($TargetPythonVersion -replace '\.', '')

    Write-Verbose "Downloading '$PackageName==$PackageVersion' (+ dependencies) from feed '$FeedName' into '$DestinationPath' (target: Python $TargetPythonVersion / $TargetPlatform)..."

    $arguments = @(
        '-m', 'pip', 'download', "$PackageName==$PackageVersion"
        '--dest', $DestinationPath
        '--index-url', $indexUrl
        '--extra-index-url', $ExtraIndexUrl
        # Resolve wheels for the target Fabric runtime rather than the build agent's interpreter.
        # --only-binary=:all: is required by pip whenever --platform/--abi/--python-version are used.
        '--only-binary', ':all:'
        '--python-version', $TargetPythonVersion
        '--implementation', 'cp'
        '--abi', $targetAbi
        '--platform', $TargetPlatform
    )

    if ($ConstraintsPath) {
        Write-Verbose "Applying pip constraints from '$ConstraintsPath'."
        $arguments += @('--constraint', $ConstraintsPath)
    }

    # Echo the exact invocation with the feed token masked. Without this, a resolution failure
    # (e.g. "Requires-Python") gives no way to tell which target pip actually resolved against.
    Write-Verbose "pip invocation: $PythonExecutable $((($arguments -join ' ') -replace [regex]::Escape($FeedToken), '***'))"

    # Out-Null guards the contract: anything pip writes must never reach this function's output,
    # which callers treat as a list of FileInfo.
    _Invoke-PipDownload -PythonExecutable $PythonExecutable -Arguments $arguments -ErrorAction Stop | Out-Null

    $files = Get-ChildItem -LiteralPath $DestinationPath -File |
        Where-Object { $_.Name -match '\.(whl|tar\.gz|zip)$' }

    if (-not $files) {
        throw "pip download completed but no package files were found in '$DestinationPath'."
    }

    Write-Verbose "Downloaded $($files.Count) file(s): $($files.Name -join ', ')"
    return $files
}
