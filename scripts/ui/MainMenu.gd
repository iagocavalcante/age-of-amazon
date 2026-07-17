# scripts/ui/MainMenu.gd
extends Control

# Entry screen. The backdrop is not artwork OF the game — it IS the game:
# real WorldGen chunks rendered by TerrainArtist, the player's gold pyramid,
# and a handful of villagers, drifting slowly behind the menu. All UI is
# code-built in the same palette as the in-game HUD.
#
# Flow logic is unchanged from the first version: Single Player loads
# Main.tscn offline; the friends flow talks to the Gateway (rooms by code)
# and hands the match URL to Main via Net.pending_match_url. Headless /
# server / harness runs skip the menu entirely.

const MAIN_SCENE: String = "res://scenes/main/Main.tscn"
const CONFIG_PATH: String = "res://server_config.json"
const BACKDROP_SEED: int = 20260712
# Invite links from non-web builds point at the public site.
const FALLBACK_SHARE_URL: String = "https://aoa.iagocavalcante.com/"

# Palette (mirrors the in-game HUD, gold from the town center).
const COLOR_BG: Color = Color("#0b160d")
const COLOR_PANEL: Color = Color(0.07, 0.12, 0.09, 0.94)
const COLOR_PANEL_BORDER: Color = Color(0.24, 0.36, 0.24, 0.9)
const COLOR_GOLD: Color = Color("#e4b45c")
const COLOR_GOLD_DARK: Color = Color("#211609")
const COLOR_TEXT: Color = Color("#d8e4d2")
const COLOR_TEXT_DIM: Color = Color(0.72, 0.78, 0.70, 0.65)

var _gateway_url: String = "ws://127.0.0.1:9000"
var _match_url_template: String = "ws://127.0.0.1:{port}"
# Stamped into server_config.json at deploy time; "dev" when absent, so any
# screenshot of the menu tells us exactly which build someone is running.
var _build_stamp: String = "dev"

var _backdrop: Node2D
var _drift_time: float = 0.0

var _main_page: VBoxContainer
var _friends_page: VBoxContainer
var _status: Label
var _url_edit: LineEdit
var _code_edit: LineEdit
var _lobby_panel: PanelContainer
var _lobby_label: Label
var _start_button: Button
var _invite_edit: LineEdit
var _room_code: String = ""
var _footer: Label
var _connected: bool = false
var _pending_action: Callable = Callable()
var _name_edit: LineEdit
var _rank_label: Label
var _board_panel: PanelContainer
var _board_label: Label
var _daily_panel: PanelContainer
var _daily_label: Label
var _profile: Dictionary = {}

func _ready() -> void:
	if _should_skip_menu(OS.get_cmdline_user_args()):
		get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)
		return
	Sfx.ambience_stop()
	_load_config()
	_build_backdrop()
	_build_ui()

	Gateway.room_updated.connect(_on_room_updated)
	Gateway.hello_result.connect(_on_hello_result)
	Gateway.match_ready.connect(_on_match_ready)
	Gateway.gateway_error.connect(_on_gateway_error)
	multiplayer.connected_to_server.connect(_on_gateway_connected)
	multiplayer.connection_failed.connect(
		func() -> void: _set_status("Could not reach the lobby server."))
	multiplayer.server_disconnected.connect(_on_gateway_lost)

	# Back in the menu: daily state must not leak into other modes (a stale
	# daily seed would replay today's map in "New Game").
	GameManager.daily_mode = false
	GameManager.map_seed = randi()
	_submit_pending_daily()

	# Why the previous session ended (disconnect, refusal, ...).
	if Net.last_status != "":
		_set_status(Net.last_status)
		Net.last_status = ""

	# Dev affordance: open the friends page directly for layout review.
	if "--show-friends" in OS.get_cmdline_user_args():
		_show_friends(true)
	if "--mock-lobby" in OS.get_cmdline_user_args():
		_show_friends(true)
		_on_room_updated("G75U", 1, 0)

	_check_invite_link()

