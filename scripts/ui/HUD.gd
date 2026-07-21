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
var _daily_label: Label
var _era_label: Label
var _advance_button: Button
var _pause_button: Button

var _sel_panel: PanelContainer
var _sel_label: Label
var _train_box: HFlowContainer
var _build_box: HFlowContainer
var _hp_bar: ProgressBar
var _train_progress: ProgressBar
var _cmd_box: HBoxContainer
var _idle_button: Button
var _idle_cycle: int = 0
# keycode -> Callable, rebuilt with the panel (see _unhandled_key_input)
var _hotkeys: Dictionary = {}

const TRAIN_KEYS: Dictionary = { "villager": KEY_V, "warrior": KEY_C, "archer": KEY_R }
const BUILD_KEYS: Dictionary = { "house": KEY_B, "barracks": KEY_N,
	"watchtower": KEY_T, "storehouse": KEY_S, "monument": KEY_M }
var _queue_label: Label

var _minimap_rect: TextureRect
var _minimap_image: Image

var _game_over: Control
var _game_over_label: Label
var _restart_button: Button
var _rematch_button: Button
var _monument_banner: Label
var _alert_label: Label
var _alert_cooldown: float = 0.0
var _minimap_ping: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_top_bar()
	_monument_banner = Label.new()
	_monument_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_monument_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_monument_banner.offset_top = 46
	_monument_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_monument_banner.add_theme_font_size_override("font_size", 16)
	_monument_banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_monument_banner.add_theme_constant_override("shadow_offset_y", 1)
	_monument_banner.visible = false
	add_child(_monument_banner)
	_build_selection_panel()
	_build_minimap()
	_build_game_over()

	EventBus.resources_changed.connect(_on_resources_changed)
	EventBus.population_changed.connect(func(_pid: int) -> void:
		_refresh_top_bar()
		_refresh_era_ui())
	EventBus.era_advanced.connect(_on_era_advanced)
	EventBus.building_constructed.connect(_on_buildings_changed)
	EventBus.building_destroyed.connect(_on_buildings_changed)
	EventBus.selection_changed.connect(_refresh_selection_panel)
	EventBus.selection_cleared.connect(_refresh_selection_panel)
	EventBus.training_queued.connect(func(_b: Node2D, _t: String) -> void: _refresh_selection_panel())
	EventBus.training_completed.connect(func(_b: Node2D, _t: String) -> void: _refresh_selection_panel())
	EventBus.game_over.connect(_on_game_over)
	EventBus.building_damaged.connect(_on_building_damaged_alert)
	# Pausing is meaningless in multiplayer — the server marches on. Mode is
	# only known after Main's boot, so decide at world_ready.
	EventBus.world_ready.connect(func() -> void:
		_pause_button.visible = Net.mode != Net.Mode.CLIENT
		# Thumbnails were built before the local tribe was known.
		for child: Node in _build_box.get_children():
			var b: Button = child as Button
			if b != null and b.has_meta("btype"):
				b.icon = AssetLibrary.building_textures[
					GameManager.local_player_id].get(b.get_meta("btype")))

	var timer: Timer = Timer.new()
	timer.wait_time = REFRESH_INTERVAL
	timer.timeout.connect(_on_refresh_tick)
	add_child(timer)
	timer.start()

	_refresh_top_bar()
	_refresh_era_ui()
	_refresh_selection_panel()

# The selection panel is a fixed-width command bar: anchored bottom-wide
# with side margins that clear the idle button (left) and minimap (right)
# BY CONSTRUCTION. Its flow rows wrap at the bar's real width, so
# horizontal overflow is structurally impossible; only the height follows
# content, pinned upward from the bottom edge each frame (Godot's
# grow_vertical is not reliable when minimum size changes while visible).
const BAR_SIDE_MARGIN: float = 210.0

