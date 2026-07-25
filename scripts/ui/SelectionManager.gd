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
var _footprint_overlay: Node2D = null

# Attack-move arming: the HUD button arms it; the next click on the map is
# the destination (shift+right-click stays as the power-user shortcut).
var attack_move_armed: bool = false

# Touch tracking: taps select, drags are camera pans (handled by GameCamera).
var _touch_start: Dictionary = {}
var _touch_moved: Dictionary = {}
var _multi_touch: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if placing_type != "":
		_placement_input(event)
		return

	if attack_move_armed:
		if event is InputEventKey and (event as InputEventKey).pressed \
				and (event as InputEventKey).keycode == KEY_ESCAPE:
			disarm_attack_move()
			return
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			var amb := event as InputEventMouseButton
			if amb.button_index == MOUSE_BUTTON_LEFT:
				_attack_move_at(amb.position)
			disarm_attack_move()
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
			elif selected_building != null and is_instance_valid(selected_building) \
					and selected_building.get("player_id") == GameManager.local_player_id:
				_set_rally(mb.position)

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

	# Shift + right-click: attack-move — march there, engaging on the way.
	if Input.is_key_pressed(KEY_SHIFT):
		_attack_move_at(screen_pos)
		return

	# A friendly site or damaged building under the cursor: build / repair.
	var site: Building = GameManager.world.building_at(
		Constants.world_to_grid(world_pos)) as Building
	if site != null and site.player_id == GameManager.local_player_id \
			and site.current_hp < site.max_hp:
		CommandRouter.submit({
			"type": "build", "player_id": GameManager.local_player_id,
			"actor_names": names, "building_name": String(site.name),
		})
		_spawn_order_marker(site.global_position, "repair")
		return

	var enemy: Node2D = _pick_enemy(screen_pos)
	if enemy != null:
		CommandRouter.submit({
			"type": "attack", "player_id": GameManager.local_player_id,
			"actor_names": names, "target_name": String(enemy.name),
		})
		_spawn_order_marker(enemy.global_position, "attack")
		return

	var cell: Vector2i = Constants.world_to_grid(world_pos)
	if not GameManager.world.get_resource_at(cell).is_empty():
		CommandRouter.submit({
			"type": "gather", "player_id": GameManager.local_player_id,
			"actor_names": names, "cell": cell,
		})
		_spawn_order_marker(Constants.grid_to_world(cell.x, cell.y), "gather")
		return

	CommandRouter.submit({
		"type": "move", "player_id": GameManager.local_player_id,
		"actor_names": names, "target": world_pos,
	})
	EventBus.units_commanded_move.emit(selected_units, world_pos)
	_spawn_order_marker(world_pos, "move")

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
	_build_footprint_overlay()
	_update_ghost(get_viewport().get_mouse_position())

func cancel_placement() -> void:
	placing_type = ""
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	if _footprint_overlay != null and is_instance_valid(_footprint_overlay):
		_footprint_overlay.queue_free()
	_footprint_overlay = null

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
	return _placement_error(base_cell).is_empty()

func _placement_error(base_cell: Vector2i) -> String:
	var def: Dictionary = Constants.BUILDING_DEFS[placing_type]
	if not GameManager.can_afford(GameManager.local_player_id, def["cost"]):
		return "Need more resources"
	var footprint: Vector2i = def["footprint"]
	for dy in range(footprint.y):
		for dx in range(footprint.x):
			var cell: Vector2i = base_cell + Vector2i(dx, dy)
			# Do not reveal terrain properties through unexplored fog.
			if GameManager.fog != null and not GameManager.fog.is_explored(cell):
				return "Explore this ground first"
			if GameManager.world.building_at(cell) != null:
				return "Another building occupies this space"
			if not GameManager.world.get_resource_at(cell).is_empty():
				return "Clear the resource first"
			if not GameManager.world.is_buildable(cell):
				return "Cannot build on this terrain"
	if def.get("requires_adjacent_water", false) \
			and not GameManager.world.footprint_touches_water(base_cell, footprint):
		return "Dock must touch the shoreline"
	return ""

