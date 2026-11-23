# CleanNest 0.11.0（49）候选验收记录

状态：开发验证中。本文记录 0.11.0 的真实证据与未通过项，不代表已提交、打 tag、创建 GitHub Release 或完成公开发布。

## 候选身份

- 目标版本：0.11.0（49）。
- 源码基线：`31f6fc4918d5e6ef58685e9584432623e5b68122`，分支 `agent/0.10.0-clarity`；当前工作树含未提交改动，不是干净 main 发布构建。
- 候选目录：`build/release-candidate/0.11.0-31f6fc4918d5-build49/`。
- Developer ID ZIP SHA-256：`dd7bb168f45b18b5c4aac949a1c562e8d9d0d660f3f86778a06811340fc923b0`。
- PKG SHA-256：`b7b419588fdf3f7e2fab477f0871aa211ea10cc51dfeec4b5cf38136604f9f97`。
- SBOM SHA-256：`d7f5f183437d390a30c47caeda678745441557e29e49df880ae8c6c7073d1f69`。
- 构建机器：Apple M4 Max／arm64；macOS 27.3（26C5035r）；Xcode 27.2（27B52）。
- 信任边界：Developer ID Application / Installer，App 与 PKG 均已 Apple 公证并装订，`gateStatus=distribution-candidate`；当前仍是含未提交改动的候选，正式发布必须从通过检查的干净提交重建。

## 自动检查

| 检查 | 当前结果 | 证据 |
| --- | --- | --- |
| 三份 plist 与 Core 版本统一为 0.11.0（49） | 通过 | 源码与 plist 检查 |
| `swift test` | 2026-11-21 最新完整运行：238 项，0 失败，1 项按既有条件跳过 | `build/distribution-candidate-0.11.0-49.log` |
| ScannerServiceClient 回归 | 7 项通过；覆盖成功、协议不匹配、无效 JSON、中断、失效、取消和握手超时 | `build/distribution-candidate-0.11.0-49.log` |
| MCPBoundedLineBuffer 回归 | 5 项通过；覆盖合批保序、逐字节与合批等价、超限行后下一行、EOF 超长征、恰好上限与空行 | `Tests/CleanNestCoreTests/MCPBoundedLineBufferTests.swift`；完整测试日志 |
| 原生系统快照映射回归 | 4 项通过；覆盖原生监测、内存、电源与真实进程数映射，无可靠证据的字段保持空值 | `Tests/CleanNestCoreTests/NativeSystemSnapshotBuilderTests.swift`；完整测试日志 |
| 严格本地化源码门 | 通过；静态缺口 0，动态插值待复核 0；词法扫描覆盖注释、嵌套插值与跨行调用 | `build/distribution-candidate-0.11.0-49.log` |
| String Catalog | 2506 条；zh-Hans／en／zh-Hant 各 2506 条非空值；精确移除 29 条旧外部引擎专用 key | 同上；`build/remove_legacy_engine_strings.py` |
| 翻译格式占位符 | 通过；已纳入 LocalizationAudit | 同上 |
| 变量显示路径 | 已修复指标、年龄、扫描完整度、维护诊断、模型状态、活动与学习事件等运行时组合文案的语言回落 | 源码改动、严格源码门与第三轮截图 |
| `git diff --check` | 2026-11-21 完整质量检查通过 | 当前工作树检查 |
| 三语言 900×700 初始视口截图 | 第三轮已生成并复核当前根目录 33 张（每语言 11 页）；这些截图属于 Build 49 之前的 UI 证据，不能代替新界面实测 | `build/ui-regression/` 与 `build/ui-regression/contact-sheets/` |
| `CleanNestSelfTest` | 通过；原生映射自检全部通过 | `build/distribution-candidate-0.11.0-49.log` |
| 分发候选自动门 | 通过；严格本地化、完整测试、自检、Universal 2 Release 构建、签名、公证、装订与 Gatekeeper 均已执行 | `build/distribution-candidate-0.11.0-49.log`；安装与核心流程另列人工门 |
| PKG 签名、公证、装订与 Gatekeeper | 通过；PKG 为 Notarized Developer ID，stapler 与 `spctl --type install` 均通过 | Build 49 `PROVENANCE.json` 与分发候选日志 |
| Apple 公证回执 | App：`45e75659-6cec-4b2f-b98f-dcc2d9d3cfea`；PKG：`df12d4ae-f170-4ebb-9344-f49408925985`，均为 Accepted | `build/distribution-candidate-0.11.0-49.log` |
| PKG 独立解包复核 | 通过；解包 App 为 0.11.0（49），严格签名、Gatekeeper 与 PKG SHA-256 均与候选清单一致 | `build/verification-build49.oi8TPC/expanded/Payload/CleanNest.app` |
| Build 49 虚拟机安装后复核 | 通过：Build 48 → 49 升级、严格签名、Developer ID、装订票据与 Gatekeeper 通过；虚拟机内 `/usr/bin/file` 四组件复核完成，`ARCHITECTURES_FILE_EXIT=0` | `build/release-candidate/0.11.0-31f6fc4918d5/build49-vm/postinstall/`；`postinstall/architectures-file.txt` |
| 四组件 Universal 2 | 通过；独立解包后的 `lipo -archs` 与虚拟机安装后的 `/usr/bin/file` 均确认 App、MCP、登录项、扫描 XPC 包含 `x86_64 arm64` | 四个可执行文件的 `lipo -archs` 检查；`build/release-candidate/0.11.0-31f6fc4918d5/build49-vm/postinstall/architectures-file.txt` |
| SBOM、SHA-256、PROVENANCE | 已生成本次分发候选证据；正式发布仍须与最终干净提交一一对应 | `build/release-candidate/0.11.0-31f6fc4918d5-build49/` |

