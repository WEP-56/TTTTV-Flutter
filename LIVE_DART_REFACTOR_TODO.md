# 直播模块 Dart 原生重构 TODO

> 日期：2026-03-27
>
> 目标：将 `ttttv_flutter` 的直播模块从当前 `Flutter -> Rust live backend` 架构，重构为 `Flutter 纯 Dart 原生直播内核`。
>
> 范围：仅直播模块。影视 / VOD 模块继续依赖 Rust 后端，不在本次重构范围内。
>
> 最终目标平台：
> - 哔哩哔哩（Bilibili）
> - 虎牙直播（Huya）
> - 斗鱼直播（Douyu）
> - 快手（Kuaishou）
> - 抖音（Douyin）
> - 自定义 M3U8 源（支持本地 / 网络导入）

---

## 一、重构决策

### 1.1 结论

直播模块不再继续依赖 Rust 后端提供平台接口、代理、弹幕桥接与认证接口，改为 Flutter 端直接实现：

- 平台推荐 / 搜索 / 房间详情
- 清晰度与线路解析
- 播放地址获取
- 弹幕连接与解析
- 平台 Cookie 管理
- 直播收藏 / 历史
- 自定义 M3U / M3U8 导入与播放

### 1.2 保留与废弃

**保留**
- `Moovie` 中 VOD、搜索、影视播放、站点源相关能力
- `ttttv_flutter` 中现有 VOD 相关架构
- `ttttv_flutter` 中现有直播页面入口、播放器页基础 UI、Phase 4 弹幕 UI 资产中可复用部分

**逐步废弃**
- `Moovie/src/api/live.rs`
- `Moovie/src/api/live_auth.rs`
- `Moovie/src/api/live_favorites.rs`
- `Moovie/src/api/live_history.rs`
- `Moovie/src/live/**`
- `Moovie/src/lib.rs` 中 `/api/live` 路由挂载
- `ttttv_flutter/lib/features/live/data/http_live_backend.dart`
- `ttttv_flutter/lib/features/live/domain/live_repository.dart`
- `ttttv_flutter/lib/core/providers.dart` 中 `liveRepositoryProvider`

### 1.3 不做的事

- 不在本轮继续扩展 Rust 直播能力
- 不把 `pure_live_TV-main` 整个项目原样搬进当前仓库
- 不为了“统一抽象”强行把 IPTV / M3U 源与平台直播做成同一种弱化模型
- 不优先追求 Android / iOS 适配，先把 Windows 端完全跑通

---

## 二、项目硬约束

### 2.1 代码约束

- 单文件代码行数不得超过 `800` 行
- 单个高复杂模块超过 `600` 行时，必须提前拆文件
- 平台实现必须按 `provider / parser / signer / danmaku / models` 分层，禁止一个文件包办

### 2.2 参考约束

必须优先参考并复用以下项目思路与实现，禁止独立造轮子：

- 示例项目根目录：
  [pure_live_TV-main](D:\TTTTV-Flutter\backend-example\pure_live_TV-main)

重点参考文件映射：

- 抽象接口参考：
  [live_site.dart](D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\interface\live_site.dart)
- 站点注册参考：
  [sites.dart](D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\sites.dart)
- IPTV 站点参考：
  [iptv_site.dart](D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\site\iptv_site.dart)
- 弹幕抽象参考：
  [live_danmaku.dart](D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\interface\live_danmaku.dart)
- 各平台弹幕实现参考：
  `lib/core/danmaku/*.dart`
- M3U 解析参考：
  [iptv_utils.dart](D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\iptv\iptv_utils.dart)
  [m3u_parser_nullsafe.dart](D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\iptv\m3u_parser_nullsafe.dart)

### 2.3 平台优先级

- 第一优先级：Windows
- 第二优先级：Windows
- 第三优先级：仍然是 Windows

解释：
- 当前播放器、文件导入、窗口行为、调试路径都已集中在 Windows 桌面环境
- 直播协议打通前，不能因为兼容多端而牺牲调试效率

---

## 三、当前现状盘点

### 3.1 当前 Flutter 直播代码

当前 Flutter 直播模块仍然是 Rust 后端驱动：

