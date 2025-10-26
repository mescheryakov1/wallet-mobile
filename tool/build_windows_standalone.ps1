param(
    [string]$Configuration = "Release",
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\build\windows_standalone"),
    [switch]$SkipPubGet
)

set-strictmode -version Latest
$ErrorActionPreference = 'Stop'

function Assert-Command {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptRoot "..")
Push-Location $repoRoot

$iconGenerator = Join-Path $scriptRoot 'generate_windows_app_icon.ps1'
if (-not (Test-Path $iconGenerator)) {
    throw "Required script '$iconGenerator' was not found."
}

& $iconGenerator

try {
    Assert-Command -Name flutter

    if (-not $SkipPubGet.IsPresent) {
        Write-Host "Running flutter pub get..." -ForegroundColor Cyan
        flutter pub get
    }

    Write-Host "Building Windows $Configuration bundle..." -ForegroundColor Cyan
    flutter build windows --$($Configuration.ToLower())

    $buildOutput = Join-Path $repoRoot "build/windows/x64/runner/$Configuration"
    if (-not (Test-Path $buildOutput)) {
        throw "Expected build output at '$buildOutput' was not found. Ensure that Flutter desktop tooling is installed."
    }

    $entryExe = 'wallet_mobile.exe'
    $entryExePath = Join-Path $buildOutput $entryExe
    if (-not (Test-Path $entryExePath)) {
        throw "Entry executable '$entryExe' was not found in build directory."
    }

    $resolvedOutputDir = [System.IO.Path]::GetFullPath($OutputDirectory)

    if (-not (Test-Path $resolvedOutputDir)) {
        New-Item -ItemType Directory -Path $resolvedOutputDir -Force | Out-Null
    }

    Write-Host "Preparing standalone bundle directory at '$resolvedOutputDir'..." -ForegroundColor Cyan

    $existingItems = Get-ChildItem -Path $resolvedOutputDir -Force -ErrorAction SilentlyContinue
    if ($existingItems) {
        $existingItems | Remove-Item -Recurse -Force
    }

    Copy-Item -Path (Join-Path $buildOutput '*') -Destination $resolvedOutputDir -Recurse -Force

    $targetExecutable = Join-Path $resolvedOutputDir $entryExe
    Write-Host "Standalone bundle prepared. Entry executable: $targetExecutable" -ForegroundColor Green
}
finally {
    Pop-Location
}
