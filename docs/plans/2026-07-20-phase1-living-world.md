# Phase 1 — The Living World Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add the **várzea** (flooded-forest) wetland biome and a deterministic
**Points-of-Interest** framework — shipping **Ancient Ruins** as the first POI —
so every existing mode (skirmish, daily, multiplayer) gets a richer, more
worth-exploring world with zero changes to those modes.

**Architecture:** Both features extend the existing pure-function world model
(ADR 5): terrain and POIs are deterministic functions of `(x, y, seed)`, stored
lazily in `ChunkData`, queried through `WorldData`, and never cross the network.
Várzea is a new `Biome` enum value plumbed through the four biome tables in
`Constants`. POIs are a new per-tile function `WorldGen.poi_at`, a `pois` store
on `ChunkData`, a claim/discovery state map on `WorldData` (mirroring the
`resource_deltas` save-compat pattern), and fog-gated discovery reusing the
building-discovery path (ADR 9). No new engine systems.

**Tech Stack:** Godot 4.5, GDScript, GL Compatibility renderer. Verification via
headless `--test-*` harnesses (ADR 12) that assert **pure data** (never
rendering, which is null under `--headless`).

---

## Before you start (worktree setup)

This worktree was created fresh. Godot's global-class cache (`.godot/`) and
import artifacts are **gitignored and absent** until the project is imported
once. Without them, every `class_name` type fails to resolve and harnesses spam
`Could not find type "WorldData"`.

**Run once, before any test:**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --import .
```

Confirm `.godot/global_script_class_cache.cfg` exists afterward. Re-run only if
you add a new `class_name`.

**Note on headless errors:** `SCRIPT ERROR: Cannot call method 'get_image' on a
null value` is expected under `--headless` (no render viewport for the fog
texture). It does **not** mean a harness failed — judge harnesses by their
printed `[test-*] ... OK/FAILED` assertions, not by these lines.

**Harness run pattern** (harnesses self-`quit()`, but boot is slow headless, so
guard with a poll-kill; macOS has no `timeout`):

```bash
run_harness() { # $1 = flag
  local log; log="$(mktemp)"
  stdbuf -oL /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- "$1" > "$log" 2>&1 &
  local pid=$!
  for i in $(seq 1 40); do kill -0 $pid 2>/dev/null || break; perl -e 'select(undef,undef,undef,2)'; done
  kill $pid 2>/dev/null
  grep -aE '\[test' "$log"
}
```

---

## Part A — Várzea biome

### Task A1: Add the `VARZEA` biome to the four Constants tables

**Files:**
- Modify: `scripts/autoloads/Constants.gd` (enum `Biome` ~line 11; `_ready` tables ~line 219)

**Step 1: Write the failing test harness**

Add a new harness. In `scripts/main/Main.gd`, register the flag near the other
`--test-*` checks in `_ready` (~line 69):

```gdscript
	if "--test-world" in args:
		_run_world_test()
		return
```

Then add the function (place it beside the other `_run_*_test` funcs):

```gdscript
func _run_world_test() -> void:
	var b: int = Constants.Biome.VARZEA
	var tables := {
		"MOVEMENT_COST": Constants.MOVEMENT_COST,
		"WALKABLE": Constants.WALKABLE,
		"BUILDABLE": Constants.BUILDABLE,
		"BIOME_RAMPS": Constants.BIOME_RAMPS,
		"BIOME_COLORS": Constants.BIOME_COLORS,
	}
	for name: String in tables:
		var present: bool = tables[name].has(b)
		print("[test-world] %s has VARZEA: %s" % [name, "OK" if present else "FAILED"])
	print("[test-world] varzea walkable=%s buildable=%s" % [
		Constants.WALKABLE.get(b, false), Constants.BUILDABLE.get(b, true)])
	get_tree().quit()
```

**Step 2: Run to verify it fails**

Run: `run_harness --test-world`
Expected: FAILED lines (enum value `VARZEA` does not exist yet → parse error, or
missing-key FAILEDs once the enum exists). This drives Steps 3–4.

**Step 3: Add the enum value and table entries**

In the `Biome` enum, append (append only — never reorder; ordinals are baked
into saved games and the network protocol):

```gdscript
enum Biome {
	GRASS,
	FOREST_DENSE,
	FOREST_LIGHT,
	WATER_DEEP,
	WATER_SHALLOW,
	SWAMP,
	CLIFF,
	HIGH_GROUND,
	VARZEA,
}
```

In `_ready`, add várzea to each table. Slow, boggy, walkable, **not**
buildable; a murky green-brown ramp:

```gdscript
	# MOVEMENT_COST: slower than swamp's cousin — waterlogged forest floor.
	Biome.VARZEA: 2.2,