func _update_ghost(screen_pos: Vector2) -> void:
	if _ghost == null:
		return
	var base_cell: Vector2i = _base_cell_at(screen_pos)
	var footprint: Vector2i = Constants.BUILDING_DEFS[placing_type]["footprint"]
	var south: Vector2i = base_cell + footprint - Vector2i.ONE
	_ghost.position = Constants.grid_to_world(south.x, south.y)
	var valid: bool = _placement_valid(base_cell)
	_ghost.modulate = Color(0.55, 1.0, 0.55, 0.65) if valid \
		else Color(1.0, 0.45, 0.45, 0.55)
	_update_footprint_overlay(base_cell, valid)

func _confirm_placement(screen_pos: Vector2) -> void:
	var base_cell: Vector2i = _base_cell_at(screen_pos)
	var error: String = _placement_error(base_cell)
	if not error.is_empty():
		WorkFx.float_text(get_tree().current_scene,
			Constants.grid_to_world(base_cell.x, base_cell.y),
			error, Color(1.0, 0.45, 0.36))
		_spawn_order_marker(
			Constants.grid_to_world(base_cell.x, base_cell.y), "invalid")
		return
	var builders: Array = selected_units.filter(is_instance_valid).filter(
		func(u: Node2D) -> bool: return u.get("can_gather"))
	CommandRouter.submit({
		"type": "place", "player_id": GameManager.local_player_id,
		"building_type": placing_type, "cell": base_cell,
		"actor_names": builders.map(func(u: Node2D) -> String: return String(u.name)),
	})
	_spawn_order_marker(
		Constants.grid_to_world(base_cell.x, base_cell.y), "build")
	cancel_placement()

func _set_rally(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var cell: Vector2i = Constants.world_to_grid(world_pos)
	CommandRouter.submit({
		"type": "rally", "player_id": GameManager.local_player_id,
		"building_name": String(selected_building.name), "cell": cell,
	})
	WorkFx.float_text(get_tree().current_scene,
		Constants.grid_to_world(cell.x, cell.y), "rally point", Color(0.6, 0.95, 0.75))
	_spawn_order_marker(Constants.grid_to_world(cell.x, cell.y), "rally")

func _attack_move_at(screen_pos: Vector2) -> void:
	selected_units.assign(selected_units.filter(is_instance_valid))
	if selected_units.is_empty():
		return
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	CommandRouter.submit({
		"type": "attack_move", "player_id": GameManager.local_player_id,
		"actor_names": selected_units.map(
			func(u: Node2D) -> String: return String(u.name)),
		"target": world_pos,
	})
	EventBus.units_commanded_move.emit(selected_units, world_pos)
	_spawn_order_marker(world_pos, "attack_move")

func arm_attack_move() -> void:
	if selected_units.filter(is_instance_valid).is_empty():
		return
	attack_move_armed = true
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)

func disarm_attack_move() -> void:
	attack_move_armed = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func select_only(unit: Node2D) -> void:
	_deselect_all()
	_select_unit(unit)

func clear_selection() -> void:
	_deselect_all()
	disarm_attack_move()

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

func _build_footprint_overlay() -> void:
	_footprint_overlay = Node2D.new()
	_footprint_overlay.name = "PlacementFootprint"
	# Keep the cell grid above the translucent building ghost so its internal
	# divisions and invalid X marks remain readable at a glance.
	_footprint_overlay.z_index = 102
	get_tree().current_scene.add_child(_footprint_overlay)
	var footprint: Vector2i = Constants.BUILDING_DEFS[placing_type]["footprint"]
	for _dy in range(footprint.y):
		for _dx in range(footprint.x):
			var tile: Node2D = Node2D.new()
			var fill: Polygon2D = Polygon2D.new()
			fill.polygon = PackedVector2Array([
				Vector2(0, -14), Vector2(29, 0),
				Vector2(0, 14), Vector2(-29, 0),
			])
			tile.add_child(fill)
			var outline: Line2D = Line2D.new()
			outline.points = PackedVector2Array([
				Vector2(0, -14), Vector2(29, 0), Vector2(0, 14),
				Vector2(-29, 0), Vector2(0, -14),
			])
			outline.width = 1.5
			outline.antialiased = false
			tile.add_child(outline)
			var slash_a: Line2D = Line2D.new()
			slash_a.points = PackedVector2Array([
				Vector2(-10, -5), Vector2(10, 5)])
			slash_a.width = 2.0
			slash_a.visible = false
			tile.add_child(slash_a)
			var slash_b: Line2D = Line2D.new()
			slash_b.points = PackedVector2Array([
				Vector2(10, -5), Vector2(-10, 5)])
			slash_b.width = 2.0
			slash_b.visible = false
			tile.add_child(slash_b)
			_footprint_overlay.add_child(tile)

