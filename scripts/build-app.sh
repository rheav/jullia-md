#!/usr/bin/env bash
# Builds build/Jullia.md.app from the Swift package (release), with its icon, ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
CONFIG=${CONFIG:-release}
APP=build/Jullia.md.app
ICON=assets/icon/AppIcon.icon

swift build -c "$CONFIG" --product Marknord
BIN=$(swift build -c "$CONFIG" --show-bin-path)/Marknord

rm -rf "$APP" build/Marknord.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Jullia"

# The layered Liquid Glass icon (Icon Composer format) → Assets.car, plus AppIcon.icns for older readers.
# actool resolves relative paths against the icon's folder, so hand it absolute ones.
xcrun actool "$PWD/$ICON" --compile "$PWD/$APP/Contents/Resources" --platform macosx --minimum-deployment-target 27.0 \
  --app-icon AppIcon --output-partial-info-plist "$PWD/build/icon-partial.plist"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Jullia.md</string>
  <key>CFBundleDisplayName</key><string>Jullia.md</string>
  <key>CFBundleIdentifier</key><string>dev.rheav.jullia</string>
  <key>CFBundleExecutable</key><string>Jullia</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
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
