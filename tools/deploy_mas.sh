#!/usr/bin/env bash
# Build the Mac App Store package (signed, sandboxed). Requires the
# Apple Distribution + Mac Installer Distribution certificates in the
# keychain (create once in Xcode -> Settings -> Accounts). Upload the
# resulting pkg yourself: Transporter.app or
#   xcrun altool --upload-app -f build/mas/AgeOfAmazon.pkg -t macos
# Store metadata lives in docs/store/mac-metadata.md.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
mkdir -p build/mas
if [ ! -f certs/aoa_mas.provisionprofile ]; then
  echo "MISSING certs/aoa_mas.provisionprofile — create a Mac App Store"
  echo "provisioning profile at developer.apple.com (see docs/store/mac-metadata.md §1)."
  exit 1
fi
"$GODOT" --headless --path . --export-release "macOS App Store" build/mas/AgeOfAmazon.pkg
echo "BUILT build/mas/AgeOfAmazon.pkg ($(git rev-parse --short HEAD)) — upload with Transporter or altool"
