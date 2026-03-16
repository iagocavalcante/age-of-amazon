# Phase 1: Map + Units Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Get a playable isometric map with camera controls and moveable villager units in Godot 4.5.

**Architecture:** Scene-node composition with autoload singletons (GameManager, EventBus, Constants). TileMapLayer for terrain, NavigationRegion2D for pathfinding, CharacterBody2D for units. All GDScript.

**Tech Stack:** Godot 4.5, GDScript, 2D Isometric (64x32 tiles), FastNoiseLite

---

### Task 1: Project Setup — Autoloads and Folder Structure

**Files:**
- Create: `scripts/autoloads/EventBus.gd`
- Create: `scripts/autoloads/GameManager.gd`
- Create: `scripts/autoloads/Constants.gd`
- Modify: `project.godot` (register autoloads)

**Step 1: Create folder structure**

```bash
cd /Users/iagocavalcante/Workspaces/IagoCavalcante/age-of-amazon
mkdir -p scenes/{main,game,map,units,buildings,camera,ui}
mkdir -p scripts/{autoloads,map,units,camera,ui}
mkdir -p assets/{tiles,units,buildings}
mkdir -p resources/{unit_data,building_data}
```

**Step 2: Create EventBus.gd**

```gdscript
# scripts/autoloads/EventBus.gd
extends Node

# Unit signals
signal unit_selected(unit: Node2D)
signal unit_deselected(unit: Node2D)
signal units_commanded_move(units: Array[Node2D], target: Vector2)
signal selection_cleared()

# Map signals
signal map_generated(width: int, height: int)

# Game signals
signal game_state_changed(new_state: String)
```

**Step 3: Create GameManager.gd**

```gdscript
# scripts/autoloads/GameManager.gd
extends Node

enum GameState { LOADING, RUNNING, PAUSED }

var state: GameState = GameState.LOADING
var map_width: int = 128
var map_height: int = 128
var map_seed: int = 0

func _ready() -> void:
	if map_seed == 0:
		map_seed = randi()

func change_state(new_state: GameState) -> void:
	state = new_state
	EventBus.game_state_changed.emit(GameState.keys()[new_state])
```

**Step 4: Create Constants.gd**

```gdscript
# scripts/autoloads/Constants.gd
extends Node

# Tile size for isometric grid
const TILE_WIDTH: int = 64
const TILE_HEIGHT: int = 32

# Biome types matching the TS version
enum Biome {
	GRASS,
	FOREST_DENSE,
	FOREST_LIGHT,
	WATER_DEEP,
	WATER_SHALLOW,
	SWAMP,
	CLIFF,
	HIGH_GROUND
}

# Movement costs per biome
const MOVEMENT_COST: Dictionary = {
	Biome.GRASS: 1.0,
	Biome.FOREST_LIGHT: 1.2,
	Biome.FOREST_DENSE: 1.5,
	Biome.WATER_SHALLOW: 2.0,
	Biome.WATER_DEEP: INF,
	Biome.SWAMP: 2.5,
	Biome.CLIFF: INF,
	Biome.HIGH_GROUND: 1.1,
}

# Biome walkability
const WALKABLE: Dictionary = {
	Biome.GRASS: true,
	Biome.FOREST_LIGHT: true,
	Biome.FOREST_DENSE: true,
	Biome.WATER_SHALLOW: true,
	Biome.WATER_DEEP: false,
	Biome.SWAMP: true,
	Biome.CLIFF: false,
	Biome.HIGH_GROUND: true,
}

# Biome colors (placeholder until PixelLab tiles)
const BIOME_COLORS: Dictionary = {
	Biome.GRASS: Color(0.55, 0.76, 0.29),
	Biome.FOREST_LIGHT: Color(0.33, 0.59, 0.24),
	Biome.FOREST_DENSE: Color(0.18, 0.40, 0.14),
	Biome.WATER_SHALLOW: Color(0.40, 0.70, 0.85),
	Biome.WATER_DEEP: Color(0.15, 0.35, 0.60),
	Biome.SWAMP: Color(0.45, 0.50, 0.30),
	Biome.CLIFF: Color(0.50, 0.45, 0.40),
	Biome.HIGH_GROUND: Color(0.60, 0.55, 0.45),
}
```

**Step 5: Register autoloads in project.godot**

Add to `project.godot` under `[autoload]`:
```ini
[autoload]

EventBus="*res://scripts/autoloads/EventBus.gd"
GameManager="*res://scripts/autoloads/GameManager.gd"
Constants="*res://scripts/autoloads/Constants.gd"
```

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: project setup with autoloads and folder structure"
```

---

### Task 2: Map Generator

**Files:**
- Create: `scripts/map/MapGenerator.gd`

This ports `AmazonMapGenerator.ts` to GDScript using `FastNoiseLite`.

**Step 1: Create MapGenerator.gd**

```gdscript
# scripts/map/MapGenerator.gd
class_name MapGenerator
extends RefCounted

# Map data
var width: int
var height: int
var seed: int
var tiles: Array[Array] = []  # 2D array of biome enum values
var tile_data: Array[Array] = []  # 2D array of dictionaries with full tile info
var spawn_zones: Array[Dictionary] = []

# Noise generators
var elevation_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var forest_noise: FastNoiseLite
var detail_noise: FastNoiseLite

# Config
var forest_threshold: float = 0.5
var swamp_moisture_threshold: float = 0.65
var cliff_elevation_threshold: float = 0.75
var river_count: int = 4
var river_width: int = 5
var lake_count: int = 8
var lake_max_radius: int = 12
var player_count: int = 2
var spawn_zone_radius: int = 12
var min_spawn_distance: int = 100
var clearing_count: int = 12

func _init(p_width: int = 128, p_height: int = 128, p_seed: int = 0) -> void:
	width = p_width
	height = p_height
	seed = p_seed if p_seed != 0 else randi()
	_setup_noise()

