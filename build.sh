#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIGURATION="${1:-release}"
APP_NAME="CleanNest"
MCP_NAME="CleanNestMCP"
LOGIN_ITEM_NAME="CleanNestLoginItem"
BUNDLE_PATH="$PROJECT_DIR/build/$APP_NAME.app"
APP_EXECUTABLE="$BUNDLE_PATH/Contents/MacOS/$APP_NAME"
MCP_EXECUTABLE="$BUNDLE_PATH/Contents/MacOS/$MCP_NAME"
LOGIN_ITEM_BUNDLE="$BUNDLE_PATH/Contents/Library/LoginItems/$LOGIN_ITEM_NAME.app"
LOGIN_ITEM_EXECUTABLE="$LOGIN_ITEM_BUNDLE/Contents/MacOS/$LOGIN_ITEM_NAME"
STAGING_PATH="$PROJECT_DIR/build/.$APP_NAME.app.staging.$$"
ICON_TOOL="$PROJECT_DIR/build/CleanNestIconGenerator"
ICONSET_PATH="$PROJECT_DIR/build/AppIcon.iconset"
ICON_PATH="$PROJECT_DIR/build/AppIcon.icns"
ENTITLEMENTS_PATH="$PROJECT_DIR/Resources/CleanNest.entitlements"
PREFERRED_SIGNING_IDENTITY="Yuan OS Local Code Signing"

running_bundle_pids() {
    ps -ww -axo pid=,command= | awk -v executable="$APP_EXECUTABLE" '
        {
            pid = $1
            sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", $0)
            if ($0 == executable || index($0, executable " ") == 1) {
                print pid
            }
        }
    '
}

refuse_if_bundle_is_running() {
    local running_pids
    running_pids="$(running_bundle_pids)"
    if [[ -n "$running_pids" ]]; then
        echo "拒绝构建：$BUNDLE_PATH 正在运行（PID: $(echo "$running_pids" | tr '\n' ' ' | sed 's/[[:space:]]*$//')）。" >&2
        echo "为避免破坏 macOS 权限身份与当前进程，请先完全退出 CleanNest，再重新运行 build.sh。" >&2
        exit 2
    fi
}

cleanup_staging_bundle() {
    if [[ -n "${STAGING_PATH:-}" && "$STAGING_PATH" == "$PROJECT_DIR/build/.$APP_NAME.app.staging."* ]]; then
        rm -rf -- "$STAGING_PATH"
    fi
}

designated_requirement() {
    local requirement_output
    local requirement
    requirement_output="$(codesign -d -r- "$1" 2>&1)"
    requirement="$(printf '%s\n' "$requirement_output" | sed -n \
        -e 's/^# designated => /designated => /' \
        -e '/^designated => /p' \
        | head -n 1)"
    if [[ -z "$requirement" ]]; then
        echo "签名验证失败：未找到 designated requirement。" >&2
        printf '%s\n' "$requirement_output" >&2
        return 1
    fi
    printf '%s\n' "$requirement"
}

verify_automation_entitlement() {
    local entitlement_value
    entitlement_value="$(
        codesign -d --entitlements :- "$1" 2>/dev/null \
            | plutil -extract 'com\.apple\.security\.automation\.apple-events' raw -o - -
    )"
    if [[ "$entitlement_value" != "true" ]]; then
        echo "签名验证失败：缺少 Finder 自动化所需的 Apple Events entitlement。" >&2
        return 1
    fi
}

# Never rebuild or replace an app bundle that still backs a live process. TCC
# binds grants to the code identity at this path; replacing it underneath a
# running process produces cdhash mismatches and repeated permission prompts.
refuse_if_bundle_is_running
trap cleanup_staging_bundle EXIT

cd "$PROJECT_DIR"

