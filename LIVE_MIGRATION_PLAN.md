

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



| 里程碑 | 完成标志 |
|---|---|
| M1：数据层就绪 | 所有直播 HTTP 接口在 Dart 层可调通（Phase 1）|
| M2：首页可用 | 直播首页展示推荐/搜索结果，四平台切换正常（Phase 2）|
| M3：播放可用 | 进入房间、选清晰度、HLS 流播放正常（Phase 3）|
| M4：弹幕可用 | 弹幕实时滚动、设置可保存（Phase 4）|
| M5：收藏历史可用 | 收藏/历史增删查正常（Phase 5）|
| M6：登录可用 | Bilibili 扫码和手动 Cookie 登录均可用（Phase 6）|
| M7：完成 | 全流程冒烟通过，合约文档更新（Phase 7）|
