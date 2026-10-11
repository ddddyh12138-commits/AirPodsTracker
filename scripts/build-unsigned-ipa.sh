#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild build -project AirPodsTracker.xcodeproj -scheme AirPodsTracker \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
APP_PATH='build/DerivedData/Build/Products/Release-iphoneos/AirPodsTracker.app'
test -d "$APP_PATH"
PACKAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/AirPodsTracker-package.XXXXXX")"
mkdir -p "$PACKAGE_DIR/Payload" build/artifacts
ditto "$APP_PATH" "$PACKAGE_DIR/Payload/AirPodsTracker.app"
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR/Payload" build/artifacts/AirPodsTracker-unsigned.ipa
echo 'Created build/artifacts/AirPodsTracker-unsigned.ipa. It still requires your own signing before installation.'
