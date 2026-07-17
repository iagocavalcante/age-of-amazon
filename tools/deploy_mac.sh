#!/usr/bin/env bash
# Build the macOS app (universal, ad-hoc signed) and print release notes.
# Not notarized: first launch needs right-click -> Open (Gatekeeper).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
STAMP=$(git rev-parse --short HEAD)
mkdir -p build/mac
"$GODOT" --headless --path . --export-release "macOS" build/mac/AgeOfAmazon.zip
echo "BUILT build/mac/AgeOfAmazon.zip ($STAMP)"
echo "Publish: gh release create mac-$STAMP build/mac/AgeOfAmazon.zip \\"
echo "  --title 'Age of Amazon (macOS)' --notes 'Right-click -> Open on first launch.'"
