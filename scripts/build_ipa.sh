#!/usr/bin/env bash
# 在 macOS 上构建未签名 IPA。
#
#   ./scripts/build_ipa.sh                      # 使用内置演示站源
#   HONGGUO_GATEWAY=http://ip:8080 ./scripts/build_ipa.sh
#
# 产物：build/ipa/hongguo-<版本>-unsigned.ipa
# 未签名 IPA 必须自签后才能安装（AltStore / Sideloadly / 爱思助手）。
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "错误：iOS 包只能在 macOS 上构建（当前系统：$(uname -s)）" >&2
  echo "Windows / Linux 请改用 GitHub Actions：.github/workflows/build-ios.yml" >&2
  exit 1
fi

command -v flutter >/dev/null || { echo "错误：未找到 flutter 命令" >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "错误：未安装 Xcode 命令行工具" >&2; exit 1; }

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build ios --release --no-codesign"
if [[ -n "${HONGGUO_GATEWAY:-}" ]]; then
  echo "    网关：$HONGGUO_GATEWAY"
  flutter build ios --release --no-codesign \
    --dart-define=HONGGUO_GATEWAY="$HONGGUO_GATEWAY"
else
  flutter build ios --release --no-codesign
fi

APP_PATH="build/ios/iphoneos/Runner.app"
[[ -d "$APP_PATH" ]] || { echo "错误：未找到 $APP_PATH" >&2; exit 1; }

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)
OUT_DIR="build/ipa"
IPA_NAME="hongguo-${VERSION}-unsigned.ipa"

echo "==> 打包 Payload"
rm -rf Payload "$OUT_DIR"
mkdir -p Payload "$OUT_DIR"
ditto "$APP_PATH" "Payload/Runner.app"
zip -qry "$OUT_DIR/$IPA_NAME" Payload
rm -rf Payload

echo
echo "完成：$OUT_DIR/$IPA_NAME"
ls -lh "$OUT_DIR/$IPA_NAME"
echo
echo "未签名 IPA 不能直接安装，请用 AltStore / Sideloadly / 爱思助手自签后再装。"
