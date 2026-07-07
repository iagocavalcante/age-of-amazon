# scripts/ui/SelectionManager.gd
extends Node

const CLICK_MAX_DRAG: float = 10.0
const CLICK_PICK_RADIUS: float = 24.0

var selected_units: Array[Node2D] = []
var selected_building: Node2D = null
var is_box_selecting: bool = false
var box_start: Vector2 = Vector2.ZERO
var selection_rect: Rect2 = Rect2()

# Touch tracking: taps select, drags are camera pans (handled by GameCamera).
var _touch_start: Dictionary = {}
var _touch_moved: Dictionary = {}
var _multi_touch: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_start_selection(mb.position)
			else:
				_end_selection(mb.position)

		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if selected_units.size() > 0:
				_command_at(mb.position)

	elif event is InputEventMouseMotion and is_box_selecting:
		var mm := event as InputEventMouseMotion
		_update_selection_box(mm.position)

	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touch_start[st.index] = st.position
			_touch_moved[st.index] = false
			if _touch_start.size() > 1:
				_multi_touch = true
		else:
			var was_tap: bool = _touch_start.has(st.index) \
				and not _touch_moved.get(st.index, true) \
				and not _multi_touch
			_touch_start.erase(st.index)
			_touch_moved.erase(st.index)
			if _touch_start.is_empty():
				_multi_touch = false
			if was_tap:
				_handle_tap(st.position)

	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _touch_start.has(sd.index):
			var start: Vector2 = _touch_start[sd.index]
			if sd.position.distance_to(start) > CLICK_MAX_DRAG:
				_touch_moved[sd.index] = true

# Tap: select own unit/building under finger, else command if selected.
func _handle_tap(screen_pos: Vector2) -> void:
	var unit: Node2D = _pick_own_unit(screen_pos)
	if unit != null:
		_deselect_all()
		_select_unit(unit)
	elif selected_units.size() > 0:
		_command_at(screen_pos)
	else:
		_left_pick_building(screen_pos)

func _start_selection(screen_pos: Vector2) -> void:
	box_start = screen_pos
	is_box_selecting = true

func _end_selection(screen_pos: Vector2) -> void:
	if not is_box_selecting:
		return
	is_box_selecting = false

	if screen_pos.distance_to(box_start) < CLICK_MAX_DRAG:
		_click_select(screen_pos)
	else:
		_box_select(box_start, screen_pos)

	selection_rect = Rect2()

func _click_select(screen_pos: Vector2) -> void:
	var additive: bool = Input.is_key_pressed(KEY_SHIFT)
	if not additive:
		_deselect_all()

	var unit: Node2D = _pick_own_unit(screen_pos)
	if unit != null:
		_select_unit(unit)
	elif not additive:
		_left_pick_building(screen_pos)

func _left_pick_building(screen_pos: Vector2) -> void:
	if GameManager.world == null:
		return
	var cell: Vector2i = Constants.world_to_grid(_screen_to_world(screen_pos))
	var building: Node2D = GameManager.world.building_at(cell)
	if building != null and building.get("player_id") == GameManager.LOCAL_PLAYER_ID:
		selected_building = building
		if building.has_method("select"):
			building.select()
	EventBus.selection_changed.emit()

