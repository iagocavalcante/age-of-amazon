# scripts/buildings/Building.gd
class_name Building
extends Node2D

# A placed building. Occupies footprint tiles in the world (blocking
# pathfinding), can take damage, and — for the Town Center — trains units
# and acts as the resource deposit point. Destroying a player's Town Center
# ends the game.

const HIT_FLASH_TIME: float = 0.18

var building_type: String = "town_center"
var player_id: int = 0
var max_hp: int = 600
var current_hp: int = 600
var footprint_cells: Array[Vector2i] = []
var is_selected: bool = false

# Training
var train_queue: Array[String] = []
var train_progress: float = 0.0

var _sprite: Sprite2D
var _health_bar: ProgressBar

# base_cell = top-left tile of the footprint.
func setup(p_type: String, p_player_id: int, base_cell: Vector2i) -> void:
	building_type = p_type
	player_id = p_player_id

	var def: Dictionary = Constants.BUILDING_DEFS[building_type]
	max_hp = def["max_hp"]
	current_hp = max_hp

	var footprint: Vector2i = def["footprint"]
	footprint_cells.clear()
	for dy in range(footprint.y):
		for dx in range(footprint.x):
			footprint_cells.append(base_cell + Vector2i(dx, dy))

	GameManager.world.occupy(footprint_cells, self)

	# y-sort origin at the south corner tile so units north of the building
	# draw behind it.
	var south: Vector2i = base_cell + footprint - Vector2i.ONE
	position = Constants.grid_to_world(south.x, south.y)

	add_to_group("buildings")
	add_to_group("player_%d" % player_id)

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = AssetLibrary.get_town_center_texture(player_id)
	_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0 + 24.0)
	add_child(_sprite)

	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.max_value = max_hp
	_health_bar.value = current_hp
	_health_bar.size = Vector2(64, 6)
	_health_bar.position = Vector2(-32, -_sprite.texture.get_height() + 16.0)
	_health_bar.add_theme_stylebox_override("background", AssetLibrary.health_bar_bg)
	_health_bar.add_theme_stylebox_override("fill", AssetLibrary.health_bar_fill)
	add_child(_health_bar)
	_update_health_bar()

func _process(delta: float) -> void:
	if train_queue.is_empty():
		return
	train_progress += delta
	var unit_type: String = train_queue[0]
	var train_time: float = Constants.UNIT_DEFS[unit_type]["train_time"]
	if train_progress >= train_time:
		# Hold a finished unit until there's population room.
		if GameManager.has_population_room(player_id):
			train_progress = 0.0
			train_queue.pop_front()
			_spawn_unit(unit_type)
			EventBus.training_completed.emit(self, unit_type)

# Returns false (and refunds nothing) when unaffordable or out of room.
func queue_train(unit_type: String) -> bool:
	var def: Dictionary = Constants.UNIT_DEFS[unit_type]
	var planned: int = GameManager.get_population(player_id) + train_queue.size()
	if planned >= Constants.POPULATION_CAP:
		return false
	if not GameManager.spend(player_id, def["cost"]):
		return false
	train_queue.append(unit_type)
	EventBus.training_queued.emit(self, unit_type)
	return true

func _spawn_unit(unit_type: String) -> void:
	var spot: Dictionary = GameManager.pathfinder.adjacent_walkable(
		footprint_cells, footprint_cells[footprint_cells.size() - 1] + Vector2i(1, 1))
	if not spot["found"]:
		return

	var containers: Array = get_tree().get_nodes_in_group("unit_container")
	if containers.is_empty():
		return

	var unit_scene: PackedScene = load("res://scenes/units/Unit.tscn")
	var unit: UnitBase = unit_scene.instantiate() as UnitBase
	unit.unit_type = unit_type
	unit.player_id = player_id
	var cell: Vector2i = spot["cell"]
	unit.position = Constants.grid_to_world(cell.x, cell.y)
	containers[0].add_child(unit)

func take_damage(amount: int, _attacker: Node2D = null) -> void:
	current_hp = maxi(0, current_hp - amount)
	_update_health_bar()

	_sprite.modulate = Color(1.6, 1.1, 1.1)
	var tween: Tween = create_tween()
	tween.tween_property(_sprite, "modulate", Color.WHITE, HIT_FLASH_TIME)

	if current_hp <= 0:
		_die()

func _die() -> void:
	GameManager.world.vacate(footprint_cells)
	EventBus.building_destroyed.emit(self)
	if building_type == "town_center":
		var winner: int = 1 - player_id
		GameManager.end_game(winner)
	queue_free()

func body_radius() -> float:
	return 44.0

func select() -> void:
	is_selected = true
	_sprite.modulate = Color(1.15, 1.15, 1.05)
	_update_health_bar()
	EventBus.building_selected.emit(self)

func deselect() -> void:
	is_selected = false
	_sprite.modulate = Color.WHITE
	_update_health_bar()

func _update_health_bar() -> void:
	_health_bar.value = current_hp
	_health_bar.visible = is_selected or current_hp < max_hp