- 页面：
  [live_page.dart](D:\TTTTV-Flutter\ttttv_flutter\lib\features\live\presentation\live_page.dart)
  [live_room_page.dart](D:\TTTTV-Flutter\ttttv_flutter\lib\features\live\presentation\live_room_page.dart)
- 控制器：
  [live_controller.dart](D:\TTTTV-Flutter\ttttv_flutter\lib\features\live\application\live_controller.dart)
  [live_room_controller.dart](D:\TTTTV-Flutter\ttttv_flutter\lib\features\live\application\live_room_controller.dart)
- Rust HTTP 仓库：
  [http_live_backend.dart](D:\TTTTV-Flutter\ttttv_flutter\lib\features\live\data\http_live_backend.dart)
  [live_repository.dart](D:\TTTTV-Flutter\ttttv_flutter\lib\features\live\domain\live_repository.dart)
- Provider 注册：
  [providers.dart](D:\TTTTV-Flutter\ttttv_flutter\lib\core\providers.dart)

### 3.2 当前 Rust 直播代码

Rust 侧仍承担直播完整逻辑：

- 路由入口：
  [lib.rs](D:\TTTTV-Flutter\Moovie\src\lib.rs)
- 直播 API：
  [live.rs](D:\TTTTV-Flutter\Moovie\src\api\live.rs)
  [live_auth.rs](D:\TTTTV-Flutter\Moovie\src\api\live_auth.rs)
  [live_favorites.rs](D:\TTTTV-Flutter\Moovie\src\api\live_favorites.rs)
  [live_history.rs](D:\TTTTV-Flutter\Moovie\src\api\live_history.rs)
- 平台实现：
  `Moovie/src/live/providers/bilibili.rs`
  `Moovie/src/live/providers/douyu.rs`
  `Moovie/src/live/providers/huya.rs`
  `Moovie/src/live/providers/douyin.rs`
- 弹幕桥接：
  `Moovie/src/live/danmaku/*`

### 3.3 当前问题

- Flutter 直播层只是 Rust API 的消费端，无法独立演进
- 每次新增平台或改协议，需要同时理解 Flutter 和 Rust 两层
- 弹幕、播放、认证被拆在两种语言两套调试链路里
- 当前目标已超出原迁移范围，需要新增 `Kuaishou` 与 `自定义 M3U8`
- 继续依赖 Rust 会让直播模块和 VOD 模块耦合过深

---

## 四、目标架构

## 4.1 总体原则

直播模块采用“Provider 驱动”：

- 平台直播是 `Platform Live Provider`
- M3U / M3U8 是 `Playlist Live Provider`
- 页面层只面向统一能力接口，不直接依赖具体平台协议

### 4.2 目标目录

```text
ttttv_flutter/lib/
  features/
    live/
      core/
        models/
          live_models.dart
          live_provider_models.dart
        providers/
          live_provider.dart
          live_provider_registry.dart
          live_capabilities.dart
        danmaku/
          live_danmaku_client.dart
          live_danmaku_message.dart
      data/
        storage/
          live_local_store.dart
          live_cookie_store.dart
          live_history_store.dart
          live_favorites_store.dart
        m3u/
          m3u_parser.dart
          m3u_import_service.dart
          m3u_source_store.dart
      providers/
        bilibili/
          bilibili_live_provider.dart
          bilibili_models.dart
          bilibili_signer.dart
          bilibili_danmaku_client.dart
          bilibili_auth_service.dart
        douyu/
          douyu_live_provider.dart
          douyu_models.dart
          douyu_signer.dart
          douyu_danmaku_client.dart
        huya/
          huya_live_provider.dart
          huya_models.dart
          huya_parser.dart
          huya_danmaku_client.dart
        kuaishou/
          kuaishou_live_provider.dart
          kuaishou_models.dart
          kuaishou_parser.dart
        douyin/
          douyin_live_provider.dart
          douyin_models.dart
          douyin_signer.dart
          douyin_danmaku_client.dart
        custom/
          custom_m3u_provider.dart
      application/
        live_home_controller.dart
        live_room_controller.dart
        live_auth_controller.dart
        live_library_controller.dart
        live_history_controller.dart
        live_favorites_controller.dart
      presentation/
        live_page.dart
        live_room_page.dart
        live_source_manage_page.dart
        widgets/
          ...
```

### 4.3 能力分层

基础能力：

- 平台列表
- 推荐
- 搜索
- 房间详情
- 清晰度
- 播放链接

