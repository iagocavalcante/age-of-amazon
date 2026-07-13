#!/usr/bin/env bash
# Lobby end-to-end harness: gateway + host client + joiner client. The host
# prints its room code; this script hands it to the joiner. Both clients must
# ride the lobby into a gateway-spawned match process and complete the match
# config handshake.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
GW_PORT="${GW_PORT:-9200}"
MATCH_BASE="${MATCH_BASE:-9300}"
DIR="$(mktemp -d)"
cd "$(dirname "$0")/.."

"$GODOT" --headless --path . ++ --gateway --port=$GW_PORT --match-port-base=$MATCH_BASE \
  > "$DIR/gateway.log" 2>&1 &
GW_PID=$!
cleanup() {
  kill $GW_PID 2>/dev/null || true
  pkill -f -- "--server --port=$MATCH_BASE" 2>/dev/null || true
}
trap cleanup EXIT
sleep 3

"$GODOT" --headless --path . ++ --test-gw-host --gateway-url=ws://127.0.0.1:$GW_PORT \
  > "$DIR/host.log" 2>&1 &
HOST_PID=$!

CODE=""
for _ in $(seq 1 40); do
  CODE=$(grep -o "code=[A-Z0-9]*" "$DIR/host.log" 2>/dev/null | head -1 | cut -d= -f2 || true)
  [ -n "$CODE" ] && break
  sleep 0.5
done
if [ -z "$CODE" ]; then
  echo "FAILED: host never printed a room code (logs in $DIR)"
  exit 1
fi
echo "room code: $CODE"

"$GODOT" --headless --path . ++ --test-gw-join --gateway-url=ws://127.0.0.1:$GW_PORT --room=$CODE \
  > "$DIR/join.log" 2>&1 &
JOIN_PID=$!

wait $HOST_PID || true
wait $JOIN_PID || true

echo "--- gateway tail ---"
tail -4 "$DIR/gateway.log"
echo "--- verdicts ---"
grep -h "\[test-gw\]" "$DIR"/host.log "$DIR"/join.log

if grep -h "\[test-gw\]" "$DIR"/host.log "$DIR"/join.log | grep -q FAILED; then
  echo "RESULT: FAILED (logs in $DIR)"
  exit 1
fi
if [ "$(grep -hc "config OK" "$DIR"/host.log "$DIR"/join.log | paste -sd+ - | bc)" -lt 2 ]; then
  echo "RESULT: INCOMPLETE (logs in $DIR)"
  exit 1
fi
if ! grep -q "stranger-refused OK" "$DIR/host.log"; then
  echo "RESULT: INCOMPLETE (no stranger-refused verdict; logs in $DIR)"
  exit 1
fi
echo "RESULT: OK"
