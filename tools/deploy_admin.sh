#!/usr/bin/env bash
# Deploy the ops dashboard end to end: dashboard.html + Caddyfile + basic-auth
# credentials to ssh-tron, restart the proxy, and verify auth is enforced.
#
#   bash tools/deploy_admin.sh                   # ship; create creds on first run
#   bash tools/deploy_admin.sh --password 'S3C'  # ship and (re)set the password
#
# Credentials: username defaults to "admin" (override with ADMIN_USER=...).
# The bcrypt hash lives only in ~/age-of-amazon/admin.env on the box; the
# plaintext is written to .admin_credentials locally (gitignored) so later
# runs can verify with auth.
set -euo pipefail
cd "$(dirname "$0")/.."

HOST=ssh-tron
ADMIN_USER="${ADMIN_USER:-admin}"
CRED_FILE=".admin_credentials"
PUBLIC=https://game.iagocavalcante.com

PASSWORD=""
if [ "${1:-}" = "--password" ]; then
  PASSWORD="${2:?--password needs a value}"
fi

echo "== credentials"
if [ -n "$PASSWORD" ] || ! ssh $HOST 'test -f ~/age-of-amazon/admin.env'; then
  if [ -z "$PASSWORD" ]; then
    PASSWORD=$(openssl rand -base64 15)
    echo "   generated new password for user '$ADMIN_USER' (saved to $CRED_FILE)"
  else
    echo "   setting supplied password for user '$ADMIN_USER'"
  fi
  # stdin (password + confirmation) so the plaintext never hits a process list
  HASH=$(printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" | ssh $HOST '~/bin/caddy hash-password' | tail -1)
  printf 'AOA_ADMIN_USER=%s\nAOA_ADMIN_HASH=%s\n' "$ADMIN_USER" "$HASH" \
    | ssh $HOST 'umask 077 && cat > ~/age-of-amazon/admin.env'
  printf '%s:%s\n' "$ADMIN_USER" "$PASSWORD" > "$CRED_FILE"
  chmod 600 "$CRED_FILE"
else
  echo "   keeping existing credentials on the box"
fi

echo "== systemd drop-in (EnvironmentFile)"
ssh $HOST 'mkdir -p ~/.config/systemd/user/aoa-proxy.service.d &&
  printf "[Service]\nEnvironmentFile=%%h/age-of-amazon/admin.env\n" \
    > ~/.config/systemd/user/aoa-proxy.service.d/admin.conf &&
  systemctl --user daemon-reload'

echo "== shipping dashboard + Caddyfile"
ssh $HOST 'mkdir -p ~/age-of-amazon/www'
scp -q tools/dashboard.html $HOST:'~/age-of-amazon/www/dashboard.html'
scp -q infra/Caddyfile $HOST:'~/age-of-amazon/Caddyfile'

echo "== restarting proxy"
ssh $HOST 'systemctl --user restart aoa-proxy && sleep 2 && systemctl --user is-active aoa-proxy'

echo "== verifying"
code() { curl -s -m 10 -o /dev/null -w '%{http_code}' "$@"; }
H=$(code $PUBLIC/health)
A=$(code $PUBLIC/admin)
S=$(code $PUBLIC/stats)
echo "   /health $H (want 200, public)  /admin $A  /stats $S (want 401 unauth)"
[ "$H" = 200 ] || { echo "FAILED: /health not public"; exit 1; }
[ "$A" = 401 ] || { echo "FAILED: /admin is not protected"; exit 1; }
[ "$S" = 401 ] || { echo "FAILED: /stats is not protected"; exit 1; }
if [ -f "$CRED_FILE" ]; then
  AA=$(code -u "$(cat "$CRED_FILE")" $PUBLIC/admin)
  SA=$(code -u "$(cat "$CRED_FILE")" $PUBLIC/stats)
  echo "   with credentials: /admin $AA  /stats $SA (want 200)"
  [ "$AA" = 200 ] && [ "$SA" = 200 ] || { echo "FAILED: credentials rejected"; exit 1; }
else
  echo "   (no $CRED_FILE locally — skipped authenticated check)"
fi
echo "ADMIN DEPLOY VERIFIED: $PUBLIC/admin (user: $ADMIN_USER)"
