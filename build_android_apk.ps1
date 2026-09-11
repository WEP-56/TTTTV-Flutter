$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$flutterDir = Join-Path $repoRoot 'ttttv_flutter'
$pubspecPath = Join-Path $flutterDir 'pubspec.yaml'
$apkOutputDir = Join-Path $flutterDir 'build\app\outputs\flutter-apk'
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

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

Write-Host 'Building Android release APKs with Flutter...' -ForegroundColor Green
Push-Location $flutterDir
try {
    flutter build apk --release --split-per-abi
}
finally {
    Pop-Location
}

$apkFiles = @(
    @{ Abi = 'arm64-v8a'; Source = Join-Path $apkOutputDir 'app-arm64-v8a-release.apk' },
    @{ Abi = 'armeabi-v7a'; Source = Join-Path $apkOutputDir 'app-armeabi-v7a-release.apk' },
    @{ Abi = 'x86_64'; Source = Join-Path $apkOutputDir 'app-x86_64-release.apk' }
)

$copiedApks = @()
foreach ($apk in $apkFiles) {
    if (-not (Test-Path $apk.Source)) {
        throw "Release APK not found: $($apk.Source)"
    }

    $destination = Join-Path $outputDir "TTTTV-Android-$safeVersion-$($apk.Abi).apk"
    Copy-Item $apk.Source $destination -Force
    $copiedApks += $destination
}

Write-Host ''
Write-Host 'Android split APK build complete.' -ForegroundColor Cyan
Write-Host 'APK outputs:' -ForegroundColor Cyan
foreach ($apk in $apkFiles) {
    Write-Host "  $($apk.Source)"
}
foreach ($path in $copiedApks) {
    Write-Host "  $path"
}
