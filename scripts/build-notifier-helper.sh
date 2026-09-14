#!/usr/bin/env bash
set -euo pipefail

helper="$TARGET_BUILD_DIR/$WRAPPER_NAME/Contents/Helpers/CodexAppBarNotifier.app"
mkdir -p "$helper/Contents/MacOS" "$helper/Contents/Resources"
cp "$SRCROOT/NotificationHelper/Info.plist" "$helper/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$CURRENT_PROJECT_VERSION" "$helper/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$MARKETING_VERSION" "$helper/Contents/Info.plist"
cp "$TARGET_BUILD_DIR/$WRAPPER_NAME/Contents/Resources/AppIcon.icns" "$helper/Contents/Resources/AppIcon.icns"

arch="${CURRENT_ARCH:-$(uname -m)}"
if [[ "$arch" == "undefined_arch" ]]; then
  arch="$(uname -m)"
fi
xcrun swiftc \
  -parse-as-library \
  -sdk "$SDKROOT" \
  -target "${arch}-apple-macos${MACOSX_DEPLOYMENT_TARGET}" \
  -O \
  -framework AppKit \
  -framework UserNotifications \
  "$SRCROOT/NotificationHelper/NotificationHelperApp.swift" \
  -o "$helper/Contents/MacOS/CodexAppBarNotifier"
