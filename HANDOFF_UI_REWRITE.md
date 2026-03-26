# UI 重写接手文档

> 生成时间：2026-03-26
> 会话目标：美化 Flutter 前端，参考 Kazumi 项目风格，实现沉静简洁 + 多配色方案

---

## 已完成

### 播放器修复
- `video_player`（不支持 Windows）已替换为 `media_kit` + `media_kit_video` + `media_kit_libs_windows_video`
- `pubspec.yaml` 已添加三个 media_kit 依赖
- `main.dart` 已添加 `MediaKit.ensureInitialized()`
- `player_page.dart` 已重写，使用 `Player` + `VideoController` + `Video` widget

### 主题系统
- `lib/core/theme/app_theme.dart` 已重写
  - `ThemeState` + `ThemeNotifier`（Riverpod `NotifierProvider`）
  - 支持 seed color 动态切换，持久化到 `SharedPreferences`（key: `theme_seed_color`）
  - `ThemeMode.system`（跟随系统深浅色）
  - `kAccentPresets`：6 套预设主题色（默认紫/深海蓝/松绿/暖红/橙金/石墨）
  - 注意：用了 `color.toARGB32()`，需要 Flutter SDK >= 3.27

### App 入口
- `lib/app/app.dart`：`TtttvApp` 改为 `ConsumerWidget`，读 `themeProvider`，`ThemeMode.system`

### Shell 布局
- `lib/app/app_shell.dart` 全部重写
  - 顶部自定义标题栏（36px，可拖动，最小化/最大化/关闭按钮，关闭悬停变红）
  - 左侧 `NavigationRail`（固定，Windows 优先）
  - 4 个导航项：首页 / 搜索 / 我的 / 设置
  - 右侧内容区：`ClipRRect` 圆角 + `Material` surface 背景
  - 保留后端健康检查 banner

### 窗口管理
- 添加 `window_manager: ^0.4.3` 依赖
- `main.dart` 初始化：
  - `TitleBarStyle.hidden`（隐藏系统边框）
  - 最小窗口尺寸 900×600
  - 初始尺寸 1280×720

### 新页面
| 文件 | 状态 |
|------|------|
| `lib/features/home/presentation/home_page.dart` | ✅ 完成 |
| `lib/features/my/presentation/my_page.dart` | ✅ 完成 |
| `lib/features/settings/presentation/settings_page.dart` | ✅ 完成 |
| `lib/features/search/presentation/search_page.dart` | ✅ 重写完成 |
| `lib/features/detail/presentation/detail_page.dart` | ✅ 补完 |
| `lib/features/player/presentation/player_page.dart` | ✅ 重写完成 |

### 首页 (home_page.dart)
- 豆瓣热映轮播（`PageController`，`AnimatedScale`，渐变遮罩，评分角标）
- 热门电影 / 热门剧集 `SliverGrid`（`maxCrossAxisExtent: 140`）
- 依赖 `doubanChartProvider` / `doubanMoviesProvider` / `doubanTvProvider`
- **点击轮播/网格卡片** → 写入 `pendingSearchProvider` → 自动跳转搜索页并触发搜索
- `_HotCarousel` 是 `ConsumerStatefulWidget`（需要 ref 触发搜索）

### 我的 (my_page.dart)
- `TabController` 两栏：观看历史 / 我的收藏
- 卡片式网格，点击进入详情页
- **注意**：`DetailPage` 构造器参数是 `initialItem:`，不是 `item:`

### 设置 (settings_page.dart)
- 主题色圆形选色器（6 个预设，选中有描边 + 光晕）
- 片源管理入口（push 到 `SourcesPage`）

### 搜索页 (search_page.dart)
- Material 3 `SearchBar` 组件
- 结果改为卡片网格（`maxCrossAxisExtent: 150`，封面 + 标题 + 备注）
- 空状态：显示历史 chip 或引导图标
- `ref.listen(pendingSearchProvider, ...)` 监听首页跳转，自动填充并搜索后清空 provider

### 详情页 (detail_page.dart)
- `SliverAppBar` expandedHeight=280，pinned，blurred cover 背景
- 封面左下角显示 poster 缩略图（90×130），右侧显示年份/地区/类型/备注标签
- AppBar actions：收藏按钮
- `_ActionRow`：继续观看 / 立即播放 / 从头播放
- `_ExpandableText`：简介折叠展开
- `_MetaChips`：导演/演员 Chip
- `_buildSourceSlivers`：集数 FilledButton.tonal 网格，高亮当前 resume 集

