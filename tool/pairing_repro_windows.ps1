param(
  [Parameter(Mandatory = $true)]
  [string]$WalletConnectUri,
  [string]$ProjectRoot = "$PSScriptRoot/..",
  [string]$LogPath = "$PSScriptRoot/../build/walletconnect-windows.log",
  [string]$Device = "windows",
  [switch]$NoRun
)

# Reproduction harness for WalletConnect pairing on Windows.
# Usage from PowerShell:
#   ./tool/pairing_repro_windows.ps1 -WalletConnectUri "wc:..." [-LogPath C:\temp\wc.log]
# The script sets WC_URI/WC_LOG_PATH for the Flutter app, enables
# Windows desktop support, and launches `flutter run -d windows --verbose`.

$env:WC_URI = $WalletConnectUri
$env:WC_LOG_PATH = $LogPath

Write-Host "WalletConnect URI: $WalletConnectUri"
Write-Host "Diagnostics log will be written to: $LogPath"

if ($NoRun) {
  Write-Host "NoRun specified; environment prepared. Start the app manually to consume WC_URI."
  return
}

Push-Location $ProjectRoot

flutter config --enable-windows-desktop | Out-Null
flutter pub get

Write-Host "Starting Flutter desktop app on device '$Device'..."
flutter run -d $Device --verbose

Pop-Location