可选能力：

- 弹幕
- Cookie / 登录
- 收藏 / 历史
- 分类 / 分区
- 本地或网络导入

### 4.4 接口约束

`LiveProvider` 最少应覆盖：

- `id`
- `name`
- `supportsSearch`
- `supportsCategories`
- `supportsDanmaku`
- `supportsAuth`
- `supportsImport`
- `fetchRecommend()`
- `search()`
- `getRoomDetail()`
- `getPlayQualities()`
- `getPlayUrls()`
- `createDanmakuClient()`

说明：
- 不要求所有 provider 功能一致
- 页面层必须依据 capability 渲染，不得假定所有平台都支持相同功能

---

## 五、阶段化 TODO

## Phase 0：冻结旧实现与准备工作

**目标**：不再继续在 Rust 直播链路上追加新需求，先建立新旧并行迁移边界。

- [ ] P0-1 在文档层明确：直播模块进入 Dart 原生重构，不再继续扩展 Rust 直播 API
- [ ] P0-2 标记旧直播文档为“旧方案”，避免后续继续按 `LIVE_MIGRATION_PLAN.md` 追加
- [ ] P0-3 新建本 TODO 文档并作为直播改造主计划
- [ ] P0-4 盘点当前 Flutter 直播功能哪些可复用，哪些必须重写
- [ ] P0-5 建立“Rust 直播移除清单”

**产出**
- 本文档
- Rust 清理清单
- Flutter 可复用清单

**验收标准**
- 团队对“直播 Rust 废弃、VOD Rust 保留”边界无歧义

---

## Phase 1：建立 Dart 原生直播基座

**目标**：搭出不依赖 Rust 的直播基础骨架。

- [ ] P1-1 新建 `features/live/core/providers/live_provider.dart`
- [ ] P1-2 新建 `features/live/core/providers/live_provider_registry.dart`
- [ ] P1-3 新建直播基础模型，拆出 provider 通用模型与 UI 模型
- [ ] P1-4 建立平台能力枚举 / capability 机制
- [ ] P1-5 建立直播本地存储接口
- [ ] P1-6 建立直播 Cookie 存储接口
- [ ] P1-7 将现有 `live_controller.dart` 重命名或重构为 provider 驱动控制器
- [ ] P1-8 让 Flutter 直播模块在没有 Rust `/api/live` 的情况下也能启动

**必须参考**
- [live_site.dart](D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\interface\live_site.dart)
- [sites.dart](D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\sites.dart)

**落地规则**
- Provider 抽象只定义能力，不夹带 UI 状态
- 控制器不直接写死 `bilibili/douyu/huya/douyin`
- 平台注册表集中维护，禁止散落在页面层硬编码

**验收标准**
- Flutter 直播首页已不依赖 `http_live_backend.dart`
- Provider Registry 可注册空实现 / mock 实现跑通页面

---

## Phase 2：先落地自定义 M3U8 / IPTV Provider

**目标**：最快形成第一个完全脱离 Rust 的可用直播源，验证新架构。

- [ ] P2-1 新建 `custom_m3u_provider.dart`
- [ ] P2-2 引入或改造 `m3u_parser_nullsafe.dart` 的解析思路
- [ ] P2-3 支持网络 M3U 地址导入
- [ ] P2-4 支持本地 M3U / M3U8 文件导入
- [ ] P2-5 设计本地分类与源列表存储结构
- [ ] P2-6 在首页新增“网络源 / 自定义源”入口
- [ ] P2-7 播放页支持 M3U 导入源的直接播放
- [ ] P2-8 明确 M3U Provider 的详情页简化策略
- [ ] P2-9 明确 M3U Provider 不支持弹幕时的 UI 降级

**必须参考**
- [iptv_site.dart](D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\site\iptv_site.dart)
- [iptv_utils.dart](D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\iptv\iptv_utils.dart)
- [m3u_parser_nullsafe.dart](D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\iptv\m3u_parser_nullsafe.dart)

**新增依赖候选**
- `file_picker`
- `path_provider`
- 继续复用 `dio`

**验收标准**
- Windows 端可导入一个网络 M3U 地址并成功播放
- Windows 端可导入一个本地 `.m3u` 文件并成功播放
- 不经过 Rust 代理也能打开至少一个可用流

