# 本机桌面 AI／Agent 与相关软件盘点

适用版本：**0.12.4（Build 54）本机候选，尚未发布**。

盘点日期：2026-11-24。

范围：本机 `/Applications` 与 `~/Applications` 中发现的独立 AI／Agent 客户端，以及容易与它们混淆的附带组件、启动器、配置工具、自动化工作台和模型运行器。CLI、后台进程和模型服务另按 Agent 工作区或“本地模型”证据处理，不凭进程名伪造桌面 App。

## 结论与分类标准

- 共记录 **23 个 App**：**12 个身份已验证的独立 AI／Agent 客户端**、**3 个身份待核验的独立客户端**、**8 个附带组件或相关工具**。
- **签名验证回答“是不是这个开发者签的”，产品分类回答“它是什么”，两者不能互相替代。** 有效签名不会把配置工具、附带组件或启动器提升为 Agent。
- KimiCU 是 Kimi 的附带自动化组件；CC Switch 是 API／提供商配置切换工具。它们仍保留在盘点中，但都不计入独立 Agent，也不在 Agent 工作区提供卸载。
- “可管理”表示本机样本通过生产签名识别，并可进入现有卸载预览；**不表示已真实卸载该第三方 App，也不表示其所有数据都能删除**。
- 本轮只复制 App 到工作区做只读核验，未改写原 App，未读取或修改第三方私有数据，未卸载任何客户端。

## 一、12 个身份已验证的独立 AI／Agent 客户端

下表版本来自盘点时的本机副本，不是对最新版本或所有历史版本的保证。每个安装副本仍需实时满足精确 Bundle ID、Signing ID、允许的 Team ID、完整签名及 `anchor apple generic` 信任要求。

| 产品 | 本机版本／Build | Bundle ID | Team ID | 当前处理级别 |
| --- | --- | --- | --- | --- |
| ChatGPT | 26.1117.41037／29803 | `com.openai.codex` | `2DC432GLL2` | 可进入卸载预览 |
| Claude | 6.6395.1／6.6395.1 | `com.anthropic.claudefordesktop` | `Q6L2SF6YDW` | 可进入卸载预览 |
| Doubao | 2.35.22／2.35.22 | `com.bot.neotix.doubao` | `96L78H6LMH` | Mac App Store 签名；可进入卸载预览 |
| Gemini | 1.147.5.1526／1.147.5.1526 | `com.google.GeminiMacOS` | `EQHXZ8M8AV` | 可进入卸载预览 |
| Grok Bot | 0.30.0／0.30.0 | `com.anysphere.sand` | `DCNK4UB866` | 可进入卸载预览 |
| Kimi | 3.2.28／3.2.28.27 | `com.moonshot.kimichat` | `2J9472RW75` | 可进入卸载预览 |
| MiniMax Design | 4.0.16／4.0.16.169 | `com.minimax.hub.global` | `5Y7L83QLXD` | 可进入卸载预览 |
| Muse | 13.1／1119850179 | `com.meta.endo` | `V9WTTPBFK9` | 本机样本已核验；可进入卸载预览 |
| NewMax | 1.1.1／1.1.1 | `cc.newmax.desktop` | `22HUP6KLKD` | 可进入卸载预览 |
| Tabbit | 1.0.29／10100029 | `com.tabbit-ai.Tabbit` | `2DE8QTFYGR` | 仅允许精确 `Caches/Tabbit`；可进入卸载预览 |
| ZCode | 3.1.2／3.1.2.1788 | `dev.zcode.app` | `8A5X4JJ39T` | 可进入卸载预览 |
| 小云雀 | 1.0.56／1.0.56 | `com.bytedance.pippit.xiaoyunque` | `JH23ZR9LF5` | 可进入卸载预览 |

另使用官方 Grok Bot 1.2.3 下载样本复核相同 Bundle ID／Team ID，避免只认可本机 0.30.0 副本。“通过识别”不等于完成品牌官方来源审计；本机样本的 Apple 分发签名和精确身份是本次可复现证据。

## 二、3 个身份待核验的独立客户端

这些产品具有独立 AI／Agent 客户端功能和精确 Bundle ID 规则，但本机副本的完整签名不满足管理条件。即使 UI 显示产品名，也不会把名称当作信任依据。

| 实际 App | 本机版本 | Bundle ID | 已见签名信息 | 只读原因 |
| --- | --- | --- | --- | --- |
| Hermes Studio | 0.6.44 | `com.hermeswebui.studio` | Signing ID 匹配；Team ID `74J93F4W83` | App 包内新增多个 `__pycache__`，完整密封资源校验失败 |
| Pi Agent | 0.7.6 | `com.abcwyc.pi-agent` | adhoc；无 Team ID | 缺少 Apple 分发信任，且 `.next-desktop` 运行缓存写入 App 包导致密封资源失效 |
| WorkBuddy | 5.3.8 | `com.workbuddy.workbuddy` | Signing ID 匹配；Team ID `FN2V63AD2J` | App 包内新增 `editor_sdk.log`，完整密封资源校验失败 |

