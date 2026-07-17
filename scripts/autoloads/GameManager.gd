# scripts/autoloads/GameManager.gd
extends Node

enum GameState { LOADING, RUNNING, PAUSED, GAME_OVER }

# Which tribe this process controls. 0 offline; set from _match_config on
# multiplayer clients (before the world scene is built).
var local_player_id: int = 0

# How many tribes are in the current match (2-4). Set via reset_players().
var player_count: int = 2

var state: GameState = GameState.LOADING
var map_seed: int = 0
var _next_entity_id: int = 0

# The "How to Play" overlay auto-opens once per session; this flag (an
# autoload, so it survives scene reloads on restart) keeps it from reopening.
var help_seen: bool = false

# Set by ChunkManager once the world exists.
var world: WorldData = null
var pathfinder: Pathfinder = null
# Set by FogOfWar.setup().
var fog: FogOfWar = null

# Per-player resource stockpiles: player_id -> {ResourceType -> int}
var stockpiles: Array[Dictionary] = []

# Match-server only: per-tribe fog knowledge (index = player_id), refreshed
# by Replication. Empty everywhere else.
var player_visions: Array[PlayerVision] = []

# Has this tribe scouted the cell? Uses the server-side visions when they
# exist, the local fog renderer otherwise; defaults to yes so single-player
# behavior without fog stays permissive.
func has_explored(player_id: int, cell: Vector2i) -> bool:
	if player_id >= 0 and player_id < player_visions.size():
		return player_visions[player_id].is_explored(cell)
	if fog != null and player_id == local_player_id:
		return fog.is_explored(cell)
	return true

# Daily challenge: everyone plays the same UTC-dated map, racing to win.
var daily_mode: bool = false
var game_time_secs: float = 0.0

func _process(delta: float) -> void:
	if state == GameState.RUNNING:
		game_time_secs += delta

func daily_date() -> String:
	return Time.get_date_string_from_system(true)  # UTC — one map worldwide

const DAILY_PENDING_PATH: String = "user://daily_pending.json"

func stash_daily_result() -> void:
	var file: FileAccess = FileAccess.open(DAILY_PENDING_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"date": daily_date(), "seconds": game_time_secs}))

func take_pending_daily() -> Dictionary:
	if not FileAccess.file_exists(DAILY_PENDING_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DAILY_PENDING_PATH))
	return parsed if parsed is Dictionary else {}

func clear_pending_daily() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DAILY_PENDING_PATH))

func daily_seed(date: String = "") -> int:
	var key: String = "aoa-daily-" + (date if date != "" else daily_date())
	var h: int = key.hash()
	return h if h != 0 else 1

func _ready() -> void:
	if map_seed == 0:
		map_seed = randi()
	reset_players()

# Deterministic, authority-issued entity names ("U1", "B2", "A3"). Node names
# double as network ids once multiplayer replicates them.
func claim_entity_name(prefix: String) -> String:
	_next_entity_id += 1
	return "%s%d" % [prefix, _next_entity_id]

func reset_players(count: int = 2) -> void:
	player_count = count
	stockpiles.clear()
	for _i in range(player_count):
		stockpiles.append({
			Constants.ResourceType.FOOD: 100,
			Constants.ResourceType.WOOD: 50,
			Constants.ResourceType.JADE: 0,
		})

func get_resource(player_id: int, type: int) -> int:
	return stockpiles[player_id].get(type, 0)

func add_resource(player_id: int, type: int, amount: int) -> void:
	stockpiles[player_id][type] = get_resource(player_id, type) + amount
	EventBus.resources_changed.emit(player_id)
	_replicate_stockpile(player_id)

func can_afford(player_id: int, cost: Dictionary) -> bool:
	for type: int in cost:
		if get_resource(player_id, type) < cost[type]:
			return false
	return true

func spend(player_id: int, cost: Dictionary) -> bool:
	if not can_afford(player_id, cost):
		return false
	for type: int in cost:
		stockpiles[player_id][type] = get_resource(player_id, type) - cost[type]
	EventBus.resources_changed.emit(player_id)
	_replicate_stockpile(player_id)
	return true

func get_population(player_id: int) -> int:
	var tree: SceneTree = get_tree()
	return tree.get_nodes_in_group("player_%d" % player_id).filter(
		func(n: Node) -> bool: return n.is_in_group("units")
	).size()

# Base cap plus a bonus per FINISHED house, up to the ceiling.
func population_cap(player_id: int) -> int:
	var cap: int = Constants.POPULATION_CAP
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var building: Building = node as Building
		if building != null and building.player_id == player_id \
				and building.is_constructed:
			cap += Constants.BUILDING_DEFS[building.building_type].get("pop_bonus", 0)
	return mini(cap, Constants.POPULATION_CEILING)

func has_population_room(player_id: int) -> bool:
	return get_population(player_id) < population_cap(player_id)

# First cell near origin where this building may legally go — used by the
# build harnesses and the AI. Mirrors CommandRouter's placement validation.
func find_buildable_cell(origin: Vector2i, building_type: String, player_id: int) -> Vector2i:
	var footprint: Vector2i = Constants.BUILDING_DEFS[building_type]["footprint"]
	for radius in range(3, 10):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var base: Vector2i = origin + Vector2i(dx, dy)
				var ok: bool = true
				for fy in range(footprint.y):
					for fx in range(footprint.x):
						var cell: Vector2i = base + Vector2i(fx, fy)
						if not world.is_walkable(cell) \
								or world.building_at(cell) != null \
								or not world.get_resource_at(cell).is_empty() \
								or not has_explored(player_id, cell):
							ok = false
							break
					if not ok:
						break
				if ok:
					return base
	return Vector2i(9999, 9999)

# Difficulty of the forest AI for offline matches ("easy"/"normal"/"hard").
var ai_difficulty: String = "normal"

func change_state(new_state: GameState) -> void:
	state = new_state
	EventBus.game_state_changed.emit(GameState.keys()[new_state])

func end_game(winner_player_id: int) -> void:
	if state == GameState.GAME_OVER:
		return
	change_state(GameState.GAME_OVER)
	if daily_mode and winner_player_id == local_player_id \
			and Net.mode == Net.Mode.OFFLINE:
		stash_daily_result()
	EventBus.game_over.emit(winner_player_id)
	if Net.mode == Net.Mode.SERVER:
		_recv_game_over.rpc(winner_player_id)

# --- Multiplayer state replication (server -> clients) ---

# A player's stockpile replicates only to the peer who owns that tribe.
func _replicate_stockpile(player_id: int) -> void:
	if Net.mode != Net.Mode.SERVER:
		return
	for peer_id: int in Net.peer_players:
		if Net.peer_players[peer_id] == player_id:
			_recv_stockpile.rpc_id(peer_id, player_id, stockpiles[player_id])

# Full push for a freshly joined peer (called from Replication's snapshot).
func push_stockpile_to_peer(peer_id: int) -> void:
	var player_id: int = Net.peer_players.get(peer_id, -1)
	if player_id >= 0:
		_recv_stockpile.rpc_id(peer_id, player_id, stockpiles[player_id])

@rpc("authority", "call_remote", "reliable")
func _recv_stockpile(player_id: int, stockpile: Dictionary) -> void:
	stockpiles[player_id] = stockpile
	EventBus.resources_changed.emit(player_id)

@rpc("authority", "call_remote", "reliable")
func _recv_game_over(winner_player_id: int) -> void:
	if state == GameState.GAME_OVER:
		return
	change_state(GameState.GAME_OVER)
	EventBus.game_over.emit(winner_player_id)
