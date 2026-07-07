# scripts/map/MapGenerator.gd
class_name MapGenerator
extends RefCounted

var width: int
var height: int
var seed_val: int
var tiles: Array = []  # 2D array of biome enum values
var tile_data: Array = []  # 2D array of dictionaries
var spawn_zones: Array = []

# Noise generators
var elevation_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var forest_noise: FastNoiseLite
var detail_noise: FastNoiseLite

# Config
var forest_threshold: float = 0.5
var swamp_moisture_threshold: float = 0.65
var cliff_elevation_threshold: float = 0.75
var river_count: int = 2
var river_width: int = 3
var lake_count: int = 4
var lake_max_radius: int = 8
var player_count: int = 2
var spawn_zone_radius: int = 8
var min_spawn_distance: int = 40
var clearing_count: int = 6

func _init(p_width: int = 128, p_height: int = 128, p_seed: int = 0) -> void:
	width = p_width
	height = p_height
	seed_val = p_seed if p_seed != 0 else randi()
	_setup_noise()

func _setup_noise() -> void:
	elevation_noise = FastNoiseLite.new()
	elevation_noise.seed = seed_val
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elevation_noise.frequency = 0.025
	elevation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	elevation_noise.fractal_octaves = 4

	moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = seed_val + 1000
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moisture_noise.frequency = 0.03
	moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	moisture_noise.fractal_octaves = 3

	forest_noise = FastNoiseLite.new()
	forest_noise.seed = seed_val + 2000
	forest_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest_noise.frequency = 0.04
	forest_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	forest_noise.fractal_octaves = 4

	detail_noise = FastNoiseLite.new()
	detail_noise.seed = seed_val + 3000
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = 0.12

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

func _initialize_tiles() -> void:
	tiles.clear()
	tile_data.clear()
	for y in range(height):
		var row: Array = []
		var data_row: Array = []
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

func _carve_rivers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 5000

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

		for p in path:
			var point: Vector2i = p as Vector2i
			var width_var := 1.0 + detail_noise.get_noise_2d(point.x * 0.1, point.y * 0.1) * 0.5
			var actual_width := int(river_width * width_var)

			for dy in range(-actual_width, actual_width + 1):
				for dx in range(-actual_width, actual_width + 1):
					var dist := sqrt(float(dx * dx + dy * dy))
					if dist <= actual_width:
						var nx: int = point.x + dx
						var ny: int = point.y + dy
						if _is_in_bounds(nx, ny):
							if dist <= actual_width * 0.6:
								tiles[ny][nx] = Constants.Biome.WATER_DEEP
							else:
								tiles[ny][nx] = Constants.Biome.WATER_SHALLOW

		_add_river_fords(path, is_horizontal, rng)

func _generate_meandering_path(sx: int, sy: int, ex: int, ey: int, meander: float) -> Array:
	var path: Array = []
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

		var noise_x := detail_noise.get_noise_2d(t * 1000.0 + 5000.0, 0.0) * meander * width * 0.15
		var noise_y := detail_noise.get_noise_2d(t * 1000.0 + 6000.0, 0.0) * meander * height * 0.15

		if length > 0:
			var perp_x := -dy_total / length
			var perp_y := dx_total / length
			x += perp_x * noise_x
			y += perp_y * noise_y

		var px := clampi(int(x), 0, width - 1)
		var py := clampi(int(y), 0, height - 1)
		var point := Vector2i(px, py)

		if path.is_empty() or path[-1] != point:
			path.append(point)

	return path

func _add_river_fords(path: Array, is_horizontal: bool, rng: RandomNumberGenerator) -> void:
	var ford_count := 2 + rng.randi() % 3
	@warning_ignore("integer_division")
	var spacing := path.size() / (ford_count + 1)

	for i in range(1, ford_count + 1):
		var idx := i * spacing
		if idx < path.size():
			var point: Vector2i = path[idx]
			var ford_len := 4 if is_horizontal else 8
			var ford_w := 8 if is_horizontal else 4

			for dy in range(-ford_w, ford_w + 1):
				for dx in range(-ford_len, ford_len + 1):
					var nx: int = point.x + dx
					var ny: int = point.y + dy
					if _is_in_bounds(nx, ny):
						if tiles[ny][nx] == Constants.Biome.WATER_DEEP:
							tiles[ny][nx] = Constants.Biome.WATER_SHALLOW

func _add_lakes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 6000

	for _i in range(lake_count):
		var best_x := 0
		var best_y := 0
		var best_score := -INF

		for _attempt in range(50):
			var x := rng.randi_range(10, width - 11)
			var y := rng.randi_range(10, height - 11)
			var m: float = tile_data[y][x]["moisture"]
			var e: float = tile_data[y][x]["elevation"]
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
						# Compact deep core (no per-tile noise) so the lake
						# center doesn't come out speckled.
						if dist <= radius * 0.55:
							tiles[ny][nx] = Constants.Biome.WATER_DEEP
						else:
							tiles[ny][nx] = Constants.Biome.WATER_SHALLOW