echo "[1/5] 编译 CleanNest、登录项与只读 MCP ($CONFIGURATION)"
if [[ -n "${CLEANNEST_PREBUILT_EXECUTABLE:-}" || -n "${CLEANNEST_PREBUILT_MCP_EXECUTABLE:-}" || -n "${CLEANNEST_PREBUILT_LOGIN_ITEM_EXECUTABLE:-}" ]]; then
    if [[ -z "${CLEANNEST_PREBUILT_EXECUTABLE:-}" || -z "${CLEANNEST_PREBUILT_MCP_EXECUTABLE:-}" || -z "${CLEANNEST_PREBUILT_LOGIN_ITEM_EXECUTABLE:-}" ]]; then
        echo "预编译模式必须同时提供 App、登录项与 MCP 三个可执行文件。" >&2
        exit 1
    fi
    if [[ ! -x "$CLEANNEST_PREBUILT_EXECUTABLE" || ! -x "$CLEANNEST_PREBUILT_MCP_EXECUTABLE" || ! -x "$CLEANNEST_PREBUILT_LOGIN_ITEM_EXECUTABLE" ]]; then
        echo "预编译可执行文件不存在或不可执行。" >&2
        exit 1
    fi
    APP_SOURCE="$CLEANNEST_PREBUILT_EXECUTABLE"
    MCP_SOURCE="$CLEANNEST_PREBUILT_MCP_EXECUTABLE"
    LOGIN_ITEM_SOURCE="$CLEANNEST_PREBUILT_LOGIN_ITEM_EXECUTABLE"
else
    swift build -c "$CONFIGURATION" --product "$APP_NAME"
    swift build -c "$CONFIGURATION" --product "$MCP_NAME"
    swift build -c "$CONFIGURATION" --product "$LOGIN_ITEM_NAME"
    BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
    APP_SOURCE="$BIN_DIR/$APP_NAME"
    MCP_SOURCE="$BIN_DIR/$MCP_NAME"
    LOGIN_ITEM_SOURCE="$BIN_DIR/$LOGIN_ITEM_NAME"
fi

if [[ "$BUNDLE_PATH" != "$PROJECT_DIR/build/CleanNest.app" ]]; then
    echo "拒绝清理异常构建路径：$BUNDLE_PATH" >&2
    exit 1
fi

echo "[2/5] 生成 App 图标"
mkdir -p "$PROJECT_DIR/build"
swiftc -framework AppKit -framework SwiftUI \
    "$PROJECT_DIR/Sources/CleanNest/BrandMark.swift" \
    "$PROJECT_DIR/Tools/IconGenerator.swift" \
    -o "$ICON_TOOL"
rm -rf -- "$ICONSET_PATH"
rm -f -- "$ICON_PATH"
"$ICON_TOOL" "$ICONSET_PATH"
iconutil -c icns "$ICONSET_PATH" -o "$ICON_PATH"

echo "[3/5] 组装 App Bundle"
cleanup_staging_bundle
mkdir -p "$STAGING_PATH/Contents/MacOS" "$STAGING_PATH/Contents/Resources" \
    "$STAGING_PATH/Contents/Library/LoginItems/$LOGIN_ITEM_NAME.app/Contents/MacOS"
install -m 755 "$APP_SOURCE" "$STAGING_PATH/Contents/MacOS/$APP_NAME"
install -m 755 "$MCP_SOURCE" "$STAGING_PATH/Contents/MacOS/$MCP_NAME"
install -m 755 "$LOGIN_ITEM_SOURCE" \
    "$STAGING_PATH/Contents/Library/LoginItems/$LOGIN_ITEM_NAME.app/Contents/MacOS/$LOGIN_ITEM_NAME"
install -m 644 "$PROJECT_DIR/Resources/Info.plist" "$STAGING_PATH/Contents/Info.plist"
install -m 644 "$PROJECT_DIR/Resources/CleanNestLoginItem-Info.plist" \
    "$STAGING_PATH/Contents/Library/LoginItems/$LOGIN_ITEM_NAME.app/Contents/Info.plist"
install -m 644 "$ICON_PATH" "$STAGING_PATH/Contents/Resources/AppIcon.icns"

echo "[4/5] 导出英文、简体中文与繁体中文资源"
swift "$PROJECT_DIR/Tools/LocalizationExporter.swift" \
    "$PROJECT_DIR/Resources/Localizable.xcstrings" \
    "$STAGING_PATH/Contents/Resources"
swift "$PROJECT_DIR/Tools/LocalizationExporter.swift" \
    "$PROJECT_DIR/Resources/InfoPlist.xcstrings" \
    "$STAGING_PATH/Contents/Resources"

