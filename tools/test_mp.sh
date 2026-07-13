#!/usr/bin/env bash
# Multiplayer convergence harness: 1 headless match server + 2 headless
# scripted clients (--test-mp-client). Greps the client logs for the
# [test-mp] verdict lines; any FAILED (or a missing verdict) fails the run.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PORT="${PORT:-9101}"
DIR="$(mktemp -d)"
cd "$(dirname "$0")/.."

"$GODOT" --headless --path . ++ --server --port="$PORT" --players=2 --seed=42 \
  > "$DIR/server.log" 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
sleep 4

"$GODOT" --headless --path . ++ --test-mp-client --join=ws://127.0.0.1:$PORT \
  > "$DIR/client0.log" 2>&1 &
C0=$!
sleep 1
"$GODOT" --headless --path . ++ --test-mp-client --join=ws://127.0.0.1:$PORT \
  > "$DIR/client1.log" 2>&1 &
C1=$!

wait $C0 || true
wait $C1 || true

echo "--- server tail ---"
tail -5 "$DIR/server.log"
echo "--- client verdicts ---"
grep -h "\[test-mp\]" "$DIR"/client*.log || { echo "NO VERDICTS (logs in $DIR)"; exit 1; }

VERDICTS=$(grep -hc "\[test-mp\].*OK" "$DIR"/client0.log "$DIR"/client1.log | paste -sd+ - | bc)
if grep -h "\[test-mp\]" "$DIR"/client*.log | grep -q FAILED; then
  echo "RESULT: FAILED (logs in $DIR)"
  exit 1
fi
# Each client must produce 3 OK verdicts (snapshot, move-sync, foreign-command).
if [ "$VERDICTS" -lt 6 ]; then
  echo "RESULT: INCOMPLETE ($VERDICTS/6 OK verdicts; logs in $DIR)"
  exit 1
fi
echo "RESULT: OK"