func _process(_delta: float) -> void:
	if _sel_panel != null and _sel_panel.visible:
		_sel_panel.offset_top = -10.0 - _sel_panel.get_combined_minimum_size().y
		_sel_panel.offset_bottom = -10.0
	if _idle_button != null:
		var idle_panel: PanelContainer = _idle_button.get_meta("panel")
		if idle_panel.visible:
			var min_size: Vector2 = idle_panel.get_combined_minimum_size()
			idle_panel.offset_left = 10.0
			idle_panel.offset_right = 10.0 + min_size.x
			idle_panel.offset_top = -10.0 - min_size.y
			idle_panel.offset_bottom = -10.0

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
	# Hovering UI blocks edge scrolling (see GameCamera), but the top bar
	# spans the whole top edge — exempt it so upward scrolling still works.
	bar.add_to_group("edge_pan_through")
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

	# Era indicator + the button that drives progression. Both read from live
	# era state (see _refresh_era_ui); the label is gold like the daily clock so
	# "what age am I in" reads at a glance beside the stats.
	_era_label = Label.new()
	_era_label.add_theme_color_override("font_color", Color(0.89, 0.71, 0.36))
	_era_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_era_label)

	_advance_button = Button.new()
	_advance_button.focus_mode = Control.FOCUS_NONE
	_advance_button.pressed.connect(func() -> void:
		CommandRouter.submit({"type": "advance_era",
			"player_id": GameManager.local_player_id}))
	row.add_child(_advance_button)

	_daily_label = Label.new()
	_daily_label.add_theme_color_override("font_color", Color(0.89, 0.71, 0.36))
	_daily_label.visible = false
	row.add_child(_daily_label)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# Sound controls: slider + mute toggle, persisted by Sfx.
	var volume_slider: HSlider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = Sfx.volume
	volume_slider.custom_minimum_size = Vector2(90, 0)
	volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume_slider.focus_mode = Control.FOCUS_NONE
	volume_slider.value_changed.connect(func(v: float) -> void: Sfx.set_volume(v))
	row.add_child(volume_slider)
	var mute_button: Button = Button.new()
	mute_button.text = "Mute" if not Sfx.muted else "Unmute"
	mute_button.focus_mode = Control.FOCUS_NONE
	mute_button.pressed.connect(func() -> void:
		Sfx.set_muted(not Sfx.muted)
		mute_button.text = "Mute" if not Sfx.muted else "Unmute"
		if not Sfx.muted:
			Sfx.ambience_start())
	row.add_child(mute_button)

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

func _format_secs(secs: float) -> String:
	return "%d:%02d" % [int(secs) / 60, int(secs) % 60]

func _refresh_top_bar() -> void:
	_daily_label.visible = GameManager.daily_mode
	if GameManager.daily_mode:
		_daily_label.text = "DAILY  %s" % _format_secs(GameManager.game_time_secs)
	for type: int in _resource_labels:
		_resource_labels[type].text = str(GameManager.get_resource(GameManager.local_player_id, type))
	_pop_label.text = "%d/%d" % [GameManager.get_population(GameManager.local_player_id),
		GameManager.population_cap(GameManager.local_player_id)]

func _on_resources_changed(player_id: int) -> void:
	if player_id == GameManager.local_player_id:
		_refresh_top_bar()
		_refresh_era_ui()
		if _sel_panel.visible:
			_refresh_selection_panel()

