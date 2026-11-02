#!/bin/sh
# Build build/nvm-app-<version>.dmg — app + an Applications symlink so the
# user can drag-install. Unsigned: first launch needs right-click → Open
# (or xattr -d com.apple.quarantine) until notarization is set up.
set -eu
cd "$(dirname "$0")/.."
VERSION="${NVM_APP_VERSION:-0.1.0}"

sh Tools/make-app-bundle.sh

DMG=build/nvm-app-$VERSION.dmg
STAGING=build/dmg-staging
rm -f "$DMG"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R build/NVMApp.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -quiet -volname "nvm-app $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
echo "built $DMG"
