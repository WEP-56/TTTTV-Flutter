$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$flutterDir = Join-Path $repoRoot 'ttttv_flutter'
$pubspecPath = Join-Path $flutterDir 'pubspec.yaml'
$apkPath = Join-Path $flutterDir 'build\app\outputs\flutter-apk\app-release.apk'
$outputDir = Join-Path $repoRoot 'build\installers'

function Get-AppVersion {
    if (-not (Test-Path $pubspecPath)) {
        return '0.1.0'
    }

    $match = Select-String -Path $pubspecPath -Pattern '^version:\s*([^\s]+)' | Select-Object -First 1
    if (-not $match) {
        return '0.1.0'
    }

    $rawVersion = $match.Matches[0].Groups[1].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($rawVersion)) {
        return '0.1.0'
    }

    return $rawVersion
}

if (-not (Test-Path $flutterDir)) {
    throw "Flutter project directory not found: $flutterDir"
}

$version = Get-AppVersion
$safeVersion = ($version -replace '[^0-9A-Za-z\.\-_+]+', '_')
$versionedApkPath = Join-Path $outputDir "TTTTV-Android-$safeVersion.apk"

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

Write-Host 'Building Android release APK with Flutter...' -ForegroundColor Green
Push-Location $flutterDir
try {
    flutter build apk --release
}
finally {
    Pop-Location
}

if (-not (Test-Path $apkPath)) {
    throw "Release APK not found: $apkPath"
}

Copy-Item $apkPath $versionedApkPath -Force

Write-Host ''
Write-Host 'Android APK build complete.' -ForegroundColor Cyan
Write-Host 'APK output:' -ForegroundColor Cyan
Write-Host "  $apkPath"
Write-Host "  $versionedApkPath"
