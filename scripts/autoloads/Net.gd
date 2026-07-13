# scripts/autoloads/Net.gd
extends Node

# Multiplayer session state and the join handshake. Transport is WebSockets
# (browser clients can't do UDP). The server owns all game state; identity is
# derived from the connection (peer_players), never from client payloads.

# Which role this process plays. OFFLINE = single-player (local authority).
# SERVER = headless authoritative match server. CLIENT = renders and sends
# commands; never simulates. GATEWAY = headless lobby that spawns match
# servers (no game world at all).
enum Mode { OFFLINE, SERVER, CLIENT, GATEWAY }

# Bump whenever the command schema or replication contract changes; clients
# with a stale build get a clear "refresh" error instead of silent desyncs.
const PROTOCOL_VERSION: int = 1

signal match_config_received
signal join_refused(reason: String)

var mode: Mode = Mode.OFFLINE

# Server only: connected peer_id -> player_id (0-based tribe slot).
var peer_players: Dictionary = {}
var expected_players: int = 2

# Match servers tear themselves down so the gateway never tracks pids:
# quit after EMPTY_SHUTDOWN_SECS with no peers (once somebody had joined),
# or GAME_OVER_SHUTDOWN_SECS after the match ends.
const EMPTY_SHUTDOWN_SECS: float = 60.0
const GAME_OVER_SHUTDOWN_SECS: float = 30.0
var _had_peers: bool = false
var _shutdown_accum: float = 0.0

# Set by the lobby flow before switching to the match scene; Main's client
# boot uses it when no --join= CLI arg is present.
var pending_match_url: String = ""

# One-shot message for the main menu (why the last session ended).
var last_status: String = ""

# Normal play returns to the menu on disconnect/refusal. Headless harnesses
# switch this off — a scene change mid-test would restart the harness.
var auto_return_to_menu: bool = true

# Client: seat token from the gateway, sent with the hello.
var pending_token: String = ""
# Server: token per tribe slot (from --tokens=). Empty = open seating, which
# direct --server runs (dev, harnesses) rely on.
var slot_tokens: PackedStringArray = PackedStringArray()

func _ready() -> void:
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)

# Tear down all match/connection state and return this process to a clean
# offline baseline. The single exit path for every way a match can end.
func reset(status: String = "") -> void:
	last_status = status
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	pending_match_url = ""
	pending_token = ""
	peer_players.clear()
	_had_peers = false
	_shutdown_accum = 0.0
	GameManager.world = null
	GameManager.pathfinder = null
	GameManager.fog = null
	GameManager.player_visions.clear()
	GameManager.state = GameManager.GameState.LOADING
	Replication.reset_client()

func back_to_menu(status: String = "") -> void:
	get_tree().paused = false
	reset(status)
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")

func _on_server_disconnected() -> void:
	if mode != Mode.CLIENT:
		return
	push_warning("[net] connection to the match server was lost")
	if auto_return_to_menu:
		back_to_menu("Connection to the match was lost.")

func _on_connection_failed() -> void:
	if mode != Mode.CLIENT:
		return
	if auto_return_to_menu:
		back_to_menu("Could not reach the match server.")

func _process(delta: float) -> void:
	if mode != Mode.SERVER:
		return
	var idle: bool = (_had_peers and peer_players.is_empty()) \
		or GameManager.state == GameManager.GameState.GAME_OVER
	if not idle:
		_shutdown_accum = 0.0
		return
	_shutdown_accum += delta
	var limit: float = GAME_OVER_SHUTDOWN_SECS \
		if GameManager.state == GameManager.GameState.GAME_OVER else EMPTY_SHUTDOWN_SECS
	if _shutdown_accum >= limit:
		print("[net] match server shutting down (idle)")
		get_tree().quit()

func is_authority() -> bool:
	return mode != Mode.CLIENT

func is_headless_server() -> bool:
	return mode == Mode.SERVER or mode == Mode.GATEWAY

# Generous socket buffers: the join snapshot is a burst of reliable RPCs, and
# a browser tab that loses focus stops draining its queue — overflow drops
# packets (including reliable ones), which is a permanent desync.
static func _configure_ws(peer: WebSocketMultiplayerPeer) -> void:
	peer.inbound_buffer_size = 256 * 1024
	peer.outbound_buffer_size = 256 * 1024
	peer.max_queued_packets = 4096

func host(port: int, players: int) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	_configure_ws(peer)
	var err: Error = peer.create_server(port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.SERVER
	expected_players = players
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[net] match server listening on port %d for %d players" % [port, players])
	return OK

func join(url: String) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	_configure_ws(peer)
	var err: Error = peer.create_client(url)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	return OK

func _on_connected_to_server() -> void:
	# The gateway connection reuses the same tree multiplayer; only greet
	# match servers.
	if mode == Mode.CLIENT:
		_client_hello.rpc_id(1, PROTOCOL_VERSION, pending_token)

func _on_peer_disconnected(peer_id: int) -> void:
	if peer_players.has(peer_id):
		print("[net] player %d disconnected (peer %d)" % [peer_players[peer_id], peer_id])
		peer_players.erase(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _client_hello(proto_version: int, token: String = "") -> void:
	if mode != Mode.SERVER:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if proto_version != PROTOCOL_VERSION:
		_refuse_and_drop(sender, "protocol mismatch - please refresh the page")
		return
	var slot: int
	if slot_tokens.is_empty():
		slot = _lowest_free_slot()
		if slot < 0:
			_refuse_and_drop(sender, "match is full")
			return
	else:
		# Gateway-issued seating: the token IS the identity, so a returning
		# player always reclaims exactly their old tribe.
		slot = slot_tokens.find(token)
		if slot < 0:
			_refuse_and_drop(sender, "not invited to this match")
			return
		if peer_players.values().has(slot):
			_refuse_and_drop(sender, "this seat is already connected")
			return
	peer_players[sender] = slot
	_had_peers = true
	print("[net] player %d joined (peer %d)" % [slot, sender])
	_match_config.rpc_id(sender, GameManager.map_seed, expected_players, slot)

# Refuse a hello and then actively drop the connection (after a beat so the
# refusal RPC flushes first) — refused peers don't get to linger.
func _refuse_and_drop(sender: int, reason: String) -> void:
	_refuse.rpc_id(sender, reason)
	await get_tree().create_timer(0.5).timeout
	if multiplayer.multiplayer_peer != null \
			and multiplayer.get_peers().has(sender):
		multiplayer.multiplayer_peer.disconnect_peer(sender)

func _lowest_free_slot() -> int:
	for slot in range(expected_players):
		if not peer_players.values().has(slot):
			return slot
	return -1

@rpc("authority", "call_remote", "reliable")
func _match_config(map_seed: int, player_count: int, my_player_id: int) -> void:
	GameManager.map_seed = map_seed
	GameManager.reset_players(player_count)
	GameManager.local_player_id = my_player_id
	match_config_received.emit()

@rpc("authority", "call_remote", "reliable")
func _refuse(reason: String) -> void:
	push_error("[net] join refused: %s" % reason)
	join_refused.emit(reason)
	if mode == Mode.CLIENT and auto_return_to_menu:
		back_to_menu("Join refused: %s" % reason)
