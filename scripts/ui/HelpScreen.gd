# scripts/ui/HelpScreen.gd
extends Control

# Modal "How to Play" overlay. Teaches the objective, controls, the two units
# (drawn with their real in-game sprites), resources, and the fog-of-war rules.
#
# It opens automatically the first time a session is played — paused, so a new
# player is taught before the match moves — and on demand via the HUD's Help
# button or the H / F1 keys. Esc, H, F1, or the button close it again. While
# open it pauses the match and shields the HUD beneath it from input.

const TITLE_COLOR: Color = Color(0.96, 0.90, 0.58)    # warm gold
const HEADER_COLOR: Color = Color(0.60, 0.85, 0.52)   # jade-leaf green
const KEY_COLOR: Color = Color(0.94, 0.82, 0.46)      # control / key hints
const NAME_COLOR: Color = Color(0.93, 0.95, 0.89)
const BODY_COLOR: Color = Color(0.85, 0.89, 0.84)
const MUTED_COLOR: Color = Color(0.66, 0.72, 0.66)
const ACCENT_LINE: Color = Color(0.30, 0.42, 0.28, 0.9)

const MAX_WIDTH: float = 1060.0
const MAX_HEIGHT: float = 692.0
const VIEWPORT_MARGIN: float = 28.0

var _panel: PanelContainer
var _return_paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_build()

	EventBus.help_requested.connect(toggle)
	get_viewport().size_changed.connect(_fit_to_viewport)

	# Teach first-time players immediately — but never during the automated
	# harnesses, which need the simulation running unpaused.
	if not GameManager.help_seen and not _is_test_run():
		call_deferred("open")

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_H, KEY_F1:
			toggle()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if visible:
				close()
				get_viewport().set_input_as_handled()

# --- Open / close ---

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	# The auto-open is deferred from _ready, which runs before Main decides
	# the boot mode — so the dedicated-server guard must live here. A paused
	# tree on the match server would freeze every tribe's simulation.
	if Net.is_headless_server():
		return
	if visible or GameManager.state == GameManager.GameState.GAME_OVER:
		return
	GameManager.help_seen = true
	# Remember the pre-open pause state so closing help never overrides a
	# pause the player set deliberately with the HUD's Pause button.
	_return_paused = get_tree().paused
	_fit_to_viewport()
	visible = true
	# In multiplayer the overlay can't pause the server, so don't pause the
	# local tree either — the match keeps rendering behind the help.
	if Net.mode != Net.Mode.CLIENT:
		get_tree().paused = true

func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _return_paused

# --- Layout ---

func _fit_to_viewport() -> void:
	if _panel == null:
		return
	var vp: Vector2 = get_viewport_rect().size
	_panel.custom_minimum_size = Vector2(
		minf(MAX_WIDTH, vp.x - VIEWPORT_MARGIN),
		minf(MAX_HEIGHT, vp.y - VIEWPORT_MARGIN)
	)

func _build() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.72)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP  # modal shield
	add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_panel.add_child(root)

	var title: Label = Label.new()
	title.text = "How to Play"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	root.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "Age of Amazon — command your tribe, tame the endless rainforest, raze the enemy Town Center."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", MUTED_COLOR)
	root.add_child(subtitle)

	var rule: ColorRect = ColorRect.new()
	rule.color = ACCENT_LINE
	rule.custom_minimum_size = Vector2(0, 2)
	root.add_child(rule)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 30)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(columns)

	var left: VBoxContainer = _column()
	var right: VBoxContainer = _column()
	columns.add_child(left)
	columns.add_child(right)
	_build_left(left)
	_build_right(right)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)

	var hint: Label = Label.new()
	hint.text = "Press H or Esc to close  ·  reopen anytime with the Help button"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", MUTED_COLOR)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(hint)

	var start: Button = Button.new()
	start.text = "Start Playing"
	start.focus_mode = Control.FOCUS_NONE
	start.custom_minimum_size = Vector2(152, 38)
	_style_primary(start)
	start.pressed.connect(close)
	footer.add_child(start)

# --- Content ---

func _build_left(col: VBoxContainer) -> void:
	_add_section(col, "Goal")
	_add_body(col, "Destroy every rival Town Center — lose yours and you are out. The map is endless: explore it, gather from it, build on it, and out-fight your rivals.")

	_add_section(col, "Move the camera")
	_add_control(col, "W A S D / Arrows", "Pan across the world")
	_add_control(col, "Middle-mouse drag", "Grab and drag the view")
	_add_control(col, "Mouse wheel", "Zoom in and out")
	_add_control(col, "Screen edge", "Nudge the view (desktop)")
	_add_control(col, "Click minimap", "Jump the camera there")

	_add_section(col, "Select")
	_add_control(col, "Left-click", "Pick a unit or your Town Center")
	_add_control(col, "Left-drag", "Box-select a group of units")
	_add_control(col, "Shift-click", "Add units to the selection")

	_add_section(col, "Command")
	_add_control(col, "Right-click ground", "March there in formation")
	_add_control(col, "Right-click a resource", "Send villagers to gather it")
	_add_control(col, "Right-click an enemy", "Attack it")
	_add_control(col, "Right-click an animal", "Hunt it for food")
	_add_control(col, "Right-click your damaged building", "Villagers build or repair it")

