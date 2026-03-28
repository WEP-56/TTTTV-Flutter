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