## Build 49：彻底移除外部引擎

- 删除外部引擎定位、JSON 解码、安装状态与探测流程；AppStore 和设置页不再提供 Mole／Homebrew 引擎安装、更新或路径选择入口。
- 新增 `NativeSystemSnapshotBuilder`，将内置原生监测、内存、电源和真实进程数映射为 `SystemSnapshot`；没有可靠证据的健康分、缓存、交换空间等字段保持 `nil`。
- 磁盘 AI 子目录采样继续由每个任务独立的 `ScannerServiceClient()` 交给 XPC 执行，没有退回主进程高成本遍历。
- `Sources`、`Tests`、`Scripts`、`scripts`、`Tools` 已无 Mole／EngineLocator／EngineInstallation 等实现残留；变更日志和历史审计中的历史名词不视为运行代码依赖。
- 本机直接运行与 Build 48 → 49 虚拟机升级均已实际执行；虚拟机安装后 `brew`、`mole`、`mo` 及六个常见路径仍全部不存在。界面与只读流程的各自覆盖范围见下两节，未执行项目不沿用其他环境的结果。

## Build 49 本机直接运行实测（2026-11-21）

环境：Apple M4 Max／arm64，macOS 27.3。通过 `open -n` 直接运行 PKG 独立解包目录中的 `CleanNest.app`；**没有在本机安装 PKG，也没有替换 `/Applications/CleanNest.app`**。启动前通过应用菜单正常退出原本运行的 Build 48，避免 LaunchServices 将新路径的启动请求转回旧实例。全程未执行清理、删除、废纸篓、模型服务启停或 MCP 写操作。

