<div align="center">

# CleanNest

**面向 AI 开发工作流的本机 Mac 管理与安全清理。**

把 Agent 工作区、本地模型服务、系统异常与磁盘占用放进同一份本机证据链。先看见、再解释、最后由你决定；文件默认移入废纸篓，AI 永远不能替你执行删除。

**简体中文** · [English](README.en.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Español](README.es.md) · [한국어](README.ko.md)

[![CI](https://github.com/n9896027/CleanNest/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/n9896027/CleanNest/actions/workflows/ci.yml)
[![CodeQL](https://github.com/n9896027/CleanNest/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/n9896027/CleanNest/actions/workflows/codeql.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)
[![MIT License](https://img.shields.io/badge/License-MIT-2F81F7.svg)](LICENSE)

[文档](#文档导航) · [查看发布页](https://github.com/n9896027/CleanNest/releases) · [报告问题](https://github.com/n9896027/CleanNest/issues) · [安全报告](SECURITY.md)

</div>

![CleanNest 总览：以当前任务、只读状态和安全入口组织本机管理](docs/images/readme/overview.png)

<p align="center"><sub>演示数据 · 本地真实 App 界面 · 截图不包含用户文件、真实进程或模型信息</sub></p>

CleanNest 不是把传统清理器套上 AI 文案。它面向同时使用 Codex、Claude、Pi Agent、本地模型和开发工具的 Mac：区分谁在占空间、什么仍在运行、为什么会自动重启、哪些指标已经异常，以及哪些内容可以恢复地处理。

| Agent 工作区 | 本地模型运行中心 | 状态与告警 | 安全清理 |
| --- | --- | --- | --- |
| 占用、变化、活跃保护、异常线索 | 平台、短 ID、监听、客户端、launchd 守护 | CPU、内存、网络、GPU、温度、风扇、电池 | 预览、身份复核、废纸篓与恢复记录 |

> [!IMPORTANT]
> 本机已具备 Developer ID 签名、Apple 公证、票据装订的 Universal 2 PKG 构建能力。是否已有公开下载以 [Releases](https://github.com/n9896027/CleanNest/releases) 为准；CI 的 ad-hoc 产物仍只用于验证，不能冒充正式安装包。

## 0.12.3：识别桌面 Agent，升级不再依赖开发工具

**0.12.3（Build 53）** 在 Agent 工作区增加独立的桌面客户端清单。通过精确 Bundle ID、有效代码签名和允许的 Team ID 识别安装副本，显示真实图标、版本、Build 和路径；同一产品的不同副本分别管理。官方 Grok Bot 1.2.3 样本（`com.anysphere.sand`／`DCNK4UB866`）已通过生产签名识别测试。Meta Muse 尚未取得可核验的官方 Mac 样本，本版不宣称支持，也不猜测其标识或目录。

选择“卸载 Agent…”后，复用应用卸载的预览、执行前身份复核、六阶段处理、部分失败重试和废纸篓恢复流程。Grok Bot 的应用数据目录保持只读；云端账户、机器人、浏览器记录、共享容器和归属不明内容不在处理范围内。在线识别规则只能扩展识别和只读证据，不能远程增加删除路径。

更新客户端现在使用 macOS 自带的 `pkgutil` 与 `spctl`，不再调用 `xcrun`；核对 SHA-256、Developer ID Installer 与 Gatekeeper 系统评估。发布机继续执行 Apple 公证与票据装订。已验证下载可持久复用，查询失败、窗口重开或打开安装器失败不会无故丢弃；限流时显示允许重试的时间。详见 [0.12.3 验证记录](docs/VERIFICATION-0.12.3.md)。

0.12.1 的候选优先清理页和 0.12.2 的用户确认更新均已保留。自动化测试与签名构建不等同于 Intel 真机、macOS 14 干净首装或真实 Grok 卸载，未完成的场景在验证记录中逐项披露。

### 0.12.0 基础：清理证据、复核与恢复

0.12.0（Build 50）引入执行前活跃文件复核、被拦截项逐路径复核、持久化执行账本与单项恢复；APFS、稀疏文件、模型配置引用和应用容器分别展示证据，不把未知或逻辑大小当成可释放空间。详见 [0.12.0 路线图](docs/ROADMAP-0.12.md)与[验证记录](docs/VERIFICATION-0.12.0.md)。

### 0.10.1：补齐 MLX Serve 监控

用 **⌘K 查找功能**，或在侧栏按“空间 / 智能工具 / 系统”进入。磁盘浏览和系统状态改为按任务切换；清理、Agent、模型、活动和设置把辅助说明收进可展开详情。卸载页在窄窗口中使用列表 → 详情的路径。风险与失败提示仍直接显示，原有扫描、预览、确认、恢复和启停能力全部保留。

0.10.1 补齐 `mlx-serve` 的进程、11234 端口、OpenAI 兼容 API 与 launchd 守护发现；原有本机模型服务监控和控制边界保持不变。参见 [0.10.1 验证记录](docs/VERIFICATION-0.10.1.md)。

### 延续 0.9.0：系统数据占用清单

在 **磁盘浏览 → 查看占用清单** 中，按需测量 25 个常见位置，看懂“谁留下的、是什么、处理后会怎样”。支持搜索、用途筛选、扫描缺口、两次完整测量的变化，以及进入现有复核 / 管理页面。模型、备份和虚拟机不会因为体积大就被标为垃圾。

这是本机独立实现的只读清单，不是 macOS 私有“系统数据”分类的精确复刻，也不承诺扫描合计就是可释放量。每处最多 10 万项，未授权路径会跳过；系统快照、系统级运行时和自定义目录尚不包含。参见 [0.9.0 验证与边界](docs/VERIFICATION-0.9.0.md)。当前未发布 0.9.0 安装包。

## 不只是清理器

<table>
  <tr>
    <td width="50%">
      <img src="docs/images/readme/agent-workspace.png" alt="Agent 工作区演示界面：占用、活跃保护与异常线索">
      <br><strong>Agent 工作区</strong><br>
      <sub>为 Codex、Claude、Pi Agent、Kimi、WorkBuddy、Hermes、OpenClaw、Trae 与 MiniMax Hub 建立有界账本。概览不读取逐文件明细；进入单个 Agent 后才按需构建证据。</sub>
    </td>
    <td width="50%">
      <img src="docs/images/readme/local-model-runtime.png" alt="本地模型运行中心演示界面：服务、模型短 ID、客户端与守护拓扑">
      <br><strong>本地模型运行中心</strong><br>
      <sub>识别 oMLX、MLX-LM、MLX Serve、Ollama、LM Studio 与 llama.cpp/OpenAI-compatible 服务，解释端口、模型短 ID、TCP 客户端和自动拉起来源。</sub>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <img src="docs/images/readme/system-alerts.png" alt="系统状态演示界面：温度与风扇告警高亮及告警时间线">
      <br><strong>本机状态与告警</strong><br>
      <sub>统一阈值驱动菜单栏、状态页和告警时间线；异常同时使用文字、图标和颜色，不把普通高负载直接判成故障。</sub>
    </td>
    <td width="50%">
      <img src="docs/images/readme/cleanup-review.png" alt="清理空间演示界面：扫描证据、分类、处理篮与恢复信息">
      <br><strong>证据化安全清理</strong><br>
      <sub>把可重建缓存、安装包、截图、个人媒体与完整 SHA-256 重复副本分开；个人文件默认不勾选，执行前重新核验身份。</sub>
    </td>
  </tr>
</table>

> 上述图片来自 `CLEANNEST_DEMO=1` 的本地运行界面，证明当前 UI 结构与状态表达；其中数值、文件、进程与模型均为合成演示数据，不是用户实测结果。

## 从问题到可复核结果

| 你遇到的问题 | CleanNest 的处理方式 |
| --- | --- |
| 多个编程 Agent 越用越大，却不知道谁在增长 | 按 Agent 展示占用、相对变化、活跃文件保护和异常线索；逐文件证据只在进入单体详情后生成 |
| 本地模型关掉又自动启动，不清楚是谁拉起 | 把进程、监听端口、模型 API、实连客户端和 launchd 守护组成证据拓扑，再按控制权限分级处理 |
| 温度或风扇进入异常，但普通百分比看不出来 | 菜单栏、状态页和最多 200 条本机时间线共用阈值，以警告/严重状态解释峰值、持续时间与恢复 |
| 磁盘空间突然不足，却不知道是什么占满了 | 用目录、所属软件、功能类型三种视角对账，并把 APFS 容量、已归类文件和清理候选分开 |
| 缓存、下载文件和真实个人数据混在一起 | 区分可重建缓存、需复核项目与应保留内容 |
| 卸载 App 后担心残留 | 只预览与 Bundle ID 精确匹配的相关文件 |
| 不想把文件清单发到云端 | 确定性扫描无需 AI；可选模型只连接显式的 `127.0.0.1` 回环端点并接收受限元数据 |

## 核心能力

- **清理空间**：扫描开发缓存、日志、安装包等候选项，逐项选择后移入 macOS 废纸篓。
- **桌面与挂载安装介质**：桌面和下载目录中的 DMG、PKG、XIP、ISO 及安装器 ZIP 会进入人工复核；已挂载的安装镜像单独显示来源与安全推出入口，`/Volumes` 内容绝不会进入删除清单。
- **下载、截图、媒体与重复文件**：`ScreenShot`、`Screenshot`、`Screen Shot`、`ScreenCapture`、`截屏` 和 `截图` 等常见截图命名会直接进入独立分组，可一键全选/取消全选；其他媒体按体积、时间与类型筛选，重复内容用完整 SHA-256 确认。个人文件永不自动勾选，执行前还会复核文件身份与计划保留的副本。
- **独立扫描隔离**：清理、磁盘体积与证据构建由内嵌、独立签名的 XPC 服务执行。取消、服务中断或崩溃不会拖垮主界面，且不用半成品覆盖上一次完整结果。
- **Agent 工作区**：为 Codex、Claude、Pi Agent、Kimi、WorkBuddy、Hermes、OpenClaw、Trae 与 MiniMax Hub 建立有界占用账本；小云雀没有可靠样本时保持待验证，不猜路径。首页只显示总量、变化、活跃保护与异常，进入单个 Agent 后才懒加载类别和逐文件证据。已安装 Agent 使用本机 App Bundle 的真实图标，模型实连只接受已建立 TCP 连接。安全处置仍硬限制为 Codex/Claude 的静置缓存、临时文件和日志，并先创建、校验本机 ZIP；其他 Agent、会话、索引、记忆、凭据和运行时只读。
- **开发工具原生账本**：使用 Git `worktree prune --dry-run`、Docker `system df`、Hugging Face `cache prune --dry-run`、npm 缓存配置和 pip `cache info`。只有 Git 与 Hugging Face 在重新 dry-run 后开放确认执行；没有官方预演的 Docker、npm 与 pip 广域清理保持禁用。
- **增量磁盘浏览**：持续显示部分结果；15 分钟内只复用元数据签名未变化的项目，并明确展示缓存命中、实扫数量和深度刷新入口。
- **清理决策中心**：Treemap 与面包屑之外，还逐项解释用途、变大原因、处理影响、可恢复性、证据强度和安全下一步；你可以手动标记待复核、保留或稍后处理，且不能覆盖安全边界。
- **菜单栏实时监测**：完全由内置原生引擎采样，可以 1/2/5/10 秒在本机读取 CPU、内存、网络、磁盘、GPU、温度、风扇和电池；默认以 State 式双层短标签紧凑显示，也可切换展开文字/曲线、调整顺序或单独隐藏。异常时以橙/红色和 `!` / `!!` 同步标记，并结合 macOS 热状态与真实压力信号，避免把普通高负载误报为故障。
- **本地模型运行中心**：把平台、服务、模型短 ID、TCP 实连客户端和 launchd 守护组成证据拓扑，并解释端口冲突、模型替换和自动拉起。CleanNest 自启、当前用户进程、用户 LaunchAgent 和系统/其他用户服务采用四级不同控制边界；可控操作执行前仍重验身份，守护配置保留且可恢复。
- **系统状态**：显示原生实时仪表、电池与健康状态；每 60 秒在本机保存长期趋势，并补充内存压力和进程说明。
- **进程管理**：在身份复核、系统进程保护和二次确认后请求正常退出进程，不自动强制结束。
- **应用卸载**：浏览已安装 App，预览 App 本体及精确匹配的相关文件。
- **系统维护**：按任务运行低风险维护动作，并集中记录结果。
- **可审核本机学习**：文件提案按类型、位置级别、风险和时间聚成类别规则；支持批量审核、7 天试用、暂停、撤销和到期清理，并显示对当前列表的实际排序影响，永不自动勾选或删除。
- **模型工作台**：对当前回环服务执行不含文件元数据的最小流式测速，显示健康延迟、首字响应、总耗时、实际模型短名和内存余量提示。
- **数据控制**：活动记录可导出为 JSON 或单独清空；“恢复安全默认设置”只重置偏好，不混同清除活动、学习、索引、指标或系统授权。
- **内置原生引擎**：清理、磁盘、系统数据、Agent 和系统状态均无需 Homebrew 或额外清理引擎。
- **自动检查与确认更新**：默认在 App 运行期间按最近成功检查时间每 24 小时查询 GitHub 最新正式 Release，可在“关于”页关闭；确认限流后有界退避，不再由失败尝试触发整天等待。你确认后才下载官方 PKG，CleanNest 用 macOS 自带工具核对文件大小、SHA-256、Developer ID Installer 签名和 Gatekeeper 系统评估，不依赖 Xcode／CLT；之后由你打开 macOS 安装器并最终确认。发布机另行核验 Apple 公证和票据装订；不会静默安装或自动替换 App。
- **原生体验**：支持明暗色、自恢复权限引导、活动记录与演示模式。
- **只读 MCP**：通过 App 内置的 stdio 进程把有界、脱敏证据交给本机 AI 客户端；没有 HTTP、删除或进程控制工具。
- **三语言资源**：核心导航与主要页面使用 String Catalog 提供 English、简体中文和繁體中文。

## 下载与运行

打开 [最新正式 Release](https://github.com/n9896027/CleanNest/releases/latest)，下载 `CleanNest-0.12.3-53.pkg`，用同页的 `SHA256SUMS` 核对摘要，然后打开 macOS 安装器并确认安装到 `/Applications`。备用 App ZIP 为 `CleanNest-0.12.3-53.zip`；内置规则离线可用，`CleanNestAgentRules.zip` 只用于后续识别规则更新。普通安装和使用不需要 Xcode 或终端。若 Build 52 的应用内更新卡在旧版校验，直接使用这里的正式 PKG。请同时核对发布页的已知限制。

系统要求：

- macOS 14 Sonoma 或更高版本
- Xcode Command Line Tools（仅源码构建需要）
- Apple Silicon Mac 与 `mlx-lm`（仅本机 AI 功能需要）

从源码构建：

```bash
git clone https://github.com/n9896027/CleanNest.git
cd CleanNest
./build.sh
open build/CleanNest.app
```

构建完成后，后续扫描、分析、清理和维护都可以在 App 内完成，无需安装额外引擎。

正式分发使用 Developer ID Application / Installer、Apple 公证和票据装订；维护者可用 `scripts/build-installer.sh` 构建 Universal 2 PKG。CI 的 ad-hoc Universal 2 产物仍只用于验证，不属于普通用户安装包。从旧自签名副本升级后，如果 macOS 提示权限失效，请按权限说明重新授权当前 `/Applications/CleanNest.app`，不要给旧副本重复授权。请勿从第三方下载声称由本项目正式发布的 CleanNest App。

## 可替换的本机 MLX 模型（可选）

CleanNest 可以连接本机 `mlx_lm.server`，为清理候选和磁盘目录补充用途解释、风险提示与查看顺序。模型不是清理引擎：规则扫描在没有 AI 时仍可正常工作，AI 失败也不会影响已有结果。

隐私和执行边界：

- 只允许显式的 `http://127.0.0.1:<端口>/v1`，不连接局域网或公网模型服务。
- 请求只包含类型、大小、时间、受限 token 和脱敏路径提示等元数据，不读取文件内容。
- 磁盘分析只采样有限数量的子项构成，不发送完整目录树。
- Swift 客户端严格验证模型返回的字段、枚举和项目身份。
- AI 只能显示建议，不能扩大扫描范围、改变勾选、关闭进程或执行删除。
- 本机学习只保存候选项类型、规范化名称、路径的不可逆指纹、成功次数和模型评价；不保存候选项完整路径或文件内容，可在“本机学习”页检查和清空。

在“设置 → 本机 AI 分析”中既可以复用 oMLX 等现有回环服务，也可以让 CleanNest 启动所选的 `mlx_lm.server`。App 会从 `/v1/models` 读取并选择真实 API 模型短名，同时把本地目录单独用于自启，避免把文件路径错误地发给 oMLX。常用模型目录（包括 `~/.omlx/models`）会被有界扫描并显示架构、量化方式和权重大小。应用不会自动下载大型模型，也不会修改 oMLX 的 DFlash 设置。

## 安全设计

- 不允许把 `/System`、`/Library`、用户主目录或允许范围的根目录作为清理目标。
- 原生清理只接受经过白名单校验的后代路径，并拒绝符号链接。
- 文件默认移入 macOS 废纸篓，不使用不可恢复的 `rm -rf`。
- 卸载 App 时先复核路径、设备号、文件号与 Bundle ID；当前账户有真实目录权限时原子移入废纸篓，权限不足时再由 Finder 显示 macOS 管理员认证。App 本体未确认成功时不会处理相关文件。
- 任何高风险交互命令都不会通过模拟键盘自动确认。
- 扫描服务没有删除、进程控制或网络能力；服务不可用时显式失败，不回退到主 App 进程悄悄扫描。
- 每个拉取请求运行核心自检、完整 App Bundle 构建和 CodeQL 静态分析。
- GitHub Actions 使用最小权限，依赖与 Action 更新由 Dependabot 检查。

完整披露范围和报告方式见 [SECURITY.md](SECURITY.md)。

## 文档导航

| 文档 | 内容 |
| --- | --- |
| [权限说明](docs/PERMISSIONS.md) | 完全磁盘访问、文件夹授权与签名身份为什么会影响权限 |
| [本机 AI](docs/LOCAL_AI.md) | MLX 模型选择、切换、发送的数据及安全边界 |
| [历史指标](docs/METRICS.md) | 60 秒采样、SQLite WAL、保留期限和字段边界 |
| [只读 MCP](docs/MCP.md) | 本机 stdio 配置、7 个工具与只读安全边界 |
| [威胁模型](docs/THREAT_MODEL.md) | 保护目标、攻击面、控制与不保证事项 |
| [故障排查](docs/TROUBLESHOOTING.md) | 内置引擎、权限、AI、构建和电池状态常见问题 |
| [架构](docs/ARCHITECTURE.md) | 模块、数据流与高风险操作边界 |
| [Agent 工作区](docs/AGENT_WORKSPACE.md) | 多 Agent 只读账本、运行依赖证据、签名规则、备份优先处置与恢复边界 |
| [隐私](PRIVACY.md) | 本机保存的数据、网络访问及清除方式 |
| [路线图](ROADMAP.md) | 已完成、近期计划与暂不承诺事项 |
| [0.6.3 验证报告](docs/VERIFICATION-0.6.3.md) | Agent 手动决策、备份校验、冲突安全恢复、原生工具边界与本机构建证据 |
| [0.6.5 验证报告](docs/VERIFICATION-0.6.5.md) | 封存版本、全栏目巡检、多 Agent 边界、测试与本机构建证据 |
| [0.7.0 验证报告](docs/VERIFICATION-0.7.0.md) | 冷启动、页面生命周期、真实内存门禁、长列表与辅助功能证据 |
| [0.7.1 验证报告](docs/VERIFICATION-0.7.1.md) | 总览任务队列、设置分层、活动追溯、累计分离与内存门禁 |
| [0.7.2 验证报告](docs/VERIFICATION-0.7.2.md) | 扫描会话、处理篮、媒体/重复复核、三种空间事实与启动卷默认入口 |
| [0.7.3 验证报告](docs/VERIFICATION-0.7.3.md) | 应用依赖地图、逐项决定、六阶段失败关闭卸载与真实恢复位置 |
| [0.7.4 验证报告](docs/VERIFICATION-0.7.4.md) | APFS 总账、文件归类完整度、可靠增长对比与 314/868/126 真机对账 |
| [0.7.5 验证报告](docs/VERIFICATION-0.7.5.md) | 统一异常阈值、本机告警时间线、菜单宽度预算、App 级进程汇总与高频刷新隔离 |
| [0.7.6 验证报告](docs/VERIFICATION-0.7.6.md) | 维护任务只读预检、影响确认、前后证据、恢复复核与诚实的不确定状态 |
| [0.7.7 验证报告](docs/VERIFICATION-0.7.7.md) | 本地模型证据拓扑、客户端实连、四级控制边界、运行时诊断与 Ollama 空服务闭环 |
| [0.7.8 验证报告](docs/VERIFICATION-0.7.8.md) | Agent 概览/单体懒加载、类别规则簇、限时试用、排序影响与 10,000 条历史投影 |
| [0.7.9 源码发布验证报告](docs/VERIFICATION-0.7.9.md) | 0.6.5 迁移/回退、取消风暴、三语言审计、48 小时证据门与 SBOM/来源证明 |
| [0.8.0 验证报告](docs/VERIFICATION-0.8.0.md) | Agent 工作区分层清理：安装包残留识别、30/60 天会话与备份静置门槛、虚拟机整组陈旧复核 |
| [0.8.1 验证报告](docs/VERIFICATION-0.8.1.md) | 缺陷修复：扫描态卡死、恢复重试阻塞、管道死锁、连接腰斩、重复键崩溃与版本单一来源 |
| [0.8.2 验证报告](docs/VERIFICATION-0.8.2.md) | 易用性：处置状态大白话双层化、侧栏收敛为 6 个常驻入口与可折叠高级工具组 |
| [0.8.3 验证报告](docs/VERIFICATION-0.8.3.md) | 本机学习页更名清理习惯：全页去官僚术语，启用按钮与流程图说人话 |
| [0.8.4 验证报告](docs/VERIFICATION-0.8.4.md) | 总览页重构：单一主行动卡 + 紧凑次要行 + 纯图形状态块，删除审计四列与防御性说明 |
| [0.11.0 候选验收记录](docs/VERIFICATION-0.11.0.md) | 历史候选自动证据、人工界面、安装升级、模型平台与真实 48 小时边界 |
| [0.12.3 验证记录](docs/VERIFICATION-0.12.3.md) | 动态 Agent、官方 Grok 样本、无开发工具更新校验、缓存与发布边界 |
| [0.12.0 验证记录](docs/VERIFICATION-0.12.0.md) | 活跃检查、逐路径复核、执行账本、恢复、APFS、稀疏文件与发布边界 |
| [0.7 数据迁移与回退](docs/MIGRATION-0.7.md) | 设置、指标、活动、索引、学习规则和 Agent 恢复记录的真实兼容边界 |
| [本地化覆盖状态](docs/LOCALIZATION-STATUS.md) | 三语言 Catalog、占位符、严格源码门与尚待完成的人工验收 |
| [0.7 系列路线图](docs/ROADMAP-0.7.md) | 0.7.0–0.7.9 的产品、架构、验收门和明确不承诺事项 |
| [0.6.5 全栏目审计](docs/AUDIT-0.6.5.md) | 每个页面的现状、缺口、性能与无障碍证据 |
| [0.6.2 验证报告](docs/VERIFICATION-0.6.2.md) | Agent 占用账本、活跃保护、XPC 内存、失败关闭与真机扫描证据 |
| [0.6.0 验证报告](docs/VERIFICATION-0.6.0.md) | XPC 扫描隔离、取消回滚、崩溃注入与冷启动内存证据 |
| [0.5.5 验证报告](docs/VERIFICATION-0.5.5.md) | 扫描峰值内存、后台降频、三级重复检测与取消语义 |
| [0.5.4 验证报告](docs/VERIFICATION-0.5.4.md) | 下载项、媒体、精确重复检测及个人文件安全边界 |
| [0.5.3 验证报告](docs/VERIFICATION-0.5.3.md) | oMLX / Ollama 真机发现、launchd 守护证据、安全启停与未完成门槛 |
| [0.5.3 本地模型运行中心](docs/ROADMAP-0.5.3-LOCAL-MODEL-BAR.md) | 模型、平台、地址发现与安全一键启停规格 |
| [0.5.2 验证报告](docs/VERIFICATION-0.5.2.md) | 紧凑菜单栏、原生指标、登录启动与签名构建的真机结果 |
| [0.5.0 验证报告](docs/VERIFICATION-0.5.0.md) | 本机测试、大目录增量扫描与待放行门槛 |
| [维护与运营](docs/OPERATIONS.md) | 变更、CI 故障、凭据、发布与安全事件流程 |
| [更新记录](CHANGELOG.md) | 版本变化与未发布工作 |
| [参与贡献](CONTRIBUTING.md) | 开发、测试、PR 与安全约束 |

## 内置原生引擎

CleanNest 的清理、磁盘、系统数据、Agent 和系统状态全部由随 App 安装的原生组件完成，不检测、调用或安装外部清理引擎。Homebrew 只作为开发缓存扫描对象，不是运行依赖。

CleanNest 自身源码采用 [MIT License](LICENSE)。可选本机模型和参考实现见[第三方项目说明](THIRD_PARTY_NOTICES.md)。

## 开发与验证

开发期直接运行：

```bash
swift run CleanNest
```

运行核心自检：

```bash
swift test
swift run CleanNestSelfTest
```

使用不接触真实文件的演示数据检查界面：

```bash
CLEANNEST_DEMO=1 swift run CleanNest
```

本次迭代版本为 **0.12.3（Build 53）**，重点是桌面 Agent 识别与卸载衔接、可信更新缓存和无开发工具的客户端校验。正式 PKG 必须从通过检查的干净 `main` 提交构建，公开下载以 [最新正式 Release](https://github.com/n9896027/CleanNest/releases/latest) 为准。完整三语言人工 UI、Intel 真机、macOS 14 和干净 Mac 实装必须分别留下证据，不能由 CI 编译或旧版本公证代替。欢迎通过 [Issues](https://github.com/n9896027/CleanNest/issues) 提交可复现的问题或功能建议；安全问题请使用私密漏洞报告渠道。

English、简体中文和繁體中文的 String Catalog、格式占位符及直接 UI 严格源码审计已通过；这不等同于人工界面验收，窄窗口、长文案、键盘和 VoiceOver 仍需逐项实测。日本語和한국어 README 仅用于说明项目范围，不声明完整 App UI。
