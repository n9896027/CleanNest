# 发布流程

本文件面向维护者。本机已具备 Developer ID 与 Apple 公证构建能力，但脚本只生成候选产物，不会自行创建 tag、GitHub Release 或上传文件；正式分发仍要求干净提交、严格本地化、核心流程、干净环境安装和人工核对全部通过。

## 发布前检查

1. 从受保护的 `main` 创建版本分支，不直接推送主分支。
2. 同步更新 `Resources/Info.plist` 的版本/Build、README 和 `CHANGELOG.md`。
3. 运行：

   ```bash
   scripts/verify-release-candidate.sh
   ```

   该脚本会核对三份 Info.plist 版本、源码洁净度、本地化目录、全部测试、自检、签名、SBOM、SHA-256 和来源清单。默认只生成明确标注信任边界的本机/源码 ZIP 候选；启用分发门时会调用 `scripts/build-installer.sh`，并把已签名、公证、装订的 Universal 2 PKG 一并纳入候选目录与 PROVENANCE。任何模式都不会创建 tag、GitHub Release 或上传文件。

   要求完整 UI 本地化门时使用：

   ```bash
   CLEANNEST_REQUIRE_STRICT_LOCALIZATION=1 scripts/verify-release-candidate.sh
   ```

   只有 Developer ID、公证装订和严格本地化均已具备时，才允许运行分发门：

   ```bash
   CLEANNEST_REQUIRE_DISTRIBUTION=1 scripts/verify-release-candidate.sh
   ```

   如需固定某次候选的输出位置，避免默认目录被后续运行覆盖，可设置可选的 `CLEANNEST_RELEASE_OUTPUT_DIR`：

   ```bash
   CLEANNEST_REQUIRE_DISTRIBUTION=1 \
   CLEANNEST_RELEASE_OUTPUT_DIR="$PWD/build/release-candidate/0.12.0-<commit>-build50" \
   scripts/verify-release-candidate.sh
   ```

4. PR 的 CI、双架构兼容性、CodeQL 和依赖审查全部通过，安全告警为零。
5. 合并后再从 `main` 的确切提交创建签名产物、tag 和 GitHub Release。

## 可选 48 小时常驻观察

真实 48 小时是可选的稳定性观察，不再作为默认发布阻断门。默认验收优先覆盖正式 Universal 2 PKG、干净环境安装、本机核心流程和升级数据保留；需要专门验证监测服务、资源增长或睡眠唤醒时可运行：

```bash
scripts/verify-system-monitor-soak.sh
scripts/verify-48h-soak-report.sh build/system-monitor-soak.tsv
```

第二个命令会核对首尾 UTC 时间、进程连续存在、RSS/CPU 样本完整和峰值 RSS。缩短 `CLEANNEST_SOAK_SECONDS` 只用于验证采集器，不能冒充完整观察；报告应与测试机器、睡眠/唤醒和外接屏幕记录一起保存。若观察发现崩溃、资源异常增长或状态错误，仍须按实际缺陷处理。

## Developer ID 构建

需要有效 Apple Developer Program 资格和 Keychain 中的 `Developer ID Application` 证书。凭据不得提交到仓库或输出到日志。

```bash
CLEANNEST_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh release
codesign --verify --deep --strict --verbose=2 build/CleanNest.app
spctl --assess --type execute --verbose=2 build/CleanNest.app
```

使用 Developer ID 身份时，构建脚本会分别签署内置 `CleanNestMCP` 和外层 App，并启用 Hardened Runtime 与可信时间戳。本机直接运行脚本仍生成当前架构版本。

项目的 `Yuan OS Local Code Signing` 是为了在开发 Mac 上稳定 TCC 代码身份的自签名证书，不是 Developer ID。构建脚本对它保留 Hardened Runtime，但明确不请求 Apple 发行时间戳，避免本机重建被网络时间戳故障阻断。这不改变其“仅本机开发”性质；指定 Developer ID 身份时仍必须获得可信时间戳。

扫描 XPC 的客户端 peer requirement 必须先通过 `SecRequirementCreateWithString` 等 Security API 校验，再交给 `NSXPCConnection`；无效 requirement 会触发 Objective-C 异常并终止扫描进程，不能当作普通 Swift 错误捕获。`teamidentifier "TEAMID"` 不是有效的 requirement-language 写法。Developer ID 分发构建应同时约束 App identifier、Apple 证书链、Developer ID 证书字段和证书 `subject.OU`，并用真实签名 App 完成扫描、取消和重扫验收。

## 免费 Universal 2 验证产物