# The era indicator + Advance button, driven entirely from current era state so
# it is safe to call on any signal (idempotent, no transient assumptions). The
# gate itself lives in GameManager (is_unlocked / missing_era_requirements /
# can_afford) — this only renders it.
func _refresh_era_ui() -> void:
	if _era_label == null:
		return
	var pid: int = GameManager.local_player_id
	_era_label.text = Constants.ERA_DEFS[GameManager.player_era(pid)]["name"]
	if not GameManager.has_next_era(pid):
		_advance_button.disabled = true
		_advance_button.text = "Chiefdom Age (max)"
		_advance_button.tooltip_text = ""
		return
	var next: int = GameManager.player_era(pid) + 1
	var next_def: Dictionary = Constants.ERA_DEFS[next]
	var cost: Dictionary = next_def["advance_cost"]
	var missing: Dictionary = GameManager.missing_era_requirements(pid)
	var affordable: bool = GameManager.can_afford(pid, cost)
	_advance_button.text = "Advance to %s (%s)" % [next_def["name"], _cost_text(cost)]
	_advance_button.disabled = not (missing.is_empty() and affordable)
	if _advance_button.disabled:
		var reasons: Array[String] = []
		for bt: String in missing:
			reasons.append("%d more %s" % [int(missing[bt]),
				bt.capitalize().replace("_", " ")])
		for res_type: int in cost:
			var short: int = int(cost[res_type]) - GameManager.get_resource(pid, res_type)
			if short > 0:
				reasons.append("%d more %s" % [short, Constants.RESOURCE_NAMES[res_type]])
		_advance_button.tooltip_text = "Need " + " and ".join(reasons)
	else:
		_advance_button.tooltip_text = ""

# A real era transition (the signal now fires only on those): refresh the label
# and menu for everyone, and give the local tribe a subtle cue.
func _on_era_advanced(player_id: int, _era: int) -> void:
	_refresh_era_ui()
	if _sel_panel.visible:
		_refresh_selection_panel()  # un-greys buildings this era unlocks
	if player_id == GameManager.local_player_id:
		Sfx.play("built")
		var tween: Tween = _era_label.create_tween()
		_era_label.modulate = Color(1.5, 1.3, 0.6)
		tween.tween_property(_era_label, "modulate", Color(1, 1, 1, 1), 1.2)

# Finishing/losing a building can change the still-unmet era requirements, so
# the Advance button (and any era-gated build buttons) must re-evaluate.
func _on_buildings_changed(_building: Node2D) -> void:
	_refresh_era_ui()
	if _sel_panel.visible:
		_refresh_selection_panel()

func _rebuild_hotkeys() -> void:
	_hotkeys.clear()
	for row: Container in [_train_box, _build_box, _cmd_box]:
		if not row.visible:
			continue
		for child: Node in row.get_children():
			var b: Button = child as Button
			if b != null and not b.is_queued_for_deletion() \
					and b.has_meta("hotkey") and int(b.get_meta("hotkey")) != 0 \
					and not b.disabled:
				_hotkeys[int(b.get_meta("hotkey"))] = b.pressed.emit

# --- Selection / training panel ---