- 总览与侧栏显示 `CleanNest 0.11.0 · 构建 49` 和“内置引擎就绪，无需额外安装”。设置“高级”只显示“内置原生引擎 / CleanNest Native”，没有 Mole／Homebrew 引擎安装、更新或路径入口。
- 系统状态实时页显示 CPU、内存、温度、网络、磁盘、GPU、风扇和电池等原生数据；内存进程页显示真实进程列表。手动刷新后进程数从 923 更新为 925，内存与列表同步更新；系统状态页停留期间已形成超过 60 秒的原生历史样本。离开该页后的定时采样使用 `includeProcesses: false`，因此对应 `latest_snapshot.process_count = null` 不能误判为页面内采样失效。
- 清理空间只读扫描完成，并如实提示“本次扫描不完整”：2480 项因读取或本轮上限未纳入；当次结果含包管理器缓存 2 项 4.3 MB、旧日志 13 项 90.1 MB。重扫中出现“取消”，取消后约 2 秒恢复“重新扫描”并保留上次结果，再次重扫完成。全程“已选 0 项”，没有执行清理。
- 磁盘页对启动卷或主目录的递归扫描被 protected-directory 访问测试阻止，并显示权限说明；这是权限保护生效，**不算完整用户目录或完整磁盘扫描通过**。
- 新建小目录夹具 `build/host-build49/disk-fixture/`，其中只有 `readme.txt` 与 `Caches/sample.cache`。通过“选择文件夹”选定后自动完成有界遍历：本次扫描 2 个顶层项目，`Caches` 与 `readme.txt` 各显示 4 KB 分配占用，总计 8 KB，两个目录项均标记“目录实测 / 目录遍历完成”。扫描后 `readme.txt` 仍为 63 字节，SHA-256 为 `a37894714eb630bc7c8ee6d2223bf9e58c9008afc3b8e2c9bfe1aca5e45b3a77`；`sample.cache` 仍为 161 字节，SHA-256 为 `e5ce6644e67a27f67041185961328cfe60f3fb4774c06cd6d5266a03941346ca`。
- 系统数据只读清单完整完成：已解释占用 47.44 GB，磁盘实际可用 82.18 GB，覆盖 8 个位置并明确标出 9 处未完整扫描；系统另估可回收 16.25 GB，界面明确“不保证立即释放”。这些是当次动态读数，不作为固定容量预期。
- 以原样 JSONL 输入运行解包 App 内的 `CleanNestMCP`：退出码 0，收到 6 条带 ID 响应和 7 个只读工具，stderr 为 0 字节；协议为 `2025-11-25`，服务状态包含 `read_only=true`、`transport=stdio`，真实 top processes 正常。证据为 `build/host-build49/mcp-readonly-output.jsonl` 与 `build/host-build49/mcp-readonly-stderr.txt`。

本机结论：Build 49 解包 App 的内置引擎界面、原生系统状态、清理扫描取消／重扫、小目录磁盘分析、系统数据清单和只读 MCP 已通过本轮直接运行验收。完整用户目录磁盘扫描因权限保护未执行；干净 PKG 首次安装、Intel 真机和 macOS 14 仍须分别验证。Build 48 → 49 虚拟机升级的覆盖范围与取消后重扫边界见下节。

## Build 49 虚拟机升级验收（主要只读流程通过，取消后重扫未核实）

环境：UTM 中名为 `macOS` 的 Apple Silicon 虚拟机，arm64，macOS 27.2.1（26B131）。本轮从 **Build 48 升级到 Build 49**，不是干净首次安装；PKG 只安装到该虚拟机，没有装进宿主机。全程未执行清理、删除、废纸篓、模型服务启停或 MCP 写操作。

