# Multiplayer (Authoritative Server) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Live 2–4 player PvP matches on a dedicated headless Godot server, per `docs/plans/2026-07-12-multiplayer-design.md`, while single-player keeps working offline.

**Architecture:** One Godot project, three run modes (client, headless match server, offline single-player). All gameplay intent flows through a new `CommandRouter` autoload; the authority validates and executes, `MultiplayerSpawner`/`MultiplayerSynchronizer` replicate entity state over `WebSocketMultiplayerPeer`.

**Tech Stack:** Godot 4.5 / GDScript, WebSockets (WSS via Caddy in prod), systemd on a VPS.

---

## How to work in this repo (read first)

- **Godot binary:** `/Applications/Godot.app/Contents/MacOS/Godot` (alias below as `$GODOT`).
- **There is no unit-test framework.** The repo's testing convention is *headless harnesses*: `Main.gd` reads `OS.get_cmdline_user_args()` and runs scripted scenarios that print `... OK` / `... FAILED` and `get_tree().quit()`. Run them as:
  `$GODOT --headless --path . ++ --test-move`
  Follow this convention for every new test. "Write the failing test" below means: write the harness (or extend one), run it, and confirm it prints FAILED / errors before implementing.
- **After adding any script with a new `class_name`, run `$GODOT --headless --path . --import` once** — otherwise every dependent script fails to parse (stale global class cache).
- **GDScript gotcha:** `typed_array = untyped.filter(...)` fails at runtime; use `typed_array.assign(...)`.
- **Regression gate for every task:** `--test-move` and `--test-systems` must still print their OK lines.
- Commit after every task. Never commit with a harness printing FAILED.

## Phasing and honesty note

Phases 1–3 are pure offline refactors with complete code in this plan — execute them as written. Phase 4 (networking) gives complete skeletons plus exact RPC contracts, but Godot's multiplayer API details must be verified in-engine as you go; treat the code as the spec and keep the harnesses green. **Phases 5–6 are intentionally coarser: STOP after Phase 4 and write a detailed sub-plan for them against the then-current code** (superpowers:writing-plans). Planning their fine detail now would be fiction.

---

# Phase 1 — Command pipeline (offline, zero behavior change)

Every gameplay order (move/gather/attack/train) becomes plain data routed through one autoload. This is the seam multiplayer plugs into.

### Task 1.1: Stable entity names

Entities need stable string ids that will later be identical on server and clients (node names replicate through `MultiplayerSpawner`).

**Files:**
- Modify: `scripts/autoloads/GameManager.gd`
- Modify: `scripts/main/Main.gd` (`_place_building`, `_spawn_unit`)
- Modify: `scripts/buildings/Building.gd` (`_spawn_unit`)
- Modify: `scripts/world/AnimalManager.gd` (wherever animals are instantiated — find `add_child` on the animal)

**Step 1: Add the counter to GameManager**

```gdscript
# GameManager.gd — add below `var map_seed: int = 0`
var _next_entity_id: int = 0

# Deterministic, authority-issued entity names ("U1", "B2", "A3"). Node names
# double as network ids once multiplayer replicates them.
func claim_entity_name(prefix: String) -> String:
	_next_entity_id += 1
	return "%s%d" % [prefix, _next_entity_id]
```

**Step 2: Name every spawned entity before `add_child`**

In `Main._spawn_unit` and `Building._spawn_unit`: `unit.name = GameManager.claim_entity_name("U")`.
In `Main._place_building`: `building.name = GameManager.claim_entity_name("B")` (before `buildings.add_child`).
In `AnimalManager` where animals spawn: `animal.name = GameManager.claim_entity_name("A")`.

**Step 3: Verify**

Run: `$GODOT --headless --path . ++ --test-systems`
Expected: same OK lines as before the change (`gathering OK`, `combat OK`, `fog OK`, ...).

**Step 4: Commit** — `feat(mp): stable authority-issued entity names`