func _build_selection_panel() -> void:
	_sel_panel = PanelContainer.new()
	_sel_panel.add_theme_stylebox_override("panel", _panel_style())
	_sel_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_sel_panel.offset_left = BAR_SIDE_MARGIN
	_sel_panel.offset_right = -BAR_SIDE_MARGIN
	_sel_panel.offset_bottom = -10
	_sel_panel.visible = false
	add_child(_sel_panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_sel_panel.add_child(box)

	_sel_label = Label.new()
	_sel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sel_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(150, 8)
	_hp_bar.add_theme_stylebox_override("background", AssetLibrary.health_bar_bg)
	_hp_bar.add_theme_stylebox_override("fill", AssetLibrary.health_bar_fill)
	box.add_child(_hp_bar)

	# Flow containers so button rows wrap instead of running off both screen
	# edges on narrow viewports (see _clamp_row).
	_train_box = HFlowContainer.new()
	_train_box.add_theme_constant_override("h_separation", 8)
	_train_box.add_theme_constant_override("v_separation", 6)
	_train_box.alignment = FlowContainer.ALIGNMENT_CENTER
	box.add_child(_train_box)


	_queue_label = Label.new()
	_queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_queue_label)

	_train_progress = ProgressBar.new()
	_train_progress.show_percentage = false
	_train_progress.max_value = 100.0
	_train_progress.custom_minimum_size = Vector2(150, 6)
	_train_progress.add_theme_stylebox_override("background", AssetLibrary.health_bar_bg)
	var progress_fill: StyleBoxFlat = AssetLibrary.health_bar_fill.duplicate()
	progress_fill.bg_color = Color(0.89, 0.71, 0.36)
	_train_progress.add_theme_stylebox_override("fill", progress_fill)
	box.add_child(_train_progress)

	# Construction buttons appear when villagers are selected.
	_build_box = HFlowContainer.new()
	_build_box.add_theme_constant_override("h_separation", 8)
	_build_box.add_theme_constant_override("v_separation", 6)
	_build_box.alignment = FlowContainer.ALIGNMENT_CENTER
	_build_box.visible = false
	box.add_child(_build_box)
	for building_type: String in ["house", "barracks", "watchtower", "storehouse", "monument"]:
		var def: Dictionary = Constants.BUILDING_DEFS[building_type]
		var button: Button = Button.new()
		button.text = "%s · %s  [%s]" % [building_type.capitalize().replace("_", " "),
			_cost_text(def["cost"]), OS.get_keycode_string(BUILD_KEYS[building_type])]
		button.icon = AssetLibrary.building_textures[0].get(building_type)
		button.add_theme_constant_override("icon_max_width", 20)
		button.focus_mode = Control.FOCUS_NONE
		var captured: String = building_type
		button.pressed.connect(func() -> void:
			SelectionManager.start_placement(captured))
		button.set_meta("cost", def["cost"])
		button.set_meta("hotkey", BUILD_KEYS[building_type])
		button.set_meta("btype", building_type)
		_build_box.add_child(button)

	# Orders for the selected units.
	_cmd_box = HBoxContainer.new()
	_cmd_box.add_theme_constant_override("separation", 8)
	_cmd_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_cmd_box.visible = false
	box.add_child(_cmd_box)
	var atk_button: Button = Button.new()
	atk_button.text = "Attack-move  [G]"
	atk_button.tooltip_text = "Then click a destination — units engage everything on the way. (Or shift+right-click.)"
	atk_button.focus_mode = Control.FOCUS_NONE
	atk_button.pressed.connect(func() -> void: SelectionManager.arm_attack_move())
	atk_button.set_meta("hotkey", KEY_G)
	_cmd_box.add_child(atk_button)
	var stop_button: Button = Button.new()
	stop_button.text = "Stop  [X]"
	stop_button.tooltip_text = "Drop all orders and stand down."
	stop_button.focus_mode = Control.FOCUS_NONE
	stop_button.pressed.connect(_stop_selected)
	stop_button.set_meta("hotkey", KEY_X)
	_cmd_box.add_child(stop_button)

	_build_idle_button()

func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for res_type: int in cost:
		parts.append("%d %s" % [cost[res_type], Constants.RESOURCE_NAMES[res_type]])
	return ", ".join(parts)

# The era-lock reason for a gated def, or "" if the local tribe has unlocked it.
# Uses the SHARED gate (GameManager.is_unlocked) so the menu can never disagree
# with the authoritative place/train validators.
func _era_lock_reason(def: Dictionary) -> String:
	if GameManager.is_unlocked(GameManager.local_player_id, def):
		return ""
	return "Unlocks in %s" % Constants.ERA_DEFS[int(def.get("era", 0))]["name"]

# Disable what the player cannot pay for, and say why.
func _apply_affordability(button: Button, cost: Dictionary, pop_gated: bool) -> void:
	var pid: int = GameManager.local_player_id
	# Era lock takes precedence over cost: content the tribe's age hasn't unlocked
	# greys out with a "comes later" reason, never a "can't afford" one. Applies
	# to both build buttons (btype) and train buttons (utype) so an era-gated unit
	# offered by an earlier-era building (e.g. Hunter at the Town Center) can't
	# show as an enabled-but-inert button.
	var lock_reason: String = ""
	if button.has_meta("btype"):
		lock_reason = _era_lock_reason(Constants.BUILDING_DEFS[button.get_meta("btype")])
	elif button.has_meta("utype"):
		lock_reason = _era_lock_reason(Constants.UNIT_DEFS[button.get_meta("utype")])
	if lock_reason != "":
		button.disabled = true
		button.tooltip_text = lock_reason
		return
	var lacking: Array[String] = []
	for res_type: int in cost:
		var short: int = cost[res_type] - GameManager.get_resource(pid, res_type)
		if short > 0:
			lacking.append("%d more %s" % [short, Constants.RESOURCE_NAMES[res_type]])
	if pop_gated and GameManager.get_population(pid) >= GameManager.population_cap(pid):
		lacking.append("room — population cap reached, build houses")
	button.disabled = not lacking.is_empty()
	button.tooltip_text = "Need " + " and ".join(lacking) if button.disabled else ""

