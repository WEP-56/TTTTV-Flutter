<p align="center">
  <img src="../assest/logo.png" alt="TTTTV Logo" width="160" />
</p>

<h1 align="center">TTTTV Flutter 工程</h1>

<p align="center">
  这是 TTTTV 客户端的 Flutter 工程目录，本文档面向需要参与开发或二次开发的同学。
  如果只是想了解项目能力或下载体验，请回到
  <a href="../README.md">仓库根 README</a>。
</p>

---

## 目录

- [本机环境](#本机环境)
- [整体架构一图流](#整体架构一图流)
- [目录结构](#目录结构)
  - [`lib/main.dart` 与 bootstrap](#libmaindart-与-bootstrap)
  - [`lib/app/` —— 应用壳](#libapp--应用壳)
  - [`lib/core/` —— 共用基础设施](#libcore--共用基础设施)
  - [`lib/features/` —— 业务功能](#libfeatures--业务功能)
- [关键模块速览](#关键模块速览)
  - [搜索（`features/search`）](#搜索featuressearch)
  - [详情（`features/detail`）](#详情featuresdetail)
  - [播放（`features/play` + `features/player`）](#播放featuresplay--featuresplayer)
  - [片源管理（`features/settings`）](#片源管理featuressettings)
  - [设置 / 历史 / 收藏](#设置--历史--收藏)
- [状态管理约定](#状态管理约定)
- [数据流：从首页搜索到点击播放](#数据流从首页搜索到点击播放)
- [HLS 本地代理是怎么工作的](#hls-本地代理是怎么工作的)
- [常见开发任务](#常见开发任务)
- [打包发布](#打包发布)
- [代码规范与风格](#代码规范与风格)

---

## 本机环境

| 项 | 版本 / 说明 |
| --- | --- |
| Flutter SDK | `>=3.5.0 <4.0.0`（见 `pubspec.yaml`） |
| Dart | 跟随 Flutter |
| 桌面构建 | Windows（已验证），未来可扩展 macOS / Linux |
| 移动构建 | Android (`compileSdk` 跟随 `flutter.compileSdkVersion`) |
| 必备工具 | Android SDK / NDK（移动构建）、Inno Setup 6（Windows 打包脚本） |

第一次拿到工程：

```powershell
cd ttttv_flutter
flutter pub get
flutter doctor                # 检查环境
flutter run -d windows        # 桌面端
flutter run -d <android-id>   # 真机或模拟器
```

## 整体架构一图流

```text
                 ┌─────────────────────────────────────────┐
                 │         lib/main.dart                   │
                 │     ↓ 选择平台 bootstrap                │
                 └─────────────────────────────────────────┘
                                │
       ┌──────────── desktop_app_bootstrap ────────────┐
       │            mobile_app_bootstrap               │
       └────────────────────────────────────────────────┘
                                │
                 ┌─────────────────────────────────────────┐
                 │           ProviderScope                 │
                 │   (Riverpod 全局状态 / 依赖注入)         │
                 └─────────────────────────────────────────┘
                                │
                 ┌─────────────────────────────────────────┐
                 │      app/TtttvApp + app/AppShell        │
                 │   主题、平台壳、Tab 切换、退出维护       │
                 └─────────────────────────────────────────┘
                                │
   ┌────────────┬────────────┬────────────┬────────────┬────────────┐
   ▼            ▼            ▼            ▼            ▼            ▼
 features/   features/   features/   features/   features/   features/
  home       search      detail      player      settings    favorites
                                     ▲ play          + sources    + history
                                     │                + my
                                     └─ 通过 PlayResult 喂给 player_page
```

每个 feature 内部按"洋葱皮"分层：`presentation` → `application` → `domain` → `data`，下文展开。

## 目录结构

```text
ttttv_flutter/
├─ lib/
│  ├─ main.dart                 入口 → bootstrapApp()
│  ├─ app/                      应用壳与导航
│  │  ├─ app.dart               TtttvApp（MaterialApp + 主题）
│  │  └─ app_shell.dart         桌面侧边栏 / 移动底部栏 + 自定义标题栏
│  ├─ bootstrap/                平台启动差异
│  │  ├─ app_bootstrap.dart     根据平台分发
│  │  ├─ desktop_app_bootstrap.dart   窗口尺寸持久化、media_kit 初始化
│  │  └─ mobile_app_bootstrap.dart    media_kit 初始化
│  ├─ core/                     跨 feature 复用
│  │  ├─ providers.dart         所有顶层 Riverpod provider
│  │  ├─ models/vod_models.dart 全局数据模型（VodItem、PlayResult ...）
│  │  ├─ network/               HTTP 异常 / 响应包装
│  │  ├─ platform/              平台窗口、网络权限提示
│  │  └─ theme/                 主题与配色
│  └─ features/                 业务功能
│     ├─ home/                  首页
│     ├─ search/                影视搜索
│     ├─ detail/                影视详情
│     ├─ play/                  播放数据层（解析 vod_play_url + HLS 代理）
│     ├─ player/                播放器 UI（视频面、控件、选集抽屉、手势）
│     ├─ settings/              设置 + 片源管理（包含主题、缓存、片源 CRUD）
│     ├─ sources/               片源管理 UI 入口
│     ├─ history/               观看历史
│     ├─ favorites/             收藏
│     └─ my/                    "我的"页面
├─ assets/vod/sources.json      默认片源种子（用户首次启动时写入 prefs）
├─ android/, windows/           平台原生工程
├─ analysis_options.yaml        lint 规则
└─ pubspec.yaml
```

### `lib/main.dart` 与 bootstrap

`main.dart` 只有一行：调用 `bootstrapApp()`。`bootstrap/` 根据 `defaultTargetPlatform` 选择桌面或移动入口：

- **桌面**：`window_manager.ensureInitialized()` → 恢复上次窗口尺寸 → `MediaKit.ensureInitialized()` → `runApp()`，并挂上 `_WindowPersistenceScope` 持续保存窗口尺寸到 `SharedPreferences`
- **移动**：仅初始化 `MediaKit` 后 `runApp()`

平台特性放在 bootstrap 而不是壳里，目的是壳层 (`app/`) 只关心 UI，不需要感知"这是桌面"。

### `lib/app/` —— 应用壳

- `app.dart`：薄薄一层 `MaterialApp`，主题来自 `themeProvider`
- `app_shell.dart`：
  - 桌面：自定义标题栏 + `NavigationRail` 侧边栏 + 圆角主内容区
  - 移动：`NavigationBar` 底部栏
  - 通过 `_Section` 枚举管理页面切换
  - 启动 / 退出时执行 `_runStartupMaintenance` / `_runExitMaintenance`，触发缓存自动清理策略

### `lib/core/` —— 共用基础设施

- **`providers.dart`**：整个工程的 provider 都在这一个文件里集中声明（`nativeVodDioProvider` / `searchControllerProvider` / `playRepositoryProvider` ...），feature 内部只暴露 `Repository` / `Controller` 类，由这里按需注入
- **`models/vod_models.dart`**：跨层的数据契约（`VodItem`、`PlaySource`、`PlayEpisode`、`WatchHistoryItem` ...），所有 feature 用同一份
- **`platform/platform_window.dart`**：`isDesktopPlatform` / `setPlatformFullscreen()` / `startPlatformWindowDrag()` 等平台抽象，UI 层不直接调 `window_manager`

### `lib/features/` —— 业务功能

每个 feature 沿用相同的分层：

```
feature/
├─ data/           网络 / 本地存储 / 解析逻辑
├─ domain/         接口契约（abstract class、入参出参 model）
├─ application/    StateNotifier / Controller，编排状态
└─ presentation/   Widget，无业务逻辑
```

不是每个 feature 都四层都有，简单功能（如 `my/`、`favorites/`）只保留必要层即可。但**层与层之间方向固定**：`presentation → application → domain ← data`，data 实现 domain 接口。

## 关键模块速览

### 搜索（`features/search`）

- `domain/search_repository.dart`
  - `SearchRepository` 抽象：`search(keyword, onBatch)` / `cancelSearch()` / `getDetail(...)`
  - `OnSourceBatch` 流式回调，每个站点完成后立刻推回
- `data/native_source_crawler.dart`
  - 调用单个站点的 apple cms `?ac=videolist` 接口，解析返回结构
  - 自动从 `vod_content` 内提取 m3u8 兜底
  - 支持自定义 detail 页（HTML 解析模式）
- `data/native_search_repository.dart`
  - 调度多站点并发搜索：page 1 → 看 `pagecount` → 按需分页（最多 5 页）
  - 失败结果（timeout / 4xx / 5xx / 解析错误）写入短 TTL 负缓存
  - `CancelToken` 真正中止 dio 请求，搜索切换不堆积连接
- `data/search_cache.dart`
  - LRU + TTL，区分成功（10 分钟）与失败（2 分钟）
- `application/search_controller.dart`
  - `StateNotifier<SearchState>`，维护 `query / results / isLoading / error / history`
  - 搜索历史用 `SharedPreferences` 持久化

### 详情（`features/detail`）

- `presentation/detail_page.dart`
  - 顶部封面 + 元信息 → 操作行（继续观看 / 从头播放 / 禁用此源） → 简介 → 演职员 → 各播放源剧集网格
  - 加载详情时同时拉历史，决定"继续观看"按钮
- 详情数据走 `searchRepositoryProvider.getDetail()`，播放链接经过 `playRepositoryProvider.parsePlayUrl()` 转为 `PlayResult`，再喂给 `PlayerPage`

### 播放（`features/play` + `features/player`）

`features/play/` 是播放**数据层**：

- `domain/play_repository.dart`
- `data/native_play_repository.dart`：把站点返回的 `vod_play_url` 拆成 `PlayResult { sources[].episodes[] }`，并为每个 m3u8 episode 生成本地代理地址
- `data/local_media_proxy.dart`：本地 HLS 代理（详见后文专题）

`features/player/` 是播放**视图层**：

- `presentation/player_page.dart`
  - 单舞台布局：视频铺满、控件叠加、抽屉从右滑入
  - 桌面键盘快捷键：`Space` 播放暂停、`F/F11` 全屏、`←/→` ±10s、`↑/↓` ±5% 音量、`PgUp/PgDn` 切集、`M` 切换抽屉、`Esc` 退出全屏 / 关闭抽屉
  - 移动端进入页面自动横屏 + 沉浸式
- `presentation/widgets/player_video_surface.dart`：视频面 + 加载 / 错误态
- `presentation/widgets/player_controls_overlay.dart`：顶栏 + 底部 dock + ⋮ 弹出"更多"底部表单
- `presentation/widgets/player_episode_panel.dart`：选集 / 线路抽屉，自动滚动到当前集
- `presentation/widgets/player_gesture_layer.dart`：移动端触摸手势
  - 单击：切换控件
  - 双击：左 -10s / 中暂停 / 右 +10s
  - 长按：临时 2× 倍速
  - 水平拖动：seek 预览
  - 垂直拖动右半屏：调节音量

### 片源管理（`features/settings`）

- `domain/sources_repository.dart`：抽象 CRUD + 健康检查
- `data/local_sources_store.dart`：基于 `SharedPreferences` 的本地存储；首次启动从 `assets/vod/sources.json` 种子化；支持远程索引拉取
- `presentation/`：设置页（外观、播放、缓存、片源管理 UI）

### 设置 / 历史 / 收藏

- `settings/`：除了片源还包括应用级设置（`AppSettings`、`appSettingsStoreProvider`）和缓存管理（`StorageManager`）
- `history/data/local_history_repository.dart`：观看历史，按 `vodId + sourceKey` 去重
- `favorites/data/local_favorites_repository.dart`：收藏

## 状态管理约定

- **统一在 `core/providers.dart` 注册** —— 找不到一个 provider 时第一站去这里
- **数据层用 `Provider`**（`Repository` / `Crawler` 等无状态依赖）
- **可变状态用 `StateNotifierProvider`**（`searchControllerProvider` / `appSettingsProvider`）
- **异步只读数据用 `FutureProvider`**（`historyItemsProvider` / `cacheUsageProvider`）
- **跨页临时通信用 `StateProvider`**（`pendingSearchProvider`，比如首页点搜索按钮把关键词推给搜索页）

## 数据流：从首页搜索到点击播放

1. 用户在搜索页输入关键词 → `searchControllerProvider.notifier.search(query)`
2. `SearchController` 调用 `SearchRepository.search()`，传入流式回调
3. `NativeSearchRepository` 取消上次的 `CancelToken`，加载 `LocalSourcesStore` 的启用站点
4. 每个启用站点：先查 `SearchCache`，未命中则 `NativeSourceCrawler.search(page=1)`
5. 拿到 `pagecount > 1` 的站才并发请求 page 2-5；任何错误写短 TTL 负缓存
6. 每个站点完成 → `onBatch` 推一批 `VodItem` 给 UI 实时渲染
7. 用户点结果 → `DetailPage`：`SearchRepository.getDetail()` + `PlayRepository.parsePlayUrl()` → 拿到 `PlayResult`
8. 用户点剧集 → `Navigator.push(PlayerPage(detail, playResult, ...))`
9. `PlayerPage` 拿 `playResult.sources[i].episodes[j].effectiveUrl`，在 media_kit 中打开播放
10. 后台异步把"继续观看"位置写入 `LocalHistoryRepository`

## HLS 本地代理是怎么工作的

`features/play/data/local_media_proxy.dart` 在内部跑一个 loopback `HttpServer`，将原始 m3u8 包装为 `http://127.0.0.1:<port>/proxy/m3u8?url=...&headers=...` 暴露给 media_kit。

- 启动单例 `HttpClient`：`maxConnectionsPerHost=8` / `idleTimeout=30s` / `autoUncompress=true`，所有 segment 请求复用 socket
- m3u8 内的 segment / key URI 会被改写为同一个本地代理 URL（保留原 referer / origin headers）
- playlist 缓存键 = `md5(url + headers)`，**只缓存包含 `#EXT-X-ENDLIST` 的点播**，直播 0 缓存
- segment / key 用流式转发；客户端断开时立即取消 subscription，HttpClient 归还连接，避免 socket 堆积
- 上游 `Content-Encoding` 不为空时不透传 `Content-Length`，防止 mediakit 等不到正确字节数永久缓冲

进入播放器一卡就找代理日志；体感"突然卡住一下又恢复" 90% 是这一层的事。

## 常见开发任务

### 加一个新的 feature

1. 在 `lib/features/` 新建目录，按 `data / domain / application / presentation` 分层
2. 在 `core/providers.dart` 注册需要的 provider
3. 如果要进主导航，在 `app/app_shell.dart` 的 `_Section` 枚举里加一项，并在 `_pages` 里挂上页面

### 加一个全局设置项

1. 在 `features/settings/domain/app_settings.dart` 给 `AppSettings` 加字段 + `copyWith`
2. 在 `features/settings/data/local_app_settings_store.dart` 处理序列化
3. 在 `features/settings/application/app_settings_notifier.dart` 暴露 setter
4. 在 `presentation/settings_page.dart` 添加 UI

### 加一个站点解析的特殊处理

`NativeSourceCrawler._handleHtmlDetail` 已经基于 `source.key` 做过定制（`ffzy` 的 m3u8 模式）。仿照写一个分支即可。

### 调试播放问题

- 把 `local_media_proxy.dart` 的 `_proxyPlaylist` / `_proxyBinary` 加临时日志，能看到上游响应码 / 缓存命中
- 直接用浏览器或 `curl` 访问 `http://127.0.0.1:<port>/proxy/m3u8?url=...` 看代理是否健康
- 注意 m3u8 是动态 / 静态：直播流没有 `#EXT-X-ENDLIST`，缓存逻辑会绕过

### 调试搜索性能

- 看 `SearchCache` 命中率：在 `get` / `set` 加日志
- 看每个站点是否都进了 `_searchSource` 且尊重 `pageCount`
- 用 `dio` 的拦截器临时打印 URL + 耗时

## 打包发布

仓库根目录有两个 PowerShell 脚本，统一输出到 `<repo>/build/installers/`。

```powershell
# 在仓库根目录执行
powershell -ExecutionPolicy Bypass -File .\build_windows_installer.ps1
powershell -ExecutionPolicy Bypass -File .\build_android_apk.ps1
```

详见 [仓库根 README 的发布构建章节](../README.md#发布构建)。

> Android 签名密钥：`android/app/ttttv.jks`（已 gitignore）。版本号统一从 `pubspec.yaml` 的 `version:` 行读取，文件名里的版本号也据此生成。

## 代码规范与风格

- 遵循 `analysis_options.yaml` 的 lints；提交前 `flutter analyze` 必须 clean
- 中文注释 OK，但**类型 / 函数命名一律英文**
- 异步流程显式 `unawaited(...)` 标注 fire-and-forget
- UI 组件优先 `StatelessWidget`，需要状态时再升级到 `ConsumerStatefulWidget`
- 不在 `presentation/` 直接持有 `Dio` / `HttpClient`，必须通过 provider 注入

如果还有不顺手的地方，欢迎在 issue / PR 里提。
