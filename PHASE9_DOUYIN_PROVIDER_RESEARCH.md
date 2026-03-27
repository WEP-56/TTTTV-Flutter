# Phase 9 Douyin Provider 调研与实施文档

日期：2026-03-27

状态：调研完成，待进入实现

## 1. 目标

在当前 `ttttv_flutter` 的 Dart 原生 live provider 架构下，按参考项目 `backend-example/pure_live_TV-main` 的 Douyin 实现，落地以下能力：

- 推荐
- 搜索
- 分类
- 房间详情
- 清晰度解析
- 播放地址解析
- Cookie 登录
- 弹幕
- Windows 播放兼容

本阶段不单独设计新协议，不脱离参考项目自行发散。

## 2. 参考来源

必须严格参考以下本地文件：

- `D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\site\douyin_site.dart`
- `D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\danmaku\douyin_danmaku.dart`
- `D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\scripts\douyin_sign.dart`
- `D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\utils\douyin\douyin_request_params.dart`
- `D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\danmaku\proto\douyin.proto`
- `D:\TTTTV-Flutter\backend-example\pure_live_TV-main\lib\core\danmaku\proto\douyin.pb.dart`

辅助参考：

- `D:\TTTTV-Flutter\Moovie\src\live\providers\douyin.rs`
- `D:\TTTTV-Flutter\Moovie\src\live\providers\douyin_abogus_native.rs`
- `D:\TTTTV-Flutter\Moovie\src\live\providers\douyin_abogus.js`

## 3. 当前项目可复用架构

Douyin 必须接入当前已稳定的 provider 架构：

- 注册入口：`ttttv_flutter/lib/core/providers.dart`
- 抽象接口：`ttttv_flutter/lib/features/live/core/providers/live_provider.dart`
- 房间页控制器：`ttttv_flutter/lib/features/live/application/live_room_controller.dart`
- 房间页 UI：`ttttv_flutter/lib/features/live/presentation/live_room_page.dart`
- 通用 Cookie 存储：`ttttv_flutter/lib/features/live/data/storage/live_cookie_store.dart`

已完成平台的可直接参考接法：

- `bilibili/`
- `douyu/`
- `huya/`
- `kuaishou/`

当前仓库中 `flutter_js` 已存在，可直接用于 Douyin JS 签名执行。

## 4. Douyin 实现复杂度结论

Douyin 是目前 live provider 里复杂度最高的平台，复杂点不在单个 HTTP 接口，而在以下四块叠加：

1. HTTP 请求参数不稳定，需要 `msToken + a_bogus`
2. 房间详情存在多入口：`web_rid`、`room_id`、HTML fallback
3. 播放地址字段存在两种结构：`stream_data` JSON 与旧式 `flv_pull_url / hls_pull_url_map`
4. 弹幕 WebSocket 需要 JS 生成 `signature`，并配合 protobuf、gzip、ack

结论：

- 推荐、分类、详情、播放这条链可以先按参考和 Rust 版平移
- 弹幕必须拆成独立阶段，不要一开始和播放链路混在一个文件里
- 必须单独保留 signer 层，禁止把 JS 签名代码塞进 provider 主文件

## 5. 参考实现拆解

### 5.1 站点能力

参考 `douyin_site.dart` 可拆成以下能力：

- `getCategores`
- `getCategoryRooms`
- `getRecommendRooms`
- `getRoomDetail`
- `getPlayQualites`
- `getPlayUrls`
- `searchRooms`
- `getLiveStatus`
- `getDanmaku`

### 5.2 签名

参考 `douyin_sign.dart` 实际包含两套 JS 逻辑：

- `getABogus(params, userAgent)`：用于 HTTP 请求 URL 的 `a_bogus`
- `getMSSDKSignature(msStub, userAgent)`：用于弹幕 WebSocket 的 `signature`

当前 Rust 版只实现了 `a_bogus`，没有实现弹幕 `signature`。

### 5.3 弹幕

参考 `douyin_danmaku.dart` 需要：

- WebSocket 连接
- `PushFrame` protobuf 包解析
- gzip 解压
- `Response` protobuf 解析
- `needAck` 时发送 ack
- 消息类型至少处理：
  - `WebcastChatMessage`
  - `WebcastRoomUserSeqMessage`

## 6. 当前仓库建议文件拆分

Douyin 必须按下列结构实现：

```text
ttttv_flutter/lib/features/live/providers/douyin/
  douyin_live_provider.dart
  douyin_models.dart
  douyin_signer.dart
  douyin_auth_service.dart
  douyin_danmaku_client.dart
  proto/
    douyin.pb.dart
    douyin.pbenum.dart
    douyin.pbjson.dart
```

