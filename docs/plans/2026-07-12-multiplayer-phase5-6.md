# Multiplayer Phase 5/6 Sub-Plan — Lobby, Gateway, Menu, Deployment

> Written at the Phase-4 checkpoint against the code as of commit `728f420`.

**Goal:** Players create/join rooms with 4-letter codes from an in-game menu;
the gateway spawns one match-server process per room; the web build deploys
against a VPS behind Caddy (WSS).

## Decisions

- **Gateway = same Godot project**, boot arg `--gateway --port=9000
  --match-port-base=9100`. New `Mode.GATEWAY` in `Net`; room RPCs live on a
  new `Gateway` autoload (client + gateway sides, same file — mirrors how
  `Net`/`Replication` are structured).
- **Match spawn:** `OS.create_process` of `OS.get_executable_path()` with
  `--headless [--path <project> in editor builds] ++ --server --port=N
  --players=K --seed=S`. Port allocation walks up from the base; bind failure
  on the match side exits nonzero and the gateway reports the room as failed.
- **Match URL:** the gateway sends only the port. The client builds the URL
  from `match_url_template` in `res://server_config.json`
  (`ws://127.0.0.1:{port}` for dev; `wss://game.example.com/m/{port}` behind
  Caddy path-routing in prod). The gateway never needs to know its public
  address.
- **Match teardown:** the match server quits itself — 60 s with zero peers
  after having had at least one, or 30 s after game over. No pid bookkeeping
  in the gateway.
- **Rejoin (v1):** reconnecting to the match port re-claims the lowest free
  tribe slot, whose units persisted. Limitation, flagged: if two players drop
  simultaneously they may swap tribes on return. Tokens are the v2 fix.
- **Main menu:** new `MainMenu.tscn` becomes `run/main_scene`. Any harness /
  `--server` / `--join` arg makes it immediately swap to `Main.tscn`, so every
  existing harness keeps working unchanged. Buttons: Single Player,
  Multiplayer (URL field, Create Room, code field + Join, lobby slot list,
  Start for the host = slot 0).
- **Room codes:** 4 chars from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no 0/O/1/I/L).

## Task order

1. Match server self-teardown (Net) — keeps orphan processes impossible
   before the gateway ever spawns one.
2. `Gateway` autoload + `--gateway` boot mode in Main.
3. `server_config.json` + `MainMenu` scene/script + `run/main_scene` swap +
   `Net.pending_match_url` hand-off into Main's client boot.
4. `tools/test_gateway.sh`: headless gateway + host client (prints the room
   code) + joiner client (gets the code via the script); both must reach
   in-match snapshot (3 units) through a gateway-spawned match process.
5. Phase 6: `Linux Server` export preset; `docs/deploy-multiplayer.md`
   (Caddyfile with `/ws` → gateway and `/m/{port}` → match ports, systemd
   unit, export/build steps); ADR entry in `docs/architecture.md`.

## Out of scope (unchanged from the design doc)

Rejoin tokens, matchmaking, spectators, server-side fog filtering, match
persistence.