后续若要升级其中任何产品，必须取得新的完整样本，重新核验 Apple 信任链、精确身份、数据路径与隔离卸载夹具，再修改内置规则；不能添加“仍然卸载”或“信任此 App”按钮绕过。

## 三、8 个附带组件与相关工具

这一组只提供功能分类、真实 App 身份、路径、签名证据和 Finder 入口。**其模型没有私有数据处置规则或 Agent 卸载动作。** CC Switch、KimiCU 等仍可在普通“应用卸载”中作为普通 App 按各自预览处理，但不能从 Agent 工作区获得额外权限。

| App | 本机版本 | Bundle ID | 实际功能分类 |
| --- | --- | --- | --- |
| CC Switch | 3.16.5 | `com.ccswitch.desktop` | API／提供商配置切换工具，不是 Agent |
| KimiCU | 0.7.6 | `ai.kimi.cu` | Kimi 附带的自动化组件，不是独立 Agent |
| MiniMax Hub 2 | 1.0／1 | `local.zone.minimax-hub2` | 本地启动器；executable 为 `MiniMax Hub 2 Launcher`，`LSUIElement=true`；adhoc、无 Team ID |
| WorkDaddy | 1.2.18 | `com.workdaddy.launcher` | WorkBuddy 自动化启动器；未签名的 shell 启动器，不是另一个独立 Agent |
| Claude Code URL Handler | Build 1.0 | `com.anthropic.claude-code-url-handler` | 辅助 URL 跳转工具；Info 标识与实际 Signing ID `com.anthropic.claude-code` 不同 |
| Hermes | 1.0／1 | `com.tianshu.hermes.shell` | Hermes Studio 的辅助 shell |
| Ollama | 0.19.0 | `com.electron.ollama` | 本地模型运行器，继续由“本地模型”管理，不重复作为 Agent 客户端 |
| YuanHub | 0.4.0.2 | `io.github.creatorhub.desktop` | 多平台内容采集、发布与账号运营工作台，内置 AI 助手；主体不是独立通用 Agent |

YuanHub 的分类依据来自 App 内置文档：`app/agent/README.md` 把 AI 助手定义为全局浮窗和可选 MCP 能力；`desktop-guide/index.html` 将产品主体描述为多平台账号、采集、监控、下载、发布与互动工作台。因此不能因为包含 AI 助手或 Bundle ID 含 `creatorhub` 就把它列为独立 Agent。

### KimiCU 的只读工作区观察

KimiCU 不再拥有独立桌面 Agent 规则。其精确 Bundle ID 加入 Kimi provider，且只观察本机索引中实际出现的位置：`~/.kimi-cu`、`Application Support/KimiCU`、`Caches/ai.kimi.cu` 与 `HTTPStorages/ai.kimi.cu`。这些路径沿用 Agent 工作区的只读边界，不因为归入 Kimi 就获得新的删除权限。

## 删除边界

### 身份门

1. Bundle ID 必须与产品规则精确匹配，大小写不折叠。
2. 生产检查使用 `SecStaticCodeCheckValidity`，启用严格校验与所有架构检查，并要求 `anchor apple generic`。
3. Signing ID 必须等于 Bundle ID，Team ID 必须在该产品允许列表内。
4. 仅自签名证书里出现相同 Team ID 不足以建立官方产品身份。
5. 点击卸载前重新扫描安装位置与签名；不再可信时退出流程，不保留旧管理权限。

### 分类门与路径门

- 独立 Agent 安装副本、待核验独立 Agent、相关软件使用三种不同结果类型。相关软件没有卸载入口，有效签名也不能改变其功能分类。
- 每款可管理产品显式保留其 Bundle ID 对应的 `Application Support`、`HTTPStorages`、`WebKit`、偏好 plist 和窗口状态。
- 已登记的 `.codex`、`.claude`、`.kimi`、`.gemini` 等工作区根，以及产品相关 Application Support 目录，继续保持只读。
- 只有内置产品中逐条登记的 `Caches`／`Logs` 精确路径，才可能进入 `removeAfterApplication`。
- 通用卸载扫描器即使通过名称额外匹配到目录，只要不在该产品白名单中，就改为“无法证明归属”并强制只读。
- Tabbit 仅放行 `~/Library/Caches/Tabbit`；浏览器数据、Cookie、会话和项目不进入删除范围。
- 在线签名规则只能增加识别和只读证据；只有与本地内置规则完全一致的产品条目才具有既定缓存／日志处置权限。
- 共享容器、macOS 管理容器、符号链接、身份变化或来源不明项目继续失败关闭。

