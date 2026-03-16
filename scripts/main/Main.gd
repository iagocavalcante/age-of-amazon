# scripts/main/Main.gd
extends Node2D

@onready var iso_map: Node2D = $IsometricMap
@onready var camera: Camera2D = $GameCamera

func _ready() -> void:
	EventBus.map_generated.connect(_on_map_generated)
	GameManager.change_state(GameManager.GameState.RUNNING)

func _on_map_generated(_w: int, _h: int) -> void:
	if iso_map.map_generator.spawn_zones.size() > 0:
		var spawn: Dictionary = iso_map.map_generator.spawn_zones[0]
		var screen_pos := iso_map.grid_to_screen(spawn["cx"], spawn["cy"])
		camera.center_on(screen_pos)