### Task 1.2: CommandRouter autoload with `move`

**Files:**
- Create: `scripts/autoloads/CommandRouter.gd`
- Modify: `project.godot` `[autoload]` — add `CommandRouter="*res://scripts/autoloads/CommandRouter.gd"` **after** GameManager/Constants (it depends on them).
- Modify: `scripts/main/Main.gd` (new harness `--test-commands`)

**Step 1: Write the failing harness**

Add to `Main._ready` arg dispatch: `if "--test-commands" in args: _run_commands_test()`, and:

```gdscript
# Prove commands flow through CommandRouter: a move command relocates units,
# a spoofed player_id is rejected.
func _run_commands_test() -> void:
	await get_tree().create_timer(0.5).timeout
	var villagers: Array = get_tree().get_nodes_in_group("player_0").filter(
		func(n: Node) -> bool: return n is UnitBase)
	var mover: UnitBase = villagers[0]
	var start: Vector2 = mover.global_position
	CommandRouter.submit({
		"type": "move", "player_id": 0,
		"actor_names": [String(mover.name)],
		"target": Constants.grid_to_world(8, 8),
	})
	await get_tree().create_timer(3.0).timeout
	var moved: bool = mover.global_position.distance_to(start) > 40.0
	print("[test-commands] move ", "OK" if moved else "FAILED")

	# Ownership: player 1 may not command player 0's unit.
	var pos_before: Vector2 = mover.global_position
	CommandRouter.submit({
		"type": "move", "player_id": 1,
		"actor_names": [String(mover.name)],
		"target": Constants.grid_to_world(-8, -8),
	})
	await get_tree().create_timer(1.5).timeout
	var rejected: bool = mover.global_position.distance_to(pos_before) < 60.0 \
		or mover.global_position.distance_to(Constants.grid_to_world(8, 8)) < 80.0
	print("[test-commands] ownership ", "OK" if rejected else "FAILED")
	get_tree().quit()
```

