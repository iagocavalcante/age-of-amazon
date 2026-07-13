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

func has_population_room(player_id: int) -> bool:
	return get_population(player_id) < Constants.POPULATION_CAP

func change_state(new_state: GameState) -> void:
	state = new_state
	EventBus.game_state_changed.emit(GameState.keys()[new_state])

func end_game(winner_player_id: int) -> void:
	if state == GameState.GAME_OVER:
		return
	change_state(GameState.GAME_OVER)
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
