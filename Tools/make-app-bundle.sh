#!/bin/sh
# Build build/NVMApp.app — a proper app bundle so the app gets normal
# activation + Dock presence (a bare `swift run` binary opens its window
# behind everything and has no Dock icon). Pattern copied from brewery.
set -eu
cd "$(dirname "$0")/.."

VERSION="${NVM_APP_VERSION:-0.1.0}"
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "invalid NVM_APP_VERSION '$VERSION' — expect MAJOR.MINOR.PATCH" >&2
    exit 1
fi

swift build -c release
BIN=$(swift build -c release --show-bin-path)

APP=build/NVMApp.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/NVMApp" "$APP/Contents/MacOS/nvm-app"

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
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>26.0</string>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force -s - "$APP"
echo "built $APP — run with: open build/NVMApp.app"