Run: `$GODOT --headless --path . ++ --test-commands`
Expected: parse error — `CommandRouter` not declared. (That's the failing state.)

**Step 2: Implement CommandRouter**

```gdscript
# scripts/autoloads/CommandRouter.gd
extends Node

# The single seam every gameplay order flows through, as plain data:
#   {type:"move",   player_id, actor_names: Array, target: Vector2}
#   {type:"gather", player_id, actor_names: Array, cell: Vector2i}
#   {type:"attack", player_id, actor_names: Array, target_name: String}
#   {type:"train",  player_id, building_name: String, unit_type: String}
# Offline the router is its own authority. In multiplayer, clients forward
# commands to the server, which validates and executes the same way.

func submit(command: Dictionary) -> void:
	_validate_and_execute(command)

func _validate_and_execute(command: Dictionary) -> void:
	match command.get("type", ""):
		"move":
			_exec_move(command)
		"gather":
			_exec_gather(command)
		"attack":
			_exec_attack(command)
		"train":
			_exec_train(command)
		_:
			push_warning("CommandRouter: unknown command %s" % [command])

# Actors resolve by name from the issuing player's group — ownership check
# and dangling-reference filtering in one step.
func _resolve_actors(command: Dictionary) -> Array[UnitBase]:
	var owned: Array[UnitBase] = []
	var wanted: Array = command.get("actor_names", [])
	for node: Node in get_tree().get_nodes_in_group("player_%d" % int(command["player_id"])):
		var unit: UnitBase = node as UnitBase
		if unit != null and String(unit.name) in wanted:
			owned.append(unit)
	return owned

func _resolve_target(target_name: String) -> Node2D:
	for group: String in ["units", "buildings", "animals"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if String(node.name) == target_name:
				return node as Node2D
	return null

func _exec_move(command: Dictionary) -> void:
	var actors: Array[UnitBase] = _resolve_actors(command)
	if actors.is_empty():
		return
	var target: Vector2 = command["target"]
	var cells: Array[Vector2i] = []
	if GameManager.pathfinder != null:
		cells = GameManager.pathfinder.formation_cells(target, actors.size())
	for i in range(actors.size()):
		var spot: Vector2 = target
		if i < cells.size():
			spot = Constants.grid_to_world(cells[i].x, cells[i].y)
		actors[i].move_to(spot)

func _exec_gather(command: Dictionary) -> void:
	var movers: Array[UnitBase] = []
	for unit: UnitBase in _resolve_actors(command):
		if unit.can_gather:
			unit.command_gather(command["cell"])
		else:
			movers.append(unit)
	if not movers.is_empty():
		var cell: Vector2i = command["cell"]
		_exec_move({
			"type": "move", "player_id": command["player_id"],
			"actor_names": movers.map(func(u: UnitBase) -> String: return String(u.name)),
			"target": Constants.grid_to_world(cell.x, cell.y),
		})

func _exec_attack(command: Dictionary) -> void:
	var target: Node2D = _resolve_target(command["target_name"])
	if target == null:
		return
	# You cannot attack your own things (animals carry no player_id).
	if target.get("player_id") != null and int(str(target.get("player_id"))) == int(command["player_id"]):
		return
	for unit: UnitBase in _resolve_actors(command):
		unit.command_attack(target)

func _exec_train(command: Dictionary) -> void:
	var building: Node2D = _resolve_target(command["building_name"])
	var b: Building = building as Building
	if b == null or b.player_id != int(command["player_id"]):
		return
	b.queue_train(command["unit_type"])
```

**Step 3: Register the autoload, refresh the class cache, run**

Run: `$GODOT --headless --path . --import`
Run: `$GODOT --headless --path . ++ --test-commands`
Expected: `[test-commands] move OK`, `[test-commands] ownership OK`.

**Step 4: Regression** — `--test-move`, `--test-systems` still OK.

**Step 5: Commit** — `feat(mp): CommandRouter autoload — validated command seam`

*Note on `_exec_attack`'s player_id check: `target.get("player_id")` returns `null` for nodes without the property (animals) — the `!= null` guard plus int comparison keeps neutral targets attackable. If this reads fragile during execution, prefer `if target is UnitBase or target is Building:` then compare `target.player_id` directly.*

### Task 1.3: Route SelectionManager through the router

**Files:**
- Modify: `scripts/ui/SelectionManager.gd` (`_command_at`, delete `_move_in_formation`)

**Step 1:** Rewrite `_command_at` to build commands (selection stays local — only *orders* go through the router):

```gdscript
func _command_at(screen_pos: Vector2) -> void:
	selected_units.assign(selected_units.filter(is_instance_valid))
	if selected_units.is_empty():
		return
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var names: Array = selected_units.map(func(u: Node2D) -> String: return String(u.name))

	var enemy: Node2D = _pick_enemy(screen_pos)
	if enemy != null:
		CommandRouter.submit({"type": "attack", "player_id": GameManager.LOCAL_PLAYER_ID,
			"actor_names": names, "target_name": String(enemy.name)})
		return

	var cell: Vector2i = Constants.world_to_grid(world_pos)
	if not GameManager.world.get_resource_at(cell).is_empty():
		CommandRouter.submit({"type": "gather", "player_id": GameManager.LOCAL_PLAYER_ID,
			"actor_names": names, "cell": cell})
		return

	CommandRouter.submit({"type": "move", "player_id": GameManager.LOCAL_PLAYER_ID,
		"actor_names": names, "target": world_pos})
	EventBus.units_commanded_move.emit(selected_units, world_pos)
```

Delete `_move_in_formation` (now lives in the router). Check `Main._run_move_test` still works — it calls `SelectionManager._command_at`, which now routes properly. Also grep for other `_move_in_formation` callers: `grep -rn "_move_in_formation" scripts/`.

**Step 2:** Run `--test-move`, `--test-commands`, `--test-systems` → all OK.
**Step 3: Commit** — `refactor(mp): SelectionManager issues commands via CommandRouter`

### Task 1.4: Route EnemyAI and the HUD's train button through the router

**Files:**
- Modify: `scripts/ai/EnemyAI.gd` — every `warrior.command_attack(...)`, `idle[0].move_to(...)`, `tc.queue_train(...)` becomes a `CommandRouter.submit` with `"player_id": ENEMY_ID`. Batch wave attacks into ONE attack command with all idle warrior names.
- Modify: `scripts/ui/HUD.gd` — find the train-villager button handler (`grep -n "queue_train" scripts/ui/HUD.gd`) and replace the direct call with a `"train"` command using the selected building's name and `GameManager.LOCAL_PLAYER_ID`.

**Verify:** `--test-scout` prints `discovery OK` and the attack line; clicking train in a `--write-movie` run still works (or add a train assertion to `--test-commands` using the player TC's name).
**Commit** — `refactor(mp): EnemyAI and HUD orders flow through CommandRouter`

---

# Phase 2 — N-player generalization (offline)

### Task 2.1: Victory = last town center standing

**Files:**
- Modify: `scripts/buildings/Building.gd` (`_die`)
- Modify: `scripts/main/Main.gd` (harness)

**Step 1 (failing test):** extend `--test-commands` (or a new `--test-victory`): spawn a third player's TC via `_place_building("town_center", 2, ...)` after raising player count (Task 2.2 provides the API — do 2.2 first if you prefer; the pair 2.1+2.2 commits together). Destroy player 1's TC with `take_damage(999999)`; assert `GameManager.state != GAME_OVER`. Destroy player 2's TC; assert game over with winner 0.

**Step 2:** Replace the hardcoded `var winner: int = 1 - player_id` in `_die` with:

```gdscript
if building_type == "town_center":
	var alive: Array[int] = []
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var b: Building = node as Building
		if b != null and b != self and b.building_type == "town_center" \
				and not alive.has(b.player_id):
			alive.append(b.player_id)
	if alive.size() == 1:
		GameManager.end_game(alive[0])
```

(An eliminated player's remaining units stay alive — accepted v1 simplification, matches the design doc.)

### Task 2.2: Player count as match data

**Files:**
- Modify: `scripts/autoloads/GameManager.gd` — `const PLAYER_COUNT: int = 2` → `var player_count: int = 2`; `reset_players()` takes `func reset_players(count: int = 2)` setting `player_count = count` and sizing `stockpiles`. `LOCAL_PLAYER_ID` stays a const **for now** (becomes a var in Phase 4).
- Modify: `scripts/world/WorldGen.gd` — `PLAYER_ORIGINS` gains slots 3/4: `[Vector2i(0, 0), Vector2i(44, 44), Vector2i(44, 0), Vector2i(0, 44)]` (verify 44,0 / 0,44 land on generatable ground the same way 44,44 does — the origin loop at `WorldGen.gd:123` carves clearings, so any origin works).
- Modify: `scripts/autoloads/Constants.gd:117` — `PLAYER_COLORS` must have 4 entries (check; add two distinct colors if only 2).
- Grep: `grep -rn "PLAYER_COUNT" scripts/` and fix all references.

**Verify:** victory harness from 2.1 passes; `--test-systems` unchanged; a quick `--write-movie` run shows 4-color units if you spawn them.
**Commit** — `feat(mp): N-player match state, last-TC-standing victory`

---

# Phase 3 — Sim/view split (offline, prepares client mode)

Clients must not simulate; the server must not render. Restructure `Unit.gd` so simulation runs only on the authority while animation derives from replicated state.

### Task 3.1: Introduce `Net` autoload (modes only, no sockets yet)

**Files:**
- Create: `scripts/autoloads/Net.gd`
- Modify: `project.godot` autoloads (add `Net` before CommandRouter)

```gdscript
# scripts/autoloads/Net.gd
extends Node

# Which role this process plays. OFFLINE = single-player (local authority).
enum Mode { OFFLINE, SERVER, CLIENT }

var mode: Mode = Mode.OFFLINE

func is_authority() -> bool:
	return mode != Mode.CLIENT

func is_headless_server() -> bool:
	return mode == Mode.SERVER
```

Run `--import`, then regression harnesses. **Commit** — `feat(mp): Net autoload (run-mode flags)`

### Task 3.2: Gate unit simulation on authority; derive animation from state

**Files:**
- Modify: `scripts/units/Unit.gd`

**Steps:**
1. Split `_physics_process` into `_sim_step(delta)` (the entire current `match current_state` block plus cooldowns) and `_view_step(delta)` (sprite frame selection + `flip_h`). `_physics_process` becomes:

```gdscript
func _physics_process(delta: float) -> void:
	if Net.is_authority():
		_sim_step(delta)
	if not Net.is_headless_server():
		_view_step(delta)
```

2. `_view_step` must derive frames from replicable state, not sim-local vars: walking animation from `velocity.length() > 1.0` (velocity of a CharacterBody2D is a plain property — replicated in Phase 4), idle frame otherwise; `flip_h` from `velocity.x` sign when moving. Move the `_anim_time` bookkeeping here. Remove frame-setting from `_follow_path`/`_set_idle_frame` call sites inside sim code (keep `_set_idle_frame` as a view helper).
3. Visual-only effects (`_flash_hit`, the `_strike` lunge tween, health bar updates) get an early-return when `Net.is_headless_server()`.
4. Same treatment for `scripts/buildings/Building.gd`: `_ready` visual creation (`_sprite`, `_health_bar`, AssetLibrary calls) skipped on headless server (guard with `if Net.is_headless_server(): return` after the non-visual setup); `take_damage` flash guarded; `_process` training loop gated on `Net.is_authority()`.

**Verify:** all harnesses OK (offline mode is authority + view, so behavior is identical). Visual smoke: `$GODOT --path . --write-movie /tmp/mp_check/f.png --fixed-fps 10 --quit-after 40` then view a frame — units animate.
**Commit** — `refactor(mp): authority-gated simulation, state-derived unit animation`

---

# Phase 4 — Networking core (server + client over WebSockets)

RPC contract (all on existing autoloads — autoload node paths match on every peer automatically):

| RPC | Direction | Config | Purpose |
|---|---|---|---|
| `CommandRouter._submit_to_server(cmd)` | client→server | `any_peer, reliable` | forward a command; server **overwrites** `cmd.player_id` from its peer→player map |
| `Net._client_hello(proto_version, slot_token)` | client→server | `any_peer, reliable` | version check + slot claim |
| `Net._match_config(seed, player_count, your_player_id)` | server→client | `authority, reliable` | client generates the map from seed, sets `GameManager.map_seed`, `LOCAL_PLAYER_ID` |
| `GameManager._replicate_stockpile(player_id, stockpile)` | server→owner client | `authority, reliable` | after every `add_resource`/`spend` |
| `GameManager._replicate_game_over(winner)` | server→all | `authority, reliable` | |

### Task 4.1: Boot modes and socket setup

**Files:**
- Modify: `scripts/autoloads/Net.gd` — add:

```gdscript
const PROTOCOL_VERSION: int = 1

# peer_id -> player_id (server only)
var peer_players: Dictionary = {}
var expected_players: int = 2

func host(port: int, players: int) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err: Error = peer.create_server(port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.SERVER
	expected_players = players
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK

func join(url: String) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err: Error = peer.create_client(url)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	return err
```

- Modify: `scripts/main/Main.gd` — parse user args in `_ready` **before** any spawning: `--server` + `--port=` + `--players=` + `--seed=` → `Net.host(...)`, seed `GameManager.map_seed`, spawn one TC + starting units per player at `WorldGen.PLAYER_ORIGINS[i]`, and **do not** run `EnemyAI` or ambient animals in server mode (v1: pure PvP; delete/skip the `$EnemyAI` node when `--server`). `--join=ws://...` → `Net.join(...)` and defer world build until `_match_config` arrives (restructure `_ready` into `_build_world()` called either immediately (offline/server) or from the config RPC (client)).

**Failing test first:** add `--test-net-handshake` harness pair — see Task 4.4's script for the pattern; at this task's stage just assert: server starts, client connects, client receives `_match_config` and prints `[test-net] config OK seed=<seed> me=<player_id>`.

**Commit** — `feat(mp): WebSocket host/join, match-config handshake`

### Task 4.2: Command forwarding with server-side identity

**Files:** `scripts/autoloads/CommandRouter.gd`

```gdscript
func submit(command: Dictionary) -> void:
	if Net.mode == Net.Mode.CLIENT:
		_submit_to_server.rpc_id(1, command)
	else:
		_validate_and_execute(command)

@rpc("any_peer", "call_remote", "reliable")
func _submit_to_server(command: Dictionary) -> void:
	if Net.mode != Net.Mode.SERVER:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not Net.peer_players.has(sender):
		return
	# Identity comes from the connection, never from the payload.
	command["player_id"] = Net.peer_players[sender]
	_validate_and_execute(command)
```

`--test-commands` still passes offline (submit falls through to local execution).
**Commit** — `feat(mp): commands forward to server, identity from connection`

### Task 4.3: Entity replication

**Files:**
- Modify: `scenes/units/Unit.tscn` — add a `MultiplayerSynchronizer` child; replication config: `position` (sync, ~10 Hz via `replication_interval = 0.1`), `velocity` (sync), `current_hp` (on change), `current_state` (on change), `unit_type` + `player_id` (spawn only).
- Modify: `scenes/main/Main.tscn` — add two `MultiplayerSpawner` nodes with `spawn_path` pointing at `World/Units` and `World/Buildings`; set a `spawn_function` in `Main.gd` that instantiates from a dictionary `{scene:"unit", unit_type, player_id, name, position}` (units) / `{type, player_id, base_cell, name}` (buildings). Server calls `spawner.spawn(data)` instead of bare `add_child` — refactor `Main._spawn_unit`, `Main._place_building`, `Building._spawn_unit` to go through two small helpers on `Main` (or a new `scripts/main/EntityFactory.gd` node in the `unit_container` group pattern already used by `Building._spawn_unit`).
- Client-side interpolation: in `Unit._view_step`, when `Net.mode == CLIENT`, lerp rendered position toward the synced one (simplest v1: `sprite` stays at node position — synchronizer already smooths at 10 Hz with `delta_interpolation`; only add manual lerp if movement visibly stutters in the movie-writer check).
- `GameManager.LOCAL_PLAYER_ID` const → `var local_player_id` set by `_match_config` (offline default 0). Grep and update ALL users: `SelectionManager`, `HUD`, `FogOfWar`/`PlayerVision`, `EnemyAI._known_player_target`. Keep the name via a property if the diff gets huge — but prefer the rename; it's mechanical.

**Verify:** handshake harness now also asserts the client sees N spawned units (`get_tree().get_nodes_in_group("units").size()`), and after the client submits a move command, the unit's position changes **on the client** within 3 s.
**Commit** — `feat(mp): server-driven entity spawn + state replication`

### Task 4.4: Stockpile/game-over replication + the convergence harness

**Files:**
- Modify: `scripts/autoloads/GameManager.gd` — after mutation in `add_resource`/`spend`, when `Net.mode == SERVER`, `rpc_id` the owning player's peer with `_replicate_stockpile`; `end_game` broadcasts `_replicate_game_over`. Client-side these RPCs write state and emit the existing EventBus signals (HUD updates for free).
- Create: `tools/test_mp.sh`:

```bash
#!/usr/bin/env bash
# Launches 1 headless match server + 2 headless scripted clients and greps
# their output for the harness verdict lines.
set -euo pipefail
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
DIR="$(mktemp -d)"
PORT=9101
"$GODOT" --headless --path . ++ --server --port=$PORT --players=2 --seed=42 \
  > "$DIR/server.log" 2>&1 &
SERVER_PID=$!
sleep 3
"$GODOT" --headless --path . ++ --test-mp-client --join=ws://127.0.0.1:$PORT \
  > "$DIR/client0.log" 2>&1 &
"$GODOT" --headless --path . ++ --test-mp-client --join=ws://127.0.0.1:$PORT \
  > "$DIR/client1.log" 2>&1 &
wait %2 %3 || true
kill $SERVER_PID || true
echo "--- verdicts ---"
grep -h "\[test-mp\]" "$DIR"/client*.log
if grep -h "\[test-mp\]" "$DIR"/client*.log | grep -q FAILED; then exit 1; fi
```

- Modify: `scripts/main/Main.gd` — `--test-mp-client` harness: connect, await config, submit a move command for one of *my* units, await 5 s, print `[test-mp] move-sync OK/FAILED` (position changed), `[test-mp] foreign-command OK/FAILED` (a command spoofing the *other* player's id did nothing — server overwrote identity so it moved MY units or was dropped; assert the other player's units did not move).

**Verify:** `bash tools/test_mp.sh` → all `[test-mp] ... OK`. Also `--test-move`/`--test-systems`/`--test-commands` offline regression.
**Commit** — `feat(mp): stockpile/game-over replication + 2-client convergence harness`

**⚠️ CHECKPOINT — end of Phase 4.** Two headless clients can play a full match against each other through the server. STOP and write the Phase 5/6 sub-plan (superpowers:writing-plans) against the current code before continuing.

---

# Phase 5 — Lobby, gateway, and client UI (sub-plan required)

Scope for the sub-plan (from the design doc):

- **Task group A — Gateway mode:** `--gateway --port=9000 --match-port-base=9100`. Rooms with 4-letter codes, slot claims, host-starts → `OS.create_process` a `--server` match on the next free port → send everyone `{match_port, map_seed, player_slots, session_token}`. Same `Net` autoload, `Mode.GATEWAY` added. Session tokens enable rejoin (design doc §lifecycle).
- **Task group B — Main menu scene:** new `scenes/ui/MainMenu.tscn` becomes `run/main_scene`; "Single Player" → load `Main.tscn` (offline, EnemyAI as today); "Multiplayer" → create/join room UI → connect to gateway → on match-start, load `Main.tscn` with `--join` semantics passed via `Net` state instead of CLI args. Server URL read from `user://` override or a `server_config.json` fetched next to the exported site.
- **Task group C — Disconnect/rejoin:** grace behavior per design doc; gateway tears down empty matches.
- **Harnesses:** `--test-gateway` (create room, join by code, start, both clients get identical seed), extend `tools/test_mp.sh` to go through the gateway.

# Phase 6 — Deployment (sub-plan required)

- `Linux Server` (dedicated_server feature) export preset in `export_presets.cfg`; build via `--headless --export-release`.
- VPS: systemd unit for the gateway; Caddyfile `wss://game.<domain>/ws → localhost:9000` plus a port range or path-routing for match processes (decide in sub-plan — path routing keeps the firewall closed tighter).
- Web client deploy keeps the existing gh-pages flow (memory: `build/web` → force-push `gh-pages`); add `server_config.json` with the WSS URL.
- Docs: `docs/deploy-multiplayer.md` runbook; new ADR entry in `docs/architecture.md` (authoritative server, process-per-match, accepted maphack risk — copy the reasoning from the design doc).

---

## Task tracking

Execute in order; each task's regression gate is non-negotiable. Suggested worktree: `git worktree add ../age-of-amazon-mp -b feature/multiplayer`.