func _stop_selected() -> void:
	var units: Array = SelectionManager.selected_units.filter(is_instance_valid)
	if units.is_empty():
		return
	CommandRouter.submit({
		"type": "stop", "player_id": GameManager.local_player_id,
		"actor_names": units.map(func(u: Node2D) -> String: return String(u.name)),
	})

func _build_idle_button() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = 10
	panel.offset_bottom = -10
	add_child(panel)
	_idle_button = Button.new()
	_idle_button.focus_mode = Control.FOCUS_NONE
	_idle_button.tooltip_text = "Select the next idle villager and jump the camera there."
	_idle_button.pressed.connect(_cycle_idle_villager)
	panel.add_child(_idle_button)
	panel.visible = false
	_idle_button.set_meta("panel", panel)

func _idle_villagers() -> Array:
	return get_tree().get_nodes_in_group(
		"player_%d" % GameManager.local_player_id).filter(
		func(n: Node) -> bool:
			var unit: UnitBase = n as UnitBase
			return unit != null and unit.can_gather \
				and unit.current_state == UnitBase.State.IDLE)

func _cycle_idle_villager() -> void:
	var idle: Array = _idle_villagers()
	if idle.is_empty():
		return
	_idle_cycle = (_idle_cycle + 1) % idle.size()
	var unit: Node2D = idle[_idle_cycle]
	SelectionManager.select_only(unit)
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null:
		camera.global_position = unit.global_position

func _refresh_idle_button() -> void:
	if _idle_button == null:
		return
	var count: int = _idle_villagers().size()
	(_idle_button.get_meta("panel") as PanelContainer).visible = count > 0
	_idle_button.text = "Idle workers: %d  [F]" % count

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or get_tree().paused:
		return
	if key.keycode == KEY_F:
		if not _idle_villagers().is_empty():
			_cycle_idle_villager()
		return
	if not _sel_panel.visible or not _hotkeys.has(key.keycode):
		return
	(_hotkeys[key.keycode] as Callable).call()

