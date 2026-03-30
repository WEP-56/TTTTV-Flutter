<p align="center">
  <img src="assest/logo.png" alt="TTTTV Logo" width="180" />
</p>

<h1 align="center">TTTTV</h1>

<p align="center">
  一款面向中文用户的影视与直播聚合播放器，兼顾桌面端沉浸体验与移动端观影效率。
</p>

<p align="center">
  影视搜索、在线播放、直播聚合、片源管理、历史记录、收藏体系、主题切换，集中在一个轻量、直接的 Flutter 客户端里。
</p>

---

## 项目简介

TTTTV 是一个以 Flutter 构建的多端客户端，目标是把常用的影视点播与直播观看能力整合到一个统一、清晰、易上手的界面中。

相比“功能很多但入口分散”的传统聚合工具，TTTTV 更强调：

- 更直接的搜索与观看路径
- 更干净的播放页和直播页体验
- 更适合长期使用的片源与缓存管理
- 更适合桌面端与 Android 端并行推进的统一代码架构

当前版本已经具备 Windows 与 Android 发布能力，并持续完善播放器体验、直播能力、设置系统与macos端、iPhone端、鸿蒙端的兼容。

## 核心亮点

- 影视点播
  - 支持片源搜索、详情解析、剧集切换、播放进度记录
- 直播聚合
  - 支持多平台直播浏览、直播间播放、弹幕能力与基础登录 Cookie 管理
- 播放器体验
  - 支持全屏切换、画面比例控制、播放记录、移动端横竖屏联动
- 片源管理
  - 支持启用、停用、健康检查、远程导入与本地维护
- 个性化设置
  - 支持主题模式、主题色、播放偏好、直播偏好、缓存策略
- 多端基础
  - Windows 桌面端与 Android 端均可构建发布

## 界面预览

### 首页

![首页](/assest/首页.png)

### 影视播放页

![影视播放页](/assest/影视播放页.png)

### 直播首页

![直播首页](/assest/直播首页.png)

### 直播播放页

![直播播放页](/assest/直播播放页.png)

### 我的页面

![我的页面](/assest/我的页面.png)

### 设置页

![设置页](/assest/设置页.png)

## 当前已实现能力

### 点播侧

- 搜索影视资源
- 查看详情与剧集列表
- 调用播放器播放
- 保存历史记录
- 收藏管理

### 直播侧

- 平台切换
- 推荐流与搜索
- 直播间播放
- 清晰度切换
- 弹幕显示与弹幕设置
- 基础 Cookie 管理与检查

### 设置侧

- 外观设置
- 播放设置
- 直播设置
- 片源策略
- 缓存策略
- 片源管理

## 技术栈

- Flutter
- Riverpod
- Dio
- media_kit
- shared_preferences
- window_manager

## 目录说明

```text
ttttv_flutter/
├─ lib/
│  ├─ app/                     应用壳与导航
│  ├─ core/                    通用模型、provider、平台适配、主题
│  ├─ features/
│  │  ├─ home/                 首页
│  │  ├─ search/               搜索
│  │  ├─ detail/               详情页
│  │  ├─ player/               点播播放器
│  │  ├─ live/                 直播能力
│  │  ├─ settings/             设置与片源管理
│  │  ├─ history/              历史记录
│  │  ├─ favorites/            收藏
│  │  └─ my/                   我的页面
│  └─ bootstrap/               桌面端 / 移动端启动入口
├─ android/                    Android 工程
├─ windows/                    Windows Runner
└─ README.md
```

## 快速开始

### 开发运行

```powershell
cd ttttv_flutter
flutter pub get
flutter run -d windows
```

### Android 调试构建

```powershell
cd ttttv_flutter
flutter build apk --debug
```

## 发布构建

项目根目录已经提供发布脚本。

### Windows 安装包

```powershell
powershell -ExecutionPolicy Bypass -File .\build_windows_installer.ps1
```

输出目录：

- `build/installers/TTTTV-Windows-<version>-Setup.exe`

### Android Release APK

```powershell
powershell -ExecutionPolicy Bypass -File .\build_android_apk.ps1
```

输出目录：

- `build/installers/TTTTV-Android-<version>.apk`

## 适用场景

- 想在桌面端快速搜索并观看影视资源
- 想在一个统一界面里切换多个直播平台
- 想自己管理片源、缓存和播放偏好
- 想在 Windows 与 Android 上保持接近一致的使用体验

## 后续方向

- 继续优化移动端播放器布局与交互
- 补齐直播的扫码、账密登录与账号相关能力（当前支持cookies登陆）
- 完善片源健康策略与自动化维护
- 提升发布流程与安装体验

## 资源仓库

[TTTTV-config](https://github.com/WEP-56/TTTTV-config)

## 免责声明

本项目仅提供公开可访问信息的聚合与播放能力，不内置影视内容，也不声明对第三方片源、直播平台或内容拥有任何权利。

请在遵守当地法律法规与相关平台服务条款的前提下使用本项目。用户应自行判断第三方内容的合法性、安全性与可用性，并自行承担使用风险。
