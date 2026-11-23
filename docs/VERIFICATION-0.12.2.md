# CleanNest 0.12.2 验证记录

日期：2026-11-23

范围：0.12.1 清理页易用性改进，以及 0.12.2 自动检查更新、用户确认下载、安装包验证与手动打开安装器。本文记录源码、自动化和本机真实更新链验收；正式签名、公证、票据装订、Gatekeeper、架构、哈希与来源信息以同一提交生成的 `PROVENANCE.json` 和 `SHA256SUMS` 为准。

## 最终源码自动化验收

以下命令均在仓库根目录运行，并显式使用完整 Xcode；未修改全局 `xcode-select` 设置。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

最终结果：**共执行 299 项，0 失败，1 项按既有条件跳过**。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run CleanNestSelfTest
```

最终结果：`✓ CleanNestSelfTest：全部检查通过`。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift Tools/LocalizationAudit.swift Resources/Localizable.xcstrings Sources/CleanNest --strict-source
```

最终结果：Catalog、zh-Hans／en／zh-Hant 各 **2672** 个非空条目；`source_static_missing=0`，`source_dynamic_requires_review=0`。

```bash
./build.sh debug
git diff --check
```

最终结果：Debug App Bundle 构建成功，补丁格式检查通过。

## 0.12.1 清理页真实界面验收

- 在本机真实只读扫描中确认清理候选位于首屏主路径，扫描诊断和保护路径证据不再淹没待处理项目。
- “未纳入本次清理”按不可读取、扫描上限、云端占位、危险根目录、符号链接和包边界分组，完整证据默认折叠；这些路径不会被当作候选处理。
- 应用日志逐项展示“是什么、为什么成为候选、处理影响、如何恢复”，明确没有读取日志正文，目录名不等于已核验 App 归属。
- 验证了应用日志批量选择确认与取消、诊断定位和分组展开；验收结束保持已选 0 项，未执行清理或权限修改。
- 本次真实扫描未产生不可读取分组，其权限与授权重扫分支由自动化测试覆盖。

## 0.12.2 更新链验收

### 当前版本与检查行为

- 真实模式确认自动检查默认开启，可在“设置 > 关于”关闭。
- 启动后延迟检查；App 活跃或系统唤醒时，距上次尝试至少 24 小时才再次检查。App 完全退出后不进行后台检查。
- 当前 0.12.2 对当时 GitHub 最新正式 Release 0.12.0 正确显示“当前版本比最新 Release 更新”，没有降级下载按钮。
- 公开 API 达到频率限制时，界面明确失败关闭，不开始下载。
- 演示模式使用合成 Release，不请求真实更新、不下载安装包，也不能打开安装器。

### 真实官方 PKG 下载与验证

- 本机临时旧版本实例已实际下载官方 **0.12.0** PKG，精确文件大小、SHA-256、Developer ID Installer 签名、Apple 公证票据与 Gatekeeper 评估全部通过后进入 `readyToInstall`。
- 公开 API 当时达到限额，因此该次仅 Release 元数据使用经 GitHub 已登录只读接口核验的临时验收夹具；PKG 仍从官方 URL 下载。临时验收入口已删除，不包含在正式源码中。
- 全程未点击“打开安装器”，未执行 `/usr/sbin/installer`，未替换 `/Applications`。
- 真实验收修正了 `pkgutil` 的 macOS 系统路径 `/usr/sbin/pkgutil`，并收紧 Developer ID Installer 与团队 ID 的同一签名行匹配；异常负数包大小失败关闭。

### 下载与安装边界

- 只接受官方仓库中与目标版本严格对应且唯一的 `CleanNest-<版本>-<构建号>.pkg`，限制 512 MiB，并验证初始下载路径与 GitHub 资产重定向目标。
- 下载使用临时、无 Cookie、无登录令牌会话和独立更新缓存目录；校验失败删除下载文件。
- 下载后依次核对精确大小、GitHub Release 提供的 SHA-256、CleanNest 团队 Developer ID Installer、Apple 公证票据和 Gatekeeper。
- 用户先确认下载，验证全部通过后还需再次点击“打开安装器”，并由 macOS 安装器继续确认。没有“仍要安装”、静默安装、自动退出或自动替换当前 App 的路径。
- 没有合格 PKG 的 Release 只保留经过仓库校验的 GitHub 手动下载路径。

## 正式发布核对

正式产物必须从同一干净 `main` 提交构建，并随 Release 提供：

- `CleanNest-0.12.2-52.pkg`
- `CleanNest-0.12.2-developer-id-macos.zip`
- `CleanNest-0.12.2.spdx.json`
- `SHA256SUMS`
- `PROVENANCE.json`

发布时必须核对四个可执行组件均为 `x86_64 arm64`，App／PKG 的 Developer ID、Apple 公证票据装订和 Gatekeeper 均通过，`source.dirty=false`，且来源提交与 Release tag 一致。

## 尚未验证／使用边界

- Intel 真机、macOS 14 实装、干净首次安装和旧自签名副本升级尚未针对 Build 52 分别实测；Universal 2 构建与 CI 检查不能替代这些硬件和场景证据。
- 三语言自动覆盖不等同于完整人工 UI、键盘和 VoiceOver 验收。
- 自动检查只查询公开 GitHub Release 元数据；用户确认前不下载 PKG，最终安装始终需要再次手动打开系统安装器。
- 正式公开下载、官网版本与哈希一致性以实际 Release 和线上验收结果为准，不在构建前预先宣称通过。
