# 直播功能 Flutter 迁移计划

> 基于 2026-03-27 现状。影视/VOD 部分已完成，本文档覆盖四平台直播（Bilibili / 斗鱼 / 虎牙 / 抖音）的完整迁移。

---

## 一、现状梳理

### 1.1 Tauri 端已有功能清单

| 功能模块 | Vue 文件 | 说明 |
|---|---|---|
| 直播首页 | `LivePage.vue` | 平台 Tab + 搜索/推荐 + 房间卡片网格 |
| 房间弹窗 | `LiveRoomDialog.vue` | 播放器 + 清晰度/线路选择 + 弹幕开关 + 收藏 |
| 直播播放器 | `LiveVideoPlayer.vue` | HLS/FLV 播放（mpegts.js） |
| 弹幕画布 | `DanmakuCanvas.vue` | Canvas 渲染，WebSocket 接收 |
| 登录对话框 | `LiveAuthDialog.vue` | Bilibili 扫码轮询；斗鱼/虎牙/抖音手动 Cookie |
| 直播收藏 Store | `liveFavorites.ts` | 增删查清 |
| 直播历史 Store | `liveHistory.ts` | 增删清 |
| 直播核心 Store | `live.ts` | 平台列表/推荐/搜索/详情/清晰度/播放/代理URL/弹幕WS URL |

### 1.2 后端 HTTP 接口（`127.0.0.1:5007`）

```
# 平台
GET  /api/live/platforms

# 推荐 / 搜索
GET  /api/live/{platform}/recommend?page=1
GET  /api/live/{platform}/search?kw=&page=1

# 房间
GET  /api/live/{platform}/room/detail?room_id=
GET  /api/live/{platform}/room/qualities?room_id=
GET  /api/live/{platform}/room/play?room_id=&quality_id=

# 代理（封面/头像/流 URL 统一走后端转发）
GET  /api/live/proxy?platform=&url=

# 弹幕（WebSocket）
WS   /api/live/{platform}/room/danmaku?room_id=

# 收藏
GET    /api/live/favorites
POST   /api/live/favorites          body: {platform, room_id, title, cover?, user_name?, user_avatar?}
DELETE /api/live/favorites          ?platform=&room_id=
GET    /api/live/favorites/check    ?platform=&room_id=
DELETE /api/live/favorites/clear

# 历史
GET    /api/live/history
POST   /api/live/history            body: 同收藏
DELETE /api/live/history            ?platform=&room_id=
DELETE /api/live/history/clear

# 认证
GET  /api/live/auth/bilibili/status
GET  /api/live/auth/bilibili/qrcode
GET  /api/live/auth/bilibili/qrcode/poll?qrcode_key=
POST /api/live/auth/bilibili/logout
GET  /api/live/auth/{platform}/status      （斗鱼/虎牙/抖音）
POST /api/live/auth/{platform}/cookie      body: {cookie: string}
POST /api/live/auth/{platform}/logout
```

### 1.3 关键数据模型

```dart
// 需在 vod_models.dart 中新增
class LivePlatformInfo { String id; String name; }
class LiveRoomItem     { String platform; String roomId; String title; String cover; String userName; int online; }
class LiveRoomDetail   { ...LiveRoomItem + userAvatar, online, introduction, notice, status, isRecord, url, showTime }
class LivePlayQuality  { String id; String name; int sort; }
class LivePlayUrl      { List<String> urls; Map<String,String>? headers; String? urlType; int? expiresAt; }
class LiveFavoriteItem { String platform; String roomId; String title; String? cover; String? userName; String? userAvatar; int createdTime; }
class LiveHistoryItem  { String platform; String roomId; String title; String? cover; String? userName; String? userAvatar; int lastWatchTime; }
class LiveMessage      { String type; String userName; String message; LiveMessageColor color; }
class LiveMessageColor { int r; int g; int b; }
// Auth
class BilibiliAuthStatus  { bool loggedIn; }
class BilibiliQrCode      { String qrcodeKey; String url; String svg; }
class BilibiliQrPollResult{ int code; String status; String message; }
```