说明：

- `douyin_live_provider.dart`
  - 只负责能力编排
  - 不写大段 JS 字符串
  - 不写 protobuf 解析

- `douyin_signer.dart`
  - 承载 `a_bogus`
  - 承载 WebSocket `signature`
  - 负责 `msToken`、`msStub`
  - 统一管理 UA 和环境字符串

- `douyin_models.dart`
  - 承载房间详情中间模型
  - 承载弹幕 args
  - 承载清晰度中间模型

- `douyin_auth_service.dart`
  - 对接 `LiveCookieStore`
  - 提供 `getCookie/saveCookie/clearCookie/hasCookie`

- `douyin_danmaku_client.dart`
  - 独立承载 WebSocket、gzip、protobuf、ack

## 7. 接口与实现映射

### 7.1 Cookie 策略

参考项目策略：

- 用户已保存 Cookie 时优先使用用户 Cookie
- 否则退回默认 `ttwid`
- 进入部分页面时还会补抓 `__ac_nonce` / `msToken`

当前项目建议：

- 继续沿用通用认证弹窗 + `LiveCookieStore`
- `douyin_auth_service.dart` 对外只暴露 Cookie 基础操作
- `douyin_signer.dart` 内部合并：
  - 用户 Cookie
  - 默认 `ttwid`
  - 临时抓取到的 `__ac_nonce`
  - 临时生成的 `msToken`

### 7.2 分类

参考实现：

- 直接请求 `https://live.douyin.com/`
- 从 HTML 中抽取 `categoryData`

实现建议：

- 沿用参考解析，不切换成新接口
- 单独写 `_extractCategoryDataJson`
- 分类页若失败，不影响推荐页与房间页主链路

### 7.3 推荐 / 分类房间

参考接口：

- `https://live.douyin.com/webcast/web/partition/detail/room/v2/`

关键点：

- 需要 `a_bogus`
- 需要 `msToken`
- UA 和环境参数要固定

建议：

- 推荐和分类共用一个 `_fetchPartitionRooms`
- 由 `douyin_signer.dart` 统一生成带签名 URL

### 7.4 房间详情

参考实现存在三条路径：

1. `getRoomDetailByWebRid`
2. `getRoomDetailByRoomId`
3. HTML fallback

当前项目建议实现顺序：

1. 先实现 `web_rid -> webcast/room/web/enter`
2. 再实现 `room_id -> webcast.amemv.com/webcast/room/reflow/info`
3. 最后补 HTML fallback

原因：

- 当前 Flutter 页面入口主要使用房间卡片里的 `web_rid`
- `room/web/enter` 是推荐、分类、搜索之后最顺的主链路
- HTML fallback 作为兜底，不应一开始就成为主路径

### 7.5 播放清晰度与播放地址

参考字段：

- `stream_url.live_core_sdk_data.pull_data.options.qualities`
- `stream_url.live_core_sdk_data.pull_data.stream_data`
- fallback:
  - `flv_pull_url`
  - `hls_pull_url_map`

实现建议：

- 先统一解析成内部 quality/url 模型
- 输出 `LivePlayQuality`
- 输出 `LivePlayUrl`
- `LivePlayUrl.urlType` 建议仍用 `auto`

注意：

- Windows 下优先让播放器先尝试 FLV
- 若字段结构异常，再回退到 HLS

### 7.6 搜索

参考接口：

- `https://www.douyin.com/aweme/v1/web/live/search/`

现状判断：

- 参考 Dart 版搜索未显式加 `a_bogus`
- 当前 Rust 版也未加 `a_bogus`
- 但会临时刷新 `ttwid + __ac_nonce`

建议：

- 第一版严格跟当前 Rust 版路径走
- 如果实测被限，再补签名，不要一开始就偏离参考

### 7.7 弹幕

参考 WebSocket：

- `wss://webcast3-ws-web-lq.douyin.com/webcast/im/push/v2/`

关键参数：

- `room_id`
- `user_unique_id`
- `signature`
- Cookie

实现建议：

- `DouyinDanmakuArgs` 至少包含：
  - `webRid`
  - `roomId`
  - `userId`
  - `cookie`

- `douyin_danmaku_client.dart` 必须处理：
  - WebSocket 建连
  - 心跳
  - gzip
  - protobuf decode
  - ack
  - chat / online 消息映射到 `LiveMessage`

## 8. 依赖与文件准备

### 8.1 已存在依赖

当前仓库已存在：

- `flutter_js`
- `dio`
- `crypto`
- `web_socket_channel`

### 8.2 需要新增依赖

Douyin 弹幕 protobuf 需要新增：

- `protobuf`

说明：

