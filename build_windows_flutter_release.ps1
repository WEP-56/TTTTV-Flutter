$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$flutterDir = Join-Path $repoRoot 'ttttv_flutter'
$backendDir = Join-Path $repoRoot 'Moovie'
$releaseDir = Join-Path $flutterDir 'build\windows\x64\runner\Release'
$backendExe = Join-Path $backendDir 'target\release\moovie.exe'
$releaseBackendExe = Join-Path $releaseDir 'moovie.exe'
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

Write-Host 'Building Moovie release...' -ForegroundColor Green
Push-Location $backendDir
try {
    cargo build --release
} finally {
    Pop-Location
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

if (-not (Test-Path $backendExe)) {
    throw "Moovie release executable not found: $backendExe"
}

Write-Host 'Copying Moovie into Flutter release directory...' -ForegroundColor Green
Copy-Item $backendExe $releaseBackendExe -Force

Write-Host ''
Write-Host 'Done.' -ForegroundColor Cyan
Write-Host "Distribute this directory:" -ForegroundColor Cyan
Write-Host "  $releaseDir"
Write-Host ''
Write-Host 'Important:' -ForegroundColor Yellow
Write-Host '  ttttv_flutter.exe will now auto-start moovie.exe when both files are in the same folder.'