### 播放页 (player_page.dart)
- **分屏布局**（默认）：左侧视频区（flex:3）+ 右侧 280px 集数面板
- **全屏模式**：视频全屏，右侧面板作为浮动抽屉（鼠标移动时显示）
- 覆盖式控制层：顶部标题栏 + 底部播放控制（3s 自动隐藏，鼠标移动恢复）
- 底部控制：上一集/播放暂停/下一集 + 进度条（`_ProgressBar` widget）+ 全屏切换
- 键盘快捷键：空格=播放暂停，F/F11=全屏，ESC=退出全屏
- 多线路：`ChoiceChip` 切换线路
- 集数网格：`FilledButton.tonal`，当前集高亮
- 依赖 `window_manager` 实现全屏

### 跨页面搜索机制
- `providers.dart` 新增 `pendingSearchProvider`（`StateProvider<String?>`）
- 流程：首页点击 → `_triggerSearch(ref, title)` → AppShell `ref.listen` 切换到搜索 tab → SearchPage `ref.listen` 填充并搜索

### 数据层
- `vod_models.dart` 新增 `DoubanSubject` 和 `DoubanSearchResponse`
- `providers.dart` 新增 `doubanChartProvider` / `doubanMoviesProvider` / `doubanTvProvider`
  - 使用 `client.getRaw` 直接解析，绕过 `ApiResponse` 包装
  - chart 路径：`/api/douban/chart?type=11&limit=8`
  - search 路径：`/api/douban/search?type=movie&tag=热门&page_limit=16`

---

## 未完成 / 需要接手

### 1. ⚠️ 播放页进一步优化（最高优先级）

#### 1a. 集数侧边栏支持伸缩
- 右侧面板（分屏模式 width=280）改为可拖拽调整宽度，或添加折叠/展开按钮
- 建议：在面板左边缘放一个 `GestureDetector` 拖拽条，`onHorizontalDragUpdate` 动态改变宽度
- 宽度范围建议：最小 0（完全折叠）或 180，最大 400
- 折叠时显示一个半透明箭头图标让用户可以展开

#### 1b. 播放页支持窗口拖拽
- 当前播放页无法拖动窗口（自定义标题栏只在 AppShell 里，PlayerPage 是全 Scaffold）
- 解决方案：在播放页覆盖控制层的**顶部栏**包裹 `GestureDetector`，`onPanStart: (_) => windowManager.startDragging()`
- 需要在 `player_page.dart` 顶部 import `package:window_manager/window_manager.dart`（已有）
- 注意全屏模式下不需要拖拽（窗口已铺满屏幕）

### 2. sources_page.dart 未美化
片源管理页保留原始实现，可在设置页完成后顺带美化。

### 3. 旧页面未清理
以下文件已被新架构替代，可以删除：
- `lib/features/history/presentation/history_page.dart`
- `lib/features/favorites/presentation/favorites_page.dart`

（历史和收藏已合并到 `my_page.dart`）

### 4. 编译验证
```
cd d:/TTTTV-Flutter/ttttv_flutter
flutter analyze --no-pub   # 当前已通过，No issues found
flutter build windows
```

---

## 文件结构（改动后）

```
ttttv_flutter/lib/
├── app/
│   ├── app.dart                    ✅ 重写
│   └── app_shell.dart              ✅ 重写（自定义标题栏 + pendingSearch 监听）
├── core/
│   ├── models/vod_models.dart      ✅ 新增 DoubanSubject
│   ├── providers.dart              ✅ 新增豆瓣 providers + pendingSearchProvider
│   └── theme/app_theme.dart        ✅ 重写（动态主题）
├── features/
│   ├── home/presentation/home_page.dart         ✅ 新建（点击触发搜索）
│   ├── my/presentation/my_page.dart             ✅ 新建
│   ├── settings/presentation/settings_page.dart ✅ 新建
│   ├── search/presentation/search_page.dart     ✅ 重写（监听 pendingSearch）
│   ├── detail/presentation/detail_page.dart     ✅ 补完
│   ├── player/presentation/player_page.dart     ✅ 重写（分屏+全屏+控制层）
│   └── settings/presentation/sources_page.dart  未动
└── main.dart                       ✅ window_manager 初始化
```

---

## 关键设计决策

- **导航**：左侧固定 `NavigationRail`，不做响应式（Windows 优先）
- **主题**：`ThemeMode.system` + seed color 可换，无 Material You 动态色
- **豆瓣**：点击卡片触发同名搜索（不直接跳详情，因为豆瓣无法对应片源）
- **播放**：media_kit，分屏左右布局，全屏覆盖控制
- **窗口**：`window_manager` 自定义标题栏，最小尺寸 900×600
- **架构**：保持 Riverpod + HTTP 后端，不引入新状态管理
