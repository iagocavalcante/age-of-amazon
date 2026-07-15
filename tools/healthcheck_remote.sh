#!/usr/bin/env bash
# Runs ON the box via a user systemd timer: checks each layer and restarts
# whichever failed. Layers are checked inside-out and the round stops at the
# first failure — the /health probes for proxy and tunnel route THROUGH the
# gateway, so restarting them for a gateway outage would only kick live
# match connections for nothing. Silent when healthy; transitions logged.
LOG="$HOME/age-of-amazon/health.log"

check() {  # name url unit
  if ! curl -sf -m 8 "$2" | grep -q '"ok":true'; then
    echo "$(date -Is) $1 UNHEALTHY -> restarting $3" >> "$LOG"
    systemctl --user restart "$3"
    exit 0  # let the next round re-check the outer layers
  fi
}

check gateway "http://127.0.0.1:9001/health" aoa-gateway
check proxy   "http://127.0.0.1:8081/health" aoa-proxy
check tunnel  "https://game.iagocavalcante.com/health" aoa-tunnel
exit 0
