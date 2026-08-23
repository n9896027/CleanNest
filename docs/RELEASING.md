# 发布流程

本文件面向维护者。当前仓库没有 Developer ID 凭据，因此不会自动发布未经 Apple 公证的 App。

## 发布前检查

1. 从受保护的 `main` 创建版本分支，不直接推送主分支。
2. 同步更新 `Resources/Info.plist` 的版本/Build、README 和 `CHANGELOG.md`。
3. 运行：

   ```bash
   bash -n build.sh
   swift test
   swift run CleanNestSelfTest
   CLEANNEST_CODESIGN_IDENTITY="-" ./build.sh release
   swift Tools/SBOMGenerator.swift build/CleanNest.app build/CleanNest.spdx.json
   ```

4. PR 的 CI、双架构兼容性、CodeQL 和依赖审查全部通过，安全告警为零。
5. 合并后再从 `main` 的确切提交创建签名产物、tag 和 GitHub Release。

## Developer ID 构建

需要有效 Apple Developer Program 资格和 Keychain 中的 `Developer ID Application` 证书。凭据不得提交到仓库或输出到日志。

```bash
CLEANNEST_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh release
codesign --verify --deep --strict --verbose=2 build/CleanNest.app
spctl --assess --type execute --verbose=2 build/CleanNest.app
```

使用真实身份时，构建脚本会分别签署内置 `CleanNestMCP` 和外层 App，并启用 Hardened Runtime 与可信时间戳。本机直接运行脚本仍生成当前架构版本。

## 免费 Universal 2 验证产物

维护者可手动运行 `Universal macOS artifact` 工作流。它分别在 Apple Silicon 与 Intel runner 测试和编译 App/MCP，用 `lipo` 组装 Universal 2，生成 SPDX SBOM 与 SHA-256，并使用 GitHub OIDC 写入来源证明。

该工作流有意不创建 tag 或 Release，产物使用 ad-hoc 签名且未 Apple 公证，只适合验证与测试。它不能称为官方可信安装包，也不能取代下方 Developer ID、公证、装订和 Gatekeeper 实测。Action 均固定到完整提交，工作流保持最小权限。

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
- 发现问题时发布新版本，不移动已经公开的版本 tag。

### 源码正式版与 App 内更新检查

在尚无 Developer ID 与 Apple 公证时，可以发布“仅源码”的正式 GitHub Release，但必须同时满足：

- Release 不是 Draft 或预发布，tag 指向已通过保护检查的 `main`。
- 发布说明第一屏明确标注“源码发布，未提供 Developer ID 签名和 Apple 公证的 App”。
- 不附加 ad-hoc 签名的 `.app` 或 ZIP，不把 Actions 临时产物描述为普通用户可信安装包。
- 发布说明包含从源码构建命令、版本变化、已知限制和对应提交 SHA。

CleanNest 的“检查更新”只读取该仓库最新的非 Draft、非预发布 Release。因此，tag 或已合并代码本身不会让 App 识别为“最新正式版本”；维护者仍需在明确授权后创建正式 GitHub Release。
