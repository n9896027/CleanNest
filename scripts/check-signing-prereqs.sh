#!/bin/bash
# Check every local prerequisite for scripts/build-installer.sh and print the
# exact environment variables to use. Never reads or prints credentials.
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

PROFILE="${CLEANNEST_NOTARY_PROFILE:-CleanNestNotary}"
ok=0
bad=0
report() { if [[ "$1" == "ok" ]]; then printf '  [OK]   %s\n' "$2"; ok=$((ok+1)); else printf '  [MISS] %s\n' "$2"; bad=$((bad+1)); fi; }

printf 'CleanNest 分发前置检查\n\n'

# 1. Full Xcode selected globally or available for this build through
# DEVELOPER_DIR (CommandLineTools cannot compile the SwiftUI target).
XCODE_PATH="$(xcode-select -p 2>/dev/null || true)"
if [[ "$XCODE_PATH" == *"Xcode.app/Contents/Developer"* ]]; then
    report ok "Xcode 工具链：${XCODE_PATH}"
elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    report ok "完整 Xcode 可用；打包脚本会为本次构建自动设置 DEVELOPER_DIR，无需 sudo 切换"
else
    report miss "未找到 /Applications/Xcode.app；当前工具链为 ${XCODE_PATH}"
fi

# 2. Developer ID Application identity (codesigning).
APP_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)"
if [[ -n "$APP_IDENTITY" ]]; then
    report ok "App 签名身份：${APP_IDENTITY}"
else
    report miss "钥匙串没有 Developer ID Application 身份（Xcode → Settings → Accounts → Manage Certificates → +）"
fi

# 3. Developer ID Installer certificate (not a codesigning identity).
INSTALLER_CERT="$(security find-certificate -a -c "Developer ID Installer" -Z 2>/dev/null \
    | grep -c 'SHA-1 hash' || true)"
INSTALLER_IDENTITY="$(security find-identity -v 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Installer: [^"]*\)".*/\1/p' | head -n 1)"
if [[ "${INSTALLER_CERT:-0}" -gt 0 ]]; then
    report ok "Developer ID Installer 证书已安装（${INSTALLER_CERT} 张）"
    [[ -n "$INSTALLER_IDENTITY" ]] && report ok "Installer 身份：${INSTALLER_IDENTITY}"
else
    report miss "钥匙串没有 Developer ID Installer 证书（pkgbuild 签名必需）"
fi

# 4. notarytool credential profile.
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    report ok "notarytool 凭证 profile：${PROFILE}"
else
    report miss "notarytool 凭证 profile「${PROFILE}」不可用（xcrun notarytool store-credentials）"
fi

# 5. CleanNest must not be running when build.sh replaces the bundle.
if pgrep -fl "$PROJECT_DIR/build/CleanNest.app/Contents/MacOS/CleanNest" >/dev/null 2>&1; then
    report miss "CleanNest 正在运行，打包前请完全退出"
else
    report ok "CleanNest 未运行"
fi

printf '\n统计：%d 项就绪，%d 项待办\n' "$ok" "$bad"
if [[ "$bad" -eq 0 ]]; then
    printf '\n全部就绪，可直接运行：\n\n'
    printf 'CLEANNEST_CODESIGN_IDENTITY="%s" \\\n' "$APP_IDENTITY"
    printf 'CLEANNEST_INSTALLER_IDENTITY="%s" \\\n' "${INSTALLER_IDENTITY:-Developer ID Installer: <请从钥匙串确认完整名称>}"
    printf 'CLEANNEST_NOTARY_PROFILE="%s" \\\n' "$PROFILE"
    printf 'scripts/build-installer.sh\n'
else
    printf '\n请补齐 [MISS] 项后再运行 build-installer.sh。\n'
fi
exit $((bad == 0 ? 0 : 1))