# The train row mirrors whatever the selected building can produce.
func _populate_train_buttons(building_type: String) -> void:
	for child: Node in _train_box.get_children():
		child.queue_free()
	for unit_type: String in Constants.BUILDING_DEFS[building_type]["trains"]:
		var def: Dictionary = Constants.UNIT_DEFS[unit_type]
		var button: Button = Button.new()
		button.text = "%s · %s  [%s]" % [unit_type.capitalize(),
			_cost_text(def["cost"]), OS.get_keycode_string(TRAIN_KEYS.get(unit_type, 0))]
		var frames: Array = AssetLibrary.get_unit_frames(
			GameManager.local_player_id, unit_type)
		if not frames.is_empty():
			button.icon = frames[0]
			button.add_theme_constant_override("icon_max_width", 14)
		button.focus_mode = Control.FOCUS_NONE
		var captured: String = unit_type
		button.pressed.connect(func() -> void: _train(captured))
		button.set_meta("cost", def["cost"])
		button.set_meta("hotkey", TRAIN_KEYS.get(unit_type, 0))
		button.set_meta("utype", unit_type)
		_train_box.add_child(button)

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
		_cmd_box.visible = false
		var constructed: bool = bool(building.get("is_constructed"))
		_train_box.visible = constructed
		_queue_label.visible = constructed
		_populate_train_buttons(String(building.get("building_type")))
		var title: String = String(building.get("building_type")).capitalize().replace("_", " ")
		if not constructed:
			title += "  ·  under construction"
		_sel_label.text = "%s  —  %d/%d HP" % [title, building.current_hp, building.max_hp]
		_hp_bar.visible = true
		_hp_bar.max_value = building.max_hp
		_hp_bar.value = building.current_hp
		var queue: Array = building.train_queue
		if queue.is_empty():
			_queue_label.text = "Queue empty"
			_train_progress.visible = false
		else:
			var train_time: float = Constants.UNIT_DEFS[queue[0]]["train_time"]
			_queue_label.text = "Training %s  —  queue: %d" % [
				queue[0].capitalize(), queue.size()]
			_train_progress.visible = constructed
			_train_progress.value = building.train_progress / train_time * 100.0
		for child: Node in _train_box.get_children():
			var b: Button = child as Button
			if b != null and not b.is_queued_for_deletion() and b.has_meta("cost"):
				_apply_affordability(b, b.get_meta("cost"), true)
		_rebuild_hotkeys()
		return

	var units: Array = SelectionManager.selected_units.filter(is_instance_valid)
	if units.is_empty():
		_sel_panel.visible = false
		_build_box.visible = false
		return

	_sel_panel.visible = true
	_train_box.visible = false
	_queue_label.visible = false
	_train_progress.visible = false
	_cmd_box.visible = true
	_build_box.visible = units.any(
		func(u: Node2D) -> bool: return bool(u.get("can_gather")))
	var hp: int = 0
	var hp_max: int = 0
	for unit: Node2D in units:
		hp += int(unit.get("current_hp"))
		hp_max += int(unit.get("max_hp"))
	_hp_bar.visible = hp_max > 0
	_hp_bar.max_value = hp_max
	_hp_bar.value = hp
	for child: Node in _build_box.get_children():
		var b: Button = child as Button
		if b != null and b.has_meta("cost"):
			_apply_affordability(b, b.get_meta("cost"), false)
	_rebuild_hotkeys()
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

# "Your base is under attack!" — sound + banner + minimap ping, at most
# once per 12 seconds so a siege doesn't become a siren.
func _on_building_damaged_alert(building: Node2D, _attacker: Node2D) -> void:
	if building.get("player_id") != GameManager.local_player_id:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _alert_cooldown < 12.0:
		return
	_alert_cooldown = now
	Sfx.play("alarm")
	if _alert_label == null:
		_alert_label = Label.new()
		_alert_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_alert_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_alert_label.offset_top = 70
		_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_alert_label.add_theme_font_size_override("font_size", 15)
		_alert_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
		_alert_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		add_child(_alert_label)
	_alert_label.text = "Your base is under attack!"
	_alert_label.modulate.a = 1.0
	var tween: Tween = _alert_label.create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(_alert_label, "modulate:a", 0.0, 0.8)
	_ping_minimap((building as Node2D).global_position)

func _ping_minimap(world_pos: Vector2) -> void:
	if _minimap_rect == null:
		return
	var center: Vector2i = Constants.world_to_grid(
		get_viewport().get_camera_2d().global_position if get_viewport().get_camera_2d() != null else Vector2.ZERO)
	var cell: Vector2i = Constants.world_to_grid(world_pos)
	var scale_px: float = float(MINIMAP_DISPLAY) / float(MINIMAP_TILES)
	var offset: Vector2 = Vector2(cell - center) * scale_px + Vector2(MINIMAP_DISPLAY, MINIMAP_DISPLAY) / 2.0
	if offset.x < 0 or offset.y < 0 or offset.x > MINIMAP_DISPLAY or offset.y > MINIMAP_DISPLAY:
		offset = offset.clamp(Vector2(4, 4), Vector2(MINIMAP_DISPLAY - 4, MINIMAP_DISPLAY - 4))
	if _minimap_ping == null or not is_instance_valid(_minimap_ping):
		_minimap_ping = ColorRect.new()
		_minimap_ping.size = Vector2(8, 8)
		_minimap_ping.color = Color(1.0, 0.25, 0.2, 0.95)
		_minimap_ping.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_minimap_rect.add_child(_minimap_ping)
	_minimap_ping.position = offset - Vector2(4, 4)
	_minimap_ping.visible = true
	var ping_tween: Tween = _minimap_ping.create_tween()
	ping_tween.set_loops(4)
	ping_tween.tween_property(_minimap_ping, "modulate:a", 0.15, 0.3)
	ping_tween.tween_property(_minimap_ping, "modulate:a", 1.0, 0.3)
	ping_tween.chain().tween_callback(func() -> void: _minimap_ping.visible = false)