```
```gdscript
	# WALKABLE:
	Biome.VARZEA: true,
```
```gdscript
	# BIOME_RAMPS: tannin-stained water under flooded canopy.
	Biome.VARZEA: [
		Color8(40, 70, 58), Color8(52, 88, 70),
		Color8(64, 104, 82), Color8(80, 120, 96), Color8(98, 138, 112),
	],
```

**Step 4: Run to verify it passes**

Run: `run_harness --test-world`
Expected: every table prints `OK`; `walkable=true buildable=false` (BUILDABLE is
added in Task A2 — until then it prints `buildable=true` from the `.get`
default; that line flips in A2).

**Step 5: Commit**

```bash
git add scripts/autoloads/Constants.gd scripts/main/Main.gd
git commit -m "feat(world): add varzea biome enum + biome tables"
```

---

### Task A2: Buildability table + `WorldData.is_buildable`, enforced everywhere

Várzea is walkable but you cannot build on it. Buildability is currently
implied by `is_walkable`; split it into its own table so wetland (and water)
reject construction while still allowing movement.

**Files:**
- Modify: `scripts/autoloads/Constants.gd` (`_ready`)
- Modify: `scripts/world/WorldData.gd`
- Modify: `scripts/autoloads/GameManager.gd:153` (`find_buildable_cell`)
- Modify: `scripts/autoloads/CommandRouter.gd` (the `place` validation — see Step 3)

**Step 1: Write the failing test**

Extend `_run_world_test` (before `get_tree().quit()`):

```gdscript
	# A cell known to be varzea is walkable-for-move but not buildable.
	var w: WorldData = GameManager.world
	var found := false
	for r in range(4, 60):
		for c: Vector2i in [Vector2i(r, 0), Vector2i(0, r), Vector2i(-r, 0), Vector2i(0, -r)]:
			if w.get_biome(c) == Constants.Biome.VARZEA:
				print("[test-world] varzea cell %s walkable=%s buildable=%s" % [
					c, w.is_walkable(c), w.is_buildable(c)])
				found = true
				break
		if found: break
	print("[test-world] found-varzea: %s" % ("OK" if found else "FAILED (bump seed/range)"))
```

**Step 2: Run to verify it fails**

Run: `run_harness --test-world`
Expected: FAIL — `is_buildable` is not defined (parse error). Fails correctly.

**Step 3: Implement**

`Constants.gd` `_ready`, after the `WALKABLE` block:

```gdscript
	# Can a building's footprint occupy this biome? Defaults to WALKABLE, but
	# wetland and water reject construction while still allowing movement.
	BUILDABLE = WALKABLE.duplicate()
	BUILDABLE[Biome.VARZEA] = false
	BUILDABLE[Biome.WATER_SHALLOW] = false
```

Declare the field near the other table vars (`var WALKABLE ...`):

```gdscript
var BUILDABLE: Dictionary = {}
```

`WorldData.gd`, next to `is_walkable`:

```gdscript
func is_buildable(cell: Vector2i) -> bool:
	if occupied.has(cell):
		return false
	return Constants.BUILDABLE.get(get_biome(cell), false)
```

`GameManager.gd:153` — swap the walkability check in `find_buildable_cell` for
buildability:

```gdscript
						if not world.is_buildable(cell) \
