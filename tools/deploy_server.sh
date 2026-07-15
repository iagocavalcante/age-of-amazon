#!/usr/bin/env bash
# Deploy the dedicated server to ssh-tron and PROVE the structure deployed:
# post-deploy health checks assert the gateway serves, the protocol matches
# this checkout, and the public URL works through the whole tunnel chain.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
HOST="${HOST:-ssh-tron}"
PUBLIC_HEALTH="${PUBLIC_HEALTH:-https://game.iagocavalcante.com/health}"
cd "$(dirname "$0")/.."

LOCAL_PROTO=$(grep -oE 'PROTOCOL_VERSION: int = [0-9]+' scripts/autoloads/Net.gd | tr -dc 0-9)
echo "== building Linux server (protocol v$LOCAL_PROTO)"
mkdir -p build/server
"$GODOT" --headless --path . --export-release "Linux Server" \
  build/server/age-of-amazon-server.x86_64 > /dev/null 2>&1
[ -s build/server/age-of-amazon-server.x86_64 ] || { echo "EXPORT FAILED"; exit 1; }

echo "== uploading + restarting"
ssh "$HOST" 'systemctl --user stop aoa-gateway'
scp -q build/server/age-of-amazon-server.x86_64 "$HOST":~/age-of-amazon/
ssh "$HOST" 'chmod +x ~/age-of-amazon/age-of-amazon-server.x86_64 && systemctl --user start aoa-gateway'
sleep 4

echo "== verifying: local health"
LOCAL_HEALTH=$(ssh "$HOST" 'curl -sf -m 5 http://127.0.0.1:9001/health')
echo "   $LOCAL_HEALTH"
echo "$LOCAL_HEALTH" | grep -q '"ok":true' || { echo "GATEWAY NOT HEALTHY"; exit 1; }
echo "$LOCAL_HEALTH" | grep -q "\"protocol\":$LOCAL_PROTO" \
  || { echo "PROTOCOL MISMATCH — deployed binary is not this checkout"; exit 1; }

echo "== verifying: public health (edge -> tunnel -> caddy -> gateway)"
PUB=$(curl -sf -m 15 "$PUBLIC_HEALTH")
echo "   $PUB"
echo "$PUB" | grep -q "\"protocol\":$LOCAL_PROTO" || { echo "PUBLIC CHAIN STALE/BROKEN"; exit 1; }

echo "DEPLOY VERIFIED (protocol v$LOCAL_PROTO live)"
