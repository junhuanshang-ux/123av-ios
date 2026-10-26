#!/usr/bin/env bash
# ============================================================================
# 123AV iOS · 在 macOS 上构建未签名 IPA（无需 Xcode 工程文件）
#
#   依赖：macOS + Xcode / Command Line Tools（提供 swiftc、actool、codesign）
#   产物：dist/123AV-unsigned.ipa      侧载工具（Sideloadly / AltStore）自签安装
#        dist/123AV.app                可直接用 TrollStore 安装
#
#   用法：
#     ./scripts/build-ipa.sh
#     APP_NAME=MyApp BUNDLE_ID=com.foo.bar ./scripts/build-ipa.sh
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-123AV}"
BUNDLE_ID="${BUNDLE_ID:-com.yidian.av123}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUM="${BUILD_NUM:-1}"
MIN_IOS="${MIN_IOS:-14.0}"
ARCH="${ARCH:-arm64}"

SRC_DIR="$HERE/Sources"
RES_DIR="$HERE/Resources"
WWW_DIR="$HERE/www"
BUILD_DIR="$HERE/build"
DIST_DIR="$HERE/dist"
APP_DIR="$BUILD_DIR/Payload/$APP_NAME.app"

echo "==> 环境检查"
command -v xcrun >/dev/null || { echo "缺少 xcrun，请安装 Xcode 或 Command Line Tools"; exit 1; }
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
SWIFTC="$(xcrun --sdk iphoneos -f swiftc)"
echo "    SDK : $SDK_PATH"
echo "    swiftc: $("$SWIFTC" --version | head -1)"

echo "==> 清理"
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR" "$DIST_DIR" "$BUILD_DIR/Payload"

echo "==> 编译 Swift 源码"
# -parse-as-library 用于 @main 入口
"$SWIFTC" \
  -sdk "$SDK_PATH" \
  -target "${ARCH}-apple-ios${MIN_IOS}" \
  -parse-as-library \
  -O -whole-module-optimization \
  -framework UIKit -framework WebKit -framework SafariServices -framework AVFoundation \
  -o "$APP_DIR/$APP_NAME" \
  "$SRC_DIR"/*.swift

echo "==> 编译资源目录（图标 / 启动色）"
xcrun actool "$RES_DIR/Assets.xcassets" \
  --compile "$APP_DIR" \
  --platform iphoneos \
  --minimum-deployment-target "$MIN_IOS" \
  --app-icon AppIcon \
  --output-partial-info-plist "$BUILD_DIR/asset-info.plist" \
  --target-device iphone --target-device ipad \
  --compress-pngs >/dev/null

echo "==> 合并 Info.plist"
python3 - "$RES_DIR/Info.plist" "$BUILD_DIR/asset-info.plist" "$APP_DIR/Info.plist" \
         "$APP_NAME" "$BUNDLE_ID" "$VERSION" "$BUILD_NUM" "$MIN_IOS" <<'PY'
import plistlib, sys

base_path, part_path, out_path, name, bundle_id, version, build, min_ios = sys.argv[1:9]

with open(base_path, 'rb') as f:
    info = plistlib.load(f)

try:
    with open(part_path, 'rb') as f:
        part = plistlib.load(f)
except Exception:
    part = {}

for key, value in part.items():
    if key.startswith('CFBundleIcon') or key in ('UILaunchStoryboardName', 'UILaunchScreen'):
        info[key] = value

info['CFBundleExecutable'] = name
info['CFBundleIdentifier'] = bundle_id
info['CFBundleName'] = name
info['CFBundleShortVersionString'] = version
info['CFBundleVersion'] = build
info['MinimumOSVersion'] = min_ios

with open(out_path, 'wb') as f:
    plistlib.dump(info, f, fmt=plistlib.FMT_BINARY)

print('    keys:', ', '.join(sorted(k for k in info if k.startswith('CFBundle'))))
PY

echo "==> 拷入前端资源 www/"
rm -rf "$APP_DIR/www"
mkdir -p "$APP_DIR/www"
cp -R "$WWW_DIR"/. "$APP_DIR/www/"
find "$APP_DIR/www" -name '.DS_Store' -delete 2>/dev/null || true

echo "==> Ad-hoc 签名（侧载工具会重新签名）"
codesign --force --sign - --timestamp=none "$APP_DIR" 2>/dev/null || echo "    （跳过 ad-hoc 签名）"

echo "==> 打包 IPA"
rm -f "$DIST_DIR/$APP_NAME-unsigned.ipa"
( cd "$BUILD_DIR/Payload" && /usr/bin/zip -qry "$DIST_DIR/$APP_NAME-unsigned.ipa" "$APP_NAME.app" )
cp -R "$APP_DIR" "$DIST_DIR/$APP_NAME.app"

echo
echo "==> 完成"
ls -lh "$DIST_DIR" | sed 's/^/    /'
if command -v shasum >/dev/null; then
  echo "    sha256: $(shasum -a 256 "$DIST_DIR/$APP_NAME-unsigned.ipa" | awk '{print $1}')"
fi
echo
echo "下一步：用 Sideloadly / AltStore 选 dist/$APP_NAME-unsigned.ipa，填 Apple ID 自签安装。"
