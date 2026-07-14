# scripts/ui/HUD.gd
extends Control

# In-game HUD: top resource bar, bottom selection/training panel,
# camera-centered minimap, pause, and the game-over overlay.
# Built in code so all styling lives beside the logic.

const MINIMAP_TILES: int = 120      # world window shown on the minimap
const MINIMAP_DISPLAY: int = 144    # on-screen pixels
const REFRESH_INTERVAL: float = 0.5

var _resource_labels: Dictionary = {}  # ResourceType -> Label
var _pop_label: Label
var _pause_button: Button

var _sel_panel: PanelContainer
var _sel_label: Label
var _train_box: HBoxContainer
var _build_box: HBoxContainer
var _queue_label: Label

var _minimap_rect: TextureRect
var _minimap_image: Image

var _game_over: Control
var _game_over_label: Label
var _restart_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_top_bar()
	_build_selection_panel()
	_build_minimap()
	_build_game_over()

	EventBus.resources_changed.connect(_on_resources_changed)
	EventBus.population_changed.connect(func(_pid: int) -> void: _refresh_top_bar())
	EventBus.selection_changed.connect(_refresh_selection_panel)
	EventBus.selection_cleared.connect(_refresh_selection_panel)
	EventBus.training_queued.connect(func(_b: Node2D, _t: String) -> void: _refresh_selection_panel())
	EventBus.training_completed.connect(func(_b: Node2D, _t: String) -> void: _refresh_selection_panel())
	EventBus.game_over.connect(_on_game_over)
	# Pausing is meaningless in multiplayer — the server marches on. Mode is
	# only known after Main's boot, so decide at world_ready.
	EventBus.world_ready.connect(func() -> void:
		_pause_button.visible = Net.mode != Net.Mode.CLIENT)

	var timer: Timer = Timer.new()
	timer.wait_time = REFRESH_INTERVAL
	timer.timeout.connect(_on_refresh_tick)
	add_child(timer)
	timer.start()

	_refresh_top_bar()
	_refresh_selection_panel()

func _panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.10, 0.08, 0.88)
	style.border_color = Color(0.25, 0.35, 0.22, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style

# --- Top bar ---

func _build_top_bar() -> void:
	var bar: PanelContainer = PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _panel_style())
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_top = 8
	add_child(bar)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)

	for type: int in [Constants.ResourceType.FOOD, Constants.ResourceType.WOOD, Constants.ResourceType.JADE]:
		row.add_child(_icon_rect(AssetLibrary.resource_icon(type)))
		var label: Label = Label.new()
		label.text = "0"
		label.custom_minimum_size = Vector2(52, 0)
		row.add_child(label)
		_resource_labels[type] = label

	row.add_child(_icon_rect(AssetLibrary.icons["pop"]))
	_pop_label = Label.new()
	_pop_label.text = "0/%d" % Constants.POPULATION_CAP
	row.add_child(_pop_label)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var help_button: Button = Button.new()
	help_button.text = "Help"
	help_button.focus_mode = Control.FOCUS_NONE
	help_button.pressed.connect(func() -> void: EventBus.help_requested.emit())
	row.add_child(help_button)

	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.pressed.connect(_on_pause_pressed)
	row.add_child(_pause_button)

func _icon_rect(texture: Texture2D) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(22, 22)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return rect

func _refresh_top_bar() -> void:
	for type: int in _resource_labels:
		_resource_labels[type].text = str(GameManager.get_resource(GameManager.local_player_id, type))
	_pop_label.text = "%d/%d" % [GameManager.get_population(GameManager.local_player_id),
		GameManager.population_cap(GameManager.local_player_id)]

func _on_resources_changed(player_id: int) -> void:
	if player_id == GameManager.local_player_id:
		_refresh_top_bar()

# --- Selection / training panel ---

