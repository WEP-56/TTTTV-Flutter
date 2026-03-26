# Enable strict error handling
$ErrorActionPreference = "Stop"

# 1. Build Backend
Write-Host "Building Backend..." -ForegroundColor Green
Set-Location "$PSScriptRoot\Moovie"
cargo build --release
if ($LASTEXITCODE -ne 0) { 
    Write-Error "Backend build failed"
    exit 1 
}

# 2. Prepare Sidecar
Write-Host "Preparing Sidecar..." -ForegroundColor Green
$target = "x86_64-pc-windows-msvc"
# Tauri expects binaries in src-tauri root by default
$binDir = "$PSScriptRoot\moovie-front\src-tauri"

# Copy and rename binary for Tauri sidecar
# Backend crate name is now "moovie", so binary is "moovie.exe"
Copy-Item "$PSScriptRoot\Moovie\target\release\moovie.exe" "$binDir\moovie-$target.exe" -Force

# 3. Build Frontend
Write-Host "Building Frontend..." -ForegroundColor Green
Set-Location "$PSScriptRoot\moovie-front"

# Ensure dependencies are installed
if (-not (Test-Path "node_modules")) {
    npm install
}

# Set GitHub mirror for Tauri bundler tools (NSIS, etc.) to avoid timeout in China
$env:TAURI_BUNDLER_TOOLS_GITHUB_MIRROR_TEMPLATE = "https://ghproxy.net/https://github.com/<owner>/<repo>/releases/download/<version>/<asset>"

# Build Tauri app
# npm run tauri build
# Using npm run to ensure local tauri cli and scripts are used
npm run tauri build

Write-Host "Build Complete! Installer is in moovie-front/src-tauri/target/release/bundle/nsis" -ForegroundColor Cyan
