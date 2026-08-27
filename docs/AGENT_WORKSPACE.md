# Agent 工作区

CleanNest 0.7.8 把多个编程 Agent 留在本机的会话、备份、生成资源、缓存、日志、运行时、虚拟机和状态索引整理为占用账本，并把应用、进程、守护服务、监听端口和本地模型组织成有证据的运行关系图。

首页先回答四个问题：总共占用多少、哪个 Agent 在变化、哪些文件正活跃、哪里出现异常。点进单个 Agent 后，才读取它的分类明细并构建可恢复候选；未进入的 Agent 不会提前生成逐文件处置令牌。

## 只读扫描

- 独立 XPC 扫描服务只读取路径/名称、文件类型、分配块、逻辑大小、修改时间、设备号和文件号；不读取会话正文、代码、提示词或凭据内容。
- 当前用户的打开文件表与近 15 分钟修改时间共同保护活跃文件。打开文件探测失败时，执行候选归零。
- 不跟随符号链接；每个 Agent 最多遍历 600,000 个目录项。概览扫描传回 0 个文件级执行令牌；单 Agent 详情最多传回 5,000 个。
- 读取失败、取消或达到上限的分组不进入执行；上一次完整基线不会被半成品覆盖。

## 概览与单 Agent 详情

- 概览只显示聚合占用、相对上次变化、活跃保护与异常线索，不展示会话/缓存长列表，也不携带执行能力。
- 点击 Agent 后，XPC 只重新验证该供应方；类别账本、逐文件候选、运行关系和恢复记录在同一详情页分层显示。
- 单 Agent 详情扫描不会覆盖全局增长基线；返回概览会释放选择和文件级明细，其他 Agent 仍保持摘要状态。
- “工具账本”是独立入口，不再混在 Agent 首页；没有供应方 dry-run 的工具继续只读。

## 0.7.8 适配器边界

| Agent | 本机验证范围 | 0.7.8 权限 |
| --- | --- | --- |
| Codex | `~/.codex`、应用/进程标记 | 只允许备份优先处理已静置缓存、临时文件和日志 |
| Claude | `~/.claude`、Claude Application Support、应用/进程标记 | 与 Codex 相同 |
| Pi Agent | `~/.pi/agent`、专属 Application Support / Caches / Logs、`com.abcwyc.pi-agent` | 只读元数据 |
| Kimi | `~/.kimi`、kimi-desktop、kimi-code 缓存/日志、Bundle ID | 只读元数据 |
| WorkBuddy | `~/.workbuddy`、WorkBuddy/@genie 数据根、Bundle ID | 只读元数据 |
| Hermes | `~/.hermes`、hermes-studio、应用/进程标记 | 只读元数据 |
| OpenClaw | `~/.openclaw`、进程/守护标记 | 只读元数据 |
| Trae | Trae CN / TRAE SOLO CN Application Support、Bundle ID | 只读元数据 |
| MiniMax Hub | 已验证的应用 Bundle ID 与日志根 | 只读元数据 |
| 小云雀 | 当前没有可复现的本机安装样本 | 仅显示适配器待验证；没有扫描路径 |

“已验证”只表示本机元数据位置或运行身份可复现，不表示供应方授权 CleanNest 改写其私有格式。新增适配器没有执行令牌，外部规则也无法改变这一点。

Agent 卡片优先通过精确 Bundle ID 读取本机已安装 App 的图标。图标只在本机运行时获取，不复制到 CleanNest 仓库或安装包；没有可验证 App 的 CLI/服务使用中性系统图标，避免伪造品牌身份。

## 可以处理什么

执行候选必须同时满足：

1. 位于 `~/.codex`、`~/.claude` 或 `~/Library/Application Support/Claude` 的已验证根内；
2. 属于缓存、临时文件或日志；
3. 是普通文件，不是目录、符号链接、包或设备；
4. 静置超过 15 分钟，扫描时没有被打开；
5. 整个扫描与打开文件探测完整。

候选默认不选择。用户可以按 Agent / 分类批量选择，再展开取消任意单文件。单次最多处理 2,000 个文件和 50 GB 逻辑体积。

## 备份优先事务

1. 执行时重新读取打开文件表，并核对设备号、文件号、所有者、逻辑/分配大小和纳秒级修改时间。
2. 在 `Application Support/CleanNest/AgentRecovery/<操作 ID>` 建立权限为 `0700` 的事务目录。
3. 用同卷硬链接建立临时备份源，再调用 macOS `/usr/bin/ditto` 创建 ZIP；`/usr/bin/unzip -tqq` 必须通过 CRC 完整性检查，并记录流式 SHA-256。
4. 备份完成后再次读取打开文件表并复核全部身份。任何变化都会删除本次未使用的备份并保持原文件不动。
5. 原文件以排他原子重命名进入事务区；任一移动失败时按相反顺序回滚。只有全部移动成功且压缩包已校验，事务原件才会释放。
6. 记录 Agent 目录减少量、备份分配块和处理前后文件系统可用空间。APFS 实测可能小于候选体积，也可能因压缩率低而没有增加。

