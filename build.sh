#!/bin/bash
set -e

APP_NAME="输入法锁定"
BUNDLE_ID="com.guangtou.inputlock"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🧹 清理旧构建..."
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "📝 生成 Info.plist (包含 LSUIElement=true 以隐藏 Dock 图标)..."
cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleName</key>
	<string>输入法锁定</string>
	<key>CFBundleDisplayName</key>
	<string>输入法锁定</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
</dict>
</plist>
EOF

echo "🔨 编译 Swift 代码..."
swiftc \
    -sdk $(xcrun --show-sdk-path --sdk macosx) \
    -o "${MACOS_DIR}/${APP_NAME}" \
    Sources/InputLock/*.swift

echo "🖼️  拷贝 AppIcon 资源..."
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# 签名以获取无障碍权限
echo "🔑 对应用进行本地签名..."
find "${APP_BUNDLE}" -name "._*" -delete
xattr -cr "${APP_BUNDLE}" || true
codesign -f -s "-" "${APP_BUNDLE}"

echo "✅ 构建完成！你可以在 build 目录下找到应用："
echo "📂 ${APP_BUNDLE}"

# ── DMG 打包 ──────────────────────────────────────────────
echo "📦 准备生成 DMG 安装包..."

DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
rm -f "$DMG_PATH"

STAGING_DIR="$(mktemp -d)"
# 清理临时目录
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# 如果有生成的 icns，设置磁盘卷标图标
if [ -f "${RESOURCES_DIR}/AppIcon.icns" ]; then
    cp "${RESOURCES_DIR}/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"
    SetFile -c icnC "$STAGING_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$STAGING_DIR" 2>/dev/null || true
fi

echo "💿 生成 DMG 镜像文件..."
hdiutil create -volname "输入法锁定" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

# 设置 DMG 文件的 Finder 图标
if [ -f "${RESOURCES_DIR}/AppIcon.icns" ] && [ -f "$DMG_PATH" ]; then
    echo "🎨 为 DMG 文件本身赋予自定义图标..."
    SWIFT_SCRIPT="${BUILD_DIR}/setIcon.swift"
    cat > "$SWIFT_SCRIPT" << 'EOF'
import Cocoa
let args = CommandLine.arguments
if args.count == 3 {
    let icon = NSImage(contentsOfFile: args[1])
    let success = NSWorkspace.shared.setIcon(icon, forFile: args[2], options: [])
    print(success ? "Icon set successfully" : "Failed to set icon")
}
EOF
    swift "$SWIFT_SCRIPT" "${RESOURCES_DIR}/AppIcon.icns" "$DMG_PATH" || true
fi

echo "✅ DMG 打包完成！"
echo "📍 DMG 文件位置：$DMG_PATH"
