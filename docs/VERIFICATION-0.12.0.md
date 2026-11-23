# CleanNest 0.12.0 验证记录

日期：2026-11-23

范围：P0-A 通用清理执行前活跃检查、P0-B 逐路径复核、P0-C 执行账本／最终对账／恢复、P0-D 配置引用与特殊占用证据。本文记录代码、自动化和隔离 Home 中的真实 App 界面验收，不是发布证明。

本轮 P0 界面验收时，App 的 `Info.plist` 为 **0.11.0（49）**，验收对象是包含 0.12.0 P0 源码的 **Debug 测试构建**。发布准备阶段已将三份 plist 与 `CleanNestVersion` 统一为 **0.12.0（50）**；这不改变上述证据对应 Debug 构建的性质，最终 RC 仍须从通过检查的干净提交重新构建。

## 最终自动化验收

以下命令均在仓库根目录运行，并显式使用完整 Xcode；未修改全局 `xcode-select` 设置。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

最终结果：**共执行 286 项，0 失败，1 项跳过**。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run CleanNestSelfTest
```

最终结果：`✓ CleanNestSelfTest：全部检查通过`。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift Tools/LocalizationAudit.swift Resources/Localizable.xcstrings Sources/CleanNest --strict-source
```

最终结果：Catalog 共 2599 条，zh-Hans／en／zh-Hant 各 2599 条；`source_static_missing=0`，`source_dynamic_requires_review=0`。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --product CleanNest
```

最终结果：Release 配置编译成功。该命令只验证 Release 代码路径可编译，没有生成或公证安装包。

## 真实 App 隔离界面验收

### 隔离方式

- 测试 Home：`ui-fixture-home`，位于本次任务工作区。
- App 以 `CFFIXED_USER_HOME=<测试 Home>`、独立 `TMPDIR` 和 Debug 专用 `CLEANNEST_UI_TEST_SAFE_RECYCLER=<测试 Home>` 启动。
- 所有清理、重试和恢复只针对测试夹具；没有清理真实用户数据，没有结束用户进程，没有清空废纸篓、删除快照或执行 purge。
- 权限入口只打开 macOS“系统设置 → 隐私与安全”，可见“完全磁盘访问权限”行；未修改任何 TCC 授权。

### 清理、单项重试、恢复和重新扫描：通过

- Active 夹具为 188416 字节，Batch 夹具为 180224 字节，界面合计显示 369 KB。
- 混合执行 `6E64FE28-8E67-4AF2-8E84-3501D6CCED98` 中，Active 被测试 holder 的活跃文件保护拦截，Batch 成功移入隔离废纸篓；没有把部分成功伪报为全部成功。
- 释放 holder 后，单项重试 `8FACF970-66E7-4EF4-A1C0-40DF32924C0E` 成功，界面显示“复核通过，已把 1 项移到废纸篓”和 188 KB。
- 两项均通过“恢复原位置”恢复；账本状态为 `restored`，恢复没有新增清理执行，执行记录数保持 3 次。
- 文件系统复核确认 Active、Batch 源目录均存在，隔离 `.Trash` 为空。
- 最新成功记录的“复核最终空间”显示 `+3.6 MB`，并明确说明包含同期系统变化、不作独占归因。
- 重新扫描后两个候选恢复为 2 项、369 KB；符号链接仍只有保护项，不提供清理重试。

### APFS 与本地快照：修复后通过

- 只读命令确认 APFS 容器容量 994662584320 B，已用 764081422336 B，未分配 230581161984 B；这些是采集时刻的系统总账，不是可清理量。
- `tmutil listlocalsnapshots /` 只返回 `Snapshots for disk /:` 标题，没有快照名称。修正标题过滤后，真实界面显示“系统返回 0 个本地快照”。
- 当前 macOS 的 `APFS Volume Disk (Role)` 与 `Capacity Consumed` 格式均已接入；旧 `Capacity`／`Used` 格式继续保留。
- 真实界面初次只显示 VM。运行时探针确认不是 SwiftUI 丢行，而是 `diskutil` 对前四个卷使用树形前缀 `|`，解析器此前只识别没有该前缀的最后一个卷。
- 修正树形前缀归一化后，有界探针解析到 `disk3s1`、`disk3s2`、`disk3s3`、`disk3s5`、`disk3s6` 五卷；重新构建后的真实界面完整显示 System、Preboot、Recovery、Data、VM。
- 容量未由单卷输出提供时保持“未知”，没有把容器共享容量重复分配给各卷，也没有把 Preboot、Recovery、VM 自动视为垃圾。

### 稀疏文件：通过

- 夹具 `Downloads/CleanNest-UI-P0-Sparse.dat` 的逻辑大小为 134217728 字节，实际分配为 16384 字节。
- 从测试 Home 进入 Downloads 后，该文件成为当前大文件清单的直接文件。
- “核对详情”显示“逻辑 134.2 MB · 实际分配 16 KB · 稀疏差额 134.2 MB”，并明确说明“稀疏差额不是可直接释放的物理空间；实际分配块才用于磁盘占用解释”。
- 目录清单按实际分配显示 16 KB，没有把 128 MiB 逻辑大小当成物理占用。

## 定向自动化结果

| 测试套件 | 结果 | 主要覆盖 |
| --- | ---: | --- |
| `CleanupActivityPreflightTests` | 10 通过 | 活跃文件、严格后代、相似前缀、探测失败、移动前新增活跃、身份变化和权限分类 |
| `CleanupReviewTests` | 8 通过 | 单项重试、重新扫描、保留副本变化、范围外路径、混合批次和重复失败原因 |
| `CleanupScanIssueTests` | 4 通过 | 逐路径扫描保护证据、数量上限、旧 JSON 兼容与复核动作边界 |
| `CleanupExecutionLedgerTests` | 6 通过 | 混合成败、持久化、中断、损坏记录、最终空间、恢复冲突、身份变化和假成功 |
| `ModelConfigurationReferenceInspectorTests` | 9 通过 | JSON／YAML／TOML、转义、缺失目标、越界、符号链接、大小上限和 Agent 候选降级 |
| `AgentWorkspaceTests` | 25 通过 | Agent 扫描、活跃保护、候选年龄门、备份恢复和只读适配回归 |
| `ApplicationContainerReadOnlyInspectorTests` | 4 通过 | 私有容器、共享组、签名归属、退出状态、越界位置和符号链接 |
| `ApplicationDependencyGraphTests` | 4 通过 | 容器证据接入、私有相关文件、系统项目只读和卸载门回归 |
| `APFSReadOnlyDiagnosticsTests` | 7 通过 | 稀疏文件、当前与旧 APFS 格式、树形前缀、快照标题、废纸篓、命令失败和敏感原始输出不保留 |
| `DiskCapacityTruthTests` | 3 通过 | 卷已用／可用／重要用途可用容量与文件归类量分离 |

最终总数以最后一次完整 `swift test` 为准。

## 已落地的关键规则

### 扫描与执行复核

- `.activeFile`、`.activityProbeUnavailable`、`.permissionDenied`、`.operationFailed` 可单项重试；重试重新进入 `TrashService`，不跳过执行门。
- `.targetChanged`、`.validation`、`.missingResult` 只允许重新扫描，不能拿旧候选强制重试。
- 扫描保护项记录实际 URL、原因和下一步；只允许 Finder 定位、权限设置和重新扫描，不能直接重试移动。
- 保留副本变化保留具体错误说明；范围外或未知路径不能注入复核项。
- 成功项仅移除自己的候选与复核记录；其他失败项和原因保持不变。

### 执行账本与恢复

- 执行开始先写入 `pending`，完成后记录实际废纸篓目标与执行前后身份；活动记录使用同一执行 ID。
- 源路径未消失、目标不在当前用户废纸篓、目标缺失或身份不符时进入 `indeterminate`，不伪造成功。
- 候选体积、确认移入量、即时 APFS delta 与最终观测分别展示；最终观测等待相关废纸篓项目消失，并声明包含同期系统变化。
- 恢复仅接受当前用户废纸篓直接子项、身份一致、原位置安全且不存在同名项目的记录；重复恢复不会覆盖文件。
- 损坏或版本不支持的账本失败关闭，不据此恢复；恢复活动不增加“清理项目”统计。

### 配置、容器与 APFS

- 配置检查限定根目录，最多 32 个配置、每个最多 1 MiB、最多访问 2000 个目录项、深度 4；符号链接配置不跟随。
- JSON 使用系统解析器；YAML／TOML 使用有界映射和数组子集，不支持或错误语法显式形成 issue 并失败关闭。
- 只检查已知路径键；绝对路径、相对路径、转义、缺失目标、`..` 越界和未展开变量分别记录。未发现已知路径键不等于没有外部引用。
- 配置引用或解析问题使命中组保持复核、预览量归零、执行候选为空；不提供“忽略引用后清理”。
- 私有容器要求当前用户 `Library/Containers` 直属位置与 Bundle ID 精确匹配；共享组必须来自代码签名声明。运行中、归属不明、身份不明或退出状态未知均只读，且报告永不授权删除容器。
- 稀疏文件通过 `lstat` 分别记录 `st_size` 与 `st_blocks * 512`；稀疏差额不冒充可释放物理空间。
- APFS 诊断只执行 `/usr/sbin/diskutil apfs list` 和 `/usr/bin/tmutil listlocalsnapshots /`，并提供重新读取入口；不存在、非零、超时和不可解析均为未知。
- 不执行 `diskutil apfs deleteSnapshot`、`tmutil deletelocalsnapshots`、purge 或任何快照删除操作；命令输出只保留有界解析摘要。

## 主要新增实现

- `Sources/CleanNestCore/CleanupExecutionLedger.swift`
- `Sources/CleanNestCore/ModelConfigurationReferenceInspector.swift`
- `Sources/CleanNestCore/ApplicationContainerReadOnlyInspector.swift`
- `Sources/CleanNestCore/APFSReadOnlyDiagnostics.swift`
- `Sources/CleanNest/AppStore+CleanupExecution.swift`
- `Sources/CleanNest/AppStore+APFSDiagnostics.swift`
- `Sources/CleanNest/CleanupExecutionLedgerCard.swift`
- `Sources/CleanNest/CleanupScanIssuesCard.swift`
- `Sources/CleanNest/APFSDiagnosticsCard.swift`

## 夹具与真实废纸篓边界

- 自动化执行、恢复和扫描夹具使用临时 Home、缓存、下载目录或临时 `.Trash`，结束后删除临时目录。
- 打开文件表、移动实现和 APFS 命令执行器均可注入；自动化 APFS 测试不读取或删除真实快照，也不运行 purge。
- 稀疏文件夹具只在隔离目录中 seek 到大 offset 后写入 1 字节，分别验证逻辑大小和分配块。
- 活跃 holder 只持有测试文件，验收后停止；未自动结束其他进程，未永久删除文件。
- 早期未加隔离回收器时，`CFFIXED_USER_HOME` 能重定向 Foundation Home，但 `FileManager.trashItem` 仍将 Batch 测试目录移到了真实 `/Users/zone/.Trash/CleanNest-UI-P0-Batch`。App 因未获得预期目标而报告“NSWorkspace 没有返回废纸篓目标”，没有伪报成功。
- 随后已按上述精确同名路径收回该测试目录，未触碰真实废纸篓中的其他项目。
- 为避免再次发生，`SafeFileOperations.swift` 在 `#if DEBUG` 内增加 `CLEANNEST_UI_TEST_SAFE_RECYCLER` 隔离回收路径：环境值必须与 Foundation Home 完全一致，源路径必须位于测试 Home，测试 `.Trash` 必须是非符号链接目录，目标不得重名。Release 不编译此分支，仍走原来的 `FileManager.trashItem`。

## 尚未验证／发布边界

- 打开文件表只覆盖当前用户、采集时刻可见的记录，不等于完整引用图，也不覆盖所有内核或其他用户消费者。
- YAML／TOML 检查是有界安全子集而非完整通用解析器；不支持语法会保持复核，不能据此证明没有引用。
- 隔离 Debug 界面验收不能替代真实用户 Home、权限弹窗、外部废纸篓变更、应用重启中途恢复等所有交互组合。
- 发布准备时已确认 Developer ID Application／Installer 私钥与 `CleanNestNotary` 可用；最终 0.12.0 RC 的签名、公证、装订和 Gatekeeper 结果必须以干净提交的实际构建为准。
- 尚未生成 0.12.0 RC 或安装包，未做本版本 Intel 真机、macOS 14、干净安装和旧自签名副本升级；Build 49 的 Apple Silicon 虚拟机结果不能冒充 Build 50 证据。
- 仓库在 P0 验收前已有大量累计改动；这些改动将进入独立发布分支审查。提交、推送、tag 和公开 Release 以实际线上记录为准，不在本文预先宣称完成。
