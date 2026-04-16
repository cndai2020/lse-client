#!/bin/bash
# LSE Build Script - macOS
# 本地构建 macOS app（需要完整 Xcode + CocoaPods）

set -e

cd "$(dirname "$0")"

echo "=== LSE macOS 构建脚本 ==="
echo ""

# 1. 检查 Flutter
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter 未安装"
    echo "   请安装 Flutter: https://docs.flutter.dev/get-started/install"
    exit 1
fi

# 2. 检查 CocoaPods
if ! command -v pod &> /dev/null; then
    echo "⚠️ CocoaPods 未安装，正在安装..."
    if command -v brew &> /dev/null; then
        brew install cocoapods
    else
        echo "❌ 需要 Homebrew 或手动安装 CocoaPods"
        echo "   手动安装: https://cocoapods.org/"
        exit 1
    fi
fi

# 3. 拉取依赖
echo "📦 拉取 Flutter 依赖..."
flutter pub get

# 4. macOS Pods
echo "📦 安装 CocoaPods 依赖..."
cd macos
pod install --repo-update
cd ..

# 5. 构建
echo "🔨 构建 macOS Release..."
flutter build macos --release

# 6. 打包
echo "📦 打包 app..."
cd build/macos/Build/Products/Release
DMG_DIR="$(pwd)"
cd "$DMG_DIR"
zip -r lse-macos.zip "LocalSend Enterprise.app"
echo ""
echo "✅ 构建完成！"
echo "   产物: $DMG_DIR/lse-macos.zip"
echo "   App路径: $DMG_DIR/LocalSend Enterprise.app"
