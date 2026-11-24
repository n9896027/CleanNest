# CleanNest 0.12.3 验证记录

日期：2026-11-24

范围：0.12.3（Build 53）的桌面 Agent 识别与卸载衔接、动态签名规则、真实图标缓存、无开发工具客户端校验、可信下载复用与 GitHub 限流退避。本文区分自动化证据、真实官方样本、签名产物和未实测场景，不以测试替身冒充真实卸载或硬件验收。

## 源码自动化与本地化

在仓库根目录显式使用完整 Xcode，不修改全局 `xcode-select`：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

2026-11-24 最终结果：**310 项测试，0 失败，1 项条件跳过**。跳过项是需要显式开启的本机 Ollama 空服务生命周期检查，未设置 `CLEANNEST_RUN_OLLAMA_INTEGRATION=1`，没有伪造通过结果。

覆盖包括：精确 Bundle ID／签名者／有效签名的共同约束、多副本、同名伪 App、错误 Team ID、旧 schema 1 规则兼容与基线合并、动态第三品牌识别、外部规则不得新增删除路径、Grok 应用数据只读、更新缓存匹配与变更拒绝、限流退避、自动检查调度及原有清理／恢复／卸载安全边界。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run CleanNestSelfTest
```

结果：`✓ CleanNestSelfTest：全部检查通过`。

```bash
swift Tools/LocalizationAudit.swift Resources/Localizable.xcstrings Sources/CleanNest --strict-source
git diff --check
zsh -n scripts/verify-release-candidate.sh
bash -n scripts/build-installer.sh
```

结果：Catalog、zh-Hans／en／zh-Hant 各 **2705** 个非空条目，`source_static_missing=0`，`source_dynamic_requires_review=0`；补丁及两个发布脚本语法检查通过。自动覆盖不等同于三语言人工 UI、键盘和 VoiceOver 验收。

## 官方 Grok Bot 样本

本次使用官方安装包提取的只读样本，以生产 `SecStaticCode` 严格校验路径执行 `AgentDesktopProductDetector`：

| 项目 | 实测结果 |
| --- | --- |
| 样本 | Grok Bot 1.2.3，Build 1.2.3 |
| Bundle ID | `com.anysphere.sand` |
| Team ID | `DCNK4UB866` |
| 签名者 | `Developer ID Application: Anysphere Incorporated (DCNK4UB866)` |
| 架构 | arm64 |
| 识别 | 通过精确 Bundle ID、有效签名和允许的 Team ID，生成动态桌面产品副本 |
| 数据范围 | `Application Support/Grok Bot` 只读保留；仅精确 Bundle ID 的缓存／日志可按现有卸载流程处理 |

官方样本验收通过设置 `CLEANNEST_GROK_SAMPLE_APP` 指向工作区内提取样本实际执行，未通过环境变量跳过签名检查。启动脚本核对显示 Electron 以 App 名称建立 `Grok Bot` 用户数据目录。

**没有**在本机真实安装、登录或卸载 Grok Bot；没有将合成 App 的签名替身称为真实卸载，也没有验证 Grok 与 Cursor 共存时的真实文件恢复。动态第三品牌、旧规则和错误签名由自动化夹具覆盖。

Meta Muse 尚未取得可核验的官方 Mac 安装样本。本版没有写入社区猜测的 Bundle ID、Team ID 或目录，不宣称支持 Muse。

## 更新与下载边界

- 客户端只调用 `/usr/sbin/pkgutil --check-signature` 与 `/usr/sbin/spctl --assess --type install`，不调用 `xcrun`，不会因验证安装包而要求安装 Xcode／CLT。
- 文件大小、Release 摘要、Developer ID Installer 与 Gatekeeper 系统评估必须分别通过。普通 403、GitHub 确认限流、系统拒绝和本机无法验证使用不同状态；不把失败显示为“已验证”。
- 客户端 Gatekeeper 接受不等于本地已钉住公证票据。发布机必须使用 `notarytool` 和 `stapler` 另行验收 App 与 PKG。
- 已验证缓存按版本、Build、大小、SHA-256、dev／inode／mtime 和信任证据匹配。窗口重开、查询失败和打开安装器失败保留可信文件；恢复及打开前重新验身份与摘要，变更后拒绝并允许重新下载。
- 自动检查按最近成功时间节流。确认限流时读取 `Retry-After` 与 GitHub reset；没有提示时默认等待 15 分钟，普通 403 不触发限流结论。
- Build 52 的下载与校验由旧版执行。Build 53 的客户端修复不能反向修补 Build 52；发布说明同时提供应用内更新和正式 PKG 手动路径。

## 正式分发验收范围

正式候选必须由同一干净提交生成，并逐项记录：四个可执行组件 `x86_64 arm64`、版本 0.12.3／53、Developer ID Application、Apple App 公证与装订、Developer ID Installer Distribution PKG、Apple PKG 公证与装订、Gatekeeper、SHA-256、SBOM 和来源证明。

预期资产为：

- `CleanNest-0.12.3-53.pkg`
- `CleanNest-0.12.3-53.zip`
- `CleanNestAgentRules.zip`
- `CleanNest-0.12.3.spdx.json`
- `SHA256SUMS`
- `PROVENANCE.json`

安装包使用 `pkgbuild --component` 生成组件包，再由 `productbuild --sign` 生成 Developer ID Installer 签名的 Distribution PKG。规则 ZIP 中只能包含一个 `CleanNestAgentRules.bundle`，必须与 App 使用同一 Developer ID Application 叶证书，保留有效签名、路径和大小边界。

## 未实测或条件限制

以下项目不能由 XCTest、源码编译、旧版验收或 Apple 公证替代：

- Intel 物理 Mac 启动和 XPC 扫描。
- macOS 14 干净首装，以及没有 Xcode／CLT 的真实系统更新评估。
- Build 52 → 53 的系统覆盖安装、设置／清理账本保留与真实恢复。
- 旧自签名副本升级后的重复 App、登录项和 TCC 重新授权。
- 官方 Grok Bot 的真实安装、首次启动前识别、登录后私有缓存卸载及废纸篓恢复。
- Meta Muse 识别、共存和卸载。
- 完整三语言人工 UI、窄窗口、键盘与 VoiceOver。

真实在线规则下载、Release 资产远端摘要和官网下载链接以实际发布后的请求结果为准；未返回有效证据前不宣称上线验收通过。