- 安装前 App 为 Build 48，`brew`、`mole`、`mo` 及六个常见路径全部不存在。虚拟机内 PKG SHA-256 与候选值 `b7b419588fdf3f7e2fab477f0871aa211ea10cc51dfeec4b5cf38136604f9f97` 一致。macOS 安装器实际输出 `installer: Upgrading at base path /` 和 `installer: The upgrade was successful.`；安装后 App 为 0.11.0（49）。
- 安装后的严格代码签名、Developer ID Authority、stapled ticket 与 Gatekeeper 均通过，`brew`、`mole`、`mo` 及六个常见路径仍全部不存在。虚拟机没有开发工具，因此未使用 `lipo`；改用系统自带 `/usr/bin/file` 复核安装后的 App、MCP、登录项和扫描 XPC，四者均为含 `x86_64` 与 `arm64` 的 Universal 2 二进制，脚本退出标记为 `ARCHITECTURES_FILE_EXIT=0`。
- 升级前后 defaults 完全相等，已有的 6 个数据文件逐文件 SHA-256 一致，没有缺失、新增或内容变化：`metrics.sqlite3`、`metrics.sqlite3-wal`、`metrics.sqlite3-shm`、`system-alert-timeline.json`、`maintenance-history.json`、`cleanup-preview.json`。该环境没有其他类别测试数据，因此这只能证明已有设置和文件保留，不能勾选完整 UPGRADE-02。
- 新版启动后显示 `CleanNest 0.11.0 (49)`，总览无旧 Mole 警告，左下角为“内置引擎就绪／无需额外安装”。设置“常规”只显示“内置原生引擎／CleanNest Native／无需额外安装”，“高级”只有只读 MCP，没有 Mole／Homebrew 安装、更新或路径入口。
- 系统状态实时页显示原生 CPU、内存、网络、磁盘和电源数据；温度、风扇无可靠数据时显示“暂不可用”，虚拟机显示“没有内置电池”，GPU 不伪造数值。内存进程页显示“已探测 570 个进程”，列出 CleanNest、Siri AI、Finder、Dock、Terminal 等真实进程及内存。趋势页已有从 `00:21:38` 到 `00:22:38` 的 CPU／内存／磁盘曲线；手动刷新后采样时间由约 `0:23:50` 更新至 `0:24:02`，满足本轮超过 60 秒历史与刷新生效检查。
- 清理空间只读扫描完成，显示“这里很干净”“0 项精选 · 7/11 个位置可读”。重扫时出现“正在启动独立扫描服务…”和“取消”；取消后扫描状态消失并保留上次结果。**取消后的再次重扫仍未核实**：后续点击未观察到新的扫描状态或结果变化，尚未排除 UTM 后台点击投递影响，因此既不宣称通过，也不据此定性为产品缺陷。旧 `/tmp/cleannest-scan-fixture/sample.cache` 本轮已不存在，但不能据此推断由 CleanNest 删除。
- 小目录磁盘分析通过：新建 `/Users/cleannest/Documents/cleannest-disk-fixture/`，仅含 `readme.txt` 与 `Caches/sample.cache`。界面列出 `Caches` 和 `readme.txt` 两个顶层项目，各显示 4 KB 分配占用，总计 8 KB，状态为“有界遍历完成／目录实测／目录遍历完成”。扫描前后文件大小和 SHA-256 完全一致：`readme.txt` 为 33 字节、`7ec73652df7c599cc91f49ccd9a787ab1a5e803c5b0d01a13eafdcaf86168952`；`sample.cache` 为 24 字节、`b787716eabd676d3445896c431927c3dd4575611530332984fd536dc8d56129d`，比较结果为 `DISK_FIXTURE_UNCHANGED=1`。没有执行完整用户目录或启动卷扫描。
- 系统数据只读清单完成：已解释占用 41 KB，覆盖 1 个位置并明确标出 5 处未完整扫描；其中应用日志 41 KB 为已测量，其他多类项目保持未测量／待访问授权。磁盘实际可用 32.94 GB，系统另估可回收 788 MB，界面明确“不保证立即释放”。这些是当次动态读数，不作为固定容量预期。
- 只读 MCP 通过：原样输入 7 行 JSONL，退出码 `MCP_EXIT=0`，收到 6 条带 ID 响应，stderr 为 0 字节。协议为 `2025-11-25`，服务版本 0.11.0，状态包含 `read_only=true`、`transport=stdio`；7 个工具为 `cleannest.server_status`、`cleannest.latest_snapshot`、`cleannest.metric_history`、`cleannest.top_processes`、`cleannest.disk_evidence`、`cleannest.cleanup_preview`、`cleannest.activity_log`。真实进程样本含 CleanNest、Siri AI、Terminal；`metric_history` 返回 20 个样本。

证据：`build/release-candidate/0.11.0-31f6fc4918d5/build49-vm/preinstall/preinstall.txt`、`postinstall/postinstall.txt`、`postinstall/data-retention-comparison.json`、`postinstall/architectures-file.txt`、`mcp-readonly-input.jsonl`、`mcp-readonly-output.jsonl`、`mcp-readonly-stderr.txt`、`disk-fixture-before.txt`、`disk-fixture-after.txt`、`disk-fixture-result.txt`、升级前后数据归档和本轮 GUI 操作记录。宿主网络中该虚拟机地址未开放 SSH，不能用远程终端替代本次 GUI 验收。

## Build 49 干净 Apple Silicon 首次安装验收（主要只读流程通过，完整安装门未通过）

环境：UTM 中独立的 `macOS 2` Apple Virtualization 虚拟机，arm64，macOS 27.2.1（26B131），4 GB 内存、64 GB 动态磁盘。系统与本地账号已创建，未登录 Apple ID。该环境与现有 `macOS` 升级虚拟机分离；没有操作 `Windows 11 ARM Dev / 不可用`，也没有把卸载旧虚拟机冒充干净首次安装。PKG 只安装到 `macOS 2`，没有装进宿主机。全程未执行清理、删除、废纸篓、模型服务启停或 MCP 写操作。

