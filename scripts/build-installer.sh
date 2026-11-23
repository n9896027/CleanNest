#!/bin/bash
# Build a notarized, Gatekeeper-accepted .pkg installer for CleanNest.
#
# Prerequisites (all must be on THIS Mac; Apple Developer Program membership
# alone is not enough):
#   1. Full Xcode selected: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
#      (CommandLineTools cannot compile the SwiftUI app target.)
#   2. "Developer ID Application: <Name> (<TEAMID>)" certificate + private key in Keychain.
#   3. "Developer ID Installer: <Name> (<TEAMID>)" certificate + private key in Keychain.
#   4. A notarytool credential profile, created once with:
#        xcrun notarytool store-credentials "CleanNestNotary" \
#          --apple-id "<apple-id>" --team-id "<TEAMID>" --password "<app-specific-password>"
#   5. CleanNest fully quit (build.sh refuses to replace a running bundle).
#
# Usage:
#   CLEANNEST_CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   CLEANNEST_INSTALLER_IDENTITY="Developer ID Installer: Name (TEAMID)" \
#   CLEANNEST_NOTARY_PROFILE="CleanNestNotary" \
#   scripts/build-installer.sh
#
# Optional: CLEANNEST_MAKE_DMG=1 also wraps the pkg into a signed/notarized DMG.
# Never pass credentials as command-line arguments or commit them to the repo.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP_IDENTITY="${CLEANNEST_CODESIGN_IDENTITY:-}"
INSTALLER_IDENTITY="${CLEANNEST_INSTALLER_IDENTITY:-}"
NOTARY_PROFILE="${CLEANNEST_NOTARY_PROFILE:-CleanNestNotary}"
MAKE_DMG="${CLEANNEST_MAKE_DMG:-0}"

APP_PATH="$PROJECT_DIR/build/CleanNest.app"
OUT_DIR="$PROJECT_DIR/build/installer"
VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
BUILD_NUMBER="$(plutil -extract CFBundleVersion raw Resources/Info.plist)"
PKG_IDENTIFIER="com.zone.cleannest.pkg"
PKG_PATH="$OUT_DIR/CleanNest-$VERSION-$BUILD_NUMBER.pkg"
NOTARY_ZIP="$OUT_DIR/CleanNest-$VERSION-$BUILD_NUMBER-notarization.zip"

