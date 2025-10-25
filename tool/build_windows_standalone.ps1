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

try {
    Assert-Command -Name flutter

    if (-not $SkipPubGet.IsPresent) {
        Write-Host "Running flutter pub get..." -ForegroundColor Cyan
        flutter pub get
    }

    Write-Host "Building Windows $Configuration bundle..." -ForegroundColor Cyan
    flutter build windows --${Configuration.ToLower()}

    $buildOutput = Join-Path $repoRoot "build/windows/x64/runner/$Configuration"
    if (-not (Test-Path $buildOutput)) {
        throw "Expected build output at '$buildOutput' was not found. Ensure that Flutter desktop tooling is installed."
    }

    $stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("wallet_mobile_standalone_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingRoot | Out-Null
    Copy-Item -Path (Join-Path $buildOutput '*') -Destination $stagingRoot -Recurse -Force

    $entryExe = 'wallet_mobile.exe'
    if (-not (Test-Path (Join-Path $stagingRoot $entryExe))) {
        throw "Entry executable '$entryExe' was not found in staging directory."
    }

    $resolvedOutputDir = Resolve-Path $OutputDirectory -ErrorAction SilentlyContinue
    if (-not $resolvedOutputDir) {
        $resolvedOutputDir = New-Item -ItemType Directory -Path $OutputDirectory -Force
        $resolvedOutputDir = $resolvedOutputDir.FullName
    } else {
        $resolvedOutputDir = $resolvedOutputDir.Path
    }

    $targetExecutable = Join-Path $resolvedOutputDir 'wallet-mobile-standalone.exe'

    $iexpress = Join-Path $env:SystemRoot 'System32\iexpress.exe'
    if (-not (Test-Path $iexpress)) {
        throw "iexpress.exe was not found. The script must be executed on Windows where IExpress is available."
    }

    $files = Get-ChildItem -Path $stagingRoot -Recurse -File
    if ($files.Count -eq 0) {
        throw "No files found in staging directory '$stagingRoot'."
    }

    $fileOptionLines = @()
    $sourceFileLines = @()
    for ($index = 0; $index -lt $files.Count; $index++) {
        $relativePath = $files[$index].FullName.Substring($stagingRoot.Length + 1)
        $relativePath = $relativePath -replace '/', '\\'
        $fileKey = "FILE$index"
        $fileOptionLines += "$fileKey=$relativePath"
        $sourceFileLines += "$fileKey="
    }

    $sedContent = @"
[Version]
Class=IEXPRESS
SEDVersion=3

[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=0
UseLongFileName=1
WindowTitle=%WINDOW_TITLE%
FriendlyName=%WINDOW_TITLE%
AppLaunched=%ENTRY_EXE%
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
TargetName=%TARGET_PATH%
SourceFiles=SourceFiles
RebootMode=I
$($fileOptionLines -join "`n")

[Strings]
WINDOW_TITLE=Wallet Mobile Standalone
ENTRY_EXE=$entryExe
TARGET_PATH=$targetExecutable
SOURCEDIR=$stagingRoot

[SourceFiles]
SourceFiles0=%SOURCEDIR%

[SourceFiles0]
$($sourceFileLines -join "`n")
"@

    $sedPath = Join-Path $stagingRoot 'bundle.sed'
    Set-Content -Path $sedPath -Value $sedContent -Encoding ASCII

    Write-Host "Packaging standalone executable..." -ForegroundColor Cyan
    & $iexpress /N $sedPath | Write-Output

    if (-not (Test-Path $targetExecutable)) {
        throw "IExpress did not produce the expected executable at '$targetExecutable'."
    }

    Write-Host "Standalone executable created at: $targetExecutable" -ForegroundColor Green
}
finally {
    Pop-Location
    if ($stagingRoot -and (Test-Path $stagingRoot)) {
        Remove-Item -Recurse -Force $stagingRoot
    }
}