func _build_selection_panel() -> void:
	_sel_panel = PanelContainer.new()
	_sel_panel.add_theme_stylebox_override("panel", _panel_style())
	_sel_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sel_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sel_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sel_panel.offset_bottom = -10
	_sel_panel.visible = false
	add_child(_sel_panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_sel_panel.add_child(box)

	_sel_label = Label.new()
	_sel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sel_label)

	_train_box = HBoxContainer.new()
	_train_box.add_theme_constant_override("separation", 8)
	_train_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_train_box)

	var villager_btn: Button = Button.new()
	villager_btn.text = "Train Villager (50 food)"
	villager_btn.focus_mode = Control.FOCUS_NONE
	villager_btn.pressed.connect(func() -> void: _train("villager"))
	_train_box.add_child(villager_btn)

	var warrior_btn: Button = Button.new()
	warrior_btn.text = "Train Warrior (40 food, 20 wood)"
	warrior_btn.focus_mode = Control.FOCUS_NONE
	warrior_btn.pressed.connect(func() -> void: _train("warrior"))
	_train_box.add_child(warrior_btn)

	_queue_label = Label.new()
	_queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_queue_label)

	# Construction buttons appear when villagers are selected.
	_build_box = HBoxContainer.new()
	_build_box.add_theme_constant_override("separation", 8)
	_build_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_build_box.visible = false
	box.add_child(_build_box)
	for building_type: String in ["house", "barracks", "watchtower"]:
		var def: Dictionary = Constants.BUILDING_DEFS[building_type]
		var parts: Array[String] = []
		for res_type: int in def["cost"]:
			parts.append("%d %s" % [def["cost"][res_type],
				Constants.RESOURCE_NAMES[res_type]])
		var button: Button = Button.new()
		button.text = "%s (%s)" % [building_type.capitalize(), ", ".join(parts)]
		button.focus_mode = Control.FOCUS_NONE
		var captured: String = building_type
		button.pressed.connect(func() -> void:
			SelectionManager.start_placement(captured))
		_build_box.add_child(button)

func _train(unit_type: String) -> void:
	var building: Node2D = SelectionManager.selected_building
	if building == null or not is_instance_valid(building):
		return
	CommandRouter.submit({
		"type": "train", "player_id": GameManager.local_player_id,
		"building_name": String(building.name), "unit_type": unit_type,
	})
	_refresh_selection_panel()

func _refresh_selection_panel() -> void:
	var building: Node2D = SelectionManager.selected_building
	if building != null and is_instance_valid(building):
		_sel_panel.visible = true
		_build_box.visible = false
		var constructed: bool = bool(building.get("is_constructed"))
		_train_box.visible = constructed
		_queue_label.visible = constructed
		var title: String = String(building.get("building_type")).capitalize().replace("_", " ")
		if not constructed:
			title += "  ·  under construction"
		_sel_label.text = "%s  —  %d/%d HP" % [title, building.current_hp, building.max_hp]
		var queue: Array = building.train_queue
		if queue.is_empty():
			_queue_label.text = "Queue empty"
		else:
			var train_time: float = Constants.UNIT_DEFS[queue[0]]["train_time"]
			var pct: int = int(building.train_progress / train_time * 100.0)
			_queue_label.text = "Training %s (%d%%)  —  queue: %d" % [queue[0].capitalize(), pct, queue.size()]
		return

	var units: Array = SelectionManager.selected_units.filter(is_instance_valid)
	if units.is_empty():
		_sel_panel.visible = false
		_build_box.visible = false
		return

	_sel_panel.visible = true
	_train_box.visible = false
	_queue_label.visible = false
	_build_box.visible = units.any(
		func(u: Node2D) -> bool: return bool(u.get("can_gather")))
	var counts: Dictionary = {}
	for unit: Node2D in units:
		var t: String = unit.get("unit_type")
		counts[t] = counts.get(t, 0) + 1
	var parts: Array[String] = []
	for t: String in counts:
		parts.append("%d× %s" % [counts[t], t.capitalize()])
	_sel_label.text = ", ".join(parts)

# --- Minimap ---

func _build_minimap() -> void:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = _panel_style()
	style.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -10
	panel.offset_bottom = -10
	add_child(panel)

	_minimap_rect = TextureRect.new()
	_minimap_rect.custom_minimum_size = Vector2(MINIMAP_DISPLAY, MINIMAP_DISPLAY)
	_minimap_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_minimap_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap_rect.gui_input.connect(_on_minimap_input)
	panel.add_child(_minimap_rect)

	_minimap_image = Image.create(MINIMAP_TILES, MINIMAP_TILES, false, Image.FORMAT_RGBA8)

func _on_refresh_tick() -> void:
	_redraw_minimap()
	if _sel_panel.visible:
		_refresh_selection_panel()