# Invite links (…/?room=CODE) drop a friend straight into the room.
func _check_invite_link() -> void:
	if not OS.has_feature("web"):
		return
	var code: Variant = JavaScriptBridge.eval(
		"new URLSearchParams(window.location.search).get('room') || ''", true)
	if not (code is String) or String(code).length() != Gateway.CODE_LENGTH:
		return
	var room: String = String(code).to_upper()
	_show_friends(true)
	_code_edit.text = room
	_set_status("Joining room %s…" % room)
	_gateway_action(func() -> void: Gateway.join_room(room))

func _should_skip_menu(args: PackedStringArray) -> bool:
	for arg: String in args:
		for prefix: String in ["--test", "--capture", "--server", "--gateway", "--join"]:
			if arg.begins_with(prefix):
				return true
	return false

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if parsed is Dictionary:
		_gateway_url = parsed.get("gateway_url", _gateway_url)
		_match_url_template = parsed.get("match_url_template", _match_url_template)
		_build_stamp = parsed.get("build", _build_stamp)

# --- Backdrop: a real slice of the game world ---

func _process(delta: float) -> void:
	if _backdrop == null:
		return
	_drift_time += delta
	var vp: Vector2 = get_viewport_rect().size
	# Anchored low-left so the backdrop pyramid keeps clear of the title.
	_backdrop.position = vp / 2.0 + Vector2(-300, 210) + Vector2(
		sin(_drift_time * 0.05) * 46.0, cos(_drift_time * 0.033) * 26.0)

