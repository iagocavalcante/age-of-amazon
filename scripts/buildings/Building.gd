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

# Construction: sites spawn at a fraction of max hp and villagers hammer
# them up to full. Training and pop bonuses only apply once constructed.
var is_constructed: bool = true

# Training
var train_queue: Array[String] = []
var train_progress: float = 0.0

# Rally point: freshly trained units march here. INVALID_RALLY = none.
const INVALID_RALLY: Vector2i = Vector2i(-999999, -999999)
var rally_cell: Vector2i = INVALID_RALLY

# Monument endgame: seconds this constructed monument has stood. Reaching
# Constants.MONUMENT_VICTORY_SECS wins the game for its owner.
var monument_timer: float = 0.0

var _sprite: Sprite2D
var _health_bar: ProgressBar

# base_cell = top-left tile of the footprint.
func setup(p_type: String, p_player_id: int, base_cell: Vector2i,
		p_constructed: bool = true) -> void:
	building_type = p_type
	player_id = p_player_id
	is_constructed = p_constructed

	var def: Dictionary = Constants.BUILDING_DEFS[building_type]
	max_hp = def["max_hp"]
	current_hp = max_hp if is_constructed else maxi(1,
		int(max_hp * Constants.SITE_STARTING_HP_FRACTION))

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
	EventBus.entity_spawned.emit(self)
	# Presentation is client-side only; the headless server keeps _sprite and
	# _health_bar null and every visual path checks for that.
	if Net.is_headless_server():
		return
	_sprite = Sprite2D.new()
	_sprite.texture = AssetLibrary.get_building_texture(building_type, player_id)
	_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0 + 24.0)
	add_child(_sprite)
	_update_construction_look()

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
	# Training and the monument countdown are simulation — authority only.
	if not Net.is_authority():
		return
	if building_type == "monument" and is_constructed \
			and GameManager.state == GameManager.GameState.RUNNING:
		monument_timer += delta
		if monument_timer >= Constants.MONUMENT_VICTORY_SECS:
			GameManager.end_game(player_id)
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

# Returns false (and refunds nothing) when unaffordable, out of room, still
# under construction, or the wrong kind of building.
func queue_train(unit_type: String) -> bool:
	if not is_constructed:
		return false
	if not (unit_type in Constants.BUILDING_DEFS[building_type]["trains"]):
		return false
	var def: Dictionary = Constants.UNIT_DEFS[unit_type]
	var planned: int = GameManager.get_population(player_id) + train_queue.size()
	if planned >= GameManager.population_cap(player_id):
		return false
	if not GameManager.spend(player_id, def["cost"]):
		return false
	train_queue.append(unit_type)
	EventBus.training_queued.emit(self, unit_type)
	return true

# One builder swing (authority only). On a site, completion flips it to a
# real building — training unlocks and any pop bonus starts counting. On a
# damaged finished building this is a REPAIR: each swing costs 1 wood, so
# healing mid-fight drains the stockpile instead of being free.
func build_tick(amount: int) -> void:
	if current_hp >= max_hp:
		return
	if is_constructed and not GameManager.spend(player_id,
			{Constants.ResourceType.WOOD: 1}):
		return
	current_hp = mini(max_hp, current_hp + amount)
	_update_health_bar()
	if not is_constructed and current_hp >= max_hp:
		is_constructed = true
		_update_construction_look()
		EventBus.building_constructed.emit(self)
		EventBus.population_changed.emit(player_id)

func _update_construction_look() -> void:
	if _sprite == null:
		return
	# Sites read as translucent, earth-toned frames until finished.
	_sprite.self_modulate = Color.WHITE if is_constructed \
		else Color(0.9, 0.78, 0.6, 0.55)

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
	unit.name = GameManager.claim_entity_name("U")
	unit.unit_type = unit_type
	unit.player_id = player_id
	var cell: Vector2i = spot["cell"]
	unit.position = Constants.grid_to_world(cell.x, cell.y)
	containers[0].add_child(unit)
	if rally_cell != INVALID_RALLY:
		unit.move_to(Constants.grid_to_world(rally_cell.x, rally_cell.y))

func take_damage(amount: int, attacker: Node2D = null) -> void:
	current_hp = maxi(0, current_hp - amount)
	_update_health_bar()
	EventBus.building_damaged.emit(self, attacker)

	if _sprite != null:
		_sprite.modulate = Color(1.6, 1.1, 1.1)
		var tween: Tween = create_tween()
		tween.tween_property(_sprite, "modulate", Color.WHITE, HIT_FLASH_TIME)

	if current_hp <= 0:
		_die()

func _die() -> void:
	GameManager.world.vacate(footprint_cells)
	EventBus.building_destroyed.emit(self)
	# Last tribe with a town center standing wins. An eliminated tribe's
	# remaining units stay alive (accepted v1 simplification).
	if building_type == "town_center":
		var alive: Array[int] = []
		for node: Node in get_tree().get_nodes_in_group("buildings"):
			var other: Building = node as Building
			if other != null and other != self and other.building_type == "town_center" \
					and not alive.has(other.player_id):
				alive.append(other.player_id)
		if alive.size() == 1:
			GameManager.end_game(alive[0])
	queue_free()

# Multiplayer client: server state ticks land here (the building never
# simulates locally — _process is authority-gated).
func net_apply(hp: int, queue: Array, progress: float, constructed: bool,
		p_monument_timer: float = 0.0) -> void:
	monument_timer = p_monument_timer
	if hp != current_hp:
		if hp < current_hp:
			# Replicated damage: raise the same local signal the authority
			# raises, so under-attack alerts work on multiplayer clients.
			EventBus.building_damaged.emit(self, null)
		current_hp = hp
		_update_health_bar()
	if constructed != is_constructed:
		is_constructed = constructed
		_update_construction_look()
		EventBus.population_changed.emit(player_id)
	train_queue.assign(queue)
	train_progress = progress

func body_radius() -> float:
	return 44.0

func select() -> void:
	is_selected = true
	if _sprite != null:
		_sprite.modulate = Color(1.15, 1.15, 1.05)
	_update_health_bar()
	EventBus.building_selected.emit(self)

func deselect() -> void:
	is_selected = false
	if _sprite != null:
		_sprite.modulate = Color.WHITE
	_update_health_bar()

func _update_health_bar() -> void:
	if _health_bar == null:
		return
	_health_bar.value = current_hp
	_health_bar.visible = is_selected or current_hp < max_hp
