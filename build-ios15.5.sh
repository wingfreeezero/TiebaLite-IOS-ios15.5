#!/usr/bin/env bash
# build-ios15.5.sh —— 在 macOS 上一条命令出 iOS 15.5 未签名 IPA
#
# 用法：
#   ./build-ios15.5.sh                 # Release，产物 TiebaLite-2.2.0-ios15.5.ipa
#   ./build-ios15.5.sh debug           # Debug
#
# 前置：macOS + Xcode 26.x（xcode-select 指向它）+ Homebrew（本脚本会装 bazelisk）。
# 产出：./TiebaLite-2.2.0-ios15.5.ipa —— ad-hoc 签名 = 无签名口径，SideStore / AltStore /
#       ESign / TrollStore 都能直接重签安装（不需要 Apple 账号，也不需要 .mobileprovision）。
set -euo pipefail

cd "$(dirname "$0")"

MODE_INPUT="${1:-release}"
case "$MODE_INPUT" in
  release|Release) MODE=release ;;
  debug|Debug)     MODE=debug ;;
  *) echo "用法: $0 [release|debug]"; exit 2 ;;
esac

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' TiebaLite/Info.plist 2>/dev/null || echo 0.0.0)"
OUT="TiebaLite-${VERSION}-ios15.5.ipa"

echo "== 1/5 检查工具链"
xcodebuild -version
command -v bazel >/dev/null 2>&1 || brew install bazelisk
bazel --version

echo "== 2/5 校验 15.5 底线"
grep -q 'ios_minimum_os=15.5' .bazelrc || { echo "!! .bazelrc 的 --ios_minimum_os 不是 15.5"; exit 1; }
grep -q 'minimum_os_version = "15.5"' BUILD.bazel || { echo "!! BUILD.bazel 的 minimum_os_version 不是 15.5"; exit 1; }

echo "== 3/5 生成占位描述文件（ad-hoc 签名不读它，但 rules_apple 要求工件存在）"
mkdir -p Signing
if [ ! -s Signing/app.mobileprovision ]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/profile.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>AppIDName</key><string>BuildPlaceholder</string>
<key>ApplicationIdentifierPrefix</key><array><string>0000000000</string></array>
<key>CreationDate</key><date>2026-01-01T00:00:00Z</date>
<key>Platform</key><array><string>iOS</string></array>
<key>Entitlements</key><dict/>
<key>ExpirationDate</key><date>2040-01-01T00:00:00Z</date>
<key>Name</key><string>BuildPlaceholder</string>
<key>TeamIdentifier</key><array><string>0000000000</string></array>
<key>TeamName</key><string>BuildPlaceholder</string>
<key>TimeToLive</key><integer>3650</integer>
<key>UUID</key><string>00000000-0000-0000-0000-000000000000</string>
<key>Version</key><integer>1</integer>
</dict></plist>
PLIST
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -subj "/CN=BuildPlaceholder" 2>/dev/null
  openssl smime -sign -in "$TMP/profile.plist" -signer "$TMP/cert.pem" -inkey "$TMP/key.pem" \
    -nodetach -outform der -out Signing/app.mobileprovision 2>/dev/null
fi

echo "== 4/5 bazel build //:AppStripped --config=ci --config=$MODE"
bazel build //:AppStripped --config=ci --config="$MODE"

echo "== 5/5 打包 + 自检"
rm -rf build && mkdir -p build
unzip -q bazel-bin/AppStripped.ipa -d build
( cd build && zip -qry "../$OUT" Payload )
GOT="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' build/Payload/*.app/Info.plist)"
echo "MinimumOSVersion = $GOT"
[ "$GOT" = "15.5" ] || { echo "!! 产物底线是 $GOT，不是 15.5"; exit 1; }
if [ -d build/Payload/*.app/PlugIns ]; then
  echo "!! 产物里仍有 PlugIns（Live Activity 扩展最低 16.1，会让 15.5 装不上）"; exit 1
fi
ls -lh "$OUT"
echo
echo "完成：$OUT"
echo "侧载：SideStore / AltStore / ESign / TrollStore 里选这个 ipa 直接安装（会用自己的证书重签）。"
