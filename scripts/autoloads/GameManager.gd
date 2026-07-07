# scripts/autoloads/GameManager.gd
extends Node

enum GameState { LOADING, RUNNING, PAUSED }

const LOCAL_PLAYER_ID: int = 0

var state: GameState = GameState.LOADING
var map_width: int = 64
var map_height: int = 64
var map_seed: int = 0

# Set by IsometricMap once the map is generated.
var map_generator: MapGenerator = null
var pathfinder: Pathfinder = null

func _ready() -> void:
	if map_seed == 0:
		map_seed = randi()

func change_state(new_state: GameState) -> void:
	state = new_state
	EventBus.game_state_changed.emit(GameState.keys()[new_state])
