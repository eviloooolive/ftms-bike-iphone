#!/bin/bash
# FTMSBike IPA 构建脚本
# 运行环境：macOS + Xcode（xcodebuild 可用）。可直接在 CodeBuddy CI 的 macOS 运行机或你本机执行。
#
# 前置准备：
#   1. 安装 Xcode 与命令行工具（xcodebuild 在 PATH 中）。
#   2. 导入 Apple 开发者证书到登录钥匙串；自动签名需 xcodebuild 能访问你的开发者账号
#      （CI 上通常先用 `security import` 导入 p12，再 `xcodebuild -allowProvisioningUpdates`）。
#   3. 把同目录 exportOptions.plist 里的 YOUR_TEAM_ID 改成你的 10 位 Team ID。
#
# 用法：
#   chmod +x build_ipa.sh
#   ./build_ipa.sh
#
# 说明：首次在 CI 上若报“找不到 scheme”，用 Xcode 打开工程一次（Product ▸ Scheme ▸ New Scheme）
#       生成共享 scheme，或在 CI 里先执行 `xcodebuild -project FTMSBike.xcodeproj -list` 确认目标名。

set -e

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJ_DIR"

SCHEME="FTMSBike"
CONFIGURATION="Release"
ARCHIVE_PATH="$PROJ_DIR/build/FTMSBike.xcarchive"
EXPORT_PATH="$PROJ_DIR/build/ipa"

echo "==> 清理旧构建产物"
rm -rf "$PROJ_DIR/build"

echo "==> 开始归档 (archive)：$SCHEME / $CONFIGURATION"
xcodebuild archive \
  -project FTMSBike.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates

echo "==> 导出 IPA"
mkdir -p "$EXPORT_PATH"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist exportOptions.plist \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates

IPA=$(find "$EXPORT_PATH" -name '*.ipa' | head -n 1)
if [ -z "$IPA" ]; then
  echo "❌ 未找到导出的 .ipa，请检查上面的 xcodebuild 输出"
  exit 1
fi
echo "✅ 构建完成，IPA 位置：$IPA"