func _build_right(col: VBoxContainer) -> void:
	_add_section(col, "Your people")
	_add_unit(col, "villager", "Gathers food, wood and jade and carries it back to the Town Center. Fragile in a fight — keep them working. Costs 50 food.")
	_add_unit(col, "warrior", "Your muscle — auto-attacks enemies it can see and defends itself when struck. Costs 40 food and 20 wood.")
	_add_unit(col, "archer", "Shoots from four times a warrior's reach but folds in melee. Trains at the Barracks. Costs 50 food and 30 wood.")
	_add_body(col, "Select your Town Center to train more. Population starts capped at %d — build houses to raise it (up to %d)." % [Constants.POPULATION_CAP, Constants.POPULATION_CEILING])

	_add_section(col, "Build")
	_add_body(col, "Select villagers and pick a building, then click open scouted ground to place it — your villagers raise it plank by plank (more builders, faster build).")
	_add_body(col, "•  House (30 wood) — +5 population.")
	_add_body(col, "•  Barracks (60 wood, 20 food) — trains warriors.")
	_add_body(col, "•  Watchtower (40 wood) — watches far into the fog.")
	_add_body(col, "Unfinished sites are fragile and can be razed — guard them. Villagers also repair damaged buildings (1 wood per swing).")

	_add_section(col, "Resources")
	_add_resource(col, Constants.ResourceType.FOOD, "Food", "trains villagers and warriors")
	_add_resource(col, Constants.ResourceType.WOOD, "Wood", "needed to train warriors")
	_add_resource(col, Constants.ResourceType.JADE, "Jade", "a rare gem, scarce across the map")

	_add_section(col, "Fog of War")
	_add_body(col, "You see only what your units and buildings can see right now. Explored ground is remembered but dimmed; the unknown stays black. The enemy is just as blind — so scouting wins games.")

	_add_section(col, "Tips")
	_add_body(col, "•  Keep every villager gathering — idle villagers lose games.")
	_add_body(col, "•  Hunt capybaras and tapirs for food — but beware jaguars, bush dog packs, and caimans lurking at the water's edge.")
	_add_body(col, "•  Scout before you strike — you can't hit what you can't see.")
	_add_body(col, "•  A watchtower on a border ridge is worth three patrols.")
	_add_body(col, "•  Solo battles autosave every few seconds — closing the tab is safe; pick Continue when you return.")

# --- Builders ---

func _column() -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return col

func _add_section(col: VBoxContainer, title: String) -> void:
	if col.get_child_count() > 0:
		var gap: Control = Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		col.add_child(gap)
	var header: Label = Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 17)
	header.add_theme_color_override("font_color", HEADER_COLOR)
	col.add_child(header)

func _add_body(col: VBoxContainer, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", BODY_COLOR)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(label)

func _add_control(col: VBoxContainer, key: String, desc: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var key_label: Label = Label.new()
	key_label.text = key
	key_label.custom_minimum_size = Vector2(132, 0)
	key_label.add_theme_font_size_override("font_size", 13)
	key_label.add_theme_color_override("font_color", KEY_COLOR)
	row.add_child(key_label)

	var desc_label: Label = Label.new()
	desc_label.text = desc
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", BODY_COLOR)
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(desc_label)

	col.add_child(row)

func _add_unit(col: VBoxContainer, unit_type: String, desc: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var icon: TextureRect = TextureRect.new()
	var frames: Array = AssetLibrary.get_unit_frames(GameManager.local_player_id, unit_type)
	if frames.size() > 0:
		icon.texture = frames[0] as Texture2D
	icon.custom_minimum_size = Vector2(46, 46)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 1)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label: Label = Label.new()
	name_label.text = unit_type.capitalize()
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", NAME_COLOR)
	body.add_child(name_label)

	var desc_label: Label = Label.new()
	desc_label.text = desc
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", BODY_COLOR)
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(desc_label)

	row.add_child(body)
	col.add_child(row)

func _add_resource(col: VBoxContainer, type: int, name: String, use: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var icon: TextureRect = TextureRect.new()
	icon.texture = AssetLibrary.resource_icon(type)
	icon.custom_minimum_size = Vector2(26, 26)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var label: Label = Label.new()
	label.text = "%s — %s" % [name, use]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", BODY_COLOR)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	col.add_child(row)

# --- Styling ---

func _panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.07, 0.98)
	style.border_color = Color(0.30, 0.42, 0.28, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(22)
	return style

func _style_primary(button: Button) -> void:
	button.add_theme_color_override("font_color", Color(0.06, 0.11, 0.06))
	button.add_theme_color_override("font_hover_color", Color(0.04, 0.09, 0.04))
	button.add_theme_color_override("font_pressed_color", Color(0.04, 0.09, 0.04))
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.52, 0.76, 0.44)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.60, 0.84, 0.50)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.44, 0.66, 0.38)))

func _button_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	style.set_content_margin_all(8)
	return style

# --- Misc ---

func _is_test_run() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--test") or arg.begins_with("--capture"):
			return true
	return false