---

## 二、Flutter 端目标架构

```
lib/
  features/
    live/
      domain/
        live_repository.dart          # 抽象接口
      data/
        http_live_backend.dart        # HTTP 实现（Dio）
      application/
        live_controller.dart          # Riverpod 状态（推荐/搜索/平台列表）
        live_room_controller.dart     # 单房间状态（详情/清晰度/播放/弹幕）
        live_favorites_controller.dart
        live_history_controller.dart
        live_auth_controller.dart
      presentation/
        live_page.dart                # 首页（Tab + 搜索 + 卡片网格）
        live_room_page.dart           # 独立播放页（替代弹窗）
        widgets/
          live_room_card.dart
          live_player_widget.dart     # video_player 封装
          danmaku_overlay.dart        # CustomPainter 弹幕层
          quality_selector.dart
          line_selector.dart
          live_auth_sheet.dart        # Bilibili 扫码 + 其他 Cookie
          live_favorites_sheet.dart
          live_history_sheet.dart
```

> **导航策略**：直播房间在 Flutter 中用独立 `push` 页面而非弹窗（Dialog），与 VOD 播放页保持一致体验，并方便 Android/iOS 适配。

---

## 三、分阶段任务

### Phase 1 — 模型 + 数据层（无 UI）

**目标**：能在 Dart 层调通所有直播 HTTP 接口，包含完整错误处理。

- [ ] **P1-1** 在 `vod_models.dart` 追加所有直播相关 DTO（见 1.3 节）
- [ ] **P1-2** 在 `live_repository.dart` 定义抽象接口，方法签名镜像 Vue live store
- [ ] **P1-3** 实现 `http_live_backend.dart`，对接全部直播 HTTP/WS 端点
  - 代理 URL 构造：`http://127.0.0.1:5007/api/live/proxy?platform=&url=`
  - 弹幕 WS URL 构造：`ws://127.0.0.1:5007/api/live/{platform}/room/danmaku?room_id=`
- [ ] **P1-4** 在 `providers.dart` 注册 `liveRepositoryProvider`
- [ ] **P1-5** 手动 curl / 单元测试验证所有接口可通

**风险**：`/api/live/auth/{platform}/cookie` 端点路径需与 Rust 路由核实（Tauri 前端仅有 `setLiveAuthCookie`，未直接暴露 path）。迁移前先 grep Rust 路由确认。

---

### Phase 2 — 直播首页

**目标**：`LivePage` 可展示平台 Tab、推荐卡片、搜索。

- [ ] **P2-1** 创建 `live_controller.dart`（StateNotifier / AsyncNotifier）：
  - `platforms`：启动时加载一次
  - `rooms`：推荐或搜索结果
  - `loading` / `error`
  - `activePlatform`：切换时自动刷新推荐
- [ ] **P2-2** 实现 `live_page.dart`：
  - 顶部：标题 + 收藏/历史入口按钮
  - 平台 TabBar（Bilibili / 斗鱼 / 虎牙 / 抖音）
  - 搜索框 + 搜索/推荐按钮
  - GridView 房间卡片（封面走代理 URL，在线人数格式化，LIVE badge）
- [ ] **P2-3** 实现 `live_room_card.dart` 组件
- [ ] **P2-4** 在 `app_shell.dart` 底部导航添加「直播」Tab，路由指向 `live_page.dart`

---

### Phase 3 — 房间播放页

**目标**：点击房间卡片 → 进入播放页，可选清晰度/线路，流可以播放。

- [ ] **P3-1** 创建 `live_room_controller.dart`：
  - 入参：`platform` + `roomId`
  - 加载 detail → qualities → play（自动选首个清晰度）
  - 切换清晰度/线路时重新拉 play
  - 进房间自动写入历史
  - 暴露 `currentStreamUrl`（已经是代理 URL）
