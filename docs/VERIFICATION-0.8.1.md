# CleanNest 0.8.1 验证报告（缺陷修复）

日期：2026-08-29
版本：0.8.1（Build 39）
分支：`agent/0.8.1-bugfixes`（叠在 `agent/0.8-cleanup-tiers` 上）
性质：本机开发里程碑，未创建 GitHub tag 或 Release

## 结论

0.8.1 修复 10 个审计确认的缺陷，其中 3 个高危（扫描态永久卡死、恢复重试永久阻塞、子进程管道死锁）。全量测试 193 项通过（0.8.0 基线 192 + 1 项新增恢复重试回归测试），1 项按设计跳过。GUI 目标在 Xcode 工具链下编译通过。

## 审计方式与覆盖说明

本轮审计最初尝试 5 路并行子代理，因账号并发限额仅 1 路完成（变动/事务/小目标模块，质量很高）；按用户指示改为**主线全量串行**，不再使用子代理。覆盖深度分三层，如实记录：

- **逐行深读**：`Sources/CleanNestMutation/`（全部）、`Sources/CleanNestScanner/`、`Sources/CleanNestMCP/`、`Sources/CleanNestLoginItem/`、`Sources/CleanNestRuleBundleTool/`、`Sources/CleanNestSelfTest/`（子代理完成，主线复核确认）；`ScannerServiceClient.swift`、`AppStore.swift` 关键路径（扫描/恢复/取消/失效守卫链）、`LocalModelSupervisor.swift`、`SafeFileOperations.swift`、`CleanupScanner.swift`、`EvolutionMemory.swift` 排序影响面、`ProcessMemoryInspector.terminate`（主线）。
- **全量模式扫描**（所有 Sources）：force unwrap/`try!`、`Dictionary(uniqueKeysWithValues:)`、Timer/Observer 泄漏、信号量、除零/NaN、整数溢出转换、进程终止调用。
- **未逐行覆盖**：本地模型发现/拓扑、LocalAIClient、MetricsStore、AppUpdate、多数 View 主体。这些只经过模式扫描，后续版本可继续深化。

## 修复清单

| # | 严重度 | 位置 | 缺陷与修法 |
| --- | --- | --- | --- |
| 1 | 高 | AppStore.swift `closeAgentWorkspaceDetail` | 详情扫描在途返回概览 → 完成回调守卫早退 → 扫描态永久卡死。修法：返回概览先取消在途详情扫描 + 守卫兜底解锁 |
| 2 | 高 | AgentWorkspaceRecoveryService 恢复路径 | 恢复崩溃后重试被 restoreConflict 永久阻塞（解压产物新 inode 与原始身份不等）。修法：逐项 `restoredAt` 持久化进度 + 对身份不符的既有文件与权威副本 SHA-256 比对，区分自身产物与 Agent 重建 |
| 3 | 高 | AgentWorkspaceRecoveryService.run | 子进程 stderr 写满管道缓冲与父进程 waitUntilExit 互等死锁。修法：等待期间并发排空 |
| 4 | 中 | CleanNestScanner/main.swift | 任一 XPC 连接失效 → 进程 50ms 后退出 → 腰斩其他连接在途扫描。修法：连接计数，末连接关闭才退出 |
| 5 | 中 | MCPServer.swift ×3 | serverInfo 硬编码 0.7.9，0.8.0 发版时漏更新。修法：新增 `CleanNestVersion` 单一版本来源 |
| 6 | 中 | 8 处（LocalModelSupervisor×2、ScannerWorker、SafeFileOperations、NativeDiskAnalyzer、DiskEvidence、DiskAnalyzeView×2） | `Dictionary(uniqueKeysWithValues:)` 遇重复键崩溃；输入来自 launchctl 输出/磁盘持久化/重叠规则，重复键真实可达。修法：保留第一条 |
| 7 | 低 | CleanNestMCP/main.swift | readLine 无界读入。修法：分块有界读取 + 超限行排空回标准错误 |
| 8 | 低 | CleanupScanner.swift | 无修改时间的文件绕过静置门槛。修法：失败关闭不进入候选 |
| 9 | 低 | AgentWorkspaceView 恢复记录行 | 崩溃遗留非终态记录永久显示进行中。修法：无活跃操作时显示为"需要恢复检查"（仅展示层） |
| 10 | 低 | AgentWorkspace.swift（0.8.0 引入） | 安装残留来源目录集合跨 walk 合并未截断。修法：统一 16 个上限 |

## 验证

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：193 项，0 失败，1 按设计跳过。
- `swift build`（Xcode 工具链，含 GUI）：通过。
- `swift run CleanNestSelfTest`：全部检查通过。
- 新增回归测试 `testRestoreRetryAfterCrashRecognizesOwnExtractedFiles`：模拟 0.8.0 旧清单（无逐项标记）+ 恢复产物已在原位，重试必须识别自身产物完成恢复而非误报冲突；既有 `testRestoreRefusesToOverwriteAgentRecreatedFile` 继续锁定真冲突仍被拒绝。
- 既有 `testBackupFirstRecoveryRemovesAndRestoresSettledCacheFile` 等处置-恢复往返测试全部通过，证明恢复协议改动向后兼容（旧清单缺省 `restoredAt=nil` 正常解码）。

## 执行记录

| 时间（2026-08-29，EDT） | 动作 | 结果 |
| --- | --- | --- |
| 15:2x | 5 路并行审计子代理：4 路被账号并发限额 403 掐死，1 路（变动/事务模块）完成并带回 4 个实锤 | 按用户指示改为主线全量串行 |
| 15:4x–21:1x | 主线串行审计 + 10 项修复 + 回归测试 | 见修复清单 |
| 21:21 | `swift test --filter AgentWorkspaceTests` | 25/25 通过 |
| 21:2x | 全量测试 + GUI 构建 + 自检 | 193 通过 / 通过 / 通过 |

## 边界与后续

- 0.8.1 未重跑真实 48 小时常驻、三语言 UI 门与 Developer ID/公证，与 0.7.9 相同。
- 未逐行覆盖的模块见"覆盖说明"；不声称本轮审计穷尽了全部缺陷。
- `CleanNestVersion` 与三份 plist 仍需人工同步（仓库已有 `scripts/verify-release-candidate.sh` 核对一致性，发版门会拦截不一致）。