func _build_backdrop() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_backdrop = Node2D.new()
	_backdrop.modulate = Color(0.52, 0.58, 0.52)
	add_child(_backdrop)

	# Real terrain: a 3x3 block of chunks around the origin clearing.
	var gen: WorldGen = WorldGen.new(BACKDROP_SEED)
	var artist: TerrainArtist = TerrainArtist.new(BACKDROP_SEED)
	for cy in range(-1, 2):
		for cx in range(-1, 2):
			var chunk: ChunkData = ChunkData.new(Vector2i(cx, cy), gen)
			var rendered: Dictionary = artist.render_chunk(gen, chunk)
			var ground: Sprite2D = Sprite2D.new()
			ground.texture = rendered["ground"]
			ground.centered = false
			ground.position = rendered["origin"]
			ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_backdrop.add_child(ground)

	# The scene: a pyramid, its keepers, the forest edge.
	_backdrop_sprite(AssetLibrary.get_town_center_texture(0),
		Constants.grid_to_world(0, 0) + Vector2(0, -26.0))
	var scatter: RandomNumberGenerator = RandomNumberGenerator.new()
	scatter.seed = BACKDROP_SEED
	for _i in range(14):
		var cell: Vector2i = Vector2i(scatter.randi_range(-9, 9), scatter.randi_range(-7, 7))
		if Vector2(cell).length() < 4.0:
			continue
		var tree: ImageTexture = AssetLibrary.tree_textures[
			scatter.randi_range(0, AssetLibrary.tree_textures.size() - 1)]
		_backdrop_sprite(tree,
			Constants.grid_to_world(cell.x, cell.y) + Vector2(0, -tree.get_height() / 4.0))
	for cell: Vector2i in [Vector2i(3, 1), Vector2i(-1, 3), Vector2i(2, -2)]:
		var frames: Array = AssetLibrary.get_unit_frames(0, "villager")
		_backdrop_sprite(frames[0],
			Constants.grid_to_world(cell.x, cell.y) + Vector2(0, -8.0))

	# Vignette: readable center column, world fading into the canopy dark.
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([
		Color(COLOR_BG, 0.25), Color(COLOR_BG, 0.62), Color(COLOR_BG, 1.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	var radial: GradientTexture2D = GradientTexture2D.new()
	radial.gradient = gradient
	radial.fill = GradientTexture2D.FILL_RADIAL
	radial.fill_from = Vector2(0.5, 0.45)
	radial.fill_to = Vector2(0.5, 1.05)
	var vignette: TextureRect = TextureRect.new()
	vignette.texture = radial
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

func _backdrop_sprite(texture: Texture2D, world_pos: Vector2) -> void:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.position = world_pos
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_backdrop.add_child(sprite)

# --- UI ---

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.add_theme_constant_override("separation", 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)

	# Emblem: the gold pyramid itself, pixel-crisp.
	var emblem: TextureRect = TextureRect.new()
	emblem.texture = AssetLibrary.get_town_center_texture(0)
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	emblem.custom_minimum_size = Vector2(0, 132)
	column.add_child(emblem)

	var title: Label = Label.new()
	title.text = "AGE OF AMAZON"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _display_font(9))
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	column.add_child(title)

	var tagline: Label = Label.new()
	tagline.text = "COMMAND YOUR TRIBE  ·  TAME THE ENDLESS RAINFOREST"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_override("font", _display_font(3))
	tagline.add_theme_font_size_override("font_size", 12)
	tagline.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	column.add_child(tagline)

	column.add_child(_spacer(14))

	var card: PanelContainer = PanelContainer.new()
	var card_style: StyleBoxFlat = StyleBoxFlat.new()
	card_style.bg_color = COLOR_PANEL
	card_style.border_color = COLOR_PANEL_BORDER
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(8)
	card_style.set_content_margin_all(18)
	card_style.shadow_color = Color(0, 0, 0, 0.45)
	card_style.shadow_size = 18
	card.add_theme_stylebox_override("panel", card_style)
	card.custom_minimum_size = Vector2(400, 0)
	column.add_child(card)

	var pages: VBoxContainer = VBoxContainer.new()
	card.add_child(pages)

	_main_page = VBoxContainer.new()
	_main_page.add_theme_constant_override("separation", 10)
	pages.add_child(_main_page)

	if SaveGame.has_save():
		var cont: Button = _primary_button("Continue Your Game")
		cont.pressed.connect(func() -> void:
			SaveGame.pending_resume = true
			get_tree().change_scene_to_file(MAIN_SCENE))
		_main_page.add_child(cont)
	var single: Button = _primary_button("Play vs. the Forest AI") \
		if not SaveGame.has_save() else _secondary_button("New Game vs. the Forest AI")
	single.pressed.connect(func() -> void:
		SaveGame.clear()
		get_tree().change_scene_to_file(MAIN_SCENE))
	_main_page.add_child(single)

	# Difficulty: three small toggles under the solo button.
	var diff_row: HBoxContainer = HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_page.add_child(diff_row)
	var diff_buttons: Dictionary = {}
	for diff: String in ["easy", "normal", "hard"]:
		var toggle: Button = _text_button(diff.capitalize())
		diff_buttons[diff] = toggle
		var captured: String = diff
		toggle.pressed.connect(func() -> void:
			GameManager.ai_difficulty = captured
			for other: String in diff_buttons:
				diff_buttons[other].add_theme_color_override("font_color",
					COLOR_GOLD if other == captured else COLOR_TEXT_DIM))
		diff_row.add_child(toggle)
	diff_buttons[GameManager.ai_difficulty].add_theme_color_override(
		"font_color", COLOR_GOLD)

	var friends: Button = _secondary_button("Play with Friends")
	friends.pressed.connect(func() -> void: _show_friends(true))
	_main_page.add_child(friends)

	# Daily challenge: one shared map per UTC day, race to win it. Fixed
	# normal AI so every time on the board was earned on equal terms.
	var daily: Button = _secondary_button(
		"Daily Challenge  ·  %s" % GameManager.daily_date())
	daily.pressed.connect(func() -> void:
		SaveGame.clear()
		GameManager.ai_difficulty = "normal"
		GameManager.daily_mode = true
		GameManager.map_seed = GameManager.daily_seed()
		get_tree().change_scene_to_file(MAIN_SCENE))
	_main_page.add_child(daily)

	var daily_board_button: Button = _text_button("today's times")
	daily_board_button.pressed.connect(_fetch_daily)
	_main_page.add_child(daily_board_button)
	_daily_panel = PanelContainer.new()
	var daily_style: StyleBoxFlat = StyleBoxFlat.new()
	daily_style.bg_color = Color(0.05, 0.09, 0.06, 0.85)
	daily_style.border_color = Color(0.25, 0.35, 0.22, 0.9)
	daily_style.set_border_width_all(1)
	daily_style.set_corner_radius_all(6)
	daily_style.set_content_margin_all(12)
	_daily_panel.add_theme_stylebox_override("panel", daily_style)
	_daily_panel.visible = false
	_main_page.add_child(_daily_panel)
	_daily_label = Label.new()
	_daily_label.add_theme_font_size_override("font_size", 12)
	_daily_label.add_theme_color_override("font_color", COLOR_TEXT)
	_daily_panel.add_child(_daily_label)

	var seat: Dictionary = Net.load_seat()
	if not seat.is_empty():
		var rejoin: Button = _secondary_button("Rejoin Last Match")
		rejoin.pressed.connect(func() -> void:
			Net.pending_match_url = seat["url"]
			Net.pending_token = seat["token"]
			get_tree().change_scene_to_file(MAIN_SCENE))
		_main_page.add_child(rejoin)

	_build_friends_page(pages)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pages.add_child(_status)

	var footer: Label = Label.new()
	_footer = footer
	footer.text = "FOG OF WAR  ·  2–4 TRIBES  ·  BUILD %s" % _build_stamp.to_upper()
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_override("font", _display_font(2))
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", Color(COLOR_TEXT_DIM, 0.45))
	footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	footer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer.offset_bottom = -16
	add_child(footer)

func _build_friends_page(parent: Control) -> void:
	_friends_page = VBoxContainer.new()
	_friends_page.add_theme_constant_override("separation", 10)
	_friends_page.visible = false
	parent.add_child(_friends_page)

	var back_row: HBoxContainer = HBoxContainer.new()
	_friends_page.add_child(back_row)
	var back: Button = _text_button("‹ Back")
	back.pressed.connect(func() -> void: _show_friends(false))
	back_row.add_child(back)
	var heading: Label = Label.new()
	heading.text = "PLAY WITH FRIENDS"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_override("font", _display_font(3))
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", COLOR_TEXT)
	back_row.add_child(heading)
	back_row.add_child(_spacer_h(52))

	_profile = Net.load_profile()
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	_friends_page.add_child(name_row)
	var name_label: Label = Label.new()
	name_label.text = "your name"
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.text = _profile["name"]
	_name_edit.max_length = 16
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_input(_name_edit)
	# Claim only when the player is DONE typing — claiming per keystroke
	# once registered every prefix of a name as its own player.
	_name_edit.text_changed.connect(func(text: String) -> void:
		_profile["name"] = text.strip_edges()
		Net.save_profile(_profile))
	_name_edit.text_submitted.connect(func(_text: String) -> void: _claim_now())
	_name_edit.focus_exited.connect(_claim_now)
	name_row.add_child(_name_edit)
	_rank_label = Label.new()
	_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_label.add_theme_font_size_override("font_size", 11)
	_rank_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_friends_page.add_child(_rank_label)

	var create: Button = _primary_button("Create a Room")
	create.pressed.connect(func() -> void: _gateway_action(Gateway.create_room))
	_friends_page.add_child(create)

	var divider: Label = Label.new()
	divider.text = "— or join with a code —"
	divider.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	divider.add_theme_font_size_override("font_size", 12)
	divider.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_friends_page.add_child(divider)

	var join_row: HBoxContainer = HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_friends_page.add_child(join_row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "ROOM CODE"
	_code_edit.max_length = 4
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_input(_code_edit)
	join_row.add_child(_code_edit)
	var join: Button = _secondary_button("Join")
	join.pressed.connect(func() -> void:
		var code: String = _code_edit.text
		_gateway_action(func() -> void: Gateway.join_room(code)))
	join_row.add_child(join)

	_lobby_panel = PanelContainer.new()
	var lobby_style: StyleBoxFlat = StyleBoxFlat.new()
	lobby_style.bg_color = Color(0.05, 0.09, 0.06, 0.85)
	lobby_style.border_color = COLOR_GOLD
	lobby_style.set_border_width_all(1)
	lobby_style.set_corner_radius_all(6)
	lobby_style.set_content_margin_all(12)
	_lobby_panel.add_theme_stylebox_override("panel", lobby_style)
	_lobby_panel.visible = false
	_friends_page.add_child(_lobby_panel)
	var lobby_box: VBoxContainer = VBoxContainer.new()
	lobby_box.add_theme_constant_override("separation", 8)
	_lobby_panel.add_child(lobby_box)
	_lobby_label = Label.new()
	_lobby_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_label.add_theme_font_override("font", _display_font(2))
	_lobby_label.add_theme_font_size_override("font_size", 15)
	_lobby_label.add_theme_color_override("font_color", COLOR_GOLD)
	lobby_box.add_child(_lobby_label)

	# One-tap sharing: the invite link is visible (manual copy always works,
	# even where the clipboard API doesn't) and one button away.
	var share_row: HBoxContainer = HBoxContainer.new()
	share_row.add_theme_constant_override("separation", 8)
	lobby_box.add_child(share_row)
	_invite_edit = LineEdit.new()
	_invite_edit.editable = false
	_invite_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_edit.add_theme_font_size_override("font_size", 11)
	_style_input(_invite_edit)
	share_row.add_child(_invite_edit)
	var copy_link: Button = _secondary_button("Copy Link")
	copy_link.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_invite_edit.text)
		_set_status("Invite link copied — send it to a friend."))
	share_row.add_child(copy_link)
	var copy_code: Button = _text_button("copy just the code")
	copy_code.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_room_code)
		_set_status("Code %s copied." % _room_code))
	lobby_box.add_child(copy_code)

	_start_button = _primary_button("Start Match")
	_start_button.visible = false
	_start_button.pressed.connect(func() -> void: Gateway.start_match())
	lobby_box.add_child(_start_button)

	# The plumbing, tucked away where players never need it.
	var server_row: HBoxContainer = HBoxContainer.new()
	server_row.add_theme_constant_override("separation", 8)
	_friends_page.add_child(server_row)
	var server_label: Label = Label.new()
	server_label.text = "server"
	server_label.add_theme_font_size_override("font_size", 11)
	server_label.add_theme_color_override("font_color", Color(COLOR_TEXT_DIM, 0.4))
	server_row.add_child(server_label)
	_url_edit = LineEdit.new()
	_url_edit.text = _gateway_url
	_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_edit.add_theme_font_size_override("font_size", 11)
	_style_input(_url_edit)
	_url_edit.modulate = Color(1, 1, 1, 0.45)
	server_row.add_child(_url_edit)

	var board_button: Button = _text_button("leaderboard")
	board_button.pressed.connect(_fetch_leaderboard)
	_friends_page.add_child(board_button)
	_board_panel = PanelContainer.new()
	var board_style: StyleBoxFlat = StyleBoxFlat.new()
	board_style.bg_color = Color(0.05, 0.09, 0.06, 0.85)
	board_style.border_color = Color(0.25, 0.35, 0.22, 0.9)
	board_style.set_border_width_all(1)
	board_style.set_corner_radius_all(6)
	board_style.set_content_margin_all(12)
	_board_panel.add_theme_stylebox_override("panel", board_style)
	_board_panel.visible = false
	_friends_page.add_child(_board_panel)
	_board_label = Label.new()
	_board_label.add_theme_font_size_override("font_size", 12)
	_board_label.add_theme_color_override("font_color", COLOR_TEXT)
	_board_panel.add_child(_board_label)