- 安装前确认无 CleanNest、Xcode、CLT、Homebrew、Mole、签名身份及公证配置；虚拟机内 PKG SHA-256 为 `b7b419588fdf3f7e2fab477f0871aa211ea10cc51dfeec4b5cf38136604f9f97`，与候选一致，`source=Notarized Developer ID`，脚本退出标记为 `CLEAN_PREINSTALL_SCRIPT_EXIT=0`。`/usr/bin/xcodebuild` 仅为系统桩，不代表已安装开发工具。
- 图形安装器可以打开，Gatekeeper 没有阻断；但图形授权安装没有完成，**不能据此宣称 GUI 安装路径通过**。最终通过 macOS 命令行安装器执行 `/usr/sbin/installer`，实际输出 `installer: Installing at base path /`、`installer: The install was successful.`，退出标记为 `CLI_INSTALL_EXIT=0`。
- 安装后 App 为 0.11.0（49），最低系统声明为 macOS 14.0，Bundle ID 为 `com.zone.cleannest`。主 App、MCP、登录项与扫描 XPC 均含 `x86_64 arm64`；严格代码签名、装订票据和 Gatekeeper 均通过，`spctl` 为 `accepted` / `Notarized Developer ID`。`brew`、`mole`、`mo` 及六个常见路径仍全部不存在，脚本退出标记为 `CLEAN_POSTINSTALL_SCRIPT_EXIT=0`。
- 通过 `open /Applications/CleanNest.app` 首次启动，无 Gatekeeper 阻断，主界面显示 `CleanNest 0.11.0 (49)` 和“内置引擎就绪”。系统状态页能读取 CPU、内存、磁盘等原生数据。本地网络以及桌面／下载／文稿权限均选择“不允许”，不妨碍本轮只读验收。
- 清理空间已实际验证：启动只读扫描后出现“取消”；取消后恢复可启动状态；再次点击开始时独立服务重新检查，证明取消后的再次重扫能够启动；第二次取消后显示“本次扫描不完整”并保留“这里很干净”。未执行真实清理。
- 只读 MCP 通过：原样输入 7 行 JSONL，退出码 `MCP_EXIT=0`，收到 6 条带 ID 响应，stderr 为 0 字节。`tools/list` 返回 7 个工具，全部标记 `readOnlyHint:true`、`destructiveHint:false`；`server_status`、`top_processes`、`latest_snapshot` 与 `metric_history` 均成功，没有调用写操作。
- “登录后常驻菜单栏”已在 GUI 中开启，设置页显示由 macOS 登录项管理，系统出现 CleanNest 可在后台运行的通知，无需额外批准。重新登录后的菜单栏实际行为尚未核实，因此不能据此勾选 STATE-05 或完整 INSTALL-01。

证据：`build/release-candidate/0.11.0-31f6fc4918d5/build49-clean-vm/preinstall/preinstall.txt`、`cli-install.txt`、`postinstall/postinstall.txt`、`mcp-readonly-input.jsonl`、`mcp-readonly-output.jsonl`、`mcp-readonly-stderr.txt` 与本轮 GUI 操作记录。

## Build 46～48 缺陷与复验

- **Build 46 扫描服务崩溃**：扫描 XPC 使用了无效的 `teamidentifier "NC33STD88A"` peer code-signing requirement，触发 `NSInvalidArgumentException` 与 `SIGABRT`，GUI 显示独立扫描服务中断。
- **Build 47 扫描修复**：改用可解析的 Developer ID requirement，并在交给 XPC 前通过 Security API 校验；虚拟机中的完整扫描、取消和再次重扫恢复。
- **Build 47 MCP 丢行**：原 stdio 循环在一次读取含多条 JSON-RPC 行时只处理首行，合批输入会丢失后续请求。
- **Build 48 MCP 修复**：改为增量、有界、保序的行缓冲；5 项定向回归、完整测试、宿主冒烟和虚拟机原样合批输入均通过。
- **Build 48 扫描复验**：虚拟机内再次完成完整扫描、重扫中取消并保留上次结果、再次完整重扫；最新扫描日志未再出现无效 requirement、`NSInvalidArgumentException` 或 `SIGABRT`。

