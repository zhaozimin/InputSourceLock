#!/bin/bash
# ============================================================
# InputLock 生成 DMG 安装包脚本
# 用法：bash scripts/create_dmg.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_NAME="锁定输入法"
DMG_NAME="${APP_NAME}.dmg"

echo "📦 准备生成 ${DMG_NAME} ..."

# 先确保已经编译打包出最新的 .app
cd "$PROJECT_ROOT"
bash scripts/package_app.sh

APP_BUNDLE="$PROJECT_ROOT/${APP_NAME}.app"
if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ 找不到 ${APP_BUNDLE}，请确保打包成功"
    exit 1
fi

echo "🗂️  创建临时打包目录..."
STAGING_DIR="$(mktemp -d)"
cleanup() { rm -rf "$STAGING_DIR"; }
trap cleanup EXIT

# 准备 DMG 内容
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# 1. 设置挂载时的 Volume（卷）图标
ICON_PATH="$PROJECT_ROOT/Resources/AppIcon.icns"
if [ -f "$ICON_PATH" ]; then
    cp "$ICON_PATH" "$STAGING_DIR/.VolumeIcon.icns"
    SetFile -c icnC "$STAGING_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$STAGING_DIR" 2>/dev/null || true
fi

echo "💿 生成 DMG 镜像文件..."
DMG_PATH="$PROJECT_ROOT/$DMG_NAME"
rm -f "$DMG_PATH"

# 使用 hdiutil 创建 DMG
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

# 2. 设置 DMG 文件本身的图标（Finder 中显示的图标）
if [ -f "$ICON_PATH" ] && [ -f "$DMG_PATH" ]; then
    echo "🎨 为 $DMG_NAME 文件赋予自定义图标..."
    SWIFT_SCRIPT="$STAGING_DIR/setIcon.swift"
    cat > "$SWIFT_SCRIPT" << 'EOF'
import Cocoa
let args = CommandLine.arguments
if args.count == 3 {
    let icon = NSImage(contentsOfFile: args[1])
    let success = NSWorkspace.shared.setIcon(icon, forFile: args[2], options: [])
    print(success ? "Icon set successfully" : "Failed to set icon")
}
EOF
    swift "$SWIFT_SCRIPT" "$ICON_PATH" "$DMG_PATH" || true
fi

echo "✅ DMG 打包完成！"
echo "📍 文件位置：$DMG_PATH"
echo "🚀 可以双击打开 ${DMG_NAME}，将『${APP_NAME}』拖入 Applications 即可安装！"
open -R "$DMG_PATH"