func _leaderboard_url() -> String:
	# wss://host/ws -> https://host/leaderboard (Caddy route);
	# ws://host:9000 -> http://host:9001/leaderboard (dev, health port).
	var ws_url: String = _url_edit.text.strip_edges()
	if ws_url.begins_with("wss://"):
		return "https://" + ws_url.trim_prefix("wss://").get_slice("/", 0) + "/leaderboard"
	var host_port: String = ws_url.trim_prefix("ws://").get_slice("/", 0)
	var host: String = host_port.get_slice(":", 0)
	var port: int = int(host_port.get_slice(":", 1)) if host_port.contains(":") else 9000
	return "http://%s:%d/leaderboard" % [host, port + 1]

# A won daily run was stashed by GameManager; push it to the gateway now
# (identity rides the same hello as everything else).
func _submit_pending_daily() -> void:
	var pending: Dictionary = GameManager.take_pending_daily()
	if pending.is_empty():
		return
	Gateway.daily_result.connect(
		func(ok: bool, reason: String) -> void:
			if ok:
				GameManager.clear_pending_daily()
				_set_status("Daily time submitted — %d:%02d.%s" % [
					int(pending["seconds"]) / 60, int(pending["seconds"]) % 60,
					("  (" + reason + ")") if reason != "" else ""])
			else:
				GameManager.clear_pending_daily()
				_set_status("Daily submit failed: %s" % reason),
		CONNECT_ONE_SHOT)
	_gateway_action(func() -> void:
		Gateway.submit_daily_score(String(pending["date"]), float(pending["seconds"])))

