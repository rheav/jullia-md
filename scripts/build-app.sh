#!/usr/bin/env bash
# Builds build/Marknord.app from the Swift package (release), ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
CONFIG=${CONFIG:-release}
APP=build/Marknord.app

swift build -c "$CONFIG" --product Marknord
BIN=$(swift build -c "$CONFIG" --show-bin-path)/Marknord

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Marknord"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Marknord</string>
  <key>CFBundleDisplayName</key><string>Marknord</string>
  <key>CFBundleIdentifier</key><string>dev.rheav.marknord</string>
  <key>CFBundleExecutable</key><string>Marknord</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Markdown</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>net.daringfireball.markdown</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Folder</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>None</string>
      <key>LSItemContentTypes</key>
      <array><string>public.folder</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "$APP ($VERSION)"
