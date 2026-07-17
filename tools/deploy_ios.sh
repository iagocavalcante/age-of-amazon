#!/usr/bin/env bash
# Regenerate the iOS Xcode project (build/ios/). Signing and upload happen
# in Xcode (or via an App Store Connect API key) — never from here.
#
#   1. bash tools/deploy_ios.sh
#   2. open build/ios/AgeOfAmazon.xcodeproj   # pick Team, Product > Archive
#   3. Organizer -> Distribute App -> App Store Connect
#
# Store metadata lives in docs/store/.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
"$GODOT" --headless --path . --export-release "iOS" build/ios/AgeOfAmazon.ipa
echo "XCODE PROJECT READY: build/ios/AgeOfAmazon.xcodeproj ($(git rev-parse --short HEAD))"