func _daily_url() -> String:
	return _leaderboard_url().replace("/leaderboard", "/daily")

func _fetch_daily() -> void:
	var request: HTTPRequest = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(
		func(_result: int, code: int, _headers: PackedStringArray, response: PackedByteArray) -> void:
			request.queue_free()
			_show_daily(code, response))
	if request.request(_daily_url()) != OK:
		request.queue_free()
		_set_status("Could not reach the daily board.")

func _show_daily(code: int, response: PackedByteArray) -> void:
	if code != 200:
		_set_status("Could not reach the daily board.")
		return
	var parsed: Variant = JSON.parse_string(response.get_string_from_utf8())
	if not (parsed is Dictionary) or not parsed.get("ok", false):
		_set_status("Could not reach the daily board.")
		return
	var rows: Array = parsed["scores"]
	if rows.is_empty():
		_daily_label.text = "No times yet for %s — be the first!" % parsed["date"]
	else:
		var lines: Array[String] = []
		for i in range(rows.size()):
			var row: Dictionary = rows[i]
			lines.append("%2d.  %-16s  %d:%02d" % [i + 1, row["name"],
				int(row["seconds"]) / 60, int(row["seconds"]) % 60])
		_daily_label.text = "\n".join(lines)
	_daily_panel.visible = true