func _setup_noise() -> void:
	elevation_noise = FastNoiseLite.new()
	elevation_noise.seed = seed
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elevation_noise.frequency = 0.025
	elevation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	elevation_noise.fractal_octaves = 4

	moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = seed + 1000
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moisture_noise.frequency = 0.03
	moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	moisture_noise.fractal_octaves = 3

	forest_noise = FastNoiseLite.new()
	forest_noise.seed = seed + 2000
	forest_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest_noise.frequency = 0.04
	forest_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	forest_noise.fractal_octaves = 4

	detail_noise = FastNoiseLite.new()
	detail_noise.seed = seed + 3000
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = 0.12

# ---- MAIN GENERATION PIPELINE ----

func generate() -> void:
	_initialize_tiles()
	_assign_base_biomes()
	_carve_rivers()
	_add_lakes()
	_place_spawn_zones()
	_add_clearings()
	_ensure_connectivity()
	_smooth_transitions()
	_calculate_tile_properties()

# ---- STEP 1: Initialize ----

func _initialize_tiles() -> void:
	tiles.clear()
	tile_data.clear()
	for y in range(height):
		var row: Array[int] = []
		var data_row: Array[Dictionary] = []
		row.resize(width)
		data_row.resize(width)
		for x in range(width):
			row[x] = Constants.Biome.GRASS
			data_row[x] = {
				"biome": Constants.Biome.GRASS,
				"elevation": 0.0,
				"moisture": 0.0,
				"forest_density": 0.0,
				"is_walkable": true,
				"movement_cost": 1.0,
				"has_resource": false,
				"resource_type": "",
				"resource_amount": 0,
			}
		tiles.append(row)
		tile_data.append(data_row)

# ---- STEP 2: Assign Biomes ----

func _assign_base_biomes() -> void:
	for y in range(height):
		for x in range(width):
			var e := _get_elevation(x, y)
			var m := _get_moisture(x, y)
			var f := _get_forest_density(x, y)

			tile_data[y][x]["elevation"] = e
			tile_data[y][x]["moisture"] = m
			tile_data[y][x]["forest_density"] = f

			var biome: int
			if e > cliff_elevation_threshold + 0.1:
				biome = Constants.Biome.CLIFF
			elif e > cliff_elevation_threshold:
				biome = Constants.Biome.HIGH_GROUND
			elif m > swamp_moisture_threshold and e < 0.4:
				biome = Constants.Biome.SWAMP
			elif f > forest_threshold + 0.15:
				biome = Constants.Biome.FOREST_DENSE
			elif f > forest_threshold - 0.1:
				biome = Constants.Biome.FOREST_LIGHT
			else:
				biome = Constants.Biome.GRASS

			tiles[y][x] = biome
			tile_data[y][x]["biome"] = biome

func _get_elevation(x: int, y: int) -> float:
	var e := (elevation_noise.get_noise_2d(x, y) + 1.0) / 2.0
	# Edge falloff
	var edge_x := minf(float(x), float(width - x)) / (width * 0.2)
	var edge_y := minf(float(y), float(height - y)) / (height * 0.2)
	var edge_falloff := minf(1.0, minf(edge_x, edge_y))
	e = e * 0.7 + e * edge_falloff * 0.3
	return clampf(e, 0.0, 1.0)

func _get_moisture(x: int, y: int) -> float:
	return clampf((moisture_noise.get_noise_2d(x, y) + 1.0) / 2.0, 0.0, 1.0)

func _get_forest_density(x: int, y: int) -> float:
	var f := (forest_noise.get_noise_2d(x, y) + 1.0) / 2.0
	var detail := (detail_noise.get_noise_2d(x, y) + 1.0) / 2.0
	f = f * 0.7 + detail * 0.3
	return clampf(f, 0.0, 1.0)

# ---- STEP 3: Rivers ----

func _carve_rivers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 5000

	for i in range(river_count):
		var is_horizontal := i % 2 == 0
		var start_x: int
		var start_y: int
		var end_x: int
		var end_y: int

		if is_horizontal:
			start_x = 0
			start_y = int(height * (0.25 + float(i) / river_count * 0.5))
			end_x = width - 1
			end_y = start_y + int((rng.randf() - 0.5) * height * 0.3)
		else:
			start_x = int(width * (0.25 + float(i) / river_count * 0.5))
			start_y = 0
			end_x = start_x + int((rng.randf() - 0.5) * width * 0.3)
			end_y = height - 1

		end_x = clampi(end_x, 0, width - 1)
		end_y = clampi(end_y, 0, height - 1)

		var path := _generate_meandering_path(start_x, start_y, end_x, end_y, 0.3)

		for point in path:
			var width_var := 1.0 + detail_noise.get_noise_2d(point.x * 0.1, point.y * 0.1) * 0.5
			var actual_width := int(river_width * width_var)

			for dy in range(-actual_width, actual_width + 1):
				for dx in range(-actual_width, actual_width + 1):
					var dist := sqrt(float(dx * dx + dy * dy))
					if dist <= actual_width:
						var nx := point.x + dx
						var ny := point.y + dy
						if _is_in_bounds(nx, ny):
							if dist <= actual_width * 0.6:
								tiles[ny][nx] = Constants.Biome.WATER_DEEP
							else:
								tiles[ny][nx] = Constants.Biome.WATER_SHALLOW

		# Add fords
		_add_river_fords(path, is_horizontal)

