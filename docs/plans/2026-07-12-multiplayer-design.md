# Multiplayer Design — Server-Based Matches for Multiple Tribes

**Date:** 2026-07-12
**Status:** Validated design, pre-implementation

## Goal

Live PvP matches where 2–4 human players each control a tribe, backed by a
dedicated server on a cheap VPS. Single-player (vs `EnemyAI`) stays fully
playable offline from the static GitHub Pages build.

## Decision summary

Authoritative headless Godot server over WebSockets. The same Godot project
runs in three modes: web/desktop **client**, headless **match server**, and
local-authority **single-player**. Deterministic lockstep was considered and
rejected: it demands perfect cross-client determinism (fixed tick, seeded RNG,
no float drift) retrofitted onto a codebase not built for it, and desyncs are
notoriously hard to debug. Player-hosted WebRTC was rejected for host
advantage and NAT/browser pain.

## Topology and transport

1. **Client** — renders, captures input; in multiplayer it sends *commands*
   instead of executing them.
2. **Dedicated server** — same project exported with the `dedicated_server`
   feature (strips rendering/audio), run with `godot --headless` on the VPS.
3. **Single-player** — client is its own authority; no server, unchanged UX.

Transport is `WebSocketMultiplayerPeer` over WSS (browsers require TLS from
HTTPS pages). Caddy on the VPS terminates TLS and reverse-proxies to Godot.
Godot's high-level multiplayer API (RPCs, `MultiplayerSpawner`,
`MultiplayerSynchronizer`) rides on top.

The server owns all game state. Clients send intent; the server validates
(ownership, affordability, population cap) and executes. Map generation stays
seed-based: the server picks `map_seed`, clients generate identical terrain
locally — terrain never crosses the wire, only entities do.

## Sim/view split and the command pipeline

Today `Unit.gd` mixes simulation with presentation, and
`SelectionManager`/`EnemyAI` call unit methods directly. The refactor
introduces one seam:

- A **command** is plain data:
  `{type: "move"|"gather"|"attack"|"build"|"train", actor_ids, target, player_id}`.
- `SelectionManager` and `EnemyAI` submit commands to a new **`CommandRouter`**
  autoload instead of calling `unit.move_to()` etc.
- Single-player: the router validates and executes locally.
- Multiplayer: the client router RPCs the command to the server; the server
  validates and executes via the same executor code.

Simulation code runs only where authority lives
(`is_multiplayer_authority()`). Clients run a thin view layer that
interpolates synced state and derives sprite frames from velocity/state.
Presentation-only code (tweens, `AssetLibrary` textures, health bars) is
skipped on the headless server.

`GameManager` match state (stockpiles, game state, winner) becomes
server-owned and replicated. `EventBus` stays process-local; both sides emit
the same signals from their own perspective. `PLAYER_COUNT` generalizes from a
hardcoded 2 to the match's player list.

## Server processes, lobby, match lifecycle

**Process-per-match.** Match state lives in autoloads, so two matches in one
process would collide. Each match runs in its own headless Godot process:
crash isolation, bounded CPU, no autoload refactor. A **gateway process**
(same project, `--mode=gateway`) accepts WSS connections, manages rooms, and
spawns match processes on internal ports. Caddy proxies
`wss://<host>/ws` → gateway; match processes are reached via ports or paths
the gateway hands out.

**Lobby flow (no matchmaking — YAGNI):** create room → 4-letter room code →
friends join by code → pick tribe slots (2–4) → host starts → gateway spawns
the match process and sends `{match_port, map_seed, player_slots}` → clients
generate the map from the seed and connect.

**Victory:** last tribe with a town center standing (today's rule generalized
to N players). **Disconnects:** the tribe's units idle but persist; the player
may rejoin with a session token while the match lives. Empty matches shut down
after a grace period.

## State sync

- Entities spawn via `MultiplayerSpawner` (server-driven) with stable network
  names.
- A `MultiplayerSynchronizer` per unit replicates
  `position, current_hp, current_state, facing` at ~10 Hz; clients interpolate
  so movement looks smooth at render rate.
- Discrete events (deaths, training completed, resource changes, game over)
  are reliable RPCs. Stockpiles replicate only to the owning player.

**Accepted risk (v1):** clients receive all entity positions and hide them
with the existing client-side fog renderer — as classic RTSes did. A modified
client could maphack. Server-side interest management (per-player visibility
filtering) is a known later hardening step, out of scope for v1 because it
roughly doubles sync complexity. Gameplay-affecting cheats (commanding foreign
units, free resources) are impossible: the server validates every command.

## Error handling

- Invalid commands are dropped server-side with a log line.
- Protocol version check on join; mismatch yields a clear "please refresh"
  error.
- Client connection loss shows a reconnect screen; the session token allows
  rejoining a live match.

## Testing

Extend the existing headless-harness pattern: `--test-mp-basic` launches one
headless server plus two headless scripted clients, issues commands from both
sides, and asserts convergence (positions, stockpiles, victory). Runs locally
and in CI with no rendering. Command validation (ownership, affordability)
gets direct harness coverage.

## Deployment

- New `Linux Server` export preset.
- systemd unit for the gateway on the VPS; gateway spawns match processes.
- Caddy for TLS/WSS.
- The web client gains a "Multiplayer" menu entry; the server URL is read from
  a small JSON config deployed next to the exported site, so GitHub Pages
  deploys don't hardcode the VPS address.

## Out of scope for v1

- Matchmaking/ranking (room codes only)
- Server-side visibility filtering (maphack hardening)
- Spectators, replays, chat
- Persistence between matches