func _redraw_minimap() -> void:
	if GameManager.world == null:
		return
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return

	var center: Vector2i = Constants.world_to_grid(camera.global_position)
	var half: int = int(MINIMAP_TILES / 2.0)
	var world: WorldData = GameManager.world
	var size: int = Constants.CHUNK_SIZE

	_minimap_image.fill(Color(0.03, 0.05, 0.04))

	var fog: FogOfWar = GameManager.fog

	# Terrain from already-generated chunks only (never force generation);
	# unexplored tiles stay dark, explored-but-unwatched tiles are dimmed.
	for py in range(MINIMAP_TILES):
		for px in range(MINIMAP_TILES):
			var cell: Vector2i = center + Vector2i(px - half, py - half)
			var cc: Vector2i = Constants.tile_to_chunk(cell)
			var chunk: ChunkData = world.chunks.get(cc)
			if chunk == null:
				continue
			if fog != null and not fog.is_explored(cell):
				continue
			var biome: int = chunk.get_biome_local(cell.x - cc.x * size, cell.y - cc.y * size)
			var color: Color = Constants.BIOME_COLORS[biome]
			if fog != null and not fog.is_cell_visible(cell):
				color = color.darkened(0.45)
			_minimap_image.set_pixel(px, py, color)

	# Buildings and units as dots. Enemies only when fog allows.
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var building: Node2D = node as Node2D
		if building != null and building.visible:
			_plot(building, center, half, 2)
	for node: Node in get_tree().get_nodes_in_group("units"):
		var unit: Node2D = node as Node2D
		if unit != null and unit.visible:
			_plot(unit, center, half, 1)

	# Wildlife dots, only where the player can currently see them.
	for node: Node in get_tree().get_nodes_in_group("animals"):
		var animal: Node2D = node as Node2D
		if animal != null and animal.visible:
			_plot(animal, center, half, 1, Constants.WILDLIFE_COLOR)

	_minimap_rect.texture = ImageTexture.create_from_image(_minimap_image)

func _plot(entity: Node2D, center: Vector2i, half: int, radius: int, color_override: Color = Color(0, 0, 0, 0)) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var cell: Vector2i = Constants.world_to_grid(entity.global_position)
	var px: int = cell.x - center.x + half
	var py: int = cell.y - center.y + half
	var color: Color = color_override
	if color.a <= 0.0:
		var pid: int = entity.get("player_id")
		color = Constants.PLAYER_COLORS[clampi(pid, 0, Constants.PLAYER_COLORS.size() - 1)]
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x: int = px + dx
			var y: int = py + dy
			if x >= 0 and x < MINIMAP_TILES and y >= 0 and y < MINIMAP_TILES:
				_minimap_image.set_pixel(x, y, color)

func _on_minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var camera: Camera2D = get_viewport().get_camera_2d()
			if camera == null:
				return
			var frac: Vector2 = mb.position / _minimap_rect.size
			var center: Vector2i = Constants.world_to_grid(camera.global_position)
			var half: int = int(MINIMAP_TILES / 2.0)
			var cell: Vector2i = center + Vector2i(
				int(frac.x * MINIMAP_TILES) - half,
				int(frac.y * MINIMAP_TILES) - half
			)
			camera.global_position = Constants.grid_to_world(cell.x, cell.y)

# --- Pause / game over ---

func _on_pause_pressed() -> void:
	if GameManager.state == GameManager.GameState.GAME_OVER:
		return
	var paused: bool = not get_tree().paused
	get_tree().paused = paused
	_pause_button.text = "Resume" if paused else "Pause"
	GameManager.change_state(GameManager.GameState.PAUSED if paused else GameManager.GameState.RUNNING)

func _build_game_over() -> void:
	_game_over = Control.new()
	_game_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over.visible = false
	add_child(_game_over)

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over.add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = _panel_style()
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	_game_over_label = Label.new()
	_game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_label.add_theme_font_size_override("font_size", 28)
	box.add_child(_game_over_label)

	_restart_button = Button.new()
	_restart_button.text = "Play Again"
	_restart_button.focus_mode = Control.FOCUS_NONE
	_restart_button.pressed.connect(_on_restart_pressed)
	box.add_child(_restart_button)

func _on_game_over(winner_player_id: int) -> void:
	get_tree().paused = true
	_game_over_label.text = "Victory!" if winner_player_id == GameManager.local_player_id else "Defeat"
	_restart_button.text = "Back to Menu" if Net.mode == Net.Mode.CLIENT else "Play Again"
	_game_over.visible = true

func _on_restart_pressed() -> void:
	get_tree().paused = false
	_game_over.visible = false
	SelectionManager.clear_selection()
	if Net.mode == Net.Mode.CLIENT:
		Net.back_to_menu()
		return
	GameManager.map_seed = randi()
	GameManager.world = null
	GameManager.pathfinder = null
	GameManager.fog = null
	GameManager.reset_players()
	GameManager.change_state(GameManager.GameState.LOADING)
	get_tree().reload_current_scene()
