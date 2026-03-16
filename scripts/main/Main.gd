# scripts/main/Main.gd
extends Node2D

@onready var iso_map := $IsometricMap
@onready var camera: Camera2D = $GameCamera

var unit_scene: PackedScene = preload("res://scenes/units/Unit.tscn")

func _ready() -> void:
	EventBus.map_generated.connect(_on_map_generated)
	GameManager.change_state(GameManager.GameState.RUNNING)

func _on_map_generated(_w: int, _h: int) -> void:
	# Center camera on player spawn
	if iso_map.map_generator.spawn_zones.size() > 0:
		var spawn: Dictionary = iso_map.map_generator.spawn_zones[0]
		var screen_pos: Vector2 = iso_map.grid_to_screen(spawn["cx"], spawn["cy"])
		camera.center_on(screen_pos)

		# Spawn 3 villagers for each player
		for zone: Dictionary in iso_map.map_generator.spawn_zones:
			_spawn_villagers(zone, 3)

func _spawn_villagers(zone: Dictionary, count: int) -> void:
	var cx: int = zone["cx"]
	var cy: int = zone["cy"]
	var pid: int = zone["player_id"]

	for i in range(count):
		var unit: CharacterBody2D = unit_scene.instantiate() as CharacterBody2D
		unit.set("player_id", pid)
		unit.set("unit_name", "Villager")

		# Offset each unit slightly
		var offset_x: int = (i % 3 - 1) * 2
		var offset_y: int = (i / 3) * 2
		var grid_x: int = cx + offset_x
		var grid_y: int = cy + offset_y

		unit.global_position = iso_map.grid_to_screen(grid_x, grid_y) as Vector2
		add_child(unit)
