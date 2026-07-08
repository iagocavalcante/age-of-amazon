# scripts/world/AnimalManager.gd
extends Node2D

# Ambient wildlife spawner (see ADR 14). Keeps a bounded number of animals alive
# near the "action" — the camera and both players' bases — spawning them on
# walkable land just outside view and despawning strays that wander far from
# everything. This is a y-sorted container: its Animal children draw correctly
# among units, doodads, and buildings.

const TARGET_POPULATION: int = 16
const SPAWN_INTERVAL: float = 1.1
const MAX_SPAWNS_PER_TICK: int = 2
const SPAWN_MIN_TILES: int = 16   # just off-screen at default zoom
const SPAWN_MAX_TILES: int = 34
const DESPAWN_TILES: int = 64     # cull only well beyond the spawn ring
const JAGUAR_CHANCE: float = 0.22
const INITIAL_SEED_COUNT: int = 7

var camera: Camera2D
var _spawn_accum: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func setup(p_camera: Camera2D) -> void:
	camera = p_camera
	_rng.seed = hash(GameManager.map_seed)
	_seed_initial()

func _process(delta: float) -> void:
	if camera == null or GameManager.world == null:
		return
	if GameManager.state != GameManager.GameState.RUNNING:
		return

	_spawn_accum += delta
	if _spawn_accum < SPAWN_INTERVAL:
		return
	_spawn_accum = 0.0

	_cull_strays()

	var spawns: int = 0
	while _population() < TARGET_POPULATION and spawns < MAX_SPAWNS_PER_TICK:
		if not _try_spawn():
			break
		spawns += 1

func _seed_initial() -> void:
	for _i in range(INITIAL_SEED_COUNT):
		_try_spawn()

func _population() -> int:
	return get_tree().get_nodes_in_group("animals").size()

# --- Spawning ---

func _try_spawn() -> bool:
	var anchors: Array[Vector2] = _spawn_anchors()
	if anchors.is_empty():
		return false
	var anchor: Vector2 = anchors[_rng.randi_range(0, anchors.size() - 1)]
	var base: Vector2i = Constants.world_to_grid(anchor)

	for _attempt in range(12):
		var dist: int = _rng.randi_range(SPAWN_MIN_TILES, SPAWN_MAX_TILES)
		var angle: float = _rng.randf() * TAU
		var cell: Vector2i = base + Vector2i(int(cos(angle) * dist), int(sin(angle) * dist))
		if GameManager.world.is_walkable(cell):
			var species: String = "jaguar" if _rng.randf() < JAGUAR_CHANCE else "capybara"
			spawn_at(species, cell)
			return true
	return false

# Public: deterministic spawn used by the test harness.
func spawn_at(species: String, cell: Vector2i) -> Animal:
	var animal: Animal = Animal.new()
	animal.setup(species)
	animal.position = Constants.grid_to_world(cell.x, cell.y)
	add_child(animal)
	return animal

# --- Culling ---

func _cull_strays() -> void:
	var keep: Array[Vector2i] = _keep_anchors()
	for node: Node in get_tree().get_nodes_in_group("animals"):
		var animal: Animal = node as Animal
		if animal == null:
			continue
		var cell: Vector2i = Constants.world_to_grid(animal.global_position)
		var near: bool = false
		for anchor: Vector2i in keep:
			if _tile_dist(cell, anchor) <= DESPAWN_TILES:
				near = true
				break
		if not near:
			animal.queue_free()

func _spawn_anchors() -> Array[Vector2]:
	var anchors: Array[Vector2] = []
	if camera != null:
		anchors.append(camera.global_position)
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		anchors.append((node as Node2D).global_position)
	return anchors

func _keep_anchors() -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	if camera != null:
		anchors.append(Constants.world_to_grid(camera.global_position))
	for group: String in ["buildings", "units"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			anchors.append(Constants.world_to_grid((node as Node2D).global_position))
	return anchors

func _tile_dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