```

`CommandRouter.gd` — the authoritative `place` handler (find it near line 142,
`Constants.BUILDING_DEFS.get(building_type, ...)`) validates each footprint cell
before deducting cost. Ensure it rejects when any cell is not buildable, using
the **same** `world.is_buildable(cell)` predicate. (Read the surrounding
validation loop and replace its `is_walkable`/walkable check with
`is_buildable`; if it already delegates to `find_buildable_cell`, no change is
needed here — verify which.)

**Step 4: Run to verify it passes**

Run: `run_harness --test-world`
Expected: `found-varzea: OK`, and the printed cell shows `walkable=true
buildable=false`. Also run `run_harness --test-build` — its existing
reject/accept assertions must still print `OK` (no regression on grass).

**Step 5: Commit**

```bash
git add scripts/autoloads/Constants.gd scripts/world/WorldData.gd scripts/autoloads/GameManager.gd scripts/autoloads/CommandRouter.gd scripts/main/Main.gd
git commit -m "feat(world): buildable-biome table; varzea/water are no-build"
```

---

### Task A3: Place várzea in the world + wetland food resource

Várzea is wet lowland flanking rivers: moist, low-mid elevation, adjacent to the
river band. Placement stays a pure function of `(x, y)`.

**Files:**
- Modify: `scripts/world/WorldGen.gd` (`biome_at` ~line 71; `resource_at` ~line 136)

**Step 1: Write the failing test**

Extend `_run_world_test`: assert várzea exists near water for the harness seed,
and that at least one várzea cell carries a FOOD resource. Reuse the
`found`-scan above; add after it:

```gdscript
	var food_on_varzea := false
	for r in range(4, 80):
		for c: Vector2i in [Vector2i(r, r), Vector2i(-r, r), Vector2i(r, -r), Vector2i(-r, -r)]:
			if w.get_biome(c) == Constants.Biome.VARZEA:
				var res: Dictionary = w.gen.resource_at(c.x, c.y, Constants.Biome.VARZEA)
				if res.get("type") == Constants.ResourceType.FOOD:
					food_on_varzea = true
	print("[test-world] varzea-food: %s" % ("OK" if food_on_varzea else "FAILED"))
```

**Step 2: Run to verify it fails**

Run: `run_harness --test-world`
Expected: `varzea-food: FAILED` (no várzea placed yet, or no food rule).

**Step 3: Implement placement + resource**

In `biome_at`, insert a várzea test **after** the `_water_at` block returns -1
(i.e. this tile is land) and **before** the elevation/forest classification
(~line 88, before `if e > 0.86`). Várzea hugs rivers: near the river-noise
channel but not in it, on moist low-mid ground, never inside a spawn clearing:

```gdscript
	# Várzea: flooded forest flanking rivers. Moist low-mid land whose river
	# noise sits just outside the water channel (a wet margin, not the river).
	if clearing <= 0.0 and e < 0.5 and m > 0.55:
		var rv: float = absf(_river.get_noise_2d(float(x), float(y)))
		if rv >= 0.042 and rv < 0.075:
			return Constants.Biome.VARZEA
```

(The `0.042` lower bound is the same threshold `_water_at` uses for the river
itself, so várzea forms the band immediately outside the water — no gaps, no
overlap.)

In `resource_at`, add a case in the `match biome` block. Wild rice / floodplain
fruit — a food node richer than a berry bush, the reward for braving the bog:

```gdscript
		Constants.Biome.VARZEA:
			if h < 0.14:
				return { "type": Constants.ResourceType.FOOD, "amount": 140 }
```

**Step 4: Run to verify it passes**

Run: `run_harness --test-world`
Expected: `found-varzea: OK` and `varzea-food: OK`.
Also `run_harness --test-systems` and `--test-move` — must still pass (várzea is
walkable, so pathing/gathering are unaffected).

**Step 5: Commit**

```bash
git add scripts/world/WorldGen.gd scripts/main/Main.gd
git commit -m "feat(world): place varzea along rivers with floodplain food"
```

---

### Task A4: Render várzea terrain

Confirm terrain rendering needs only the ramp (Task A1 added it) or a small
`TerrainArtist` branch.

**Files:**
- Inspect: `scripts/art/TerrainArtist.gd`
- Possibly modify: `scripts/art/TerrainArtist.gd`, `scripts/world/ChunkManager.gd`

**Step 1: Inspect.** Read `TerrainArtist.gd`. If it draws every biome by looking
up `BIOME_RAMPS[biome]` generically, várzea already renders (dithered water-forest
tint) and this task is **inspection + a capture only** — skip to Step 3. If it
`match`es specific biomes (e.g. animated water for `WATER_*`), add a `VARZEA`
branch styled like a darker, static shallow-water-under-canopy tile.

**Step 2 (only if a branch was added): re-import if needed, then build.**

**Step 3: Visual check via movie-writer capture.** There is a `--capture-*`
pattern (see `_run_capture_help`). Add a `--capture-world` that positions the
camera over a known várzea cluster and saves a screenshot (copy the structure of
the existing capture harness). Inspect the PNG: wetland reads as distinct from
grass, swamp, and open water.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat(world): render varzea terrain + capture harness"
```