# The wonder-timer rule: everyone gets warned, fog or not.
func _refresh_monument_banner() -> void:
	var best: Building = null
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var building: Building = node as Building
		if building != null and building.building_type == "monument" \
				and building.is_constructed:
			if best == null or building.monument_timer > best.monument_timer:
				best = building
	if best == null:
		_monument_banner.visible = false
		return
	var remaining: int = maxi(0, int(ceil(Constants.MONUMENT_VICTORY_SECS - best.monument_timer)))
	_monument_banner.visible = true
	if best.player_id == GameManager.local_player_id:
		_monument_banner.text = "Your Monument stands — victory in %ds" % remaining
		_monument_banner.add_theme_color_override("font_color", Color(0.6, 0.95, 0.75))
	else:
		_monument_banner.text = "A rival Monument rises! Raze it within %ds" % remaining
		_monument_banner.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))

func _on_refresh_tick() -> void:
	_redraw_minimap()
	_refresh_monument_banner()
	_refresh_idle_button()
	_refresh_top_bar()
	_refresh_era_ui()
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

	# Discovered, unclaimed ancient ruins as pale stone dots — a breadcrumb to
	# landmarks worth claiming. Gated on explored (never reveals unseen ruins)
	# and unclaimed (a razed ruin drops off the map). Only already-generated
	# chunks are consulted, like the terrain pass, so no generation is forced.
	# One POI type today (ancient_ruins) → every POI dots the same. Key off the
	# POI's "type" when a second POI type is added.
	for py in range(MINIMAP_TILES):
		for px in range(MINIMAP_TILES):
			var cell: Vector2i = center + Vector2i(px - half, py - half)
			var chunk: ChunkData = world.chunks.get(Constants.tile_to_chunk(cell))
			if chunk == null or not chunk.pois.has(cell):
				continue
			if fog != null and not fog.is_explored(cell):
				continue
			if world.is_poi_claimed(cell):
				continue
			for dy in range(0, 2):
				for dx in range(0, 2):
					var x: int = px + dx
					var y: int = py + dy
					if x >= 0 and x < MINIMAP_TILES and y >= 0 and y < MINIMAP_TILES:
						_minimap_image.set_pixel(x, y, Constants.RUINS_MINIMAP_COLOR)

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

	_rematch_button = Button.new()
	_rematch_button.text = "Rematch"
	_rematch_button.focus_mode = Control.FOCUS_NONE
	_rematch_button.visible = false
	_rematch_button.pressed.connect(func() -> void:
		Net.request_rematch()
		_rematch_button.text = "Waiting for the others…"
		_rematch_button.disabled = true)
	box.add_child(_rematch_button)

func _on_game_over(winner_player_id: int) -> void:
	get_tree().paused = true
	if winner_player_id == GameManager.local_player_id:
		_game_over_label.text = "Victory!"
		if GameManager.daily_mode:
			_game_over_label.text = "Victory!  —  %s\nyour daily time" % \
				_format_secs(GameManager.game_time_secs)
	elif Net.mode == Net.Mode.CLIENT and not Net.player_names.is_empty():
		_game_over_label.text = "%s wins" % Net.display_name_of(winner_player_id)
	else:
		_game_over_label.text = "Defeat"
	_restart_button.text = "Back to Menu" if Net.mode == Net.Mode.CLIENT else "Play Again"
	_rematch_button.visible = Net.mode == Net.Mode.CLIENT
	_rematch_button.disabled = false
	_rematch_button.text = "Rematch"
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