## Build 48 虚拟机实测（2026-11-21，历史）

环境：UTM Apple Silicon 虚拟机，arm64，macOS 27.2.1（26B131）。该轮是从 **Build 47 升级到 Build 48**，不是干净首次安装。未在宿主机安装 PKG，未执行清理、删除、废纸篓或 MCP 写操作。

- PKG 由 macOS 安装器报告升级成功；安装后 App、扫描服务均为 0.11.0（48），最低系统声明为 macOS 14.0。
- 安装后的四组件均为 Universal 2；严格代码签名通过，Gatekeeper 返回 `accepted` / `Notarized Developer ID`。
- 清理扫描完整完成后显示“这里很干净”；重扫中出现“取消”和“正在启动独立扫描服务…”，取消后恢复“重新扫描”并保留上次完整结果；再次重扫完整完成，无服务中断。
- 扫描日志记录有效的 Developer ID peer requirement；未再出现 Build 46 的崩溃特征。扫描夹具 `/tmp/cleannest-scan-fixture/sample.cache` 保持存在且 `fixture_size=0`。
- 将 initialize、initialized、tools/list 和 tools/call 原样合批写入 MCP stdio，恰好收到 4 条响应：协议 `2025-11-25`、7 个只读工具、服务状态及 3 条真实进程样本。状态包含 `read_only: true` 和 `transport: "stdio"`，标准错误为 0 字节。
- “登录后常驻菜单栏”开关注册成功，设置页显示“已由 macOS 登录项管理；下次登录后只在菜单栏安静启动。”，系统出现 CleanNest 可在后台运行的通知。
- 登录项的重新登录、菜单栏实际可见性、采样频率切换及退出后停止采样尚未实测；本轮没有据此勾选 STATE-05 或完整安装门。

证据：`build/release-candidate/0.11.0-31f6fc4918d5/build48-vm/mcp-readonly-output.jsonl`、`mcp-readonly-stderr.txt`、`vm-postinstall/`，以及本轮 GUI 操作记录。

## 人工界面门

执行时填写机器、macOS、App 语言、日期和结果。未实际执行的项目保持未勾选。

截图补充证据（2026-11-20）：第三轮的 33 张当前截图及三张联系表已复核，并额外查看英文、繁体的磁盘与维护单张截图。该结果只覆盖 11 个页面的演示初始视口，不覆盖滚动区域、展开面板、完整明暗色组合、键盘或 VoiceOver，因此不能据此勾选 UI-01～UI-08。

- [ ] **UI-01 900 px 窄窗口**：窗口宽度压到 900 px，逐页检查总览、清理、卸载、磁盘、系统数据、Agent、本地模型、清理习惯、活动、系统状态、维护和设置；主要按钮、风险提示、取消与恢复入口不被裁切。
- [ ] **UI-02 长文案**：重点展开安全确认、扫描缺口、模型保护、恢复记录和维护影响；文本可换行，不能遮挡执行或取消动作。
- [ ] **UI-03 明暗色**：Light 与 Dark 各完成一次逐页检查；文本、状态颜色、图表、选中态和警示保持可辨识，不只依赖颜色传达风险。
- [ ] **UI-04 键盘**：仅用 Tab、方向键、Space、Return 和 Escape 完成导航、扫描取消、选择、确认与关闭；⌘K、⌘[、⌘] 和对话框默认／取消键行为正确，无键盘焦点陷阱。
- [ ] **UI-05 VoiceOver**：开启 VoiceOver 检查标题、按钮、图表摘要、候选选择、进程退出、Agent 处置和维护确认；朗读名称、数值、状态和结果与当前界面一致。
- [ ] **UI-06 English**：逐页检查 English，记录任何回落简体中文、占位符错误、语序错误和关键动作截断。
- [ ] **UI-07 简体中文**：逐页检查简体中文，确认 0.11.0 修改没有造成空白、错误替换或占位符残留。
- [ ] **UI-08 繁體中文**：逐页检查繁體中文，记录任何回落简体、术语不一致、占位符错误和关键动作截断。

人工结果／阻断项：初始视口截图复核已完成；其余人工项目待实际执行。

## 状态与中断回归

