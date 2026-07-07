# scripts/ui/SelectionManager.gd
extends Node

const CLICK_MAX_DRAG: float = 10.0
const CLICK_PICK_RADIUS: float = 24.0

var selected_units: Array[Node2D] = []
var is_box_selecting: bool = false
var box_start: Vector2 = Vector2.ZERO
var selection_rect: Rect2 = Rect2()

# Touch tracking: taps select, drags are camera pans (handled by GameCamera).
var _touch_start: Dictionary = {}  # index -> start position
var _touch_moved: Dictionary = {}  # index -> true once dragged past threshold
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
				_command_move(mb.position)

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

# Tap: select own unit under finger, or command a move if units are selected.
func _handle_tap(screen_pos: Vector2) -> void:
	var unit: Node2D = _pick_unit(screen_pos)
	if unit != null:
		_deselect_all()
		_select_unit(unit)
	elif selected_units.size() > 0:
		_command_move(screen_pos)
	else:
		_deselect_all()

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

	var unit: Node2D = _pick_unit(screen_pos)
	if unit != null:
		_select_unit(unit)

func _pick_unit(screen_pos: Vector2) -> Node2D:
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var closest_unit: Node2D = null
	var closest_dist: float = CLICK_PICK_RADIUS

	for node: Node in get_tree().get_nodes_in_group("player_%d" % GameManager.LOCAL_PLAYER_ID):
		var unit: Node2D = node as Node2D
		if unit == null:
			continue
		var dist: float = unit.global_position.distance_to(world_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest_unit = unit

	return closest_unit

func _box_select(start: Vector2, end: Vector2) -> void:
	if not Input.is_key_pressed(KEY_SHIFT):
		_deselect_all()

	var world_start: Vector2 = _screen_to_world(start)
	var world_end: Vector2 = _screen_to_world(end)
	var rect: Rect2 = Rect2(world_start, world_end - world_start).abs()

	for node: Node in get_tree().get_nodes_in_group("player_%d" % GameManager.LOCAL_PLAYER_ID):
		var unit: Node2D = node as Node2D
		if unit == null:
			continue
		if rect.has_point(unit.global_position):
			_select_unit(unit)

func _select_unit(unit: Node2D) -> void:
	if unit in selected_units:
		return
	if unit.has_method("select"):
		unit.select()
	selected_units.append(unit)

func _command_move(screen_pos: Vector2) -> void:
	# filter() returns an untyped Array; assign() converts it back into the
	# typed Array[Node2D] (a plain `=` would fail at runtime).
	selected_units.assign(selected_units.filter(is_instance_valid))
	if selected_units.is_empty():
		return

	var world_pos: Vector2 = _screen_to_world(screen_pos)

	# Fan the group out over distinct walkable cells so units don't stack.
	var cells: Array[Vector2i] = []
	if GameManager.pathfinder != null:
		cells = GameManager.pathfinder.formation_cells(world_pos, selected_units.size())

	for i in range(selected_units.size()):
		var unit: Node2D = selected_units[i]
		if not unit.has_method("move_to"):
			continue
		var target: Vector2 = world_pos
		if i < cells.size():
			target = Constants.grid_to_world(cells[i].x, cells[i].y)
		unit.move_to(target)

	EventBus.units_commanded_move.emit(selected_units, world_pos)

func _deselect_all() -> void:
	for unit: Node2D in selected_units:
		if is_instance_valid(unit) and unit.has_method("deselect"):
			unit.deselect()
	selected_units.clear()
	EventBus.selection_cleared.emit()

func _update_selection_box(screen_pos: Vector2) -> void:
	selection_rect = Rect2(box_start, screen_pos - box_start).abs()

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	# The canvas transform already accounts for camera position, zoom and
	# offset — unlike the previous hand-rolled math, which broke under drag.
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos
