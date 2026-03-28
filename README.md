# TTTTV Flutter

<p align="center">
  <img src="assest/logo.png" width="112" alt="TTTTV Logo" />
</p>


<p align="center">
  Windows 优先的影视、直播搜索与观看项目。<br />
  当前阶段以功能稳定、桌面体验调优和小问题修复为主。
</p>

## 项目结构

- `ttttv_flutter`：Flutter Windows 客户端
- `Moovie`：影视模块后端服务
- `build_windows_flutter_release.ps1`：绿色版打包脚本
- `build_windows_installer.ps1`：Windows 安装包打包脚本

## 本地运行

### 1. 启动后端

```powershell
cd D:\TTTTV-Flutter\Moovie
cargo build
cargo run
```

### 2. 启动前端

```powershell
cd D:\TTTTV-Flutter\ttttv_flutter
flutter pub get
flutter run -d windows
```

## Windows 打包
打包前需做：
前往ttttv_flutter\pubspec.yaml
修改版本号

### 方法 1：手动打包

```powershell
cd ~\TTTTV-Flutter\Moovie
cargo build --release

cd ~\TTTTV-Flutter\ttttv_flutter
flutter build windows --release

Copy-Item 
  `~\TTTTV-Flutter\Moovie\target\release\moovie.exe`
  `~\TTTTV-Flutter\ttttv_flutter\build\windows\x64\runner\Release\moovie.exe `
  -Force
```

如果你需要绿色启动脚本，可以在发布目录内补一个 `start_ttttv.bat`：

```bat
@echo off
cd /d %~dp0
start "" /B moovie.exe
timeout /t 2 /nobreak >nul
start "" ttttv_flutter.exe
```

### 方法 2：使用仓库脚本

```powershell
cd ~\TTTTV-Flutter

# 绿色版
.\build_windows_flutter_release.ps1

# 安装包
.\build_windows_installer.ps1
```

安装包产物通常位于：

```text
~\TTTTV-Flutter\build\installers\TTTTV-Windows-0.1.0_1-Setup.exe
```

## 开发说明

- 直播模块已接入多个平台，并持续针对移动端等其他设备体验做调优和发布。




## 致谢

感谢社区 [linux.do](https://linux.do/) 的支持。

## License
MIT