- [ ] **STATE-01 取消／重扫**：清理、磁盘、系统数据和 Agent 扫描分别连续取消并重扫；上一次完整结果保留，不发布半份新会话。

  部分实测：Build 48 虚拟机与 Build 49 本机的**清理扫描**均已完成完整扫描、取消保留结果和再次重扫。Build 49 的 `macOS` 升级虚拟机已完成扫描、取消和保留上次结果，但取消后的再次重扫未观察到启动证据，仍未核实；独立 `macOS 2` 干净虚拟机已实际观察到取消后再次启动独立扫描服务。磁盘、系统数据和 Agent 扫描的取消／重扫未完整覆盖，因此本项保持未勾选。

- [ ] **STATE-02 睡眠／唤醒**：扫描中睡眠再唤醒；旧任务不继续重复执行，进度、取消和结果状态可解释。
- [ ] **STATE-03 XPC 中断／重启**：只使用可丢弃测试数据触发扫描服务中断和重启；主 App 不卡死，不回退主进程扫描，不覆盖上次完整结果。

  已修复并复验 Build 46 的启动即崩溃缺陷，但尚未主动执行本项要求的中断／重启故障注入，因此保持未勾选。

- [ ] **STATE-04 退出收束**：在清理、磁盘、系统数据、AI 收集和 Agent 扫描进行中退出；无失控后台任务，下一次启动状态一致。
- [ ] **STATE-05 菜单栏／登录项**：切换菜单栏可见性、登录启动和采样频率；退出后采样停止，重新登录行为与设置一致。

  部分实测：Build 48 及 Build 49 干净虚拟机的登录项注册 UI 与系统后台活动提示通过；Build 49 的开关由 macOS 接管且无需额外批准。重新登录、菜单栏实际可见性、采样频率和退出后停止均未完成，因此保持未勾选。

## 安装与升级门

2026-11-21 已在 Apple Silicon 测试虚拟机完成 Build 47 → 48 的 PKG 升级、启动和主要只读流程；Build 48 → 49 的 PKG 升级、启动、内置引擎界面、原生状态、已有数据保留、四组件架构、清理扫描与取消、小目录磁盘分析、系统数据清单和只读 MCP 也已实测。`macOS` 升级虚拟机取消后的再次重扫仍未核实。独立 `macOS 2` 干净虚拟机已完成 Build 49 命令行安装、Gatekeeper 首次启动、主要只读流程和登录项注册；图形授权安装及重新登录后的菜单栏行为尚未完成。上述环境都不是 Intel、macOS 14 或宿主机旧自签名版本升级。

Intel 安装能力：PKG 内 App、MCP、登录项和扫描 XPC 均含 `x86_64 arm64`，三份 plist 最低系统为 macOS 14.0，源码检查未发现只限 arm64 的条件编译。这支持“macOS 14+ Intel Mac 具备安装与运行的架构条件”，但不等于 Intel 真机已实测。本机没有 Rosetta x86_64 执行环境，`arch -x86_64 /usr/bin/true` 返回 `Bad CPU type in executable`，因此本轮也没有 Rosetta 翻译运行证据。

- [ ] **INSTALL-01 干净 Apple Silicon Mac**：没有 Xcode、开发证书和公证凭据；从 PKG 安装到 `/Applications`，经 Gatekeeper 首次启动，验证扫描 XPC、MCP、登录项和菜单栏。

  部分实测：独立 `macOS 2` 已确认无 Xcode、CLT、开发证书、公证凭据和外部引擎；Build 49 PKG 已通过 macOS 命令行安装器安装到 `/Applications`，严格签名、Gatekeeper 首次启动、扫描 XPC、取消后重扫、只读 MCP 和登录项注册均通过。图形授权安装没有完成，重新登录后的菜单栏行为仍未核实，因此保持未勾选。

- [ ] **INSTALL-02 干净 Intel Mac**：执行同等安装和启动检查，确认四组件均能在 Intel 真机运行；需要 Intel 实机或云 Mac，不能由 Universal 2 编译结果代替。
- [ ] **UPGRADE-01 旧自签名／ad-hoc 升级**：从旧副本升级到 Developer ID PKG；按说明重新检查完全磁盘访问与 Finder 自动化，权限状态可理解。
- [ ] **UPGRADE-02 数据保留**：升级前后核对设置、活动、指标、本机学习、磁盘决定和 Agent 恢复记录；任何清空或错位都阻断发布。

  部分实测：Build 48 → 49 前后 defaults 完全相等，已有的 6 个数据文件 SHA-256 全部一致；环境没有其他类别测试数据，不能据此证明活动、本机学习、磁盘决定和 Agent 恢复记录的完整数据矩阵，故保持未勾选。

