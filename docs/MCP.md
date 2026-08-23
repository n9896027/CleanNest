# CleanNest 只读 MCP

CleanNest App Bundle 内含 `Contents/MacOS/CleanNestMCP`。它让本机 AI 客户端读取 CleanNest 已生成的健康指标和脱敏证据，不提供任何写入或执行能力。

## 连接方式

MCP 只使用标准输入/输出：每行一个 JSON-RPC 消息，标准输出只写协议响应。它不监听 HTTP/TCP 端口，不进行服务发现，也不接受远程连接。

在支持本地 stdio MCP 的客户端中，将命令设置为 App 内的完整路径：

```json
{
  "mcpServers": {
    "cleannest": {
      "command": "/Applications/CleanNest.app/Contents/MacOS/CleanNestMCP"
    }
  }
}
```

设置页可以复制当前 App 的实际路径和配置片段。

## 可读取工具

| 工具 | 返回内容 |
| --- | --- |
| `cleannest.server_status` | 哪些 CleanNest 本机数据源已存在 |
| `cleannest.latest_snapshot` | 最近一次 CPU、内存、磁盘、电池和温度样本 |
| `cleannest.metric_history` | 有界的 1 小时、24 小时、7 天或 30 天趋势 |
| `cleannest.top_processes` | 最多 20 个近似内存足迹；无命令行参数和可执行路径 |
| `cleannest.disk_evidence` | 最近一次显式磁盘分析生成的脱敏元数据证据 |
| `cleannest.cleanup_preview` | 最近一次清理扫描的 token 化预览 |
| `cleannest.activity_log` | 有界的活动记录，主目录路径替换为 `~` |

所有工具都声明 `readOnlyHint=true`、`destructiveHint=false`、`openWorldHint=false`。输入 schema 禁止额外参数，消息最大 1 MiB，列表和历史查询都有数量上限。

## 协议兼容

服务支持 MCP `2026-07-28` 的 `server/discover` 和逐请求版本元数据，同时兼容仍采用 `initialize` 的 `2025-11-25`、`2025-06-18` 与 `2025-03-26` 客户端。未知版本、未初始化请求、未知工具和额外参数会被拒绝。

## 信任边界

“只读”表示 MCP 没有删除文件、移动废纸篓、结束进程、运行维护任务、启动模型或修改设置的工具。它仍会把已保存的本机元数据交给你配置的 MCP 客户端；只应在你信任的本机客户端中启用。退出 CleanNest 不会自动结束由其他客户端启动的 MCP 子进程，生命周期由客户端管理。
