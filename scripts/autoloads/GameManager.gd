# scripts/autoloads/GameManager.gd
extends Node

enum GameState { LOADING, RUNNING, PAUSED }

var state: GameState = GameState.LOADING
var map_width: int = 64
var map_height: int = 64
var map_seed: int = 0

func _ready() -> void:
	if map_seed == 0:
		map_seed = randi()

func change_state(new_state: GameState) -> void:
	state = new_state
	EventBus.game_state_changed.emit(GameState.keys()[new_state])