备份 ZIP 会读取所选文件的真实内容，但只写入本机恢复区，不进入 AI、MCP、遥测或网络请求。恢复清单包含原始绝对路径，这是精确恢复所必需的本机信息。

## 恢复

- 恢复先复核 ZIP 的 CRC 与 SHA-256，拒绝符号链接替换的事务目录，并检查每个原位置。
- 如果 Agent 已重建同名文件，整个恢复失败关闭，不覆盖新文件。
- 事务中断后若原件仍在暂存区，优先原子放回同一文件身份；已释放的原件从校验过的 ZIP 解压恢复。
- 恢复成功后压缩包仍保留，避免自动删除最后一份备份。

## 会话和索引为什么继续只读

当前适配的 Agent 没有一套公开、稳定、统一且可验证的会话索引事务接口。直接改写私有 SQLite、JSONL 或状态文件可能让会话列表与磁盘文件分离。因此 0.7.8 不处理：

- 活跃或已归档会话；
- 状态数据库、队列、索引和锁；
- 记忆、计划、项目资料、凭据、运行时和虚拟机；
- 新增 Agent 的任何文件，即便分类为缓存或日志；
- 未经验证的自定义目录。

这些分组仍可显示占用与归档建议，但没有执行令牌。未来版本只有在存在供应方原生接口或可验证事务契约后才会增加动作。

## 运行关系图

- App 安装证据来自精确 Bundle ID 或规则中列出的应用名。
- Agent 进程必须匹配应用包内可执行路径或有界进程名；不会因为命令参数里偶然出现品牌词就认领进程。
- 用户 launchd 标签只作为守护证据，不自动赋予停止或卸载能力。
- 本地模型节点复用“本地模型”功能栏的进程、监听端口和平台 API 证据。
- 只有 Agent 进程 PID 的已建立 TCP 连接，其对端端口又精确属于已发现模型监听器时，才建立“Agent → 本地模型”关系。只安装 Agent、只启动模型或只配置相同端口都不够。

## 签名可更新规则

用户可以手动导入 `.bundle` 或 `.cleannestrules` 目录包。导入链会：

1. 让 macOS 严格校验整个包的代码签名；
2. 比较规则包与当前 CleanNest 的叶签名证书；
3. 限制 JSON 为 1 MB，验证 schema、修订号、供应方唯一性、规则数量与字符串长度；
4. 拒绝绝对路径、`..`、`file://`、符号链接和直接指向 Library/Caches/Documents/Desktop/Downloads 等宽根的规则；
5. 复制到 CleanNest 数据目录后再次完成签名和内容校验，再启用。

外部规则只描述只读检测根、Bundle ID、进程/守护标记和元数据分类；规则格式没有清理授权字段。任何失败都会回退内置规则，用户可从界面恢复内置基线。

仓库维护者可用 `CleanNestRuleBundleTool <绝对输出.bundle> --sign <身份>` 从当前内置目录生成候选规则包。工具拒绝覆盖现有路径，且不保存或读取私钥；签名仍由 macOS Keychain 中明确指定的身份完成。普通用户只需要在 App 内选择规则包，不需要使用终端。

## 开发工具原生接口

CleanNest 不把所有开发工具缓存都当普通目录删除：

| 工具 | 0.6.4 预览 | 执行边界 |
| --- | --- | --- |
| Git worktree | 用户选择仓库后运行 `worktree list --porcelain` 与 `worktree prune --dry-run --verbose` | 每次执行前重新 dry-run；仅调用 `worktree prune --verbose`，不删除仍存在的工作树目录 |
| Docker | `docker system df --format json` | `system prune` 没有官方 dry-run，保持只读 |
| Hugging Face | 离线运行 `hf cache ls` 与 `hf cache prune --dry-run` | 重新 dry-run 后可调用 `hf cache prune --yes`；未引用修订可能需要重新下载，不进入 CleanNest ZIP 恢复区 |
| npm | `npm config get cache` | `cache verify` 会同时垃圾回收，`cache clean --force` 会清空；不开放广域执行 |
| pip | `python -m pip cache info` | `cache purge` 没有 dry-run；不开放广域执行 |

Hugging Face 检查设置 `HF_HUB_OFFLINE=1`、`HF_HUB_DISABLE_TELEMETRY=1` 与 `DO_NOT_TRACK=1`。CleanNest 不为这些功能自动安装 CLI。

更完整的隐私与失效边界见 [隐私说明](../PRIVACY.md)、[威胁模型](THREAT_MODEL.md) 与 [架构](ARCHITECTURE.md)。