fail() { echo "安装包构建中止：$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

# Do not require a system-wide xcode-select change. Full Xcode can be selected
# for this build only, which also works for unattended release builds.
if ! xcodebuild -version >/dev/null 2>&1; then
    [[ -d /Applications/Xcode.app/Contents/Developer ]] \
        || fail "需要完整 Xcode，且当前 xcode-select 指向 Command Line Tools"
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

[[ -n "$APP_IDENTITY" ]] || fail "缺少 CLEANNEST_CODESIGN_IDENTITY（Developer ID Application）"
[[ -n "$INSTALLER_IDENTITY" ]] || fail "缺少 CLEANNEST_INSTALLER_IDENTITY（Developer ID Installer）"
[[ "$APP_IDENTITY" == "Developer ID Application:"* ]] || fail "App 签名身份必须是 Developer ID Application，本地自签名证书不能用于分发"
[[ "$INSTALLER_IDENTITY" == "Developer ID Installer:"* ]] || fail "安装包签名身份必须是 Developer ID Installer"

step "检查本机签名身份与工具"
security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$APP_IDENTITY\"" \
    || fail "Keychain 中没有找到 App 签名身份：$APP_IDENTITY"
# Developer ID Installer is not a codesigning identity, so find-identity will
# not list it reliably. Check the certificate itself instead.
security find-certificate -a -c "Developer ID Installer" -Z 2>/dev/null | grep -Fq "SHA-1 hash" \
    || fail "Keychain 中没有 Developer ID Installer 证书（pkgbuild 签名需要，且必须含私钥）"
for tool in notarytool stapler; do xcrun --find "$tool" >/dev/null 2>&1 || fail "缺少 xcrun $tool"; done
for tool in pkgbuild pkgutil spctl hdiutil ditto; do command -v "$tool" >/dev/null 2>&1 || fail "缺少 $tool"; done
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || fail "notarytool 凭证 profile「$NOTARY_PROFILE」不可用，请先运行 xcrun notarytool store-credentials"

if pgrep -fl "$APP_PATH/Contents/MacOS/CleanNest" >/dev/null 2>&1; then
    fail "CleanNest 正在运行，请先完全退出（build.sh 会拒绝替换运行中的 bundle）"
fi

mkdir -p "$OUT_DIR"
rm -f -- "$PKG_PATH" "$NOTARY_ZIP" "$OUT_DIR/CleanNest-$VERSION-$BUILD_NUMBER.dmg"

step "1/6 用 Developer ID 重新构建并签名 App"
if [[ "${CLEANNEST_UNIVERSAL:-1}" == "1" ]]; then
    for product in CleanNest CleanNestMCP CleanNestLoginItem CleanNestScanner; do
        swift build -c release --arch arm64 --arch x86_64 --product "$product"
    done
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
    CLEANNEST_CODESIGN_IDENTITY="$APP_IDENTITY" \
    CLEANNEST_PREBUILT_EXECUTABLE="$BIN_DIR/CleanNest" \
    CLEANNEST_PREBUILT_MCP_EXECUTABLE="$BIN_DIR/CleanNestMCP" \
    CLEANNEST_PREBUILT_LOGIN_ITEM_EXECUTABLE="$BIN_DIR/CleanNestLoginItem" \
    CLEANNEST_PREBUILT_SCANNER_EXECUTABLE="$BIN_DIR/CleanNestScanner" \
        ./build.sh release
    for executable in \
        "$APP_PATH/Contents/MacOS/CleanNest" \
        "$APP_PATH/Contents/MacOS/CleanNestMCP" \
        "$APP_PATH/Contents/Library/LoginItems/CleanNestLoginItem.app/Contents/MacOS/CleanNestLoginItem" \
        "$APP_PATH/Contents/XPCServices/CleanNestScanner.xpc/Contents/MacOS/CleanNestScanner"; do
        [[ "$(lipo -archs "$executable")" == "x86_64 arm64" ]] \
            || fail "不是 Universal 2 可执行文件：$executable"
    done
else
    CLEANNEST_CODESIGN_IDENTITY="$APP_IDENTITY" ./build.sh release
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

step "2/6 提交 App 到 Apple 公证并装订"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
# An unnotarized Developer ID app can be rejected by Gatekeeper. Assess only
# after Apple's ticket has been stapled to the final bundle.
spctl --assess --type execute --verbose=2 "$APP_PATH"

step "3/6 生成组件安装包（安装到 /Applications）"
pkgbuild \
    --component "$APP_PATH" \
    --install-location "/Applications" \
    --identifier "$PKG_IDENTIFIER" \
    --version "$VERSION" \
    --sign "$INSTALLER_IDENTITY" \
    "$PKG_PATH"
pkgutil --check-signature "$PKG_PATH"

step "4/6 公证并装订安装包"
xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$PKG_PATH"
xcrun stapler validate "$PKG_PATH"

step "5/6 Gatekeeper 与校验值"
spctl --assess --type install --verbose=2 "$PKG_PATH"
( cd "$OUT_DIR" && shasum -a 256 "$(basename "$PKG_PATH")" > "SHA256SUMS" )

if [[ "$MAKE_DMG" == "1" ]]; then
    step "6/6 生成并公证 DMG 载体"
    DMG_PATH="$OUT_DIR/CleanNest-$VERSION-$BUILD_NUMBER.dmg"
    DMG_STAGE="$(mktemp -d "$OUT_DIR/dmg-stage.XXXXXX")"
    trap 'rm -rf -- "$DMG_STAGE"' EXIT
    cp "$PKG_PATH" "$DMG_STAGE/"
    hdiutil create -volname "CleanNest $VERSION" -srcfolder "$DMG_STAGE" \
        -ov -format UDZO "$DMG_PATH"
    codesign --force --options runtime --timestamp --sign "$APP_IDENTITY" "$DMG_PATH"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
    ( cd "$OUT_DIR" && shasum -a 256 "$(basename "$DMG_PATH")" >> "SHA256SUMS" )
else
    step "6/6 跳过 DMG（设置 CLEANNEST_MAKE_DMG=1 可同时生成）"
fi

printf '\n完成：%s\n' "$PKG_PATH"
echo "版本：$VERSION ($BUILD_NUMBER)"
echo "分发前请人工核对：签名主体、公证装订、Gatekeeper 评估、SHA256SUMS 与 CHANGELOG。"