func _fetch_leaderboard() -> void:
	var request: HTTPRequest = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(
		func(_result: int, code: int, _headers: PackedStringArray, response: PackedByteArray) -> void:
			request.queue_free()
			_show_leaderboard(code, response))
	if request.request(_leaderboard_url()) != OK:
		request.queue_free()
		_set_status("Could not reach the leaderboard.")

func _show_leaderboard(code: int, response: PackedByteArray) -> void:
	if code != 200:
		_set_status("Could not reach the leaderboard.")
		return
	var parsed: Variant = JSON.parse_string(response.get_string_from_utf8())
	if not (parsed is Dictionary) or not parsed.get("ok", false):
		_set_status("Could not reach the leaderboard.")
		return
	var rows: Array = parsed["players"]
	if rows.is_empty():
		_board_label.text = "No ranked players yet — win a match!"
	else:
		var lines: Array[String] = []
		for i in range(mini(rows.size(), 10)):
			var row: Dictionary = rows[i]
			lines.append("%2d.  %-16s  %4d elo   %dW %dL" % [i + 1,
				row["name"], int(row["elo"]), int(row["wins"]), int(row["losses"])])
		_board_label.text = "\n".join(lines)
	_board_panel.visible = true

func _show_friends(show_friends: bool) -> void:
	_friends_page.visible = show_friends
	_main_page.visible = not show_friends
	# The lobby card runs tall; give it the footer's breathing room.
	if _footer != null:
		_footer.visible = not show_friends
	_set_status("")

# --- Style helpers ---

func _display_font(tracking: int) -> FontVariation:
	var font: FontVariation = FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.spacing_glyph = tracking
	return font

func _spacer(height: float) -> Control:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer

func _spacer_h(width: float) -> Control:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(width, 0)
	return spacer

func _flat_style(bg: Color, border: Color, radius: int = 6) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	return style

func _primary_button(text: String) -> Button:
	var button: Button = Button.new()
	button.pressed.connect(func() -> void: Sfx.play("click"))
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _flat_style(COLOR_GOLD, COLOR_GOLD))
	button.add_theme_stylebox_override("hover",
		_flat_style(COLOR_GOLD.lightened(0.12), COLOR_GOLD.lightened(0.2)))
	button.add_theme_stylebox_override("pressed",
		_flat_style(COLOR_GOLD.darkened(0.15), COLOR_GOLD.darkened(0.1)))
	button.add_theme_stylebox_override("disabled",
		_flat_style(Color(COLOR_GOLD, 0.25), Color(COLOR_GOLD, 0.2)))
	button.add_theme_color_override("font_disabled_color", Color(COLOR_TEXT_DIM, 0.5))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, COLOR_GOLD_DARK)
	button.add_theme_font_size_override("font_size", 16)
	return button

