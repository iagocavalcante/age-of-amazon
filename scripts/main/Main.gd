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
		var spawn: Dictionary = iso_map.map_generator.spawn_zones[0]
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
		var offset_y := (i / 3) * 2
		var grid_x := cx + offset_x
		var grid_y := cy + offset_y

		unit.global_position = iso_map.grid_to_screen(grid_x, grid_y)
		add_child(unit)
