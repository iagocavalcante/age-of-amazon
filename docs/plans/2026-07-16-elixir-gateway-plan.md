# Plan: Elixir/BEAM Gateway (saved for later)

Agreed direction (2026-07-16): move the LOBBY tier to pure Elixir + Cowboy
for BEAM state control and supervision; the match SIMULATION stays Godot —
the sim's whole safety model is "identical GDScript on client and server",
and a rewrite would mean maintaining two simulations in lockstep forever.

## Shape

```
server/                   # mix project inside this repo
  lib/aoa/room.ex         # GenServer per room: code, seats, votes, heartbeat
  lib/aoa/room_registry.ex# Registry + DynamicSupervisor (crash = one room)
  lib/aoa/match_port.ex   # spawn/monitor Godot match binaries as Ports —
                          # linked processes make match leaks impossible
  lib/aoa/socket.ex       # Cowboy WS handler, small JSON protocol
  lib/aoa/health.ex       # /health + /stats, native
```

- Protocol change required: Godot's lobby client (`Gateway.gd`) switches
  from Godot multiplayer RPC framing to plain JSON over WebSocket
  (~7 message types: hello, create, join, room_update, start, match_ready,
  error). Cowboy cannot speak Godot's proprietary RPC framing. Match
  connections are untouched.
- Deploy: Mix release under the existing systemd user unit; Caddy and the
  health watchdog barely change.
- Later meta-layer on the same BEAM: accounts, matchmaking queue,
  leaderboards, match history.

## Why not now
The Godot gateway works and is harness-covered; the admin dashboard and
gameplay had higher priority. Revisit when lobby features (matchmaking,
persistence) outgrow GenServer-shaped-GDScript.
