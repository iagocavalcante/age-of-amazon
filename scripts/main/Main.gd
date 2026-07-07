# scripts/main/Main.gd
extends Node2D

@onready var iso_map: Node2D = $IsometricMap
@onready var camera: Camera2D = $GameCamera
@onready var doodads: Node2D = $World/Doodads
@onready var units: Node2D = $World/Units

var unit_scene: PackedScene = preload("res://scenes/units/Unit.tscn")

func _ready() -> void:
	# Generation is triggered here — after every child (camera included) has
	# run _ready and connected its signals — so map_generated can't be missed.
	iso_map.generate()
	iso_map.populate_doodads(doodads)

	var spawn_zones: Array = iso_map.map_generator.spawn_zones
	if spawn_zones.size() > 0:
		var spawn: Dictionary = spawn_zones[0]
		camera.center_on(Constants.grid_to_world(spawn["cx"], spawn["cy"]))

	for zone: Dictionary in spawn_zones:
		_spawn_villagers(zone, 3)

	GameManager.change_state(GameManager.GameState.RUNNING)

	if "--test-move" in OS.get_cmdline_user_args():
		_run_move_test()

# Verification harness (run with `++ --test-move`): selects all player-0
# units and issues a move command through the real SelectionManager pipeline.
func _run_move_test() -> void:
	await get_tree().create_timer(0.5).timeout
	var spawn: Dictionary = iso_map.map_generator.spawn_zones[0]
	var target_world: Vector2 = Constants.grid_to_world(spawn["cx"] + 8, spawn["cy"] + 8)
	var target_screen: Vector2 = get_viewport().get_canvas_transform() * target_world
	var test_units: Array = get_tree().get_nodes_in_group("player_0")
	print("[test-move] commanding ", test_units.size(), " units via SelectionManager to ", target_world)
	for u: Node2D in test_units:
		print("[test-move] unit start: ", u.global_position)
		SelectionManager.selected_units.assign(test_units)
	SelectionManager._command_move(target_screen)
	await get_tree().create_timer(3.0).timeout
	for u: Node2D in test_units:
		print("[test-move] unit after 3s: ", u.global_position, " state=", u.current_state)

func _spawn_villagers(zone: Dictionary, count: int) -> void:
	var cx: int = zone["cx"]
	var cy: int = zone["cy"]
	var pid: int = zone["player_id"]

	for i in range(count):
		var unit: CharacterBody2D = unit_scene.instantiate() as CharacterBody2D
		unit.set("player_id", pid)
		unit.set("unit_name", "Villager")

		var offset_x: int = (i % 3 - 1) * 2
		var offset_y: int = int(i / 3.0) * 2
		var cell: Vector2i = Vector2i(cx + offset_x, cy + offset_y)
		unit.position = Constants.grid_to_world(cell.x, cell.y)
		units.add_child(unit)
