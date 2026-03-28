TTTTV flutter版本，施工中

## 启动后端：
cd Moovie
cargo build
cargo run
## 启动前端：
cd ttttv_flutter
flutter pub get
flutter run -d windows
## 当前施工落地工作计划表：
D:\TTTTV-Flutter\LIVE_DART_REFACTOR_TODO.md
## windows端打包
### 方法1：
```powershell
cd D:\TTTTV-Flutter\Moovie
cargo build --release

cd D:\TTTTV-Flutter\ttttv_flutter
flutter build windows --release

后端exe移入
Copy-Item `
  D:\TTTTV-Flutter\Moovie\target\release\moovie.exe `
  D:\TTTTV-Flutter\ttttv_flutter\build\windows\x64\runner\Release\moovie.exe `
  -Force

添加start_ttttv.bat
@echo off
cd /d %~dp0
start "" /B moovie.exe
timeout /t 2 /nobreak >nul
start "" ttttv_flutter.exe
```

### 方法二
```powershell
cd D:\TTTTV-Flutter
# 免安装绿色
./build_windows_flutter_release.ps1
# 安装包
.\build_windows_installer.ps1
```
产物通常在 ~\TTTTV-Flutter\build\installers\TTTTV-Windows-0.1.0_1-Setup.exe