- [ ] **OS-01 macOS 14**：在最低声明版本实机安装并完成主要只读流程；若无法实测，发布说明必须保留限制，不能写成已验证。
- [ ] **OS-02 当前 macOS**：记录当前系统版本并完成安装、启动、升级与主要只读流程。

  部分实测：macOS 27.2.1 虚拟机内的 Build 47 → 48 升级、启动、清理扫描和 MCP 只读流程通过；Build 48 → 49 升级、启动、内置引擎界面、原生状态、清理扫描与取消、小目录磁盘、系统数据和 MCP 只读流程通过，但 `macOS` 升级虚拟机取消后的再次重扫未核实。独立 `macOS 2` 的 Build 49 干净命令行安装、首次启动、原生状态、清理扫描取消后重扫、只读 MCP 和登录项注册通过；图形授权安装、重新登录、完整用户目录磁盘扫描及其他组合流程未完整覆盖，因此保持未勾选。

## 模型平台真实样本

只用可丢弃的测试服务做启停；不得为验收停止用户真实模型或修改真实 LaunchAgent。

- [ ] **MODEL-01 Ollama**：记录版本、系统、架构、进程、回环端口、`/api/tags` 或现有 API 证据、客户端与守护状态。
- [ ] **MODEL-02 LM Studio**：记录版本、系统、架构、进程、回环端口、API、客户端与启动方式。
- [ ] **MODEL-03 llama.cpp／OpenAI-compatible**：记录版本、系统、架构、进程、回环端口、`/v1/models`、模型短 ID 与守护状态。
- [ ] **MODEL-04 小云雀**：没有正式样本与供应方文档时保持“待验证”，不得把猜测写成支持。
- [ ] **MODEL-05 身份变化**：在可丢弃服务上验证 PID 替换、端口变化和模型切换；身份不一致时拒绝危险动作。

本机只读盘点（2026-11-20）：检测到 Ollama 客户端 0.20.0-rc1，但客户端明确报告无法连接运行中的 Ollama 实例；未发现匹配的 Ollama、LM Studio、llama.cpp 或 MLX Serve 运行进程。`lms`、`llama-server` 与 `llama-cli` 不在当前 PATH。上述事实只证明当前可用样本状态，不构成 MODEL-01～05 的通过证据，也没有为测试启动或停止真实模型服务。

## 可选真实耐久观察

真实 48 小时不再作为默认发布阻断门。当前优先验收正式 Universal 2 PKG、干净环境安装、本机核心流程和升级数据保留；耐久只用于发现常驻崩溃、资源增长和监测异常。

2026-11-20 15:59:24 +0800 曾启动一次观察，首个样本确认当前候选进程为 `running`。维护者随后按新的验收策略停止任务，未达到 172800 秒，也没有生成通过结论。`build/system-monitor-soak.tsv` 只保留这次短期观察样本，不冒充 48 小时证据。

## 发布结论

- [ ] 所有自动门、核心流程、干净环境安装升级门和计划内人工门均通过。
- [ ] 最终 PKG、SBOM、SHA-256、PROVENANCE、CHANGELOG 和验收记录对应同一干净提交。
- [ ] 维护者明确授权后才提交、推送、打 tag 或创建 GitHub Release。

当前结论：**Build 49 是已生成并完成自动质量门的 dirty tree 分发候选，不是正式 GitHub Release。本机独立解包 App 的核心只读流程、Build 48 → 49 虚拟机升级，以及独立 `macOS 2` 干净虚拟机的命令行安装、Gatekeeper 首次启动、四组件 Universal 2、原生界面、清理扫描取消后重扫和只读 MCP 已通过；登录项已注册。图形授权安装、重新登录后的菜单栏行为、`macOS` 升级虚拟机取消后的再次重扫、完整升级数据矩阵、Intel 真机、macOS 14 和计划内人工门尚未全部完成，不得宣称全部验收通过。**