维护者可手动运行 `Universal macOS artifact` 工作流。它分别在 Apple Silicon 与 Intel runner 测试和编译 App/MCP，用 `lipo` 组装 Universal 2，生成 SPDX SBOM 与 SHA-256，并使用 GitHub OIDC 写入来源证明。

该工作流有意不创建 tag 或 Release，产物使用 ad-hoc 签名且未 Apple 公证，只适合验证与测试。它不能称为官方可信安装包，也不能取代下方 Developer ID、公证、装订和 Gatekeeper 实测。Action 均固定到完整提交，工作流保持最小权限。

## 安装包（.pkg / .dmg）

`build.sh` 只产出 `.app`，历史上分发物是 ZIP。需要真正的安装包时运行：

```bash
CLEANNEST_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
CLEANNEST_INSTALLER_IDENTITY="Developer ID Installer: Your Name (TEAMID)" \
CLEANNEST_NOTARY_PROFILE="CleanNestNotary" \
scripts/build-installer.sh
```

设置 `CLEANNEST_MAKE_DMG=1` 会额外生成签名并公证的 DMG 载体。脚本依次完成：Developer ID 构建与签名 → App 公证装订 → `pkgbuild --component`（安装到 `/Applications`）→ 安装包公证装订 → Gatekeeper 评估与 SHA-256，并输出 `build/installer/`。

注意 Apple Developer Program 会员资格不等于本机可用凭据：Keychain 中必须同时安装 `Developer ID Application` 和 `Developer ID Installer` 证书（含私钥），并事先用 `xcrun notarytool store-credentials` 建好凭证 profile；还需完整 Xcode（`xcode-select` 指向 Xcode.app，CommandLineTools 无法编译 SwiftUI App target）。脚本会在任何前置条件缺失时立即中止，且不接受本地自签名身份。打包前必须完全退出 CleanNest，否则 `build.sh` 会拒绝替换运行中的 bundle。

## 公证与封装

先在本机 Keychain 中创建 `notarytool` profile，再提交 ZIP。示例只引用 profile 名，不包含 Apple ID、Team ID 或 app-specific password：

```bash
ditto -c -k --keepParent build/CleanNest.app build/CleanNest-notarization.zip
xcrun notarytool submit build/CleanNest-notarization.zip --keychain-profile CleanNestNotary --wait
xcrun stapler staple build/CleanNest.app
xcrun stapler validate build/CleanNest.app
spctl --assess --type execute --verbose=2 build/CleanNest.app
```

公证成功后重新封装最终下载 ZIP，计算 SHA-256，并在 Release 中同时提供版本、架构、最低 macOS、提交 SHA、校验值和更新记录。失败的公证、未装订的 App 或来源不明的本地证书不得作为官方二进制发布。

## Tag 与 Release

- 使用与 Info.plist 一致的 `vX.Y.Z` annotated tag。
- Tag 必须指向已通过保护检查的 `main` 提交。
- 先创建 Draft Release，人工核对产物签名、公证、架构和校验值后再公开。
- 同时核对内置 `CleanNestMCP` 的签名、架构与实际 stdio 响应。
- MCP 验收必须把 initialize、notifications/initialized、tools/list 和 tools/call 按 JSON-RPC 帧**原样合批、一次写入** stdin，核对预期响应数、保序内容、EOF 末行和 stderr；不能靠每行之间 `sleep` 绕过合批丢行缺陷，也不能只验证 initialize。
- 发现问题时发布新版本，不移动已经公开的版本 tag。

### 源码正式版与 App 内更新检查

在尚无 Developer ID 与 Apple 公证时，可以发布“仅源码”的正式 GitHub Release，但必须同时满足：

- Release 不是 Draft 或预发布，tag 指向已通过保护检查的 `main`。
- 发布说明第一屏明确标注“源码发布，未提供 Developer ID 签名和 Apple 公证的 App”。
- 不附加 ad-hoc 签名的 `.app` 或 ZIP，不把 Actions 临时产物描述为普通用户可信安装包。
- 发布说明包含从源码构建命令、版本变化、已知限制和对应提交 SHA。

CleanNest 的“检查更新”只读取该仓库最新的非 Draft、非预发布 Release。因此，tag 或已合并代码本身不会让 App 识别为“最新正式版本”；维护者仍需在明确授权后创建正式 GitHub Release。

0.6.5 到 0.7.x 的数据兼容和学习规则回退方式见 [迁移与回退说明](MIGRATION-0.7.md)；三语言的真实覆盖缺口见 [本地化覆盖状态](LOCALIZATION-STATUS.md)。