---

## Phase 3：重构 Flutter 首页与播放页为 Provider 驱动

**目标**：现有 UI 不再依赖 Rust 数据结构和 HTTP 仓库，而是面向 `LiveProvider`。

- [ ] P3-1 重写首页 tab 数据源，不再硬编码四平台
- [ ] P3-2 页面顶部增加 provider 切换策略
- [ ] P3-3 推荐、搜索、空状态、错误状态统一改为 provider 返回值驱动
- [ ] P3-4 播放页改为 capability 驱动控制按钮
- [ ] P3-5 当 provider 不支持清晰度、线路、弹幕、认证时，UI 自动降级
- [ ] P3-6 将现有 `live_room_controller.dart` 从 `LiveRepository` 模式改造为 `LiveProvider` 模式
- [ ] P3-7 现有 Phase 4 弹幕叠层仅保留 UI 渲染，不再依赖 Rust WebSocket bridge

**影响文件**
- [live_page.dart](D:\TTTTV-Flutter\ttttv_flutter\lib\features\live\presentation\live_page.dart)
- [live_room_page.dart](D:\TTTTV-Flutter\ttttv_flutter\lib\features\live\presentation\live_room_page.dart)
- [live_room_controller.dart](D:\TTTTV-Flutter\ttttv_flutter\lib\features\live\application\live_room_controller.dart)
- [providers.dart](D:\TTTTV-Flutter\ttttv_flutter\lib\core\providers.dart)

**验收标准**
- 首页与播放页在仅启用 `custom_m3u_provider` 时也能正常使用
- 页面没有对 `http_live_backend.dart` 的运行时依赖

---

## Phase 4：本地收藏、历史、认证存储迁移

**目标**：将直播模块的用户数据从 Rust API 迁移到 Flutter 本地存储。

- [ ] P4-1 新建直播收藏本地仓库
- [ ] P4-2 新建直播历史本地仓库
- [ ] P4-3 新建平台 Cookie 仓库
- [ ] P4-4 迁移现有 Flutter 直播收藏逻辑，不再请求 Rust `/api/live/favorites`
- [ ] P4-5 迁移现有 Flutter 直播历史逻辑，不再请求 Rust `/api/live/history`
- [ ] P4-6 迁移现有登录状态判定，不再请求 Rust `/api/live/auth/*`
- [ ] P4-7 设计本地数据升级策略，避免旧版本用户数据丢失

**存储建议**
- 轻量数据：
  `SharedPreferences`
- 导入源 / 分类 / 文件路径等结构化数据：
  本地 JSON 文件

**验收标准**
- 断开 Rust 直播 API 后，收藏 / 历史 / Cookie 仍可正常工作

---

## Phase 5：Bilibili Provider

**目标**：先落地一个成熟度最高、参考实现最完整的平台。

- [ ] P5-1 新建 `bilibili_live_provider.dart`
- [ ] P5-2 迁移推荐接口
- [ ] P5-3 迁移搜索接口
- [ ] P5-4 迁移房间详情接口
- [ ] P5-5 迁移清晰度解析
- [ ] P5-6 迁移播放地址解析
- [ ] P5-7 迁移 Bilibili Cookie / 登录策略
- [ ] P5-8 迁移 Bilibili 弹幕连接
- [ ] P5-9 与现有 Flutter 弹幕叠层打通
- [ ] P5-10 验证高清流在已登录状态下可用

**必须参考**
- [bilibili_site.dart](D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\site\bilibili_site.dart)
- `pure_live_TV-main/lib/core/danmaku/bilibili_danmaku.dart`

**验收标准**
- 推荐、搜索、详情、清晰度、播放、弹幕全部可用
- 不依赖 Rust `/api/live/*`

---

## Phase 6：Douyu Provider

**目标**：打通斗鱼平台。

- [ ] P6-1 新建 `douyu_live_provider.dart`
- [ ] P6-2 迁移推荐 / 搜索 / 详情
- [ ] P6-3 迁移清晰度 / 线路
- [ ] P6-4 迁移斗鱼弹幕协议
- [ ] P6-5 验证 Windows 下稳定播放

**必须参考**
- `pure_live_TV-main/lib/core/site/douyu_site.dart`
- `pure_live_TV-main/lib/core/danmaku/douyu_danmaku.dart`