- [ ] **P3-2** 实现 `live_room_page.dart` 布局：
  - 16:9 播放区（`live_player_widget.dart` + 弹幕叠层）
  - 控制行：清晰度选择 / 线路选择 / 弹幕开关 / 刷新 / 收藏
  - 主播信息卡：头像（代理）+ 主播名 + 在线人数 + 平台 + 简介
- [ ] **P3-3** 实现 `live_player_widget.dart`：
  - 基于 `video_player` 包；HLS 流直接传代理 URL
  - 播放出错时显示错误提示 + 重试按钮
  - 注意：FLV 流目前后端代理已转为 m3u8 或直出，前端只需处理 HLS
- [ ] **P3-4** 接入 `live_favorites_controller.dart`，收藏按钮状态联动

---

### Phase 4 — 弹幕

**目标**：播放页上叠加实时弹幕，视觉效果与 Tauri 版一致。

- [ ] **P4-1** 实现 `danmaku_overlay.dart`：
  - 用 `CustomPainter` + `AnimationController` 渲染滚动弹幕轨道
  - `Bullet` 结构：text / color / x / y / width / speed
  - 轨道分配逻辑：按 fontSize+6 高度切分，循环分配行
  - 超出 200 条自动裁剪
- [ ] **P4-2** 在 `live_room_controller` 中管理 WebSocket 连接（`dart:io` WebSocket 或 `web_socket_channel`）：
  - 连接 `ws://127.0.0.1:5007/api/live/{platform}/room/danmaku?room_id=`
  - 只处理 `type == "chat"` 消息
  - 指数退避重连（上限 30s，最多 10 次）
  - 离开页面时 dispose
- [ ] **P4-3** 弹幕设置面板（`BottomSheet` 或侧边抽屉）：透明度 / 字号 / 速度，设置持久化到 `SharedPreferences`
- [ ] **P4-4** 弹幕开关联动：关闭时断开 WS 并清空画布，开启时重连

---

### Phase 5 — 收藏 & 历史

**目标**：直播收藏/历史的增删查清可用，入口在直播首页顶部。

- [ ] **P5-1** 实现 `live_favorites_controller.dart`（Riverpod）：
  - `fetchFavorites` / `addFavorite` / `deleteFavorite` / `clearFavorites` / `isFavoriteLocally`
- [ ] **P5-2** 实现 `live_history_controller.dart`：
  - `fetchHistory` / `addHistory` / `deleteHistory` / `clearHistory`
- [ ] **P5-3** 实现 `live_favorites_sheet.dart`（BottomSheet 或全屏页）：
  - 列表展示：平台 / 封面 / 标题 / 主播 / 删除
  - 点击行 → 关闭 sheet → 进入房间播放页
- [ ] **P5-4** 实现 `live_history_sheet.dart`（同上结构）

---

### Phase 6 — 登录认证

**目标**：Bilibili 扫码登录；斗鱼/虎牙/抖音 Cookie 粘贴保存。

**前置**：先用 grep 确认 Rust 路由中 cookie 保存接口的实际 path 和 body 格式。

- [ ] **P6-1** 实现 `live_auth_controller.dart`：
  - Bilibili：`getAuthStatus` / `getQrCode` / `pollQrCode`（2s 轮询 Timer）/ `logout`
  - 其他平台：`getAuthStatus` / `saveCookie` / `logout`
- [ ] **P6-2** 实现 `live_auth_sheet.dart`：
  - Bilibili：展示后端返回的 SVG 二维码（`flutter_svg` 包或 WebView 渲染）+ 轮询状态提示
  - 其他平台：多行文本框粘贴 Cookie + 保存按钮
  - 所有平台：当前登录状态展示 / 退出登录按钮
- [ ] **P6-3** 在直播首页或设置页提供各平台登录入口
- [ ] **P6-4** 未登录时推荐/搜索仍可用（现有后端行为），仅高清晰度需登录时给出提示

**注意（Tauri 差异）**：Tauri 版用 `@tauri-apps/plugin-opener` 打开外部浏览器登录页。Flutter 用 `url_launcher` 包替代。