func _generate_meandering_path(sx: int, sy: int, ex: int, ey: int, meander: float) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var steps := maxi(absi(ex - sx), absi(ey - sy)) * 2
	if steps == 0:
		return path

	var dx_total := float(ex - sx)
	var dy_total := float(ey - sy)
	var length := sqrt(dx_total * dx_total + dy_total * dy_total)

	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var x := float(sx) + dx_total * t
		var y := float(sy) + dy_total * t

		# Noise-based meandering
		var noise_x := detail_noise.get_noise_2d(t * 1000.0 + 5000.0, 0.0) * meander * width * 0.15
		var noise_y := detail_noise.get_noise_2d(t * 1000.0 + 6000.0, 0.0) * meander * height * 0.15

		if length > 0:
			var perp_x := -dy_total / length
			var perp_y := dx_total / length
			x += perp_x * noise_x
			y += perp_y * noise_y

		var px := clampi(int(x), 0, width - 1)
		var py := clampi(int(y), 0, height - 1)

		if path.is_empty() or path[-1] != Vector2i(px, py):
			path.append(Vector2i(px, py))

	return path

func _add_river_fords(path: Array[Vector2i], is_horizontal: bool) -> void:
	var ford_count := 2 + randi() % 3
	var spacing := path.size() / (ford_count + 1)

	for i in range(1, ford_count + 1):
		var idx := i * spacing
		if idx < path.size():
			var point := path[idx]
			var ford_len := 4 if is_horizontal else 8
			var ford_w := 8 if is_horizontal else 4

			for dy in range(-ford_w, ford_w + 1):
				for dx in range(-ford_len, ford_len + 1):
					var nx := point.x + dx
					var ny := point.y + dy
					if _is_in_bounds(nx, ny):
						if tiles[ny][nx] == Constants.Biome.WATER_DEEP:
							tiles[ny][nx] = Constants.Biome.WATER_SHALLOW

# ---- STEP 4: Lakes ----

func _add_lakes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 6000

	for i in range(lake_count):
		var best_x := 0
		var best_y := 0
		var best_score := -INF

		for _attempt in range(50):
			var x := rng.randi_range(10, width - 11)
			var y := rng.randi_range(10, height - 11)
			var m := tile_data[y][x]["moisture"]
			var e := tile_data[y][x]["elevation"]
			var score: float = m * 2.0 - e

			var near_spawn := false
			for zone in spawn_zones:
				var dist := Vector2(x, y).distance_to(Vector2(zone["cx"], zone["cy"]))
				if dist < zone["radius"] + lake_max_radius:
					near_spawn = true
					break

			if not near_spawn and score > best_score:
				best_score = score
				best_x = x
				best_y = y

		var radius := rng.randi_range(3, lake_max_radius)
		_create_organic_lake(best_x, best_y, radius)

func _create_organic_lake(cx: int, cy: int, radius: int) -> void:
	for dy in range(-radius - 2, radius + 3):
		for dx in range(-radius - 2, radius + 3):
			var dist := sqrt(float(dx * dx + dy * dy))
			var noise_offset := detail_noise.get_noise_2d((cx + dx) * 0.2, (cy + dy) * 0.2) * radius * 0.4

			if dist <= radius + noise_offset:
				var nx := cx + dx
				var ny := cy + dy
				if _is_in_bounds(nx, ny):
					if tiles[ny][nx] != Constants.Biome.WATER_DEEP:
						if dist <= (radius + noise_offset) * 0.6:
							tiles[ny][nx] = Constants.Biome.WATER_DEEP
						else:
							tiles[ny][nx] = Constants.Biome.WATER_SHALLOW

# ---- STEP 5: Spawn Zones ----

func _place_spawn_zones() -> void:
	spawn_zones.clear()
	var r := spawn_zone_radius

	var candidates: Array[Vector2i] = [
		Vector2i(r + 5, r + 5),
		Vector2i(width - r - 5, height - r - 5),
		Vector2i(r + 5, height - r - 5),
		Vector2i(width - r - 5, r + 5),
		Vector2i(width / 2, r + 5),
		Vector2i(width / 2, height - r - 5),
		Vector2i(r + 5, height / 2),
		Vector2i(width - r - 5, height / 2),
	]

	for player_id in range(player_count):
		var best_candidate: Vector2i = Vector2i.ZERO
		var best_score := -INF
		var best_idx := -1

		for ci in range(candidates.size()):
			var c := candidates[ci]
			var min_dist := INF
			for zone in spawn_zones:
				var dist := Vector2(c).distance_to(Vector2(zone["cx"], zone["cy"]))
				min_dist = minf(min_dist, dist)

			if spawn_zones.size() > 0 and min_dist < min_spawn_distance:
				continue

			# Score by walkable area
			var walkable := 0
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var nx := c.x + dx
					var ny := c.y + dy
					if _is_in_bounds(nx, ny):
						var b := tiles[ny][nx]
						if b != Constants.Biome.WATER_DEEP and b != Constants.Biome.CLIFF:
							walkable += 1

			var score := float(walkable) + min_dist * 0.1
			if score > best_score:
				best_score = score
				best_candidate = c
				best_idx = ci

		if best_idx >= 0:
			_create_spawn_zone(best_candidate.x, best_candidate.y, r, player_id)
			candidates.remove_at(best_idx)

