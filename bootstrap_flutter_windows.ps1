$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$flutterDir = Join-Path $repoRoot 'ttttv_flutter'

if (-not (Test-Path $flutterDir)) {
    throw "Flutter workspace not found: $flutterDir"
}

$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCommand) {
    throw 'flutter was not found in PATH. Install Flutter and reopen the shell before running this script.'
}

Push-Location $flutterDir
try {
    if (-not (Test-Path (Join-Path $flutterDir 'windows'))) {
        flutter create . --platforms=windows
    }

    flutter pub get

    Write-Host ''
    Write-Host 'Flutter workspace is ready.'
    Write-Host 'Next steps:'
    Write-Host '1. Start the Rust backend from .\Moovie'
    Write-Host '2. Run: flutter run -d windows'
} finally {
    Pop-Location
}
