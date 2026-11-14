#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
for arch in arm64 x86_64; do
  swift build -c release --arch "$arch" --scratch-path ".build/$arch"
done
APP="dist/Audience Screen.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ARM_BIN=$(swift build -c release --arch arm64 --scratch-path .build/arm64 --show-bin-path)
INTEL_BIN=$(swift build -c release --arch x86_64 --scratch-path .build/x86_64 --show-bin-path)
lipo -create "$ARM_BIN/AudienceScreen" "$INTEL_BIN/AudienceScreen" -output "$APP/Contents/MacOS/AudienceScreen"
cp packaging/Info.plist "$APP/Contents/Info.plist"
swift scripts/make-icon.swift "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
lipo -verify_arch arm64 x86_64 "$APP/Contents/MacOS/AudienceScreen"
"$APP/Contents/MacOS/AudienceScreen" --smoke-test | tee dist/smoke-test.log
grep -q AUDIENCE_SCREEN_SMOKE_OK dist/smoke-test.log
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/Audience-Screen-macOS-Universal.zip
shasum -a 256 dist/Audience-Screen-macOS-Universal.zip > dist/SHA256SUMS.txt
