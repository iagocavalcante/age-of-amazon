#!/usr/bin/env bash
# Multiplayer convergence harness: 1 headless match server + PLAYERS headless
# scripted clients (--test-mp-client). Each client must produce 3 OK verdicts
# (snapshot, move-sync, foreign-command); any FAILED fails the run.
#   PLAYERS=4 bash tools/test_mp.sh   # 4-tribe match
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PORT="${PORT:-9101}"
PLAYERS="${PLAYERS:-2}"
DIR="$(mktemp -d)"
cd "$(dirname "$0")/.."

"$GODOT" --headless --path . ++ --server --port="$PORT" --players="$PLAYERS" --seed=42 \
  > "$DIR/server.log" 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
sleep 4

PIDS=()
for i in $(seq 0 $((PLAYERS - 1))); do
  "$GODOT" --headless --path . ++ --test-mp-client --join=ws://127.0.0.1:$PORT \
    > "$DIR/client$i.log" 2>&1 &
  PIDS+=($!)
  sleep 1
done
for pid in "${PIDS[@]}"; do wait "$pid" || true; done

echo "--- server tail ---"
tail -4 "$DIR/server.log"
echo "--- client verdicts ---"
grep -h "\[test-mp\]" "$DIR"/client*.log || { echo "NO VERDICTS (logs in $DIR)"; exit 1; }

if grep -h "\[test-mp\]" "$DIR"/client*.log | grep -q FAILED; then
  echo "RESULT: FAILED (logs in $DIR)"
  exit 1
fi
OKS=$(grep -h "\[test-mp\].* OK" "$DIR"/client*.log | wc -l | tr -d ' ')
NEED=$((PLAYERS * 3))
if [ "$OKS" -lt "$NEED" ]; then
  echo "RESULT: INCOMPLETE ($OKS/$NEED OK verdicts; logs in $DIR)"
  exit 1
fi
echo "RESULT: OK ($OKS/$NEED verdicts, $PLAYERS players)"