**验收标准**
- 可稳定进入房间播放，并显示斗鱼弹幕

---

## Phase 7：Huya Provider

**目标**：打通虎牙平台。

- [ ] P7-1 新建 `huya_live_provider.dart`
- [ ] P7-2 迁移推荐 / 搜索 / 详情
- [ ] P7-3 迁移播放地址解析
- [ ] P7-4 迁移虎牙弹幕协议
- [ ] P7-5 处理虎牙在 Windows 下的 UA / 流地址兼容问题

**必须参考**
- `pure_live_TV-main/lib/core/site/huya_site.dart`
- `pure_live_TV-main/lib/core/danmaku/huya_danmaku.dart`

**验收标准**
- 虎牙房间播放与弹幕均可用

---

## Phase 8：Kuaishou Provider

**目标**：打通快手平台。

- [ ] P8-1 新建 `kuaishou_live_provider.dart`
- [ ] P8-2 迁移推荐 / 搜索 / 详情
- [ ] P8-3 迁移播放地址解析
- [ ] P8-4 评估是否支持弹幕
- [ ] P8-5 如不支持弹幕，提供明确 UI 降级

**必须参考**
- `pure_live_TV-main/lib/core/site/kuaishou_site.dart`

**验收标准**
- 快手直播间可进入并播放

---

## Phase 9：Douyin Provider

**目标**：最后攻克抖音，因为它协议、签名、弹幕复杂度最高。

- [ ] P9-1 新建 `douyin_live_provider.dart`
- [ ] P9-2 拆分 `douyin_signer.dart`，禁止把签名代码塞进 provider 主文件
- [ ] P9-3 迁移推荐 / 搜索 / 分类 / 详情
- [ ] P9-4 迁移清晰度与播放地址解析
- [ ] P9-5 迁移 Douyin Cookie 方案
- [ ] P9-6 迁移 Douyin 弹幕协议
- [ ] P9-7 验证签名逻辑在 Windows 端稳定运行
- [ ] P9-8 处理浏览器 UA、请求参数、WebSocket 连接细节

**必须参考**
- [douyin_site.dart](D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\site\douyin_site.dart)
- `pure_live_TV-main/lib/core/danmaku/douyin_danmaku.dart`

**高风险项**
- 签名算法
- 请求参数时效性
- 弹幕 protobuf / gzip / ack 机制

**验收标准**
- 抖音直播间在 Windows 上可播放、可连弹幕、可配置 Cookie

---

## Phase 10：Windows 端专项适配

**目标**：确保直播模块先在 Windows 上完全落地。

- [ ] P10-1 核查 `media_kit` 与直播流兼容性
- [ ] P10-2 核查 HLS、重试、切线、切清晰度时的播放器行为
- [ ] P10-3 核查全屏与窗口恢复
- [ ] P10-4 核查本地文件导入 UX
- [ ] P10-5 核查导入源路径存储与权限问题
- [ ] P10-6 核查弹幕 200 条并发渲染性能
- [ ] P10-7 形成 Windows 直播专项问题清单

**验收标准**
- 以上 6 类直播源在 Windows 端均至少有一条可播路径
- 页面、播放、导入、全屏、弹幕无阻断级问题

---

## Phase 11：Rust 直播代码隔离与下线

**目标**：在 Dart 直播链路完全替代后，再移除 Rust 直播实现。

### 11.1 第一阶段：隔离

- [ ] P11-1 将 Flutter 端所有直播入口改为 Dart 原生 provider
- [ ] P11-2 移除 Flutter 对 `/api/live/*` 的请求
- [ ] P11-3 移除 Flutter 对 `http_live_backend.dart` 的依赖
- [ ] P11-4 在测试环境关闭 `/api/live` 路由验证 Flutter 直播仍可工作

### 11.2 第二阶段：删除

- [ ] P11-5 删除 [http_live_backend.dart](D:\TTTTV-Flutter\ttttv_flutter\lib\features\live\data\http_live_backend.dart)
- [ ] P11-6 删除 [live_repository.dart](D:\TTTTV-Flutter\ttttv_flutter\lib\features\live\domain\live_repository.dart)
- [ ] P11-7 删除 `Moovie/src/api/live.rs`
- [ ] P11-8 删除 `Moovie/src/api/live_auth.rs`
- [ ] P11-9 删除 `Moovie/src/api/live_favorites.rs`
- [ ] P11-10 删除 `Moovie/src/api/live_history.rs`
- [ ] P11-11 删除 `Moovie/src/live/**`
- [ ] P11-12 修改 [lib.rs](D:\TTTTV-Flutter\Moovie\src\lib.rs)，移除 `/api/live` 路由
- [ ] P11-13 清理 Rust 侧不再使用的依赖与模块导出