- 参考 `douyin.pb.dart` 依赖 `package:protobuf/protobuf.dart`
- `fixnum` 一般会作为传递依赖进入，不需要单独先加

### 8.3 需要迁入文件

如果采用参考项目已生成代码，建议直接迁入：

- `douyin.pb.dart`
- `douyin.pbenum.dart`
- `douyin.pbjson.dart`

不建议在本阶段现场重新设计 proto 结构。

## 9. Windows 风险点

### 9.1 UA 固定

Douyin 对 UA 比较敏感。

参考项目关键 UA：

- HTTP 默认使用 QQBrowser 风格 UA
- 搜索请求里还会使用 Edge/Chrome 风格字段

建议：

- `douyin_signer.dart` 统一维护：
  - 默认 HTTP UA
  - 搜索 UA
  - WebSocket 相关 UA

### 9.2 `a_bogus` 与环境字符串

`a_bogus` 的 JS 里带固定环境字符串。

这意味着：

- 不能随意改浏览器版本字段
- 不能把 query 参数顺序随意重排
- 不能在 provider 内多处拼 URL

建议：

- 统一由 signer 层构造 query 参数并签名

### 9.3 播放流兼容

Douyin 返回的播放地址可能存在：

- FLV
- HLS

建议：

- 第一版输出多条 URL，顺序为 FLV 优先，HLS 次之
- 若 Windows 实测某类流更稳定，再调整排序，不修改 UI 层

## 10. 实施顺序

### 阶段 A：非弹幕主链路

先完成：

1. `douyin_auth_service.dart`
2. `douyin_signer.dart`
3. `douyin_models.dart`
4. `douyin_live_provider.dart`
5. registry 接入

交付标准：

- 推荐可用
- 搜索可用
- 房间详情可用
- 清晰度可切换
- 播放地址可解析
- Cookie 可保存

### 阶段 B：弹幕链路

再完成：

1. protobuf 文件迁入
2. `douyin_danmaku_client.dart`
3. 房间页弹幕接线
4. ack/online/chat 消息验证

交付标准：

- 可稳定收到聊天消息
- 可收到在线人数消息
- 连接断开后可自动重连

### 阶段 C：Windows 定向稳定

最后完成：

- 真实房间联调
- 质量切换验证
- Cookie 登录后高质量流验证
- 房间页 UI 降级检查

## 11. 预计修改文件

必改：

- `ttttv_flutter/lib/core/providers.dart`
- `ttttv_flutter/lib/features/live/presentation/live_page.dart`

新增：

- `ttttv_flutter/lib/features/live/providers/douyin/douyin_live_provider.dart`
- `ttttv_flutter/lib/features/live/providers/douyin/douyin_models.dart`
- `ttttv_flutter/lib/features/live/providers/douyin/douyin_signer.dart`
- `ttttv_flutter/lib/features/live/providers/douyin/douyin_auth_service.dart`
- `ttttv_flutter/lib/features/live/providers/douyin/douyin_danmaku_client.dart`
- `ttttv_flutter/lib/features/live/providers/douyin/proto/douyin.pb.dart`
- `ttttv_flutter/lib/features/live/providers/douyin/proto/douyin.pbenum.dart`
- `ttttv_flutter/lib/features/live/providers/douyin/proto/douyin.pbjson.dart`

可能小改：

- `ttttv_flutter/lib/features/live/application/live_room_controller.dart`
- `ttttv_flutter/lib/features/live/presentation/live_room_page.dart`
- `ttttv_flutter/lib/features/live/presentation/widgets/live_player_widget.dart`

说明：

- 只有在 Douyin 播放 headers 或特殊重试需要扩展时，才动这些通用文件
- 默认不改房间页布局

## 12. 验证清单

实施完成后至少做以下验证：

1. 推荐页可展示 Douyin 房间卡片
2. 搜索“王者荣耀”等关键词可返回直播房间
3. 进入房间后可拿到详情与封面、主播信息
4. 至少一个真实房间可在 Windows 下播放
5. 清晰度切换不报错
6. 保存 Cookie 后再次进入房间仍能播放
7. 弹幕连接能收到 chat
8. 弹幕连接能收到 online
9. `flutter analyze` 通过

## 13. 本轮结论

可以进入实现，但必须按以下原则执行：

- 先做非弹幕主链路，再做弹幕
- signer 独立成文件
- protobuf 直接复用参考生成文件
- 搜索先跟 Rust 版，不先加额外签名
- 不推翻现有房间页结构

如果进入下一步实现，推荐直接从：

1. `douyin_auth_service.dart`
2. `douyin_signer.dart`
3. `douyin_models.dart`
4. `douyin_live_provider.dart`

开始。
