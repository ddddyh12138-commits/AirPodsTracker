#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --package-path Packages/TrackerCore
DESTINATION_ID="${1:-}"
if [ -z "$DESTINATION_ID" ]; then
  DESTINATION_ID="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((x["udid"] for k,v in d["devices"].items() if "iOS" in k for x in v if x.get("isAvailable") and x["name"].startswith("iPhone")), ""))')"
fi
if [ -z "$DESTINATION_ID" ]; then
  echo 'No available iPhone simulator. Install an iOS simulator runtime in Xcode.' >&2
  exit 1
fi
xcodebuild test -project AirPodsTracker.xcodeproj -scheme AirPodsTracker \
  -destination "platform=iOS Simulator,id=$DESTINATION_ID" \
  -resultBundlePath "${TMPDIR:-/tmp}/AirPodsTracker-$(date +%s).xcresult" CODE_SIGNING_ALLOWED=NO
