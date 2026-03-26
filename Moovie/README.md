# Moovie - Rust 影视聚合服务

基于 Rust 重构的本地优先影视聚合搜索 API 服务，为前端提供支持。

## 功能特性

- ✅ 多源并发搜索
- ✅ 插件化资源站协议
- ✅ 播放链接解析
- ✅ 统一 RESTful API
- ✅ 本地 SQLite 存储（待完善）
- ✅ 观影记忆系统（待完善）

## 快速开始

### 环境要求

- Rust 1.75+
- Cargo

### 安装依赖

```bash
cd Moovie
cargo build
```

### 运行服务

```bash
cargo run
```

服务将在 `http://127.0.0.1:5007` 启动。

## 项目架构

```
Moovie/
├── src/
│   ├── api/          # API 接口层
│   │   ├── health.rs # 健康检查
│   │   ├── search.rs # 搜索相关API
│   │   └── play.rs   # 播放解析API
│   ├── core/         # 核心模块
│   │   ├── config.rs # 配置管理
│   │   └── app_state.rs # 应用状态
│   ├── models/       # 数据模型
│   │   ├── vod_item.rs
│   │   ├── site.rs
│   │   └── history.rs
│   ├── services/     # 业务服务
│   │   ├── search_service.rs
│   │   ├── source_crawler.rs
│   │   └── play_parser.rs
│   ├── utils/        # 工具模块
│   │   ├── error.rs
│   │   └── response.rs
│   └── main.rs      # 程序入口
├── API.md           # API 文档
└── Cargo.toml
```

## API 使用示例

详细文档请参考 [API.md](./API.md)

### 搜索视频

```bash
curl "http://127.0.0.1:5007/api/search?kw=海贼王"
```

### 获取详情

```bash
curl "http://127.0.0.1:5007/api/detail?source_key=yinghua&vod_id=12345"
```

### 解析播放链接

```bash
curl "http://127.0.0.1:5007/api/play/parse?play_url=xxx"
```

## 技术栈

- **Web框架**: Axum 0.7
- **异步运行时**: Tokio
- **HTTP客户端**: Reqwest
- **数据库**: SQLx + SQLite
- **序列化**: Serde
- **日志**: Tracing

## 开发计划

- [ ] 完善 SQLite 本地存储
- [ ] 实现观影记忆系统
- [ ] 添加配置文件支持
- [ ] 单元测试和集成测试
- [ ] Docker 支持

## 许可证

本项目仅供学习交流使用。