**注意**
- 删除前必须先完成双重验证：
  - Flutter 不再有运行时依赖
  - 文档不再指向旧接口

**验收标准**
- Rust 编译通过
- Flutter 直播可独立工作
- VOD 不受影响

---

## Phase 12：文档与收尾

**目标**：冻结新架构，防止后续再次回到 Rust 直播依赖。

- [ ] P12-1 新建直播 Dart 架构说明文档
- [ ] P12-2 更新原有直播迁移文档，标明“Rust 方案已废弃”
- [ ] P12-3 更新开发约束文档，写入“直播模块优先参考 pure_live_TV-main”
- [ ] P12-4 补充 Windows 联调手册
- [ ] P12-5 补充平台验证清单

**验收标准**
- 新成员只看文档即可知道直播模块不应继续往 Rust 里写

---

## 六、拆文件规则

以下文件强制拆分，禁止单文件堆积：

- `douyin_live_provider.dart`
  必拆：
  - `douyin_live_provider.dart`
  - `douyin_signer.dart`
  - `douyin_models.dart`
  - `douyin_danmaku_client.dart`

- `bilibili_live_provider.dart`
  必拆：
  - `bilibili_live_provider.dart`
  - `bilibili_auth_service.dart`
  - `bilibili_danmaku_client.dart`

- `custom_m3u_provider.dart`
  必拆：
  - `custom_m3u_provider.dart`
  - `m3u_parser.dart`
  - `m3u_import_service.dart`
  - `m3u_source_store.dart`

- `live_room_controller.dart`
  若超过 600 行，拆出：
  - `live_room_state.dart`
  - `live_room_actions.dart`
  - `live_room_danmaku_mixin.dart`

---

## 七、推荐实施顺序

实际开发顺序建议固定如下：

1. 建立 Provider 抽象与 Registry
2. 先打通自定义 M3U8 / 网络源
3. 重构首页与播放页为 Provider 驱动
4. 迁移收藏 / 历史 / Cookie 到 Flutter 本地
5. 打通 Bilibili
6. 打通 Douyu
7. 打通 Huya
8. 打通 Kuaishou
9. 最后处理 Douyin
10. 完成 Windows 专项验证
11. 下线 Rust 直播实现

原因：
- 先拿 M3U 验证架构，再上平台协议，风险最低
- Bilibili / Douyu / Huya 参考实现成熟
- Douyin 最复杂，不能作为起点

---

## 八、完成定义

满足以下全部条件，才算直播模块重构完成：

- Flutter 直播模块不再依赖 Rust `/api/live`
- Rust 直播 API 与 provider / danmaku 模块已删除
- Windows 端五个平台与自定义 M3U8 均已打通
- 直播收藏 / 历史 / Cookie 均已迁移到 Flutter 本地
- 弹幕至少在 Bilibili / Douyu / Huya / Douyin 上可用
- 所有新文件遵守单文件不超过 `800` 行约束
- 实现中对 `pure_live_TV-main` 已明确复用或改造，而不是重写同类轮子

---

## 九、首批建议立即执行的任务

如果从下一步开始动手，建议先做这 8 项：

- [ ] A1 新建 `LIVE_DART_REFACTOR_TODO.md` 并冻结方案
- [ ] A2 建立 `LiveProvider` / `LiveProviderRegistry`
- [ ] A3 迁移 Flutter 首页为动态 provider 列表
- [ ] A4 落地 `custom_m3u_provider`
- [ ] A5 实现网络 M3U 导入
- [ ] A6 实现本地 M3U 文件导入
- [ ] A7 让播放页支持无弹幕 provider 的能力降级
- [ ] A8 移除 Flutter 对 `http_live_backend.dart` 的首页依赖

这 8 项完成后，直播模块就真正从“Rust 直播客户端”变成“Dart 原生直播框架”了。
