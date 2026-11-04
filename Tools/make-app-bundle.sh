#!/bin/sh
# Build build/NVMApp.app — a proper app bundle so the app gets normal
# activation + Dock presence (a bare `swift run` binary opens its window
# behind everything and has no Dock icon). Pattern copied from brewery.
set -eu
cd "$(dirname "$0")/.."

VERSION="${NVM_APP_VERSION:-0.1.1}"
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "invalid NVM_APP_VERSION '$VERSION' — expect MAJOR.MINOR.PATCH" >&2
    exit 1
fi

swift build -c release
BIN=$(swift build -c release --show-bin-path)

APP=build/NVMApp.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/NVMApp" "$APP/Contents/MacOS/nvm-app"

# App icon: Resources/app-icon.png (1024+) -> AppIcon.icns via iconutil.
if [ -f Resources/app-icon.png ]; then
    ICONSET=build/AppIcon.iconset
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    make_size() { sips -z "$1" "$1" Resources/app-icon.png --out "$ICONSET/$2" >/dev/null; }
    make_size 16   icon_16x16.png
    make_size 32   icon_16x16@2x.png
    make_size 32   icon_32x32.png
    make_size 64   icon_32x32@2x.png
    make_size 128  icon_128x128.png
    make_size 256  icon_128x128@2x.png
    make_size 256  icon_256x256.png
    make_size 512  icon_256x256@2x.png
    make_size 512  icon_512x512.png
    make_size 1024 icon_512x512@2x.png
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>nvm-app</string>
    <key>CFBundleDisplayName</key>       <string>Node Versions</string>
    <key>CFBundleExecutable</key>        <string>nvm-app</string>
    <key>CFBundleIdentifier</key>        <string>com.illusion.nvm-app</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>26.0</string>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force -s - "$APP"
echo "built $APP — run with: open build/NVMApp.app"