func _secondary_button(text: String) -> Button:
	var button: Button = Button.new()
	button.pressed.connect(func() -> void: Sfx.play("click"))
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	var base: Color = Color(0.10, 0.18, 0.12, 0.9)
	button.add_theme_stylebox_override("normal", _flat_style(base, COLOR_PANEL_BORDER))
	button.add_theme_stylebox_override("hover", _flat_style(base.lightened(0.06), COLOR_GOLD))
	button.add_theme_stylebox_override("pressed", _flat_style(base.darkened(0.2), COLOR_GOLD))
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 15)
	return button

func _text_button(text: String) -> Button:
	var button: Button = Button.new()
	button.pressed.connect(func() -> void: Sfx.play("click"))
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_font_size_override("font_size", 13)
	return button

func _style_input(edit: LineEdit) -> void:
	edit.add_theme_stylebox_override("normal",
		_flat_style(Color(0.04, 0.08, 0.05, 0.9), COLOR_PANEL_BORDER))
	edit.add_theme_stylebox_override("focus",
		_flat_style(Color(0.04, 0.08, 0.05, 0.95), COLOR_GOLD))
	edit.add_theme_color_override("font_color", COLOR_TEXT)

# --- Gateway flow (unchanged behavior) ---

# Connect lazily on the first action; queue the action until connected.
func _gateway_action(action: Callable) -> void:
	if _connected:
		action.call()
		return
	_pending_action = action
	_set_status("Connecting…")
	if Gateway.connect_to_gateway(_url_edit.text.strip_edges()) != OK:
		_set_status("That server address doesn't look right.")

func _on_gateway_connected() -> void:
	_connected = true
	# Claim the player name first; RPCs are ordered, so the queued room
	# action lands after the claim is processed.
	Gateway.send_hello(_profile["name"], _profile["secret"])
	if _pending_action.is_valid():
		_pending_action.call()
		_pending_action = Callable()

func _on_hello_result(ok: bool, reason: String, elo: int, wins: int, losses: int) -> void:
	if ok:
		_rank_label.text = "%s  ·  %d elo  ·  %dW %dL" % [
			_profile["name"], elo, wins, losses]
	else:
		_set_status(reason + " — pick another name.")
		_rank_label.text = ""

func _claim_now() -> void:
	if _connected and _current_name_valid():
		Gateway.send_hello(_profile["name"], _profile["secret"])

func _current_name_valid() -> bool:
	return RegEx.create_from_string(Gateway.NAME_REGEX) \
		.search(_name_edit.text.strip_edges()) != null

func _invite_link(code: String) -> String:
	var base: String = FALLBACK_SHARE_URL
	if OS.has_feature("web"):
		var origin: Variant = JavaScriptBridge.eval(
			"window.location.origin + window.location.pathname", true)
		if origin is String and String(origin).begins_with("http"):
			base = String(origin)
	return "%s?room=%s" % [base, code]

func _on_room_updated(code: String, player_count: int, my_slot: int,
		names: PackedStringArray = PackedStringArray()) -> void:
	_room_code = code
	_invite_edit.text = _invite_link(code)
	_lobby_panel.visible = true
	_lobby_label.text = "ROOM %s  —  %d/%d PLAYERS" % [code, player_count, Gateway.MAX_PLAYERS]
	if not names.is_empty():
		_lobby_label.text += "\n" + " · ".join(names)
	_start_button.visible = my_slot == 0
	_start_button.disabled = player_count < Gateway.MIN_PLAYERS
	if my_slot == 0:
		_set_status("Share the code — the match starts when you do."
			if player_count >= Gateway.MIN_PLAYERS else "Share the code with a friend.")
	else:
		_set_status("Waiting for the host to start…")

func _on_match_ready(port: int, token: String) -> void:
	Net.pending_match_url = _match_url_template.replace("{port}", str(port))
	Net.pending_token = token
	Net.save_seat(Net.pending_match_url, token)
	get_tree().change_scene_to_file(MAIN_SCENE)

func _on_gateway_error(reason: String) -> void:
	_set_status(reason)

func _on_gateway_lost() -> void:
	_connected = false
	_lobby_panel.visible = false
	_set_status("Lost the lobby connection.")

func _set_status(text: String) -> void:
	_status.text = text
