# 架构与安全边界

## 主要层次

```text
SwiftUI 界面
    ↓ 用户明确操作
AppStore 状态与任务编排
    ├─ CleanNestCore：扫描、解码、安全策略、进程复核、SQLite 指标
    ├─ Mole CLI：独立本地子进程，可替换、可升级
    ├─ mlx_lm.server：仅 127.0.0.1 的可选本机解释服务
            ↓ 严格 JSON 校验
       只读建议，不产生执行能力
    └─ CleanNestMCP：stdio only 的独立只读进程
            ↓ 只读打开本机快照与 SQLite WAL
       无 HTTP、无写工具、无文件正文
```

- `Sources/CleanNest`：窗口、视图、App 生命周期、本机 MLX 进程管理和用户操作编排。
- `Sources/CleanNestCore`：不依赖 SwiftUI 的模型、扫描器、命令运行器、JSON 解码、AI 协议和安全策略。
- `Sources/CleanNestSelfTest`：跨模块集成自检，包括进程树终止和协议绕过回归。
- `Sources/CleanNestMCP`：换行分隔 JSON-RPC 的 stdio 入口；协议和工具实现位于 Core。
- `Tests/CleanNestCoreTests`：可定位的确定性单元测试。
- `build.sh`：编译、生成图标、原子组装 App Bundle、签名并验证指定要求。

## 扫描与解释数据流

1. 用户选择功能或目录。
2. App 根据路径和完全磁盘访问探测决定是否允许遍历。
3. Mole 可用时读取其结构化输出；否则只在安全允许时使用原生扫描器。
4. 磁盘结果生成有界的文件类型、年龄、来源、用途、可恢复性与增长证据，并用 Treemap 展示当前层级。
5. 用户主动请求 AI 时，客户端构造脱敏、限量、token 化快照。
6. 回环模型返回严格 JSON；客户端验证完整字段、token、枚举、大小和语义边界。
7. UI 展示经本机规则校正后的说明。模型没有执行通道。

## 本机学习数据流

1. 用户在清理项菜单中明确选择“以后优先清理”或“以后优先保留”，或在 AI 结果上提交一次有帮助 / 不准确评价。
2. `EvolutionMemory` 将候选项类型、规范化名称与路径的不可逆指纹作为稳定键，不写入候选项完整路径；模型 ID 同样只保存不可逆的稳定哈希。
3. 成功移到废纸篓只增加观察次数，永远不能覆盖用户明确的保留偏好。
4. 后续清理扫描先按用户偏好排序，再参考 AI 优先级；记忆不会改变勾选状态或安全策略。
5. 用户可在“本机学习”页审计记录并清空整个记忆文件。

## 本机状态数据流

Mole 状态与原生内存探测合并为单次 `SystemSnapshot`。App 运行时每 60 秒写入 `metrics.sqlite3`，默认保留 30 天；图表按时间窗口有界查询。MCP 只读打开同一 WAL 数据库，不创建表、不修剪数据。详见 [METRICS.md](METRICS.md) 与 [MCP.md](MCP.md)。

## 高风险操作边界

- 文件：只接受白名单根目录的严格后代，拒绝根目录、受保护路径和符号链接，默认移到废纸篓。
- 应用卸载：App 本体必须位于标准 Applications 目录，相关文件只接受 Bundle ID 精确匹配。
- 进程：操作前后复核 PID 身份、启动时间和可执行文件，保护系统/关键进程，先正常退出再由用户决定是否强制。
- 权限：只根据实际读取结果分类，不把系统设置跳转当授权成功，也不循环触发访问窗口。
- 网络：AI 端点固定为 IPv4 loopback HTTP，禁用代理、Cookie、凭据存储、缓存和重定向。
- 更新检查：仅在用户点击后通过临时无 Cookie 会话读取 GitHub 公开的最新正式 Release；限制响应大小、验证语义版本和官方仓库 HTTPS 页面，只提供浏览器跳转，不下载或替换 App。
- MCP：只允许本机 stdio，工具集合固定为只读查询；不暴露文件处理、进程结束或设置修改。

## 发布信任边界

CI 的 ad-hoc 签名只证明 Bundle 结构可构建，不代表发布者身份。面向普通用户的二进制必须使用 Developer ID、Hardened Runtime、Apple 公证和可验证校验值。流程见 [RELEASING.md](RELEASING.md)。
