$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$flutterDir = Join-Path $repoRoot 'ttttv_flutter'
$releaseDir = Join-Path $flutterDir 'build\windows\x64\runner\Release'
$sourceIcon = Join-Path $repoRoot 'assest\doubaoTTTTV.ico'
$runnerIcon = Join-Path $flutterDir 'windows\runner\resources\app_icon.ico'
$runnerRc = Join-Path $flutterDir 'windows\runner\Runner.rc'

if (Test-Path $sourceIcon) {
    Write-Host 'Syncing Windows app icon...' -ForegroundColor Green
    Copy-Item $sourceIcon $runnerIcon -Force

    $now = Get-Date
    (Get-Item $runnerIcon).LastWriteTime = $now
    (Get-Item $runnerRc).LastWriteTime = $now
}

Write-Host 'Building Flutter Windows release...' -ForegroundColor Green
Push-Location $flutterDir
try {
    flutter pub get
    flutter build windows --release
} finally {
    Pop-Location
}

if (-not (Test-Path $releaseDir)) {
    throw "Flutter release output not found: $releaseDir"
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Cyan
Write-Host "Distribute this directory:" -ForegroundColor Cyan
Write-Host "  $releaseDir"
