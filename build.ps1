<#
.SYNOPSIS
    InvokeBuild bootstrapper for ZeroFailed.Deploy.Fabric.
.DESCRIPTION
    Downloads and bootstraps the ZeroFailed build framework, then delegates
    to Invoke-Build with the tasks defined in .zf/config.ps1.
.PARAMETER Tasks
    The build task(s) to run. Defaults to the default task defined in config.ps1.
.PARAMETER Configuration
    Build configuration (e.g. Debug, Release). Defaults to 'Release'.
.PARAMETER NuGetApiKey
    NuGet API key used when publishing the module.
#>
[CmdletBinding()]
param(
    [string[]]$Tasks = @('.'),
    [string]$Configuration = 'Release',
    [string]$NuGetApiKey
)

Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'

# Bootstrap: ensure InvokeBuild is available
if (-not (Get-Module -ListAvailable -Name InvokeBuild)) {
    Write-Host 'Installing InvokeBuild...' -ForegroundColor Cyan
    Install-Module InvokeBuild -Scope CurrentUser -Force -ErrorAction Stop
}

Import-Module InvokeBuild -ErrorAction Stop

# Bootstrap ZeroFailed framework
$zfPath = Join-Path $PSScriptRoot '.zf'
if (-not (Test-Path (Join-Path $zfPath 'ZeroFailed.tasks.ps1'))) {
    Write-Host 'Bootstrapping ZeroFailed framework...' -ForegroundColor Cyan

    $bootstrapUrl = 'https://raw.githubusercontent.com/zerofailed/ZeroFailed/main/bootstrap.ps1'
    $bootstrapScript = Join-Path ([System.IO.Path]::GetTempPath()) 'zf-bootstrap.ps1'
    Invoke-WebRequest -Uri $bootstrapUrl -OutFile $bootstrapScript -ErrorAction Stop
    & $bootstrapScript -ZfPath $zfPath
}

# Run the build
Invoke-Build -File (Join-Path $PSScriptRoot '.zf/config.ps1') -Task $Tasks `
    -Configuration $Configuration `
    -NuGetApiKey $NuGetApiKey
