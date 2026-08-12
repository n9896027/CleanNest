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

使用真实身份时，构建脚本会启用 Hardened Runtime 和可信时间戳。当前脚本按本机架构生成 App；在 Universal 2 流水线落地前，产物名称和发布说明必须明确标注 `arm64` 或 `x86_64`，不得误称通用包。

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
- 发现问题时发布新版本，不移动已经公开的版本 tag。
