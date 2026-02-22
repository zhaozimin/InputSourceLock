#!/bin/bash
# ============================================================
# InputLock 打包脚本
# 用途：将 Swift Package 编译产物打包为独立 .app bundle
# 运行：bash scripts/package_app.sh
# ============================================================

set -euo pipefail

# ── 配置 ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_NAME="InputLock"
BUNDLE_ID="com.local.inputlock"
APP_BUNDLE="$PROJECT_ROOT/$APP_NAME.app"
# ────────────────────────────────────────────────────────────

echo "🔨 [1/5] 编译 Release 版本..."
cd "$PROJECT_ROOT"
swift build -c release 2>&1

BINARY_PATH="$PROJECT_ROOT/.build/release/$APP_NAME"
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ 找不到编译产物：$BINARY_PATH"
    exit 1
fi

echo "📁 [2/5] 创建 .app 目录结构..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "📋 [3/5] 拷贝文件..."
# 二进制
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Info.plist
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# 写入 PkgInfo（标准 .app bundle 标志）
printf "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "✍️  [4/5] Ad-hoc 代码签名（本地开发用）..."
codesign --sign - --force --deep "$APP_BUNDLE"

echo "✅ [5/5] 打包完成："
echo "   $APP_BUNDLE"
echo ""
echo "💡 提示："
echo "   - 首次运行需授予「辅助功能」权限（系统设置 > 隐私与安全性 > 辅助功能）"
echo "   - 如需安装到应用程序文件夹：cp -R '$APP_BUNDLE' /Applications/"
echo ""
echo "🚀 正在启动应用..."
open "$APP_BUNDLE"
