#!/usr/bin/env bash
# The one sanctioned web deploy: exports with the production server config
# and build stamp, ships to gh-pages WITH the custom-domain CNAME file
# (force-pushes without it silently un-set aoa.iagocavalcante.com), and
# waits until the CDN serves the new bytes.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
DOMAIN="aoa.iagocavalcante.com"
REPO="git@github.com:iagocavalcante/age-of-amazon.git"
cd "$(dirname "$0")/.."

HASH=$(git rev-parse --short HEAD)
cat > server_config.json << CONF
{
	"gateway_url": "wss://game.iagocavalcante.com/ws",
	"match_url_template": "wss://game.iagocavalcante.com/m/{port}",
	"build": "$HASH"
}
CONF
mkdir -p build/web
echo "== exporting web build ($HASH)"
"$GODOT" --headless --path . --export-release "Web" build/web/index.html > /dev/null 2>&1
git checkout -- server_config.json
[ -s build/web/index.wasm ] || { echo "EXPORT FAILED"; exit 1; }

echo "$DOMAIN" > build/web/CNAME
cd build/web
rm -rf .git
git init -q && git checkout -q -b gh-pages
git add -A && git commit -q -m "deploy: $HASH"
git push -f "$REPO" gh-pages:gh-pages 2>&1 | tail -1
cd ../..
rm -rf build/web/.git

echo "== waiting for the CDN"
LOCAL=$(stat -f%z build/web/index.pck)
for _ in $(seq 1 40); do
  R=$(curl -sI "https://$DOMAIN/index.pck" | grep -i content-length | tr -dc 0-9 || true)
  [ "$R" = "$LOCAL" ] && { echo "DEPLOY VERIFIED: https://$DOMAIN (build $HASH)"; exit 0; }
  sleep 15
done
echo "WARNING: CDN not serving new pck yet (cert may still be provisioning)"