func _pick_own_unit(screen_pos: Vector2) -> Node2D:
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var closest_unit: Node2D = null
	var closest_dist: float = CLICK_PICK_RADIUS

	for node: Node in get_tree().get_nodes_in_group("player_%d" % GameManager.LOCAL_PLAYER_ID):
		var unit: Node2D = node as Node2D
		if unit == null or not unit.is_in_group("units"):
			continue
		var dist: float = unit.global_position.distance_to(world_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest_unit = unit

	return closest_unit

func _pick_enemy(screen_pos: Vector2) -> Node2D:
	var world_pos: Vector2 = _screen_to_world(screen_pos)

	# Enemy unit near the click?
	var closest: Node2D = null
	var closest_dist: float = CLICK_PICK_RADIUS
	for node: Node in get_tree().get_nodes_in_group("units"):
		var unit: Node2D = node as Node2D
		if unit == null or unit.get("player_id") == GameManager.LOCAL_PLAYER_ID:
			continue
		var dist: float = unit.global_position.distance_to(world_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = unit
	if closest != null:
		return closest

	# Enemy building on the clicked tile?
	var building: Node2D = GameManager.world.building_at(Constants.world_to_grid(world_pos))
	if building != null and building.get("player_id") != GameManager.LOCAL_PLAYER_ID:
		return building
	return null

func _box_select(start: Vector2, end: Vector2) -> void:
	if not Input.is_key_pressed(KEY_SHIFT):
		_deselect_all()

	var world_start: Vector2 = _screen_to_world(start)
	var world_end: Vector2 = _screen_to_world(end)
	var rect: Rect2 = Rect2(world_start, world_end - world_start).abs()

	for node: Node in get_tree().get_nodes_in_group("player_%d" % GameManager.LOCAL_PLAYER_ID):
		var unit: Node2D = node as Node2D
		if unit == null or not unit.is_in_group("units"):
			continue
		if rect.has_point(unit.global_position):
			_select_unit(unit)

func _select_unit(unit: Node2D) -> void:
	if unit in selected_units:
		return
	if unit.has_method("select"):
		unit.select()
	selected_units.append(unit)
	EventBus.selection_changed.emit()

# Right-click / command tap: attack enemies, gather resources, else move.
func _command_at(screen_pos: Vector2) -> void:
	# filter() returns an untyped Array; assign() converts it back into the
	# typed Array[Node2D] (a plain `=` would fail at runtime).
	selected_units.assign(selected_units.filter(is_instance_valid))
	if selected_units.is_empty():
		return

	var world_pos: Vector2 = _screen_to_world(screen_pos)

	var enemy: Node2D = _pick_enemy(screen_pos)
	if enemy != null:
		for unit: Node2D in selected_units:
			if unit.has_method("command_attack"):
				unit.command_attack(enemy)
		return

	var cell: Vector2i = Constants.world_to_grid(world_pos)
	if not GameManager.world.get_resource_at(cell).is_empty():
		var movers: Array[Node2D] = []
		for unit: Node2D in selected_units:
			if unit.get("can_gather") and unit.has_method("command_gather"):
				unit.command_gather(cell)
			else:
				movers.append(unit)
		if movers.is_empty():
			return
		_move_in_formation(movers, world_pos)
		return

	_move_in_formation(selected_units, world_pos)
	EventBus.units_commanded_move.emit(selected_units, world_pos)

func _move_in_formation(units: Array[Node2D], world_pos: Vector2) -> void:
	var cells: Array[Vector2i] = []
	if GameManager.pathfinder != null:
		cells = GameManager.pathfinder.formation_cells(world_pos, units.size())

	for i in range(units.size()):
		var unit: Node2D = units[i]
		if not unit.has_method("move_to"):
			continue
		var target: Vector2 = world_pos
		if i < cells.size():
			target = Constants.grid_to_world(cells[i].x, cells[i].y)
		unit.move_to(target)

func clear_selection() -> void:
	_deselect_all()

func _deselect_all() -> void:
	for unit: Node2D in selected_units:
		if is_instance_valid(unit) and unit.has_method("deselect"):
			unit.deselect()
	selected_units.clear()
	if selected_building != null and is_instance_valid(selected_building):
		if selected_building.has_method("deselect"):
			selected_building.deselect()
	selected_building = null
	EventBus.selection_cleared.emit()
	EventBus.selection_changed.emit()

func _update_selection_box(screen_pos: Vector2) -> void:
	selection_rect = Rect2(box_start, screen_pos - box_start).abs()

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos
