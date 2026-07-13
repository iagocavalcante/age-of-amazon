# scripts/ui/MainMenu.gd
extends Control

# Entry scene: Single Player launches the classic offline game; Multiplayer
# talks to the gateway (create/join room by code), then hands the match URL
# to Main via Net.pending_match_url. Headless/server/harness runs skip the
# menu entirely so every CLI workflow behaves exactly as before.

const MAIN_SCENE: String = "res://scenes/main/Main.tscn"
const CONFIG_PATH: String = "res://server_config.json"

var _gateway_url: String = "ws://127.0.0.1:9000"
var _match_url_template: String = "ws://127.0.0.1:{port}"

var _status: Label
var _url_edit: LineEdit
var _code_edit: LineEdit
var _lobby_panel: PanelContainer
var _lobby_label: Label
var _start_button: Button
var _connected: bool = false
var _pending_action: Callable = Callable()
var _my_slot: int = -1
var _player_count: int = 0

func _ready() -> void:
	if _should_skip_menu(OS.get_cmdline_user_args()):
		get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)
		return
	_load_config()
	_build_ui()

	Gateway.room_updated.connect(_on_room_updated)
	Gateway.match_ready.connect(_on_match_ready)
	Gateway.gateway_error.connect(_on_gateway_error)
	multiplayer.connected_to_server.connect(_on_gateway_connected)
	multiplayer.connection_failed.connect(
		func() -> void: _set_status("Could not reach the gateway."))
	multiplayer.server_disconnected.connect(_on_gateway_lost)

	# Why the previous session ended (disconnect, refusal, ...).
	if Net.last_status != "":
		_set_status(Net.last_status)
		Net.last_status = ""

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

# --- UI ---

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.05, 0.09, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(360, 0)
	add_child(box)

	var title: Label = Label.new()
	title.text = "AGE OF AMAZON"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	box.add_child(title)

	var single: Button = Button.new()
	single.text = "Single Player"
	single.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_SCENE))
	box.add_child(single)

	box.add_child(HSeparator.new())

	var mp_label: Label = Label.new()
	mp_label.text = "Multiplayer"
	mp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(mp_label)

	_url_edit = LineEdit.new()
	_url_edit.text = _gateway_url
	_url_edit.placeholder_text = "gateway url"
	box.add_child(_url_edit)

	var create: Button = Button.new()
	create.text = "Create Room"
	create.pressed.connect(func() -> void: _gateway_action(Gateway.create_room))
	box.add_child(create)

	var join_row: HBoxContainer = HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	box.add_child(join_row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "room code"
	_code_edit.max_length = 4
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_code_edit)
	var join: Button = Button.new()
	join.text = "Join"
	join.pressed.connect(func() -> void:
		var code: String = _code_edit.text
		_gateway_action(func() -> void: Gateway.join_room(code)))
	join_row.add_child(join)

	_lobby_panel = PanelContainer.new()
	_lobby_panel.visible = false
	box.add_child(_lobby_panel)
	var lobby_box: VBoxContainer = VBoxContainer.new()
	lobby_box.add_theme_constant_override("separation", 8)
	_lobby_panel.add_child(lobby_box)
	_lobby_label = Label.new()
	_lobby_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_box.add_child(_lobby_label)
	_start_button = Button.new()
	_start_button.text = "Start Match"
	_start_button.visible = false
	_start_button.pressed.connect(func() -> void: Gateway.start_match())
	lobby_box.add_child(_start_button)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_status)

# --- Gateway flow ---

# Connect lazily on the first action; queue the action until connected.
func _gateway_action(action: Callable) -> void:
	if _connected:
		action.call()
		return
	_pending_action = action
	_set_status("Connecting to gateway…")
	if Gateway.connect_to_gateway(_url_edit.text.strip_edges()) != OK:
		_set_status("Invalid gateway URL.")

func _on_gateway_connected() -> void:
	_connected = true
	if _pending_action.is_valid():
		_pending_action.call()
		_pending_action = Callable()

func _on_room_updated(code: String, player_count: int, my_slot: int) -> void:
	_my_slot = my_slot
	_player_count = player_count
	_lobby_panel.visible = true
	_lobby_label.text = "Room %s — %d/%d players" % [code, player_count, Gateway.MAX_PLAYERS]
	_start_button.visible = my_slot == 0
	_start_button.disabled = player_count < Gateway.MIN_PLAYERS
	_set_status("Waiting for players…" if my_slot == 0 else "Waiting for the host to start…")

func _on_match_ready(port: int, token: String) -> void:
	Net.pending_match_url = _match_url_template.replace("{port}", str(port))
	Net.pending_token = token
	get_tree().change_scene_to_file(MAIN_SCENE)

func _on_gateway_error(reason: String) -> void:
	_set_status(reason)

func _on_gateway_lost() -> void:
	_connected = false
	_lobby_panel.visible = false
	_set_status("Lost connection to the gateway.")

func _set_status(text: String) -> void:
	_status.text = text