---

## Part B — Points-of-Interest framework + Ancient Ruins

### Task B1: Deterministic `poi_at` + `ChunkData` storage

**Files:**
- Modify: `scripts/world/WorldGen.gd`
- Modify: `scripts/world/ChunkData.gd`
- Modify: `scripts/world/WorldData.gd`

**Step 1: Write the failing test**

New harness `--test-poi`. Register it in `Main.gd` like the others and add:

```gdscript
func _run_poi_test() -> void:
	var w: WorldData = GameManager.world
	# Determinism: same coords -> same POI, twice.
	var a: Dictionary = w.gen.poi_at(1234, -567)
	var b: Dictionary = w.gen.poi_at(1234, -567)
	print("[test-poi] deterministic: %s" % ("OK" if a == b else "FAILED"))
	# Rarity + storage: scan a wide area, expect a handful, all on buildable land.
	var count := 0
	var on_bad := 0
	for y in range(-120, 120):
		for x in range(-120, 120):
			var p: Dictionary = w.gen.poi_at(x, y)
			if p.is_empty():
				continue
			count += 1
			if not Constants.BUILDABLE.get(w.gen.biome_at(x, y), false):
				on_bad += 1
	print("[test-poi] found %d POIs in 240x240; on-unbuildable=%d" % [count, on_bad])
	print("[test-poi] rarity: %s" % ("OK" if count >= 1 and count <= 40 else "FAILED"))
	print("[test-poi] placement: %s" % ("OK" if on_bad == 0 else "FAILED"))
	# Stored on the chunk that owns the tile.
	if count > 0:
		var cc: Vector2i = Constants.tile_to_chunk(Vector2i(0, 0))
		var chunk: ChunkData = w.get_chunk(cc)
		print("[test-poi] chunk store type=%s" % typeof(chunk.pois))
	get_tree().quit()
```

**Step 2: Run to verify it fails**

Run: `run_harness --test-poi`
Expected: FAIL — `poi_at` and `chunk.pois` do not exist.

**Step 3: Implement**

`WorldGen.gd` — a new rare per-tile function. POIs are much rarer than
resources, only on buildable land, never in spawn clearings, and keyed off an
independent hash so they don't correlate with resource scatter:

```gdscript
# A point of interest on this tile, or empty. Pure and deterministic, like
# resource_at. Very rare. Only on buildable land outside spawn clearings.
func poi_at(x: int, y: int) -> Dictionary:
	if _clearing_factor(x, y) > 0.0:
		return {}
	var biome: int = biome_at(x, y)
	if not Constants.BUILDABLE.get(biome, false):
		return {}
	var h: float = PixelArt.hash2(x, y, seed_val + 9001)
	if h < 0.00035:
		return { "type": "ancient_ruins",
			"loot": { Constants.ResourceType.JADE: 40, Constants.ResourceType.WOOD: 60 } }
	return {}
```

`ChunkData.gd` — declare the store and populate it in `_init`. Add beside
`decor`:

```gdscript
var pois: Dictionary = {}  # Vector2i cell -> {type, ...} (see WorldGen.poi_at)
```

In `_init`, inside the per-tile loop, after the resource/decor block:

```gdscript
				var poi: Dictionary = gen.poi_at(x, y)
				if not poi.is_empty():
					pois[Vector2i(x, y)] = poi
```

`WorldData.gd` — a query, mirroring `get_resource_at`:

```gdscript
func get_poi_at(cell: Vector2i) -> Dictionary:
	var chunk: ChunkData = get_chunk(Constants.tile_to_chunk(cell))
	return chunk.pois.get(cell, {})
```

**Step 4: Run to verify it passes**

Run: `run_harness --test-poi`
Expected: `deterministic: OK`, `rarity: OK`, `placement: OK`, a `chunk store
type=27` (Dictionary) line. If `found 0`, widen the scan or raise the `0.00035`
gate slightly and re-run — tune so a 240×240 area yields a small handful.

