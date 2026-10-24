#!/bin/sh
# Build "Warcraft I & II for Mac.app" into $1 (build dir). $2 = version.
set -eu
B="$1"; VERSION="$2"
APP="$B/Warcraft I & II for Mac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -target arm64-apple-macos14.0 mac/W1RMac.swift -o "$APP/Contents/MacOS/W1RMac"
cp "$B/VERSION.dll" mac/sync_mods.sh "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>W1RMac</string>
  <key>CFBundleIdentifier</key><string>io.github.vifill.warcraft1-mac</string>
  <key>CFBundleName</key><string>Warcraft I &amp; II for Mac</string>
  <key>CFBundleDisplayName</key><string>Warcraft I &amp; II for Mac</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign -f -s - "$APP"
echo "built $APP"
