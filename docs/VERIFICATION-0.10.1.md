# CleanNest 0.10.1（45）MLX Serve 监控与外部关闭修复

日期：2026-09-24（验证更新）。基线：0.10.0（44）。本版本补齐独立 `mlx-serve` 服务发现，并修复外部服务关闭被误判为 PID 复用的问题。

## 根因

macOS 的 `ps comm=` 会把长路径截断为 `/Users/zone/.mlx`，而关闭前的系统身份复核读取的是完整 `proc_pidpath`；两者不一致时，CleanNest 为防止 PID 复用而拒绝发送退出信号。GUI App 还可能处于自己的 bootstrap 子域，未显式读取 `gui/<uid>` 时会漏掉用户 LaunchAgent。

此前平台适配器只覆盖 oMLX、MLX-LM、Ollama、LM Studio 和 llama.cpp；监听端口筛选也写死为 8080、11434、1234。使用 MLX Serve 的进程名 `mlx-serve`、默认端口 11234 因此在 `/v1/models` 探测前就被过滤，launchd 配置也无法关联到运行进程。

## 修复

- 从进程参数的完整 `argv[0]` 保存可执行路径，避免 `ps comm=` 截断造成的假身份冲突。
- 显式读取当前用户 `gui/<uid>` launchd 域，并通过 `launchctl print` 补齐 PID、配置路径、KeepAlive、RunAtLoad 和用户归属。
- 外部服务关闭会先复核进程、守护标签、作用域与配置文件身份；发现 KeepAlive 时改为“停用并关闭”，只对当前用户 LaunchAgent 执行精确 `disable` 与 `bootout`，不编辑或删除 plist。

- 新增 `mlxServe` 平台适配器，识别 `mlx-serve` 进程和 11234 默认端口。
- 复用 OpenAI-compatible `/v1/models` 与 `/health` 探测，读取真实模型短 ID，不把模型目录路径当成 API model ID。
- launchd 配置分类复用同一适配器，因此可显示用户 LaunchAgent、KeepAlive / RunAtLoad 和外部停止边界。
- 监听候选端口统一从适配器注册表生成，不再维护第二份硬编码端口列表。
- 未扩大扫描到局域网；仍只探测本机回环地址，未改变外部服务停止的身份复核和确认流程。

## 本机证据

修复前本机存在：

- `/Users/zone/.mlx-serve/bin/mlx-serve`
- 模型：`ARC4NUM-Qwen3.8-Flash-Next-Uncensored-MLX-Serve-4bit`
- `127.0.0.1:11234`
- LaunchAgent：`com.zone.mlx-serve-flash`

该服务的 `/v1/models` 和 `/health` 均返回 HTTP 200，模型状态为 ready；旧版 CleanNest 因识别白名单缺口没有显示它。

## 验证

- Xcode XCTest 全量运行：`CleanNestCoreTests.xctest` 共 218 项，218 通过、1 跳过、0 失败。
- 新增覆盖：`LocalModelRuntimeDiscoveryTests` 确认 `mlx-serve` 命令分类、完整 `argv[0]` 路径和进程身份；`LocalModelSupervisorTests` 确认当前用户 launchd 域、守护标签、ASCII 标签白名单及停用策略；`LocalModelRuntimeTopologyTests` 确认平台适配器、OpenAI-compatible API 和 11234 端口注册。
- `CleanNestSelfTest`：全部检查通过。
- `./build.sh release`：成功构建；App、扫描 XPC、登录项和 MCP 的 Info.plist 版本均为 0.10.1（45）。`codesign --verify --deep --strict` 通过。
- 真机只读验收：本机 CleanNest 显示“1 个模型服务健康运行”，平台为 MLX Serve；详情显示 PID 54748、RSS 约 11.6 GB、`127.0.0.1:11234`、仅本机暴露、“进程 + 监听端口 + 平台 API + launchd 守护”证据，并显示模型短 ID `ARC4NUM-Qwen3.8-Flash-Next-Uncensored-MLX-Serve-4bit`。关闭确认窗正确列出完整可执行路径和 `com.zone.mlx-serve-flash.plist`；本次未停用真实模型。
- 系统 `swift test` 入口仍受本机 Xcode License 状态影响；本次使用 Xcode 同一 toolchain 编译并直接运行 XCTest bundle 完成等价全量验证。真实服务探测不通过测试自动停止或修改服务。

本次验证只读取进程、监听端口、平台 API 和 launchd 元数据；没有停止模型、修改 LaunchAgent 或删除模型文件。正式操作仍需用户在风险确认窗明确确认。