**Step 5: Commit**

```bash
git add scripts/world/WorldGen.gd scripts/world/ChunkData.gd scripts/world/WorldData.gd scripts/main/Main.gd
git commit -m "feat(world): deterministic POI framework (poi_at + chunk store)"
```

---

### Task B2: POI claim state on `WorldData` (fog-remembered, save-safe)

Discovery is remembered permanently (like buildings, ADR 9); claiming is
one-time and must survive save/load via a delta map (like `resource_deltas`).

**Files:**
- Modify: `scripts/world/WorldData.gd`
- Modify: `scripts/autoloads/EventBus.gd` (new signal)

**Step 1: Write the failing test**

Extend `_run_poi_test` before `quit()`: find the nearest generated ruin, assert
it starts unclaimed, claim it, assert claimed and idempotent:

```gdscript
	var ruin := Vector2i(9999, 9999)
	for y in range(-40, 40):
		for x in range(-40, 40):
			if w.get_poi_at(Vector2i(x, y)).get("type") == "ancient_ruins":
				ruin = Vector2i(x, y); break
		if ruin.x != 9999: break
	if ruin.x != 9999:
		print("[test-poi] pre-claim: %s" % ("OK" if not w.is_poi_claimed(ruin) else "FAILED"))
		var first: bool = w.claim_poi(ruin)
		var second: bool = w.claim_poi(ruin)
		print("[test-poi] claim-once: %s" % ("OK" if first and not second else "FAILED"))
		print("[test-poi] now-claimed: %s" % ("OK" if w.is_poi_claimed(ruin) else "FAILED"))
```

**Step 2: Run to verify it fails**

Run: `run_harness --test-poi`
Expected: FAIL — `is_poi_claimed`/`claim_poi` undefined.

**Step 3: Implement**

`WorldData.gd`:

```gdscript
# Claimed POIs (one-time rewards already taken). Serialized for save/restore,
# same pattern as resource_deltas.
var claimed_pois: Dictionary = {}  # Vector2i cell -> true

func is_poi_claimed(cell: Vector2i) -> bool:
	return claimed_pois.has(cell)

# Marks a POI claimed. Returns true only on the first claim (idempotent).
func claim_poi(cell: Vector2i) -> bool:
	if claimed_pois.has(cell):
		return false
	if get_poi_at(cell).is_empty():
		return false
	claimed_pois[cell] = true
	return true
```

`EventBus.gd` — add to the signal catalogue:

```gdscript
signal poi_claimed(cell: Vector2i, poi_type: String, player_id: int)
```

**Step 4: Run to verify it passes**

Run: `run_harness --test-poi`
Expected: `pre-claim: OK`, `claim-once: OK`, `now-claimed: OK`.

**Step 5: Commit**

```bash
git add scripts/world/WorldData.gd scripts/autoloads/EventBus.gd scripts/main/Main.gd
git commit -m "feat(world): POI claim state (idempotent, save-safe) + signal"
```

---

### Task B3: Ancient Ruins — proximity claim grants loot to the claimer

When any unit comes within claim range of an undiscovered/unclaimed ruin, the
ruin is looted: resources go to that unit's player, once, and `poi_claimed`
fires. This is symmetric — the AI's units trigger it identically (P2).

**Files:**
- Create: `scripts/world/PoiManager.gd`
- Modify: `scenes/main/Main.tscn` (add a `PoiManager` node) **or** instantiate it
  in `Main.gd._boot_offline`/`_boot_server` — match how `AnimalManager` is wired
  (read that first and mirror it exactly).
- Modify: `scripts/autoloads/GameManager.gd` (credit resources — reuse the
  existing `add_resource`/stockpile API; find the method wildlife bounty uses on
  kill and reuse it)

**Step 1: Write the failing test**

New harness `--test-poi-claim`: place/relocate a player-0 unit adjacent to a
known ruin, step the manager a few frames, assert the player's resources rose by
the loot and the POI is claimed. Model it on `_run_hunt_test` (which sets up a
unit near a target and checks a bounty). Assert:

```gdscript
	print("[test-poi-claim] looted: %s" % ("OK" if jade_after == jade_before + 40 else "FAILED"))
	print("[test-poi-claim] claimed: %s" % ("OK" if w.is_poi_claimed(ruin) else "FAILED"))
	print("[test-poi-claim] no-double: %s" % ("OK" if jade_after2 == jade_after else "FAILED"))
```

**Step 2: Run to verify it fails** (manager/harness absent).

**Step 3: Implement `PoiManager`**

Mirror `AnimalManager`'s shape (a `Node2D` ticking on a timer/`_process`, scoped
to the active area around the camera and player units). Each tick, for units in
groups `player_0`/`player_1`, check nearby unclaimed POIs within a small claim
radius (e.g. 1.5 tiles). On a hit:

```gdscript
func _try_claim(cell: Vector2i, player_id: int) -> void:
	var poi: Dictionary = world.get_poi_at(cell)
	if poi.is_empty() or not world.claim_poi(cell):
		return
	for res_type: int in poi.get("loot", {}):
		GameManager.add_resource(player_id, res_type, poi["loot"][res_type])
	EventBus.poi_claimed.emit(cell, poi["type"], player_id)
```

(Use the real stockpile-credit method name from `GameManager` — verify it; the
wildlife food-on-kill path in ADR 14 already credits a player, reuse that.)

Only scan **generated** chunks near activity (never force far-off generation —
same discipline as `find_nearest_resource`).

**Step 4: Run to verify it passes**

Run: `run_harness --test-poi-claim`
Expected: `looted: OK`, `claimed: OK`, `no-double: OK`.
Regression: `run_harness --test-systems`, `--test-hunt`, `--test-build` still OK.

**Step 5: Commit**

```bash
git add scripts/world/PoiManager.gd scripts/main/Main.gd scenes/main/Main.tscn scripts/autoloads/GameManager.gd
git commit -m "feat(world): ancient ruins — proximity loot, symmetric for AI"
```

---

### Task B4: Render ruins + show discovered ruins on the minimap

**Files:**
- Modify: `scripts/art/DoodadArtist.gd` (a procedural ruins sprite — a small
  broken-stone glyph)
- Modify: `scripts/world/ChunkManager.gd` (draw a POI sprite where a chunk has an
  unclaimed POI, gated by fog like resource/doodad sprites)
- Modify the minimap (find the node that plots buildings/resources — likely under
  `scripts/ui/`) to dot **discovered, unclaimed** ruins.

**Step 1:** Read `DoodadArtist.gd` and how `ChunkManager` places doodad/resource
sprites; mirror that path for a POI sprite. Ruins appear only where
`chunk.pois[cell]` exists and `not world.is_poi_claimed(cell)`; they vanish when
claimed (subscribe to `EventBus.poi_claimed` to free the sprite).

**Step 2:** Fog: ruins follow the same discovery rule as enemy buildings —
visible once their tile is explored, remembered after. Reuse
`PlayerVision.has_discovered_building`-style logic or the existing
explored-tile check.

**Step 3:** Visual check with a `--capture-world`-style screenshot over a known
ruin; confirm the glyph reads as a landmark and disappears after a unit claims it.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat(world): render ancient ruins + minimap markers, fog-gated"
```

---

## Definition of done (Phase 1)

- `--test-world`, `--test-poi`, `--test-poi-claim` all print only `OK`.
- `--test-systems`, `--test-move`, `--test-build`, `--test-hunt`, `--test-daily`
  still pass (no regression to existing modes).
- A movie-writer capture shows várzea terrain and a claimable ruin.
- The web export still builds and boots (`tools/deploy_web.sh` dry-run or the
  export step alone) — Phase 1 must not break the browser build (P4).
- Multiplayer unaffected by construction: várzea/POIs are pure functions of the
  shared `map_seed`, so client and server generate identical worlds; POI claims
  flow through server-authoritative resource credit (verify the claim path runs
  on the SERVER authority, not the client, when `Net.mode == SERVER`).

## Deliberately deferred to later Phase-1 follow-ups (not this plan)

Framework-reusing POIs, each a small addition once B1–B4 land: **sacred groves**
(presence aura), **abandoned villages** (repair-to-claim neutral buildings),
**wildlife hotspots** (bias `AnimalManager` spawns). Additional biomes
(savanna patches) only if playtesting shows grass is too uniform — YAGNI until
then. These are separate plans; do not scope-creep this one.
