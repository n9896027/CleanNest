# CleanNest 0.8.0 验证报告（Agent 工作区分层清理）

日期：2026-08-29
版本：0.8.0（Build 38）
分支：`agent/0.8-cleanup-tiers`（叠在 `agent/github-project-introduction` 上）
性质：本机开发里程碑，未创建 GitHub tag 或 Release

## 结论

0.8.0 把 Agent 工作区的处置能力从"仅缓存/临时文件/日志"扩展为按类别分层的静置门槛，全部走既有的备份优先可恢复事务。全量测试 192 项通过（含 9 项新增），1 项按设计跳过（需真实 Ollama 环境）。GUI 目标在 Xcode 工具链下编译通过。

本轮没有扩大执行权限的供应方边界：处置仍然只限 Codex/Claude 已验证根，其余 8 个适配器继续只读，但它们共享同一套分类智能（安装包残留识别、虚拟机陈旧标记在所有工作区都生效）。

## 版本说明（用户可见变化）

| 变化 | 说明 |
| --- | --- |
| 新类别"安装包残留" | 压缩包（`.zst`/`.zip`/`.dmg`/`.pkg`/`.tar` 系）+ 同目录已有同名解压内容 + ≥16 MB → 重分类为可再生态，15 分钟门槛即可处置 |
| 分层静置门槛 | 缓存/临时/日志/安装残留 15 分钟；备份、已归档会话、超时虚拟机 30 天；活跃会话 60 天 |
| 虚拟机整组陈旧判定 | 整组 30 天未写入 → "默认保留"降"可归档复核"；活跃组不拆零件 |
| 类别行文案分层 | "可进入安全处置"（已有候选）与"仅供后续复核"（仅建议层）分开显示 |
| 会话风险明示 | 候选组与归档建议页提示：移除会话文件后 Agent 列表可能短暂保留失效条目，恢复备份即还原 |

## 优化思路（两次人工清理 → 规则映射）

本版设计依据是 2026-08-29 本机两次真实清理的复盘（Claude 工作区回收 8.6 GB、Codex 工作区回收 3.2 GB），每一条规则都对应一个手工验证过的判断：

| 人工清理经验 | 0.8.0 规则 |
| --- | --- |
| `cache-backup-20260605_*`（1.4 GB）：升级时备份的缓存，是"备份的备份" | 名称含 cache 已命中可再生态；本版起处置层真正可达，UI 区分"可处置/仅复核"避免误读 |
| `rootfs.img.zst`（1.2 GB）：解压件 `rootfs.img` 就在旁边，压缩包是重复内容 | 新类别"安装包残留"：兄弟存在才成立，无兄弟的压缩包可能是唯一副本，保持原类别 |
| 虚拟机本体 2 个月未启动（5.9 GB） | 整组 30 天未写入才进入复核；整组判定防止从活跃 VM 上拆 `efivars.fd` 这类保持创建时间的零件 |
| `~/.codex/backups/logs_2_*`（1.7 GB）：一次性维护快照 | 备份类 30 天静置门槛后可处置 |
| Codex 会话按月分层删除（留当月与上月） | 已归档会话 30 天、活跃会话 60 天；UI 不假设用户意图，只提供候选与逐文件勾选 |
| `generated_images`（414 MB）是 gpt-image 产出资产 | 生成内容永久只读，新增明示保护理由，任何年龄不豁免 |

反向约束同样入库：记忆、计划、状态索引、凭据、运行时继续只读；外部签名规则包仍然无法扩张处置边界。

## 改动清单

- `Sources/CleanNestCore/AgentWorkspace.swift`：新增 `installerLeftovers` 类别与 `AgentWorkspaceMutationPolicy` 共享策略；`Configuration` 增加 `sessionCandidateInterval`（默认 60 天）与 `installerLeftoverMinimumBytes`（默认 16 MB）；`walk()` 改为按类别分流输出；虚拟机组两遍扫描（首遍判陈旧，陈旧后二遍收集候选）。
- `Sources/CleanNestMutation/AgentWorkspaceRecoveryService.swift`：准入与执行校验改用同一策略的每类别年龄门；错误文案更新。
- `Sources/CleanNest/AgentWorkspaceView.swift`：新类别图标（`doc.zipper`）、预览文案分层、归档建议页 0.8.0 说明、会话候选组索引漂移提示。
- `Sources/CleanNest/AppStore.swift`：空选择提示文案更新。
- `Sources/CleanNestCore/ScannerXPCContracts.swift`：扫描 XPC 协议 6 → 7（契约新增类别枚举值）。
- `Resources/*.plist` ×3：0.8.0 / Build 38。
- `Tests/CleanNestCoreTests/AgentWorkspaceTests.swift`：9 项新测试 + 1 项既有测试锁定 60 天门。
- `docs/AGENT_WORKSPACE.md`：适配器边界表、处置条件、会话/索引/内容资产边界三节重写。

## 自动验证

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：192 项，0 失败，1 项按设计跳过（真实 Ollama 环境）。
- `swift build`（Xcode 工具链）：全部目标含 GUI 编译通过。
- 新增测试覆盖：安装残留有/无兄弟双向判定、16 MB 体积下限、备份 30 天门、已归档 30 天门、活跃会话 45 天拒/61 天放、虚拟机活跃保持与陈旧复核、生成内容 120 天仍只读、执行侧对低于门槛会话候选的二次拒绝、陈旧备份的完整处置-恢复往返。

注意：CLT-only 环境无法编译 GUI 目标（SwiftUI 宏插件缺失）与 XCTest；本机验证统一使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

## 执行记录

| 时间（2026-08-29） | 动作 | 结果 |
| --- | --- | --- |
| 14:46 | 分支 `agent/0.8-cleanup-tiers` 创建（基于未合入的 `agent/github-project-introduction`，含其 README/演示截图两个提交；PR 时需先合入前置分支或变基） | — |
| 14:47–15:03 | Core/Mutation/View/AppStore/XPC/Plist/测试改动 | 见改动清单 |
| 15:04 | `swift test --filter AgentWorkspaceTests` | 24/24 通过 |
| 15:04 | `swift test` 全量 | 192 项 0 失败 1 跳过 |
| 15:05 | `swift build`（含 GUI 目标） | 通过 |

本版动机清理（同日早些时候手动执行，已验证安全路径）：Claude 侧删除 `cache-backup-20260605_002356`、`rootfs.img.zst` 与整个陈旧 `claudevm.bundle`；Codex 侧删除 `backups/logs_2_*` 与 2026-03~06 月会话。合计回收约 11.8 GB，两应用运行无异常。

## 边界与后续

- 处置仍是文件级：清空后的空目录留在原位。目录级回收（含空目录修剪）是后续候选，需要目录身份的同等强度校验。
- 会话清理不修 Agent 私有索引，列表失效条目属已知现象；若 Codex/Claude 未来提供索引事务接口，再评估 Index-aware 清理。
- 其余 8 个只读适配器要获得处置权限，需要逐供应方验证根目录与事务安全性后单独放开，不随规则包扩张。
- 0.8.0 未重跑真实 48 小时常驻、三语言 UI 门与 Developer ID/公证流程；这些仍是 0.7.9 同款未过门项。