实现位于 `Sources/CleanNestCore/AgentDesktopProduct.swift`、`AgentRelatedSoftware.swift`、`AgentRuleCatalog.swift` 和 `AgentDesktopDependencyGraph.swift`。功能分类与签名信任是两条独立判断，UI 类型本身不能授予删除权限。

## 验收夹具与覆盖范围

专项测试位于 `Tests/CleanNestCoreTests/AgentDesktopProductTests.swift`，当前共 **15 项**，覆盖：

- 12 个已验证独立客户端、3 个待核验独立客户端和 8 个相关软件的独立清单，防止漏项、角色混淆或误改 Team ID。
- 全部 23 个本机真实样本及官方 Grok 1.2.3 样本的生产签名识别。
- 即使相关软件签名有效，也不会进入 Agent 安装副本或待核验 Agent 集合。
- 独立 Agent 与相关软件的 Bundle ID 不允许交叉重复。
- KimiCU 只作为 Kimi 附带组件观察已索引路径，不再拥有独立 Agent 产品规则。
- 精确 Bundle ID、有效签名、Signing ID、Team ID、伪造签名者、敏感标准目录保护及未登记路径只读降级。
- 在线产品规则不能引入新的删除路径，旧 schema 规则继续读取并合并新的内置分类基线。

真实样本测试使用两个只读环境变量；样本只从原 App 复制到工作区，不纳入 Git，也不应作为用户真实安装副本展示：

```bash
CLEANNEST_AGENT_SAMPLE_ROOT="<工作区>/build/desktop-agent-inventory/samples" \
CLEANNEST_GROK_SAMPLE_APP="<工作区>/samples/grok-bot/extracted/Grok Bot.app" \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter AgentDesktopProductTests
```

完整测试结果、三语言审查和本机构建记录见 `CHANGELOG.md` 的 0.12.4 未发布条目。

## 真实界面只读验收

2026-11-24 已在工作区运行 **0.12.4／54** 同一构建的独立验收副本，使用真实简体中文界面逐屏检查，不使用演示模式。由于已安装的 0.12.3／53 正在运行，且 App 设置了 `LSMultipleInstancesProhibited`，验收副本使用临时 Bundle ID 并在工作区本地重签；原始候选构建与 `/Applications/CleanNest.app` 均未替换。

- **已验证的独立 AI／Agent：12 个安装副本。** ChatGPT、Claude、Doubao、Gemini、Grok Bot、Kimi、MiniMax Design、Muse、NewMax、Tabbit、ZCode 与小云雀均在各自卡片显示“在 Finder 中显示”和“卸载 Agent…”。
- **待核验的独立客户端：3 个安装副本。** Hermes Studio、Pi Agent 与 WorkBuddy 均显示实际身份说明、Finder 入口和“只读，不提供卸载”，没有“卸载 Agent…”按钮。
- **附带组件与相关工具：8 类、10 个安装副本。** CC Switch、Claude Code URL Handler、Hermes、KimiCU、MiniMax Hub 2、Ollama、WorkDaddy 各 1 个副本，YuanHub 有 3 个副本。所有副本均显示 Finder 入口和“只读，不提供卸载”，没有 Agent 卸载按钮；有效签名没有把相关软件提升为 Agent。
- 本轮只核对实际清单、角色说明和控件权限，**没有点击任何卸载按钮，没有卸载、恢复或修改第三方 App 和私有数据**。

独立验收副本的界面同时显示“Agent 工作区扫描没有完成：无法与帮助程序通信”。桌面客户端清单独立于该扫描，因此上述清单与按钮结果有效，但本轮**不构成正式包 Agent 占用扫描或卸载流程的验收**。

## 未完成的验收

- 没有真实卸载或恢复任何第三方客户端；隔离目录图测试不能替代真实卸载。
- 没有对 3 个待核验独立客户端或相关软件修复签名、重签或放宽规则。
- 本机 Debug 构建不是 Universal 2 正式 PKG，不含 Apple 公证，也未完成 Intel 真机、macOS 14 或干净 Mac 安装验收。
- 本轮只覆盖简体中文真实 UI；英文、繁体中文、系统性窄窗口、键盘和 VoiceOver 验收仍未完成。
- 样本可能因厂商升级改变 Bundle ID、签名者、产品功能或数据布局；每次打开卸载预览时仍需重新验证，不能把本记录当作永久白名单。
