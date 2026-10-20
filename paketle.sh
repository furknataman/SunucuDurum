#!/bin/bash
# Derler, "~/Applications/Sunucu Durum.app" paketini oluşturur, ad-hoc imzalar ve uygulamayı yeniden başlatır.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="$HOME/Applications/Sunucu Durum.app"
pkill -x SunucuDurum 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SunucuDurum "$APP/Contents/MacOS/SunucuDurum"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.solvy.sunucudurum</string>
    <key>CFBundleName</key><string>Sunucu Durum</string>
    <key>CFBundleDisplayName</key><string>Sunucu Durum</string>
    <key>CFBundleExecutable</key><string>SunucuDurum</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>tr</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose "$APP"
open "$APP"
echo "Hazır: $APP"
