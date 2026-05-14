# 影视模块开发任务

参考项目: `example/` (luna-tv-fork)

---

## 阶段 1: 修复插件不能播 — 缺失特殊源处理

### 1.1 HTML 详情页解析
- [x] 在 `NativeSourceCrawler.getDetail()` 中使用源的 `detailUrl` 配置
- [x] 实现 HTML 页面 m3u8 提取（正则匹配 ffzy 等源）
- [x] 实现 HTML 页面标题/封面/描述/年份提取
- 参考: `example/src/lib/downstream.ts:199-366` (`handleSpecialSourceDetail`)

### 1.2 vod_content M3U8 兜底提取
- [x] 当 `vod_play_url` 解析不到 m3u8 时，从 `vod_content` 正则提取 m3u8 链接
- 参考: `example/src/lib/downstream.ts:265-269`

### 1.3 通用 M3U8 正则匹配
- [x] 添加通用 m3u8 链接正则 `M3U8_PATTERN` 用于各种源的内容解析
- 参考: `example/src/lib/downstream.ts:198`

### 1.x 配置标记
- [x] `LocalVodSource` 添加 `hasCustomDetail` getter（当 `detailUrl != apiUrl` 时启用 HTML 解析）

---

## 阶段 2: 播放慢 — 代理层无缓存

### 2.1 M3U8 代理缓存
- [x] `LocalMediaProxy` 添加内存缓存，缓存已重写的 M3U8 playlist
- [x] TTL 5 分钟，最大 50 条
- [x] 缓存键: upstream_url，过期自动淘汰
- 文件: `lib/features/play/data/local_media_proxy.dart`

### 2.2 图片代理（可选）
- [ ] 豆瓣封面图代理（降低源站暴露风险）

---

## 阶段 3: 搜索慢 — 三个关键缺失

### 3.1 搜索缓存
- [x] 创建 `SearchCache` 类，内存 Map 缓存
- [x] 正缓存: 成功结果 10 分钟 TTL
- [x] 负缓存: timeout/forbidden 状态缓存
- [x] 自动过期清理（LRU，最大 1000 条）
- 文件: `lib/features/search/data/search_cache.dart`
- 参考: `example/src/lib/search-cache.ts`

### 3.2 单源超时控制
- [x] 每源搜索 8 秒超时（`Future.timeout`）
- [x] 超时的源写入负缓存，后续搜索跳过
- 文件: `lib/features/search/data/native_search_repository.dart`

### 3.3 搜索多页支持
- [x] `SourceCrawler.search()` 支持 `page` 参数
- [x] `SearchRepository.search()` 拉取多页（最多 5 页）
- [x] 并行获取各源的额外页
- 文件: `lib/features/search/data/native_source_crawler.dart`, `native_search_repository.dart`
- 参考: `example/src/lib/downstream.ts:138-195`

---

## 变更文件清单

| 文件 | 变更 |
|---|---|
| `lib/features/search/data/native_source_crawler.dart` | HTML 详情页解析、M3U8 兜底提取、通用正则、page 参数支持 |
| `lib/features/search/data/native_search_repository.dart` | 搜索缓存集成、8s 超时、多页拉取 |
| `lib/features/search/data/search_cache.dart` | **新建** 搜索缓存类 |
| `lib/features/play/data/local_media_proxy.dart` | M3U8 playlist 内存缓存 |
| `lib/features/settings/data/local_sources_store.dart` | `hasCustomDetail` getter |

## 已完成

- [x] 拆除直播模块及相关代码
- [x] 修复插件不能播 — 缺失特殊源处理
- [x] 播放慢 — 代理层无缓存
- [x] 搜索慢 — 三个关键缺失
