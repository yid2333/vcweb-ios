#!/usr/bin/env bash
# 在 macOS 上编出未签名 ipa，供 LiveContainer / 自签工具安装。
# 用法：bash scripts/build-ipa.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "缺少 xcodegen：brew install xcodegen" >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "缺少 xcodebuild：这台机器没装 Xcode 命令行工具" >&2
  exit 1
fi

echo "==> xcodebuild: $(xcodebuild -version | tr '\n' ' ')"
echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> 编译"
rm -rf build Payload
# 用 generic/platform=iOS 而不是 -sdk iphoneos：新版 Xcode 对只有 -sdk
# 的命令会抱怨 destination，做无签名构建时用 destination 更稳。
xcodebuild \
  -project VCWeb.xcodeproj \
  -scheme VCWeb \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  ONLY_ACTIVE_ARCH=NO \
  build

APP_PATH="build/Build/Products/Release-iphoneos/VCWeb.app"
if [ ! -d "$APP_PATH" ]; then
  echo "没找到 $APP_PATH，编译产物在这里：" >&2
  find build/Build/Products -maxdepth 2 -name '*.app' >&2 2>/dev/null || true
  exit 1
fi

echo "==> 打包"
mkdir -p Payload
cp -R "$APP_PATH" Payload/
rm -f VCWeb-unsigned.ipa
zip -qry VCWeb-unsigned.ipa Payload
rm -rf Payload

echo "==> 完成：$(pwd)/VCWeb-unsigned.ipa"
ls -lh VCWeb-unsigned.ipa
