# Deploying Multiplayer

> **Current deployment (2026-07-13):** live on the `ssh-tron` box
> (ssh.iagocavalcante.com, Ubuntu 22.04) WITHOUT root: user systemd services
> `aoa-gateway` (gateway :9000, matches 9100+) and `aoa-proxy` (user-space
> Caddy from `~/bin/caddy`, plain HTTP :8081 doing `/ws` + `/m/<port>`
> routing), linger enabled so both survive reboots. Binary + Caddyfile live
> in `~tron/age-of-amazon/`. Public exposure: dedicated locally-managed
> cloudflared tunnel `aoa-game` (id 535313f6, config
> `~/.cloudflared/aoa-game-config.yml`, `protocol: http2` — QUIC dies under
> the box's VPN) run by user service `aoa-tunnel`, serving
> `game.iagocavalcante.com -> http://localhost:8081`. PUBLIC AND VERIFIED:
> the gateway harness passes end-to-end against
> `wss://game.iagocavalcante.com/ws` + `/m/{port}`.
> Web builds for production need `server_config.json` set to those wss URLs
> before exporting. Gotchas learned: `cloudflared tunnel route dns` reads the
> default `~/.cloudflared/config.yml` and can route to the WRONG tunnel —
> pass `--config` explicitly (and `--overwrite-dns` to fix a bad record).
> The generic runbook below describes the root-based layout for a dedicated
> VPS; adapt as needed.

One small VPS runs everything: a **gateway** process (lobby, room codes) that
spawns one **match server** process per room. Browser clients need WSS, so
Caddy terminates TLS and path-routes to the local ports.

## 1. Build the server binary

Requires the Linux export templates (Editor → Manage Export Templates).

```bash
godot --headless --path . --export-release "Linux Server" build/server/age-of-amazon-server.x86_64
```

The `Linux Server` preset is a dedicated-server export (`dedicated_server=true`,
PCK embedded): one self-contained binary, no textures/audio.

## 2. VPS layout

```bash
sudo useradd -r -m -d /opt/age-of-amazon ageofamazon
sudo cp build/server/age-of-amazon-server.x86_64 /opt/age-of-amazon/
sudo chown -R ageofamazon: /opt/age-of-amazon
```

`/etc/systemd/system/aoa-gateway.service`:

```ini
[Unit]
Description=Age of Amazon multiplayer gateway
After=network-online.target
Wants=network-online.target

[Service]
User=ageofamazon
ExecStart=/opt/age-of-amazon/age-of-amazon-server.x86_64 --headless ++ --gateway --port=9000 --match-port-base=9100
Restart=on-failure
# Match servers are children of the gateway; keep them in the same cgroup.
KillMode=control-group

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now aoa-gateway
```

Match servers are spawned by the gateway on ports 9100+ and shut themselves
down when idle (60 s empty / 30 s after game over) — nothing else to manage.

## 3. Caddy (TLS/WSS)

Browsers on an HTTPS page can only open `wss://`. Caddy handles certificates
automatically. `/etc/caddy/Caddyfile`:

```caddy
game.example.com {
	# Lobby
	handle /ws* {
		reverse_proxy 127.0.0.1:9000
	}
	# Match servers: /m/<port> -> localhost:<port>
	@match path_regexp m ^/m/(9[1-2][0-9][0-9])$
	handle @match {
		reverse_proxy 127.0.0.1:{re.m.1}
	}
}
```

Only ports 80/443 need to be open in the firewall; game traffic never hits
9000/91xx directly. The path regexp caps which internal ports are reachable.

## 4. Client configuration

`server_config.json` (bundled into the export from the project root):

```json
{
	"gateway_url": "wss://game.example.com/ws",
	"match_url_template": "wss://game.example.com/m/{port}"
}
```

Set these before exporting the Web build; the local-dev defaults are
`ws://127.0.0.1:9000` / `ws://127.0.0.1:{port}`. The Web deploy itself is
unchanged (export preset "Web" → `build/web` → `gh-pages`).

## 5. Browser caveats

- A backgrounded/occluded tab throttles `requestAnimationFrame`, freezing the
  Godot loop: the world stops updating and inbound packets queue up. The
  WebSocket buffers (256 KB / 4096 packets) absorb a few minutes of this;
  beyond that, packets drop and the client desyncs — rejoining the match
  (fresh snapshot) recovers. Verified: an occluded tab shows exactly
  "Buffer payload full! Dropping data." in the console.
- Browsers on HTTPS pages require `wss://` — set both URLs in
  `server_config.json` accordingly before exporting.

## 6. Local smoke tests

```bash
bash tools/test_mp.sh        # 1 match server + 2 scripted clients
bash tools/test_gateway.sh   # gateway + host + code-fed joiner, end to end
```

Or by hand: run `--gateway` headless, launch two editor instances, and use
the main menu's Create Room / Join flow against `ws://127.0.0.1:9000`.