func _place_spawn_zones() -> void:
	spawn_zones.clear()
	var r := spawn_zone_radius

	var candidates: Array = [
		Vector2i(r + 5, r + 5),
		Vector2i(width - r - 5, height - r - 5),
		Vector2i(r + 5, height - r - 5),
		Vector2i(width - r - 5, r + 5),
		Vector2i(int(width / 2.0), r + 5),
		Vector2i(int(width / 2.0), height - r - 5),
		Vector2i(r + 5, int(height / 2.0)),
		Vector2i(width - r - 5, int(height / 2.0)),
	]

	for player_id in range(player_count):
		var best_candidate: Vector2i = Vector2i.ZERO
		var best_score := -INF
		var best_idx := -1

		for ci in range(candidates.size()):
			var c: Vector2i = candidates[ci]
			var min_dist := INF
			for zone in spawn_zones:
				var dist := Vector2(c).distance_to(Vector2(zone["cx"], zone["cy"]))
				min_dist = minf(min_dist, dist)

			if spawn_zones.size() > 0 and min_dist < min_spawn_distance:
				continue

			var walkable := 0
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var nx := c.x + dx
					var ny := c.y + dy
					if _is_in_bounds(nx, ny):
						var b: int = tiles[ny][nx]
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
					if tiles[ny][nx] == Constants.Biome.WATER_DEEP:
						# Keep rivers flowing through spawns, but fordable.
						tiles[ny][nx] = Constants.Biome.WATER_SHALLOW
					elif dist <= radius * 0.6:
						tiles[ny][nx] = Constants.Biome.GRASS
					else:
						tiles[ny][nx] = Constants.Biome.FOREST_LIGHT

	spawn_zones.append({
		"cx": cx,
		"cy": cy,
		"radius": radius,
		"player_id": player_id,
	})

func _add_clearings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 7000

	for _i in range(clearing_count):
		for _attempt in range(100):
			var x := rng.randi_range(10, width - 11)
			var y := rng.randi_range(10, height - 11)

			var near_spawn := false
			for zone in spawn_zones:
				if Vector2(x, y).distance_to(Vector2(zone["cx"], zone["cy"])) < 20:
					near_spawn = true
					break

			var b: int = tiles[y][x]
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
					var b: int = tiles[ny][nx]
					if b != Constants.Biome.WATER_DEEP and b != Constants.Biome.WATER_SHALLOW and b != Constants.Biome.CLIFF:
						tiles[ny][nx] = Constants.Biome.GRASS

func _ensure_connectivity() -> void:
	if spawn_zones.size() < 2:
		return

	var first: Dictionary = spawn_zones[0]
	var reachable := _flood_fill(first["cx"], first["cy"])

	for i in range(1, spawn_zones.size()):
		var zone: Dictionary = spawn_zones[i]
		var key := Vector2i(zone["cx"], zone["cy"])
		if not reachable.has(key):
			_carve_path(first["cx"], first["cy"], zone["cx"], zone["cy"])

func _flood_fill(sx: int, sy: int) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array = [Vector2i(sx, sy)]

	while queue.size() > 0:
		var pos: Vector2i = queue.pop_front()
		if visited.has(pos):
			continue
		if not _is_in_bounds(pos.x, pos.y):
			continue
		var b: int = tiles[pos.y][pos.x]
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
	for p in path:
		var point: Vector2i = p as Vector2i
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx: int = point.x + dx
				var ny: int = point.y + dy
				if _is_in_bounds(nx, ny):
					if tiles[ny][nx] == Constants.Biome.WATER_DEEP:
						tiles[ny][nx] = Constants.Biome.WATER_SHALLOW
					elif tiles[ny][nx] == Constants.Biome.CLIFF:
						tiles[ny][nx] = Constants.Biome.HIGH_GROUND

func _smooth_transitions() -> void:
	var changes: Array = []

	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var b: int = tiles[y][x]
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
				var b: int = tiles[ny][nx]
				counts[b] = counts.get(b, 0) + 1
	return counts

func _calculate_tile_properties() -> void:
	for y in range(height):
		for x in range(width):
			var b: int = tiles[y][x]
			tile_data[y][x]["biome"] = b
			tile_data[y][x]["is_walkable"] = Constants.WALKABLE.get(b, false)
			tile_data[y][x]["movement_cost"] = Constants.MOVEMENT_COST.get(b, INF)

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

func get_movement_cost(x: int, y: int) -> float:
	if not _is_in_bounds(x, y):
		return INF
	return tile_data[y][x]["movement_cost"]
