# scripts/autoloads/GameManager.gd
extends Node

enum GameState { LOADING, RUNNING, PAUSED, GAME_OVER }

const LOCAL_PLAYER_ID: int = 0
const PLAYER_COUNT: int = 2

var state: GameState = GameState.LOADING
var map_seed: int = 0

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

func _ready() -> void:
	if map_seed == 0:
		map_seed = randi()
	reset_players()

func reset_players() -> void:
	stockpiles.clear()
	for _i in range(PLAYER_COUNT):
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
