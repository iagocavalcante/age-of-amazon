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
  "--match-args=--end-after=45" \
  > "$DIR/gateway.log" 2>&1 &
GW_PID=$!
cleanup() {
  kill $GW_PID 2>/dev/null || true
  pkill -f -- "--server --port=$MATCH_BASE" 2>/dev/null || true
}
trap cleanup EXIT
sleep 3

HEALTH=$(curl -sf -m 5 "http://127.0.0.1:$((GW_PORT + 1))/health")
echo "health: $HEALTH"
echo "$HEALTH" | grep -q '"ok":true' || { echo "RESULT: FAILED (no health endpoint)"; exit 1; }
STATS=$(curl -sf -m 5 "http://127.0.0.1:$((GW_PORT + 1))/stats")
echo "stats: $STATS"
echo "$STATS" | grep -q '"matches"' || { echo "RESULT: FAILED (no stats endpoint)"; exit 1; }

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

# While the match runs, /stats must report it (via the match telemetry
# sidecar) and must never leak the full room code.
MATCH_SEEN=0
for _ in $(seq 1 40); do
  S=$(curl -sf -m 5 "http://127.0.0.1:$((GW_PORT + 1))/stats" || true)
  if echo "$S" | grep -q "$CODE"; then
    echo "RESULT: FAILED (/stats leaked the full room code)"
    exit 1
  fi
  if echo "$S" | grep -q '"port":'; then
    MATCH_SEEN=1
    echo "stats saw live match: $S"
    break
  fi
  sleep 0.5
done

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
if ! grep -q "rejoin-takeover OK" "$DIR/host.log"; then
  echo "RESULT: INCOMPLETE (no rejoin-takeover verdict; logs in $DIR)"
  exit 1
fi
if [ "$MATCH_SEEN" -ne 1 ]; then
  echo "RESULT: INCOMPLETE (/stats never reported the live match; logs in $DIR)"
  exit 1
fi

# Ranking E2E: the match self-ends (--end-after via --match-args), the match
# server reports the winner to the gateway, and the leaderboard must move.
HOST_NAME=$(grep -o "hello OK name=GwH[0-9]*" "$DIR/host.log" | head -1 | cut -d= -f2)
RANKED=0
for _ in $(seq 1 50); do
  BOARD=$(curl -sf -m 5 "http://127.0.0.1:$((GW_PORT + 1))/leaderboard" || true)
  if echo "$BOARD" | grep -q "\"name\":\"$HOST_NAME\",\"wins\":1"; then
    RANKED=1
    echo "leaderboard: $BOARD"
    break
  fi
  sleep 2
done
if [ "$RANKED" -ne 1 ]; then
  echo "RESULT: FAILED (winner never appeared on the leaderboard; logs in $DIR)"
  exit 1
fi
echo "RESULT: OK"