---

### Phase 7 — 集成测试 & 收尾

- [ ] **P7-1** 端到端冒烟测试：
  - 直播首页加载推荐 → 切换平台 → 搜索 → 点击进入房间 → 流可播放 → 弹幕出现 → 收藏 → 历史可见
- [ ] **P7-2** 异常路径测试：后端未启动 / 平台返回空 / 流过期刷新
- [ ] **P7-3** 弹幕性能检查：Windows 上 200 条并发弹幕无明显掉帧
- [ ] **P7-4** 更新 `LIVE_HTTP_CONTRACT.md`（参照 `VOD_HTTP_CONTRACT.md` 格式，冻结直播接口）
- [ ] **P7-5** 更新 `MIGRATION_STATUS.md`，标记直播迁移完成

---

## 四、依赖包

| 包 | 用途 | 现有/新增 |
|---|---|---|
| `video_player` | HLS 直播流播放 | 现有（VOD 已用） |
| `web_socket_channel` | 弹幕 WebSocket | 新增 |
| `shared_preferences` | 弹幕设置持久化 | 新增（或复用已有方案）|
| `flutter_svg` | Bilibili 二维码 SVG 渲染 | 新增 |
| `url_launcher` | 打开外部浏览器（替代 Tauri opener）| 新增 |
| `dio` | HTTP 客户端 | 现有 |
| `riverpod` | 状态管理 | 现有 |

---

## 五、已知风险与注意事项

| 风险 | 说明 | 缓解措施 |
|---|---|---|
| FLV 流支持 | `video_player` 原生不支持 FLV，但后端代理已将流统一包装为 m3u8 | 先验证，如仍有 FLV 直出考虑 `flutter_vlc_player` 或让后端全量转码 |
| Bilibili 二维码 SVG | 后端直接返回 SVG 字符串 | 用 `flutter_svg` 的 `SvgPicture.string()` 渲染 |
| 弹幕性能 | Canvas 逐帧渲染 200 条弹幕 | 用 `RepaintBoundary` 隔离重绘区域；若帧率不达标考虑降级为纯文字列表 |
| 认证 Cookie 路径 | Tauri 客户端代码未直接暴露 `/api/live/auth/{platform}/cookie` 完整路径 | Phase 6 开始前 grep `Moovie/src` 确认路由 |
| 代理 URL 图片加载 | `Image.network` 默认不携带自定义 Header | 直播封面/头像已通过后端代理转发，直接用代理 URL 即可，无需额外 Header |
| 弹幕 WS 重连 | Dart 中无 `window.setInterval`，需用 `Timer.periodic` | 在 controller dispose 时务必 cancel Timer 和 WS |

---

## 六、与现有 VOD 代码的复用点

- `http_backend_client.dart` 的 Dio 实例和 `_baseUrl` 可直接复用
- `ApiResponse<T>` 解析逻辑（`http_vod_backend.dart`）可提取公共方法后复用
- `app_shell.dart` 底部导航只需新增一个 Tab 项
- 播放器页面布局（16:9 + 控制行）与 `player_page.dart` 结构相近，可参考但不复制（直播与点播控制逻辑差异较大）

---

## 七、里程碑

| 里程碑 | 完成标志 |
|---|---|
| M1：数据层就绪 | 所有直播 HTTP 接口在 Dart 层可调通（Phase 1）|
| M2：首页可用 | 直播首页展示推荐/搜索结果，四平台切换正常（Phase 2）|
| M3：播放可用 | 进入房间、选清晰度、HLS 流播放正常（Phase 3）|
| M4：弹幕可用 | 弹幕实时滚动、设置可保存（Phase 4）|
| M5：收藏历史可用 | 收藏/历史增删查正常（Phase 5）|
| M6：登录可用 | Bilibili 扫码和手动 Cookie 登录均可用（Phase 6）|
| M7：完成 | 全流程冒烟通过，合约文档更新（Phase 7）|
