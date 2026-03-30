$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$flutterDir = Join-Path $repoRoot 'ttttv_flutter'
$releaseBuilder = Join-Path $repoRoot 'build_windows_flutter_release.ps1'
$releaseDir = Join-Path $flutterDir 'build\windows\x64\runner\Release'
$installerBuildDir = Join-Path $repoRoot 'build\installer'
$issPath = Join-Path $installerBuildDir 'ttttv_flutter.iss'
$outputDir = Join-Path $repoRoot 'build\installers'
$pubspecPath = Join-Path $flutterDir 'pubspec.yaml'
$iconPath = Join-Path $flutterDir 'windows\runner\resources\app_icon.ico'

function Get-InnoCompiler {
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe',
        'C:\Program Files (x86)\Inno Setup 5\ISCC.exe',
        'C:\Program Files\Inno Setup 5\ISCC.exe'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

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

if (-not (Test-Path $releaseBuilder)) {
    throw "Release builder script not found: $releaseBuilder"
}

$iscc = Get-InnoCompiler
if (-not $iscc) {
    throw @"
Inno Setup compiler was not found.
Install Inno Setup 6 first, then rerun this script.
Download: https://jrsoftware.org/isinfo.php
"@
}

Write-Host 'Building release payload first...' -ForegroundColor Green
& $releaseBuilder

if (-not (Test-Path $releaseDir)) {
    throw "Release directory not found: $releaseDir"
}

$appExe = Join-Path $releaseDir 'ttttv_flutter.exe'
if (-not (Test-Path $appExe)) {
    throw "Flutter executable not found: $appExe"
}

$version = Get-AppVersion
$safeVersion = ($version -replace '[^0-9A-Za-z\.\-_]+', '_')

New-Item -ItemType Directory -Force -Path $installerBuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$appId = '{{9C9B5EF0-9D57-46A6-AF6A-4FD6F21D9A30}'
$appName = 'TTTTV'
$publisher = 'TTTTV'

$issContent = @"
[Setup]
AppId=$appId
AppName=$appName
AppVersion=$version
AppPublisher=$publisher
DefaultDirName={localappdata}\Programs\$appName
DefaultGroupName=$appName
AllowNoIcons=yes
OutputDir=$outputDir
OutputBaseFilename=TTTTV-Windows-$safeVersion-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
SetupIconFile=$iconPath
UninstallDisplayIcon={app}\ttttv_flutter.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "$releaseDir\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\$appName"; Filename: "{app}\ttttv_flutter.exe"; IconFilename: "{app}\ttttv_flutter.exe"
Name: "{autodesktop}\$appName"; Filename: "{app}\ttttv_flutter.exe"; Tasks: desktopicon; IconFilename: "{app}\ttttv_flutter.exe"

[Run]
Filename: "{app}\ttttv_flutter.exe"; Description: "Launch $appName"; Flags: nowait postinstall skipifsilent
"@

Set-Content -Path $issPath -Value $issContent -Encoding UTF8

Write-Host 'Building installer with Inno Setup...' -ForegroundColor Green
& $iscc $issPath

Write-Host ''
Write-Host 'Installer build complete.' -ForegroundColor Cyan
Write-Host "Installer output:" -ForegroundColor Cyan
Write-Host "  $outputDir"