func _update_footprint_overlay(base_cell: Vector2i, valid: bool) -> void:
	if _footprint_overlay == null:
		return
	var footprint: Vector2i = Constants.BUILDING_DEFS[placing_type]["footprint"]
	var index: int = 0
	var fill_color: Color = Color(0.20, 0.92, 0.48, 0.18) if valid \
		else Color(1.0, 0.22, 0.18, 0.20)
	var line_color: Color = Color(0.35, 1.0, 0.62, 0.86) if valid \
		else Color(1.0, 0.38, 0.28, 0.95)
	for dy in range(footprint.y):
		for dx in range(footprint.x):
			var tile: Node2D = _footprint_overlay.get_child(index) as Node2D
			var cell: Vector2i = base_cell + Vector2i(dx, dy)
			tile.position = Constants.grid_to_world(cell.x, cell.y)
			(tile.get_child(0) as Polygon2D).color = fill_color
			(tile.get_child(1) as Line2D).default_color = line_color
			for child_index in [2, 3]:
				var slash: Line2D = tile.get_child(child_index) as Line2D
				slash.default_color = line_color
				slash.visible = not valid
			index += 1

func _spawn_order_marker(world_pos: Vector2, kind: String) -> void:
	if Net.is_headless_server() or get_tree().current_scene == null:
		return
	var colors: Dictionary = {
		"move": Color(0.42, 0.94, 0.76),
		"attack": Color(1.0, 0.30, 0.22),
		"attack_move": Color(1.0, 0.58, 0.20),
		"gather": Color(0.96, 0.82, 0.30),
		"repair": Color(0.48, 0.90, 0.55),
		"build": Color(0.55, 0.98, 0.64),
		"rally": Color(0.54, 0.84, 1.0),
		"invalid": Color(1.0, 0.22, 0.16),
	}
	var color: Color = colors.get(kind, colors["move"])
	var marker: Node2D = Node2D.new()
	marker.position = world_pos
	marker.z_index = 105
	get_tree().current_scene.add_child(marker)

	var diamond: Polygon2D = Polygon2D.new()
	diamond.polygon = PackedVector2Array([
		Vector2(0, -7), Vector2(15, 0), Vector2(0, 7), Vector2(-15, 0),
	])
	diamond.color = Color(color, 0.32)
	marker.add_child(diamond)
	var outline: Line2D = Line2D.new()
	outline.points = PackedVector2Array([
		Vector2(0, -8), Vector2(17, 0), Vector2(0, 8),
		Vector2(-17, 0), Vector2(0, -8),
	])
	outline.width = 2.0
	outline.default_color = color
	outline.antialiased = false
	marker.add_child(outline)

	if kind in ["attack", "attack_move", "invalid"]:
		for points: PackedVector2Array in [
			PackedVector2Array([Vector2(-7, -4), Vector2(7, 4)]),
			PackedVector2Array([Vector2(7, -4), Vector2(-7, 4)]),
		]:
			var slash: Line2D = Line2D.new()
			slash.points = points
			slash.width = 2.0
			slash.default_color = color
			slash.antialiased = false
			marker.add_child(slash)

	if WorkFx.reduced_motion():
		marker.modulate.a = 0.88
		await get_tree().create_timer(0.45).timeout
		if is_instance_valid(marker):
			marker.queue_free()
		return

	marker.scale = Vector2(0.55, 0.55)
	var tween: Tween = marker.create_tween()
	tween.set_parallel(true)
	tween.tween_property(marker, "scale", Vector2(1.20, 1.20), 0.34) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(marker, "modulate:a", 0.0, 0.46).set_delay(0.10)
	tween.chain().tween_callback(marker.queue_free)
