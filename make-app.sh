#!/bin/sh
# Builds build/WalkingPad.app: CoreBluetooth needs a bundle with an Info.plist, a bare binary gets killed.
set -eu
cd "$(dirname "$0")"
# xcodebuild, not `swift build`: SwiftPM's resource accessor only looks at the .app root (which codesign
# refuses to seal) and at the absolute .build path, so KeyboardShortcuts' strings would crash the app once
# .build is gone. Xcode's accessor looks in Contents/Resources first.
products=.build/xcode/Build/Products/Release
xcodebuild -scheme WalkingPad -configuration Release -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode -quiet build
app=build/WalkingPad.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$products/WalkingPad" "$app/Contents/MacOS/"
cp -R "$products"/*.bundle "$app/Contents/Resources/"
cp Info.plist "$app/Contents/"
# A stable identity keeps the Bluetooth permission across rebuilds; ad-hoc signing loses it every build.
identity=$(security find-identity -v -p codesigning | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"' || true)
codesign --force --sign "${identity:--}" "$app"
echo "$app"
