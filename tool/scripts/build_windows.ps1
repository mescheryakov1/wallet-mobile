[CmdletBinding()]
param(
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir '..')
Set-Location $projectRoot

flutter config --enable-windows-desktop | Out-Null
flutter pub get
flutter build windows --release @ExtraArgs
