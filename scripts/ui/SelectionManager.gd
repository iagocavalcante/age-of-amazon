# scripts/ui/SelectionManager.gd
extends Node

var selected_units: Array[Node2D] = []
var is_box_selecting: bool = false
var box_start: Vector2 = Vector2.ZERO
var selection_rect: Rect2 = Rect2()

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

	if event is InputEventMouseMotion and is_box_selecting:
		_update_selection_box(event.position)

	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_start_selection(st.position)
		else:
			_end_selection(st.position)

func _start_selection(screen_pos: Vector2) -> void:
	box_start = screen_pos
	is_box_selecting = true

func _end_selection(screen_pos: Vector2) -> void:
	is_box_selecting = false
	var box_size := (screen_pos - box_start).abs()

	if box_size.length() < 10:
		_click_select(screen_pos)
	else:
		_box_select(box_start, screen_pos)

	selection_rect = Rect2()

func _click_select(screen_pos: Vector2) -> void:
	if not Input.is_key_pressed(KEY_SHIFT):
		_deselect_all()

	var world_pos := _screen_to_world(screen_pos)
	var closest_unit: Node2D = null
	var closest_dist := 20.0

	for unit in get_tree().get_nodes_in_group("units"):
		var dist := unit.global_position.distance_to(world_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest_unit = unit

	if closest_unit and closest_unit.has_method("select"):
		closest_unit.select()
		if closest_unit not in selected_units:
			selected_units.append(closest_unit)
	elif not Input.is_key_pressed(KEY_SHIFT):
		_deselect_all()

func _box_select(start: Vector2, end: Vector2) -> void:
	_deselect_all()

	var world_start := _screen_to_world(start)
	var world_end := _screen_to_world(end)
	var rect := Rect2(world_start, world_end - world_start).abs()

	for unit in get_tree().get_nodes_in_group("units"):
		if rect.has_point(unit.global_position):
			if unit.has_method("select"):
				unit.select()
				selected_units.append(unit)

func _command_move(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)

	for unit in selected_units:
		if unit.has_method("move_to"):
			unit.move_to(world_pos)

	EventBus.units_commanded_move.emit(selected_units, world_pos)

func _deselect_all() -> void:
	for unit in selected_units:
		if is_instance_valid(unit) and unit.has_method("deselect"):
			unit.deselect()
	selected_units.clear()
	EventBus.selection_cleared.emit()

func _update_selection_box(screen_pos: Vector2) -> void:
	selection_rect = Rect2(box_start, screen_pos - box_start).abs()

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return screen_pos
	var viewport_size := get_viewport().get_visible_rect().size
	var offset := screen_pos - viewport_size / 2.0
	return camera.global_position + offset / camera.zoom