func _create_spawn_zone(cx: int, cy: int, radius: int, player_id: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var dist := sqrt(float(dx * dx + dy * dy))
			var noise_offset := detail_noise.get_noise_2d((cx + dx) * 0.3, (cy + dy) * 0.3) * 2.0

			if dist <= radius + noise_offset:
				var nx := cx + dx
				var ny := cy + dy
				if _is_in_bounds(nx, ny):
					if tiles[ny][nx] != Constants.Biome.WATER_DEEP:
						if dist <= radius * 0.6:
							tiles[ny][nx] = Constants.Biome.GRASS
						else:
							tiles[ny][nx] = Constants.Biome.FOREST_LIGHT

	spawn_zones.append({
		"cx": cx,
		"cy": cy,
		"radius": radius,
		"player_id": player_id,
	})

# ---- STEP 6: Clearings ----

func _add_clearings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 7000

	for _i in range(clearing_count):
		for _attempt in range(100):
			var x := rng.randi_range(10, width - 11)
			var y := rng.randi_range(10, height - 11)

			var near_spawn := false
			for zone in spawn_zones:
				if Vector2(x, y).distance_to(Vector2(zone["cx"], zone["cy"])) < 20:
					near_spawn = true
					break

			var b := tiles[y][x]
			if not near_spawn and b != Constants.Biome.WATER_DEEP and b != Constants.Biome.WATER_SHALLOW:
				var radius := rng.randi_range(5, 9)
				_create_clearing(x, y, radius)
				break

func _create_clearing(cx: int, cy: int, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var dist := sqrt(float(dx * dx + dy * dy))
			var noise_offset := detail_noise.get_noise_2d((cx + dx) * 0.4, (cy + dy) * 0.4) * 2.0

			if dist <= radius + noise_offset:
				var nx := cx + dx
				var ny := cy + dy
				if _is_in_bounds(nx, ny):
					var b := tiles[ny][nx]
					if b != Constants.Biome.WATER_DEEP and b != Constants.Biome.WATER_SHALLOW and b != Constants.Biome.CLIFF:
						tiles[ny][nx] = Constants.Biome.GRASS

# ---- STEP 7: Connectivity ----

func _ensure_connectivity() -> void:
	if spawn_zones.size() < 2:
		return

	var first := spawn_zones[0]
	var reachable := _flood_fill(first["cx"], first["cy"])

	for i in range(1, spawn_zones.size()):
		var zone := spawn_zones[i]
		var key := Vector2i(zone["cx"], zone["cy"])
		if not reachable.has(key):
			_carve_path(first["cx"], first["cy"], zone["cx"], zone["cy"])

func _flood_fill(sx: int, sy: int) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [Vector2i(sx, sy)]

	while queue.size() > 0:
		var pos := queue.pop_front()
		if visited.has(pos):
			continue
		if not _is_in_bounds(pos.x, pos.y):
			continue
		var b := tiles[pos.y][pos.x]
		if b == Constants.Biome.WATER_DEEP or b == Constants.Biome.CLIFF:
			continue

		visited[pos] = true

		queue.append(Vector2i(pos.x + 1, pos.y))
		queue.append(Vector2i(pos.x - 1, pos.y))
		queue.append(Vector2i(pos.x, pos.y + 1))
		queue.append(Vector2i(pos.x, pos.y - 1))

	return visited

func _carve_path(x1: int, y1: int, x2: int, y2: int) -> void:
	var path := _generate_meandering_path(x1, y1, x2, y2, 0.1)
	for point in path:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := point.x + dx
				var ny := point.y + dy
				if _is_in_bounds(nx, ny):
					if tiles[ny][nx] == Constants.Biome.WATER_DEEP:
						tiles[ny][nx] = Constants.Biome.WATER_SHALLOW
					elif tiles[ny][nx] == Constants.Biome.CLIFF:
						tiles[ny][nx] = Constants.Biome.HIGH_GROUND

# ---- STEP 8: Smooth Transitions ----

func _smooth_transitions() -> void:
	var changes: Array[Dictionary] = []

	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var b := tiles[y][x]
			var neighbors := _count_neighbor_biomes(x, y)

			if b == Constants.Biome.GRASS and neighbors.get(Constants.Biome.FOREST_DENSE, 0) >= 6:
				changes.append({"x": x, "y": y, "biome": Constants.Biome.FOREST_LIGHT})
			elif b == Constants.Biome.FOREST_DENSE and neighbors.get(Constants.Biome.GRASS, 0) >= 6:
				changes.append({"x": x, "y": y, "biome": Constants.Biome.FOREST_LIGHT})

	for change in changes:
		tiles[change["y"]][change["x"]] = change["biome"]

func _count_neighbor_biomes(x: int, y: int) -> Dictionary:
	var counts: Dictionary = {}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if _is_in_bounds(nx, ny):
				var b := tiles[ny][nx]
				counts[b] = counts.get(b, 0) + 1
	return counts

# ---- STEP 9: Calculate Properties ----

func _calculate_tile_properties() -> void:
	for y in range(height):
		for x in range(width):
			var b := tiles[y][x]
			tile_data[y][x]["biome"] = b
			tile_data[y][x]["is_walkable"] = Constants.WALKABLE.get(b, false)
			tile_data[y][x]["movement_cost"] = Constants.MOVEMENT_COST.get(b, INF)

# ---- UTILITIES ----

func _is_in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height

func get_biome(x: int, y: int) -> int:
	if not _is_in_bounds(x, y):
		return Constants.Biome.CLIFF
	return tiles[y][x]

func is_walkable(x: int, y: int) -> bool:
	if not _is_in_bounds(x, y):
		return false
	return tile_data[y][x]["is_walkable"]
```

**Step 2: Commit**

```bash
git add scripts/map/MapGenerator.gd
git commit -m "feat: port procedural map generator from TS to GDScript"
```

---

### Task 3: Isometric Map Scene with Colored Tiles

**Files:**
- Create: `scripts/map/IsometricMap.gd`
- Create: `scenes/map/IsometricMap.tscn`

Since we don't have PixelLab tiles yet, we render colored polygons directly.

**Step 1: Create IsometricMap.gd**

```gdscript
# scripts/map/IsometricMap.gd
extends Node2D

var map_generator: MapGenerator
var tile_size := Vector2(64, 32)  # Isometric tile dimensions

# Navigation
@onready var nav_region: NavigationRegion2D = $NavigationRegion2D

func _ready() -> void:
	map_generator = MapGenerator.new(GameManager.map_width, GameManager.map_height, GameManager.map_seed)
	map_generator.generate()
	queue_redraw()
	_bake_navigation()
	EventBus.map_generated.emit(GameManager.map_width, GameManager.map_height)

func _draw() -> void:
	if map_generator == null:
		return

	for y in range(map_generator.height):
		for x in range(map_generator.width):
			var biome := map_generator.get_biome(x, y)
			var color: Color = Constants.BIOME_COLORS.get(biome, Color.MAGENTA)
			_draw_iso_tile(x, y, color)

func _draw_iso_tile(grid_x: int, grid_y: int, color: Color) -> void:
	var screen_pos := grid_to_screen(grid_x, grid_y)
	var half_w := tile_size.x / 2.0
	var half_h := tile_size.y / 2.0

	var points := PackedVector2Array([
		screen_pos + Vector2(0, -half_h),   # Top
		screen_pos + Vector2(half_w, 0),     # Right
		screen_pos + Vector2(0, half_h),     # Bottom
		screen_pos + Vector2(-half_w, 0),    # Left
	])
	draw_colored_polygon(points, color)

func grid_to_screen(grid_x: int, grid_y: int) -> Vector2:
	var screen_x := (grid_x - grid_y) * tile_size.x / 2.0
	var screen_y := (grid_x + grid_y) * tile_size.y / 2.0
	return Vector2(screen_x, screen_y)

func screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var gx := (screen_pos.x / (tile_size.x / 2.0) + screen_pos.y / (tile_size.y / 2.0)) / 2.0
	var gy := (screen_pos.y / (tile_size.y / 2.0) - screen_pos.x / (tile_size.x / 2.0)) / 2.0
	return Vector2i(int(round(gx)), int(round(gy)))

func _bake_navigation() -> void:
	var nav_poly := NavigationPolygon.new()

	# Create walkable polygons per tile
	for y in range(map_generator.height):
		for x in range(map_generator.width):
			if map_generator.is_walkable(x, y):
				var screen_pos := grid_to_screen(x, y)
				var half_w := tile_size.x / 2.0
				var half_h := tile_size.y / 2.0

				var outline := PackedVector2Array([
					screen_pos + Vector2(0, -half_h),
					screen_pos + Vector2(half_w, 0),
					screen_pos + Vector2(0, half_h),
					screen_pos + Vector2(-half_w, 0),
				])
				nav_poly.add_outline(outline)

	nav_poly.make_polygons_from_outlines()
	nav_region.navigation_polygon = nav_poly
```

**Step 2: Create IsometricMap.tscn scene**

This must be created via Godot editor or script. The scene tree is:

```
IsometricMap (Node2D)
  ├── Script: res://scripts/map/IsometricMap.gd
  └── NavigationRegion2D
```

Create the `.tscn` file:

```ini
[gd_scene load_steps=2 format=3 uid="uid://iso_map"]

[ext_resource type="Script" path="res://scripts/map/IsometricMap.gd" id="1"]

[node name="IsometricMap" type="Node2D"]
script = ExtResource("1")

[node name="NavigationRegion2D" type="NavigationRegion2D" parent="."]
```

**Step 3: Commit**

```bash
git add scenes/map/IsometricMap.tscn scripts/map/IsometricMap.gd
git commit -m "feat: isometric map renderer with colored tile polygons"
```

---

### Task 4: Camera System

**Files:**
- Create: `scripts/camera/GameCamera.gd`
- Create: `scenes/camera/GameCamera.tscn`

**Step 1: Create GameCamera.gd**

```gdscript
# scripts/camera/GameCamera.gd
extends Camera2D

# Pan
@export var pan_speed: float = 600.0
@export var edge_scroll_margin: int = 30
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var camera_drag_start: Vector2 = Vector2.ZERO

# Zoom
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.3
@export var max_zoom: float = 2.0
var target_zoom: float = 0.7

# Pinch zoom
var touch_points: Dictionary = {}  # id -> position
var pinch_start_distance: float = 0.0
var pinch_start_zoom: float = 0.0

# Bounds (set after map generates)
var map_bounds: Rect2 = Rect2(-5000, -5000, 10000, 10000)

# Mobile detection
var is_mobile: bool = false

func _ready() -> void:
	zoom = Vector2(target_zoom, target_zoom)
	is_mobile = OS.has_feature("mobile")
	EventBus.map_generated.connect(_on_map_generated)

func _on_map_generated(w: int, h: int) -> void:
	# Calculate approximate pixel bounds of the isometric map
	var half_w := w * 64.0 / 2.0
	var total_h := h * 32.0
	map_bounds = Rect2(-half_w - 200, -200, half_w * 2.0 + 400, total_h + 400)

func _process(delta: float) -> void:
	# Keyboard pan
	var direction := Vector2.ZERO

	if Input.is_action_pressed("ui_up"):
		direction.y -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_right"):
		direction.x += 1

	# Edge scrolling (desktop only)
	if not is_mobile and not is_dragging:
		var mouse := get_viewport().get_mouse_position()
		var vp_size := get_viewport_rect().size

		if mouse.x < edge_scroll_margin:
			direction.x -= 1
		elif mouse.x > vp_size.x - edge_scroll_margin:
			direction.x += 1
		if mouse.y < edge_scroll_margin:
			direction.y -= 1
		elif mouse.y > vp_size.y - edge_scroll_margin:
			direction.y += 1

	if direction != Vector2.ZERO:
		position += direction.normalized() * pan_speed * delta / zoom.x

	# Smooth zoom
	zoom = zoom.lerp(Vector2(target_zoom, target_zoom), 10.0 * delta)

	# Clamp to bounds
	position.x = clampf(position.x, map_bounds.position.x, map_bounds.end.x)
	position.y = clampf(position.y, map_bounds.position.y, map_bounds.end.y)

func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_zoom = clampf(target_zoom + zoom_speed, min_zoom, max_zoom)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				target_zoom = clampf(target_zoom - zoom_speed, min_zoom, max_zoom)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_MIDDLE:
				is_dragging = true
				drag_start = mb.position
				camera_drag_start = position
				get_viewport().set_input_as_handled()
		else:
			if mb.button_index == MOUSE_BUTTON_MIDDLE:
				is_dragging = false

	# Mouse drag pan (middle button)
	if event is InputEventMouseMotion and is_dragging:
		var mm := event as InputEventMouseMotion
		position = camera_drag_start + (drag_start - mm.position) / zoom.x
		get_viewport().set_input_as_handled()

	# Touch events for mobile
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			touch_points[st.index] = st.position
			if touch_points.size() == 2:
				_start_pinch()
		else:
			touch_points.erase(st.index)

	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		touch_points[sd.index] = sd.position

		if touch_points.size() == 1:
			# Single finger drag = pan
			position -= sd.relative / zoom.x
		elif touch_points.size() == 2:
			# Two finger = pinch zoom
			_handle_pinch()

func _start_pinch() -> void:
	var points := touch_points.values()
	pinch_start_distance = (points[0] as Vector2).distance_to(points[1] as Vector2)
	pinch_start_zoom = target_zoom

func _handle_pinch() -> void:
	var points := touch_points.values()
	var current_distance := (points[0] as Vector2).distance_to(points[1] as Vector2)

	if pinch_start_distance > 0:
		var scale_factor := current_distance / pinch_start_distance
		target_zoom = clampf(pinch_start_zoom * scale_factor, min_zoom, max_zoom)

func center_on(world_pos: Vector2) -> void:
	position = world_pos
```

**Step 2: Create GameCamera.tscn**

```ini
[gd_scene load_steps=2 format=3 uid="uid://game_cam"]

[ext_resource type="Script" path="res://scripts/camera/GameCamera.gd" id="1"]

[node name="GameCamera" type="Camera2D"]
script = ExtResource("1")
```

**Step 3: Commit**

```bash
git add scripts/camera/GameCamera.gd scenes/camera/GameCamera.tscn
git commit -m "feat: camera with pan, zoom, edge scroll, and touch support"
```

---

### Task 5: Main Scene — Wire Everything Together

**Files:**
- Create: `scripts/main/Main.gd`
- Create: `scenes/main/Main.tscn`
- Modify: `project.godot` (set main scene)

**Step 1: Create Main.gd**

```gdscript
# scripts/main/Main.gd
extends Node2D

@onready var iso_map: Node2D = $IsometricMap
@onready var camera: Camera2D = $GameCamera

func _ready() -> void:
	# Center camera on first spawn zone after map generates
	EventBus.map_generated.connect(_on_map_generated)
	GameManager.change_state(GameManager.GameState.RUNNING)

func _on_map_generated(_w: int, _h: int) -> void:
	if iso_map.map_generator.spawn_zones.size() > 0:
		var spawn := iso_map.map_generator.spawn_zones[0]
		var screen_pos := iso_map.grid_to_screen(spawn["cx"], spawn["cy"])
		camera.center_on(screen_pos)
```

**Step 2: Create Main.tscn**

```ini
[gd_scene load_steps=4 format=3 uid="uid://main_scene"]

[ext_resource type="Script" path="res://scripts/main/Main.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/map/IsometricMap.tscn" id="2"]
[ext_resource type="PackedScene" path="res://scenes/camera/GameCamera.tscn" id="3"]

[node name="Main" type="Node2D"]
script = ExtResource("1")

[node name="IsometricMap" parent="." instance=ExtResource("2")]

[node name="GameCamera" parent="." instance=ExtResource("3")]
```

**Step 3: Set as main scene in project.godot**

Add under `[application]`:
```ini
run/main_scene="res://scenes/main/Main.tscn"
```

**Step 4: Run and verify**

Open Godot, run the project. You should see:
- A 128x128 isometric map with colored tiles
- Rivers (blue), forests (green), grass (light green), swamps, cliffs
- Camera pans with arrow keys and zooms with scroll wheel
- Camera starts centered on player 1 spawn zone

**Step 5: Commit**

```bash
git add scenes/main/Main.tscn scripts/main/Main.gd project.godot
git commit -m "feat: main scene wiring map and camera together"
```

---

### Task 6: Base Unit Scene

**Files:**
- Create: `scripts/units/Unit.gd`
- Create: `scenes/units/Unit.tscn`

**Step 1: Create Unit.gd**

```gdscript
# scripts/units/Unit.gd
class_name UnitBase
extends CharacterBody2D

# State machine
enum State { IDLE, MOVING, ATTACKING, GATHERING, BUILDING }
var current_state: State = State.IDLE

# Stats
@export var unit_name: String = "Unit"
@export var max_hp: int = 40
@export var current_hp: int = 40
@export var move_speed: float = 100.0
@export var attack_power: int = 3
@export var armor: int = 0
@export var attack_range: float = 32.0
@export var vision_range: float = 128.0
@export var player_id: int = 0

# Selection
var is_selected: bool = false

# Navigation
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var selection_indicator: Sprite2D = $SelectionIndicator
@onready var health_bar: ProgressBar = $HealthBar

# Colors per player
const PLAYER_COLORS: Array[Color] = [
	Color(0.2, 0.6, 1.0),  # Player 0: Blue
	Color(1.0, 0.3, 0.3),  # Player 1: Red
]

func _ready() -> void:
	add_to_group("units")
	add_to_group("player_%d" % player_id)

	# Setup nav agent
	nav_agent.path_desired_distance = 8.0
	nav_agent.target_desired_distance = 8.0
	nav_agent.velocity_computed.connect(_on_velocity_computed)

	# Visual setup
	_update_color()
	selection_indicator.visible = false
	health_bar.visible = false
	health_bar.max_value = max_hp
	health_bar.value = current_hp

func _physics_process(delta: float) -> void:
	match current_state:
		State.IDLE:
			pass
		State.MOVING:
			_process_movement(delta)

func _process_movement(_delta: float) -> void:
	if nav_agent.is_navigation_finished():
		current_state = State.IDLE
		return

	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()
	nav_agent.velocity = direction * move_speed

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()

func move_to(target: Vector2) -> void:
	nav_agent.target_position = target
	current_state = State.MOVING

func select() -> void:
	is_selected = true
	selection_indicator.visible = true
	health_bar.visible = true
	EventBus.unit_selected.emit(self)

func deselect() -> void:
	is_selected = false
	selection_indicator.visible = false
	health_bar.visible = false
	EventBus.unit_deselected.emit(self)

func take_damage(amount: int) -> void:
	var actual := maxi(0, amount - armor)
	current_hp = maxi(0, current_hp - actual)
	health_bar.value = current_hp
	if current_hp <= 0:
		_die()

func _die() -> void:
	queue_free()

func _update_color() -> void:
	if player_id < PLAYER_COLORS.size():
		sprite.modulate = PLAYER_COLORS[player_id]

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			select()
			get_viewport().set_input_as_handled()
```

**Step 2: Create Unit.tscn**

```ini
[gd_scene load_steps=2 format=3 uid="uid://base_unit"]

[ext_resource type="Script" path="res://scripts/units/Unit.gd" id="1"]

[node name="Unit" type="CharacterBody2D"]
script = ExtResource("1")
input_pickable = true

[node name="Sprite2D" type="Sprite2D" parent="."]
scale = Vector2(0.5, 0.5)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]

[node name="NavigationAgent2D" type="NavigationAgent2D" parent="."]

[node name="SelectionIndicator" type="Sprite2D" parent="."]
position = Vector2(0, 4)
visible = false

[node name="HealthBar" type="ProgressBar" parent="."]
offset_left = -16.0
offset_top = -24.0
offset_right = 16.0
offset_bottom = -18.0
visible = false
show_percentage = false
```

Note: CollisionShape2D and Sprite2D textures will need to be set up in the editor (CircleShape2D for collision, placeholder texture for sprite). We'll create placeholder textures programmatically in the Main scene.

**Step 3: Commit**

```bash
git add scripts/units/Unit.gd scenes/units/Unit.tscn
git commit -m "feat: base unit with navigation, selection, and health"
```

---

### Task 7: Selection System

**Files:**
- Create: `scripts/ui/SelectionManager.gd` (autoload)
- Modify: `project.godot` (register autoload)

**Step 1: Create SelectionManager.gd**

```gdscript
# scripts/ui/SelectionManager.gd
extends Node

var selected_units: Array[Node2D] = []
var is_box_selecting: bool = false
var box_start: Vector2 = Vector2.ZERO

# Selection box visual
var selection_rect: Rect2 = Rect2()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_start_selection(mb.position)
			else:
				_end_selection(mb.position)

		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if selected_units.size() > 0:
				_command_move(mb.global_position)

	if event is InputEventMouseMotion and is_box_selecting:
		_update_selection_box(event.position)

	# Touch: tap = select, long press or two-finger tap = command
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_start_selection(st.position)
		else:
			_end_selection(st.position)

func _start_selection(screen_pos: Vector2) -> void:
	box_start = screen_pos
	is_box_selecting = true

func _end_selection(screen_pos: Vector2) -> void:
	is_box_selecting = false
	var box_size := (screen_pos - box_start).abs()

	if box_size.length() < 10:
		# Click select - check if we clicked a unit
		_click_select(screen_pos)
	else:
		# Box select
		_box_select(box_start, screen_pos)

	selection_rect = Rect2()

func _click_select(screen_pos: Vector2) -> void:
	# Deselect all first if not shift-clicking
	if not Input.is_key_pressed(KEY_SHIFT):
		_deselect_all()

	# Check units under click using physics query
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return

	var world_pos := _screen_to_world(screen_pos)

	# Find closest unit to click
	var closest_unit: Node2D = null
	var closest_dist := 20.0  # Click tolerance in world pixels

	for unit in get_tree().get_nodes_in_group("units"):
		var dist := unit.global_position.distance_to(world_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest_unit = unit

	if closest_unit and closest_unit.has_method("select"):
		closest_unit.select()
		if closest_unit not in selected_units:
			selected_units.append(closest_unit)
	elif not Input.is_key_pressed(KEY_SHIFT):
		_deselect_all()

func _box_select(start: Vector2, end: Vector2) -> void:
	_deselect_all()

	var world_start := _screen_to_world(start)
	var world_end := _screen_to_world(end)
	var rect := Rect2(world_start, world_end - world_start).abs()

	for unit in get_tree().get_nodes_in_group("units"):
		if rect.has_point(unit.global_position):
			if unit.has_method("select"):
				unit.select()
				selected_units.append(unit)

func _command_move(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)

	for unit in selected_units:
		if unit.has_method("move_to"):
			unit.move_to(world_pos)

	EventBus.units_commanded_move.emit(selected_units, world_pos)

func _deselect_all() -> void:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("deselect"):
			unit.deselect()
	selected_units.clear()
	EventBus.selection_cleared.emit()

func _update_selection_box(screen_pos: Vector2) -> void:
	selection_rect = Rect2(box_start, screen_pos - box_start).abs()

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return screen_pos

	var viewport_size := get_viewport().get_visible_rect().size
	var offset := screen_pos - viewport_size / 2.0
	return camera.global_position + offset / camera.zoom
```

**Step 2: Register autoload in project.godot**

Add to `[autoload]`:
```ini
SelectionManager="*res://scripts/ui/SelectionManager.gd"
```

**Step 3: Commit**

```bash
git add scripts/ui/SelectionManager.gd project.godot
git commit -m "feat: selection system with click, box select, and move commands"
```

---

### Task 8: Spawn Units on Map + Integration Test

**Files:**
- Modify: `scripts/main/Main.gd` (spawn villagers at spawn zones)

**Step 1: Update Main.gd to spawn units**

```gdscript
# scripts/main/Main.gd
extends Node2D

@onready var iso_map: Node2D = $IsometricMap
@onready var camera: Camera2D = $GameCamera

var unit_scene: PackedScene = preload("res://scenes/units/Unit.tscn")

func _ready() -> void:
	EventBus.map_generated.connect(_on_map_generated)
	GameManager.change_state(GameManager.GameState.RUNNING)

func _on_map_generated(_w: int, _h: int) -> void:
	# Center camera on player spawn
	if iso_map.map_generator.spawn_zones.size() > 0:
		var spawn := iso_map.map_generator.spawn_zones[0]
		var screen_pos := iso_map.grid_to_screen(spawn["cx"], spawn["cy"])
		camera.center_on(screen_pos)

		# Spawn 3 villagers for each player
		for zone in iso_map.map_generator.spawn_zones:
			_spawn_villagers(zone, 3)

func _spawn_villagers(zone: Dictionary, count: int) -> void:
	var cx: int = zone["cx"]
	var cy: int = zone["cy"]
	var pid: int = zone["player_id"]

	for i in range(count):
		var unit := unit_scene.instantiate() as CharacterBody2D
		unit.player_id = pid
		unit.unit_name = "Villager"

		# Offset each unit slightly
		var offset_x := (i % 3 - 1) * 2
		var offset_y := (i / 3 - 1) * 2
		var grid_x := cx + offset_x
		var grid_y := cy + offset_y

		unit.global_position = iso_map.grid_to_screen(grid_x, grid_y)
		add_child(unit)
```

**Step 2: Run the project and verify**

Expected behavior:
- Map renders with colored isometric tiles
- Camera centers on player 1 spawn
- 3 blue villagers at player 1 spawn, 3 red at player 2
- Left-click a villager → selection indicator appears
- Right-click ground with units selected → villagers navigate to clicked position
- Arrow keys / scroll wheel → camera pans and zooms
- Drag box → multi-select units

**Step 3: Commit**

```bash
git add scripts/main/Main.gd
git commit -m "feat: spawn villagers at player spawn zones"
```

---

### Task 9: Selection Box Visual (HUD Overlay)

**Files:**
- Create: `scripts/ui/SelectionBoxOverlay.gd`
- Modify: `scenes/main/Main.tscn` (add CanvasLayer + overlay)

**Step 1: Create SelectionBoxOverlay.gd**

```gdscript
# scripts/ui/SelectionBoxOverlay.gd
extends Control

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if SelectionManager.is_box_selecting and SelectionManager.selection_rect.size.length() > 5:
		var rect := SelectionManager.selection_rect
		draw_rect(rect, Color(0.2, 0.8, 0.2, 0.15), true)   # Fill
		draw_rect(rect, Color(0.2, 0.8, 0.2, 0.8), false, 1.0)  # Border
```

**Step 2: Add to Main scene**

Add a CanvasLayer with the overlay to `Main.tscn`:

```ini
[node name="UILayer" type="CanvasLayer" parent="."]
layer = 10

[node name="SelectionBoxOverlay" type="Control" parent="UILayer"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
script = ExtResource("selection_box_script")
```

**Step 3: Commit**

```bash
git add scripts/ui/SelectionBoxOverlay.gd scenes/main/Main.tscn
git commit -m "feat: selection box visual overlay"
```

---

### Task 10: Placeholder Unit Sprites

**Files:**
- Create: `scripts/utils/PlaceholderTextures.gd` (autoload)

Instead of needing actual images, generate simple colored textures at runtime.

**Step 1: Create PlaceholderTextures.gd**

```gdscript
# scripts/utils/PlaceholderTextures.gd
extends Node

var unit_texture: ImageTexture
var selection_circle: ImageTexture

func _ready() -> void:
	unit_texture = _create_diamond_texture(24, 24, Color.WHITE)
	selection_circle = _create_circle_texture(32, Color(0.2, 1.0, 0.2, 0.5))

func _create_diamond_texture(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := w / 2.0
	var cy := h / 2.0

	for y in range(h):
		for x in range(w):
			var dx := absf(x - cx) / cx
			var dy := absf(y - cy) / cy
			if dx + dy <= 1.0:
				img.set_pixel(x, y, color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(img)

func _create_circle_texture(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := size / 2.0
	var radius := center - 1.0

	for y in range(size):
		for x in range(size):
			var dist := Vector2(x, y).distance_to(Vector2(center, center))
			if dist <= radius and dist >= radius - 2.0:
				img.set_pixel(x, y, color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(img)
```

**Step 2: Register autoload and update Unit.gd to use it**

Add to `[autoload]` in project.godot:
```ini
PlaceholderTextures="*res://scripts/utils/PlaceholderTextures.gd"
```

Update `Unit.gd` `_ready()` to assign textures:
```gdscript
func _ready() -> void:
	# ... existing code ...
	sprite.texture = PlaceholderTextures.unit_texture
	selection_indicator.texture = PlaceholderTextures.selection_circle
```

**Step 3: Commit**

```bash
git add scripts/utils/PlaceholderTextures.gd project.godot scripts/units/Unit.gd
git commit -m "feat: runtime placeholder textures for units"
```

---

## Summary

After completing all 10 tasks you will have:

1. **Project structure** with autoloads (EventBus, GameManager, Constants)
2. **Procedural map** (128x128) with all 8 biomes, rivers, lakes, spawn zones
3. **Isometric rendering** with colored diamond tiles
4. **Camera** with keyboard pan, edge scroll, zoom, and mobile touch/pinch
5. **Unit system** with navigation, selection, health
6. **Selection** with click, box-select, and right-click move commands
7. **Placeholder visuals** that work without any art assets
8. **6 villagers** (3 per player) spawned at their respective bases

This is the playable foundation for Phase 2 (resources, gathering, buildings).