echo "[5/5] 本地签名"
if [[ "${CLEANNEST_CODESIGN_IDENTITY+x}" == "x" ]]; then
    SIGN_IDENTITY="${CLEANNEST_CODESIGN_IDENTITY:-}"
    if [[ -z "$SIGN_IDENTITY" ]]; then
        echo "CLEANNEST_CODESIGN_IDENTITY 已设置但为空，拒绝使用不明确的签名身份。" >&2
        exit 1
    fi
    SIGN_IDENTITY_DISPLAY="${SIGN_IDENTITY}（CLEANNEST_CODESIGN_IDENTITY 覆盖）"
elif security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$PREFERRED_SIGNING_IDENTITY\""; then
    SIGN_IDENTITY="$PREFERRED_SIGNING_IDENTITY"
    SIGN_IDENTITY_DISPLAY="${PREFERRED_SIGNING_IDENTITY}（自动选择的稳定身份）"
else
    SIGN_IDENTITY="-"
    SIGN_IDENTITY_DISPLAY="ad-hoc（未找到稳定身份）"
    echo "警告：未找到有效的“${PREFERRED_SIGNING_IDENTITY}”，将使用 ad-hoc 签名。" >&2
    echo "警告：ad-hoc 的 designated requirement 会绑定每次构建的代码哈希，macOS 授权可能在重建后失效。" >&2
fi

plutil -lint "$STAGING_PATH/Contents/Info.plist"
plutil -lint "$STAGING_PATH/Contents/Library/LoginItems/$LOGIN_ITEM_NAME.app/Contents/Info.plist"
plutil -lint "$ENTITLEMENTS_PATH"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$STAGING_PATH/Contents/MacOS/$MCP_NAME"
    codesign --force --sign "$SIGN_IDENTITY" \
        "$STAGING_PATH/Contents/Library/LoginItems/$LOGIN_ITEM_NAME.app"
    codesign --force --entitlements "$ENTITLEMENTS_PATH" --sign "$SIGN_IDENTITY" "$STAGING_PATH"
else
    # A real distribution identity must opt into Hardened Runtime and a trusted
    # timestamp before the bundle can be submitted to Apple's notarization service.
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$STAGING_PATH/Contents/MacOS/$MCP_NAME"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
        "$STAGING_PATH/Contents/Library/LoginItems/$LOGIN_ITEM_NAME.app"
    codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS_PATH" --sign "$SIGN_IDENTITY" "$STAGING_PATH"
fi
codesign --verify --strict --verbose=2 "$STAGING_PATH/Contents/MacOS/$MCP_NAME"
codesign --verify --strict --verbose=2 \
    "$STAGING_PATH/Contents/Library/LoginItems/$LOGIN_ITEM_NAME.app"
codesign --verify --strict --verbose=2 "$STAGING_PATH"
verify_automation_entitlement "$STAGING_PATH"
DESIGNATED_REQUIREMENT="$(designated_requirement "$STAGING_PATH")"
if [[ "$SIGN_IDENTITY" != "-" && "$DESIGNATED_REQUIREMENT" == *"cdhash"* ]]; then
    echo "签名验证失败：稳定签名身份仍生成了仅绑定 cdhash 的 designated requirement。" >&2
    exit 1
fi

# Re-check immediately before replacing the published bundle. Compilation can
# take long enough for somebody to launch the old build after the first check.
refuse_if_bundle_is_running
if [[ "$BUNDLE_PATH" != "$PROJECT_DIR/build/CleanNest.app" ]]; then
    echo "拒绝覆盖异常构建路径：$BUNDLE_PATH" >&2
    exit 1
fi
rm -rf -- "$BUNDLE_PATH"
mv "$STAGING_PATH" "$BUNDLE_PATH"
STAGING_PATH=""

codesign --verify --strict --verbose=2 "$BUNDLE_PATH"
codesign --verify --strict --verbose=2 "$MCP_EXECUTABLE"
codesign --verify --strict --verbose=2 "$LOGIN_ITEM_BUNDLE"
verify_automation_entitlement "$BUNDLE_PATH"
FINAL_REQUIREMENT="$(designated_requirement "$BUNDLE_PATH")"
if [[ "$FINAL_REQUIREMENT" != "$DESIGNATED_REQUIREMENT" ]]; then
    echo "签名验证失败：发布后 designated requirement 发生变化。" >&2
    exit 1
fi

echo "签名身份：$SIGN_IDENTITY_DISPLAY"
echo "指定要求：$FINAL_REQUIREMENT"

echo "完成：$BUNDLE_PATH"
echo "运行：open '$BUNDLE_PATH'"
