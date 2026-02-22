#!/bin/bash
# ============================================================
# InputLock 打包 & 安装脚本
# 用法：
#   bash scripts/package_app.sh           # 只打包
#   bash scripts/package_app.sh --install  # 打包并安装到 /Applications/
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_NAME="InputLock"
APP_BUNDLE_NAME="锁定输入法"
BUNDLE_ID="com.local.inputlock"
VERSION="1.0.0"
BUILD_NUMBER="1"
MIN_OS="13.0"

# 在系统本地磁盘的临时目录中组装 bundle，避免 ExFAT 问题
STAGING_DIR="$(mktemp -d)"
APP_BUNDLE="$STAGING_DIR/$APP_BUNDLE_NAME.app"
INSTALL_FLAG="${1:-}"

cleanup() { rm -rf "$STAGING_DIR"; }
trap cleanup EXIT

echo "🔨 [1/6] 编译 Release 版本..."
cd "$PROJECT_ROOT"
swift build -c release 2>&1

BINARY_PATH="$PROJECT_ROOT/.build/release/$APP_NAME"
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ 找不到编译产物：$BINARY_PATH"
    exit 1
fi

echo "📁 [2/6] 创建 .app 目录结构（临时目录）..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "📋 [3/6] 拷贝二进制与资源文件..."
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
printf "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "📝 [4/6] 生成展开后的 Info.plist..."
# 用 PlistBuddy 直接生成，避免 Xcode 变量未展开的问题
PLIST="$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable        string $APP_NAME"      "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleName              string 锁定输入法"     "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName       string 锁定输入法"     "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile          string AppIcon"        "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier        string $BUNDLE_ID"     "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion           string $BUILD_NUMBER"  "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION"      "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType       string APPL"           "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion    string $MIN_OS"        "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSUIElement               bool   true"           "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass          string NSApplication"  "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright  string Copyright © 2026" "$PLIST"

echo "✍️  [5/6] Ad-hoc 代码签名..."
codesign --sign - --force --deep "$APP_BUNDLE"

echo "✅ [6/6] 打包完成"

# ── 安装到 /Applications（可选）────────────────────────────
OUTPUT_DIR="$PROJECT_ROOT"
if [ "$INSTALL_FLAG" = "--install" ]; then
    DEST="/Applications/$APP_BUNDLE_NAME.app"
    echo ""
    echo "📦 正在安装到 /Applications/..."
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.5
    rm -rf "$DEST"
    ditto "$APP_BUNDLE" "$DEST"
    echo "✅ 已安装：$DEST"
    echo ""
    echo "🚀 启动应用..."
    open "$DEST"
    echo ""
    echo "💡 提示："
    echo "   1. 首次运行请在「系统设置 → 隐私与安全性 → 辅助功能」中授权 InputLock"
    echo "   2. 点击菜单栏图标，开启「开机自启」以实现登录后自动启动"
else
    # 同时在项目目录保留一份（供参考）
    ditto "$APP_BUNDLE" "$OUTPUT_DIR/$APP_BUNDLE_NAME.app"
    echo ""
    echo "📍 已输出到：$OUTPUT_DIR/$APP_BUNDLE_NAME.app"
    echo ""
    echo "💡 安装到应用程序文件夹：bash scripts/package_app.sh --install"
    echo ""
    echo "🚀 正在启动..."
    open "$OUTPUT_DIR/$APP_BUNDLE_NAME.app"
fi
