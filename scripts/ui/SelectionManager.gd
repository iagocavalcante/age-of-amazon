# scripts/ui/SelectionManager.gd
extends Node

const CLICK_MAX_DRAG: float = 10.0
const CLICK_PICK_RADIUS: float = 24.0

var selected_units: Array[Node2D] = []
var selected_building: Node2D = null
var is_box_selecting: bool = false
var box_start: Vector2 = Vector2.ZERO
var selection_rect: Rect2 = Rect2()

# Building placement mode: HUD calls start_placement(); a ghost snaps to the
# grid under the cursor until the player confirms (left) or cancels (right).
var placing_type: String = ""
var _ghost: Sprite2D = null

# Touch tracking: taps select, drags are camera pans (handled by GameCamera).
var _touch_start: Dictionary = {}
var _touch_moved: Dictionary = {}
var _multi_touch: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if placing_type != "":
		_placement_input(event)
		return

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
	if building != null and building.get("player_id") == GameManager.local_player_id:
		selected_building = building
		if building.has_method("select"):
			building.select()
	EventBus.selection_changed.emit()

func _pick_own_unit(screen_pos: Vector2) -> Node2D:
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var closest_unit: Node2D = null
	var closest_dist: float = CLICK_PICK_RADIUS

	for node: Node in get_tree().get_nodes_in_group("player_%d" % GameManager.local_player_id):
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

	# Enemy unit or huntable animal near the click. Fog-hidden targets can't be
	# picked (a neutral animal is never the local player's, so it's always fair
	# game once visible).
	var closest: Node2D = null
	var closest_dist: float = CLICK_PICK_RADIUS
	for group: String in ["units", "animals"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var target: Node2D = node as Node2D
			if target == null or not target.visible:
				continue
			if group == "units" and target.get("player_id") == GameManager.local_player_id:
				continue
			var dist: float = target.global_position.distance_to(world_pos)
			if dist < closest_dist:
				closest_dist = dist
				closest = target
	if closest != null:
		return closest

	# Enemy building on the clicked tile? (only if remembered/visible)
	var building: Node2D = GameManager.world.building_at(Constants.world_to_grid(world_pos))
	if building != null and building.get("player_id") != GameManager.local_player_id and building.visible:
		return building
	return null

func _box_select(start: Vector2, end: Vector2) -> void:
	if not Input.is_key_pressed(KEY_SHIFT):
		_deselect_all()

	var world_start: Vector2 = _screen_to_world(start)
	var world_end: Vector2 = _screen_to_world(end)
	var rect: Rect2 = Rect2(world_start, world_end - world_start).abs()

	for node: Node in get_tree().get_nodes_in_group("player_%d" % GameManager.local_player_id):
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
# Selection is purely local; only the resulting ORDER goes through the
# CommandRouter (which is the multiplayer seam).
func _command_at(screen_pos: Vector2) -> void:
	# filter() returns an untyped Array; assign() converts it back into the
	# typed Array[Node2D] (a plain `=` would fail at runtime).
	selected_units.assign(selected_units.filter(is_instance_valid))
	if selected_units.is_empty():
		return

	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var names: Array = selected_units.map(
		func(u: Node2D) -> String: return String(u.name))

	# A friendly site or damaged building under the cursor: build / repair.
	var site: Building = GameManager.world.building_at(
		Constants.world_to_grid(world_pos)) as Building
	if site != null and site.player_id == GameManager.local_player_id \
			and site.current_hp < site.max_hp:
		CommandRouter.submit({
			"type": "build", "player_id": GameManager.local_player_id,
			"actor_names": names, "building_name": String(site.name),
		})
		return

	var enemy: Node2D = _pick_enemy(screen_pos)
	if enemy != null:
		CommandRouter.submit({
			"type": "attack", "player_id": GameManager.local_player_id,
			"actor_names": names, "target_name": String(enemy.name),
		})
		return

	var cell: Vector2i = Constants.world_to_grid(world_pos)
	if not GameManager.world.get_resource_at(cell).is_empty():
		CommandRouter.submit({
			"type": "gather", "player_id": GameManager.local_player_id,
			"actor_names": names, "cell": cell,
		})
		return

	CommandRouter.submit({
		"type": "move", "player_id": GameManager.local_player_id,
		"actor_names": names, "target": world_pos,
	})
	EventBus.units_commanded_move.emit(selected_units, world_pos)

# --- Building placement ---

func start_placement(building_type: String) -> void:
	cancel_placement()
	placing_type = building_type
	_ghost = Sprite2D.new()
	_ghost.texture = AssetLibrary.get_building_texture(
		building_type, GameManager.local_player_id)
	_ghost.offset = Vector2(0, -_ghost.texture.get_height() / 2.0 + 24.0)
	_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ghost.z_index = 100
	get_tree().current_scene.add_child(_ghost)
	_update_ghost(get_viewport().get_mouse_position())

func cancel_placement() -> void:
	placing_type = ""
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null

func _placement_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cancel_placement()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_update_ghost((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_confirm_placement(mb.position)
			get_viewport().set_input_as_handled()

func _base_cell_at(screen_pos: Vector2) -> Vector2i:
	return Constants.world_to_grid(_screen_to_world(screen_pos))

func _placement_valid(base_cell: Vector2i) -> bool:
	var def: Dictionary = Constants.BUILDING_DEFS[placing_type]
	if not GameManager.can_afford(GameManager.local_player_id, def["cost"]):
		return false
	var footprint: Vector2i = def["footprint"]
	for dy in range(footprint.y):
		for dx in range(footprint.x):
			var cell: Vector2i = base_cell + Vector2i(dx, dy)
			if not GameManager.world.is_walkable(cell):
				return false
			if GameManager.world.building_at(cell) != null:
				return false
			if not GameManager.world.get_resource_at(cell).is_empty():
				return false
			if GameManager.fog != null and not GameManager.fog.is_explored(cell):
				return false
	return true

func _update_ghost(screen_pos: Vector2) -> void:
	if _ghost == null:
		return
	var base_cell: Vector2i = _base_cell_at(screen_pos)
	var footprint: Vector2i = Constants.BUILDING_DEFS[placing_type]["footprint"]
	var south: Vector2i = base_cell + footprint - Vector2i.ONE
	_ghost.position = Constants.grid_to_world(south.x, south.y)
	_ghost.modulate = Color(0.55, 1.0, 0.55, 0.65) if _placement_valid(base_cell) \
		else Color(1.0, 0.45, 0.45, 0.55)

func _confirm_placement(screen_pos: Vector2) -> void:
	var base_cell: Vector2i = _base_cell_at(screen_pos)
	if not _placement_valid(base_cell):
		return
	var builders: Array = selected_units.filter(is_instance_valid).filter(
		func(u: Node2D) -> bool: return u.get("can_gather"))
	CommandRouter.submit({
		"type": "place", "player_id": GameManager.local_player_id,
		"building_type": placing_type, "cell": base_cell,
		"actor_names": builders.map(func(u: Node2D) -> String: return String(u.name)),
	})
	cancel_placement()

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
