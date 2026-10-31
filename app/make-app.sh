#!/bin/bash
# Builds Pitchside.app from source. Needs Apple's free Command Line Tools
# (run `xcode-select --install` once) or Xcode.
#   bash make-app.sh   →   ./Pitchside.app   (drag it to Applications if you like)
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift isn't installed. Run this once, then try again:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

swift build -c release --product Pitchside
BIN="$(swift build -c release --show-bin-path)/Pitchside"

APP="Pitchside.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pitchside"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Pitchside</string>
  <key>CFBundleDisplayName</key><string>Pitchside</string>
  <key>CFBundleIdentifier</key><string>local.pitchside.app</string>
  <key>CFBundleExecutable</key><string>Pitchside</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.7.6</string>
  <key>CFBundleVersion</key><string>17</string>
  <key>LSMinimumSystemVersion</key><string>14.4</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.sports-games</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force -s - "$APP" >/dev/null 2>&1 || true
touch "$APP"   # refresh the Finder/Dock icon cache
echo "Built: $(pwd)/$APP"
