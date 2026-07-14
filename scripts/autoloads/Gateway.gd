# scripts/autoloads/Gateway.gd
extends Node

# Lobby service and its client API, mirroring the Net/Replication structure:
# one script, both sides. The gateway process (--gateway) holds rooms keyed by
# 4-letter codes; when the host starts, it spawns a dedicated match-server
# process and hands every member the match port. The client builds the final
# URL from server_config.json's match_url_template, so the gateway never
# needs to know its public address.

const CODE_ALPHABET: String = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const CODE_LENGTH: int = 4
const MIN_PLAYERS: int = 2
const MAX_PLAYERS: int = 4
# Grace between spawning the match process and telling clients to connect,
# so the match socket is listening before anyone dials it.
const MATCH_BOOT_GRACE: float = 2.0
# A waiting lobby is otherwise silent, and idle websockets get culled by
# proxies along the way (Cloudflare's edge kills them after ~100 s). Ping
# every connected peer well inside that window; the pong keeps traffic
# flowing in both directions.
const HEARTBEAT_INTERVAL: float = 40.0

# Client-side signals for the menu UI.
signal room_updated(code: String, player_count: int, my_slot: int)
signal match_ready(port: int, token: String)
signal gateway_error(reason: String)

# Gateway side: code -> {"peers": Array[int], "started": bool}
var _rooms: Dictionary = {}
var _peer_rooms: Dictionary = {}  # peer_id -> code
var _next_match_port: int = 9100
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _heartbeat_accum: float = 0.0

func _process(delta: float) -> void:
	if Net.mode != Net.Mode.GATEWAY:
		return
	_heartbeat_accum += delta
	if _heartbeat_accum < HEARTBEAT_INTERVAL:
		return
	_heartbeat_accum = 0.0
	for peer: int in multiplayer.get_peers():
		_ping.rpc_id(peer)

@rpc("authority", "call_remote", "reliable")
func _ping() -> void:
	# Client side: answer so every proxy hop sees two-way traffic.
	_pong.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _pong() -> void:
	pass

func host(port: int, match_port_base: int) -> Error:
	_rng.randomize()
	_next_match_port = match_port_base
	var peer := WebSocketMultiplayerPeer.new()
	Net._configure_ws(peer)
	var err: Error = peer.create_server(port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	Net.mode = Net.Mode.GATEWAY
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[gw] gateway listening on port %d, matches from %d" % [port, match_port_base])
	return OK

# Client side: dial the gateway (the match connection later replaces this
# peer via Net.join).
func connect_to_gateway(url: String) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	Net._configure_ws(peer)
	var err: Error = peer.create_client(url)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK

func create_room() -> void:
	_create_room.rpc_id(1, Net.PROTOCOL_VERSION)

func join_room(code: String) -> void:
	_join_room.rpc_id(1, code.strip_edges().to_upper(), Net.PROTOCOL_VERSION)

func start_match() -> void:
	_start_match.rpc_id(1)

# --- Gateway side ---

@rpc("any_peer", "call_remote", "reliable")
func _create_room(proto_version: int = 0) -> void:
	if Net.mode != Net.Mode.GATEWAY:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _version_ok(sender, proto_version):
		return
	_leave_current_room(sender)
	var code: String = _new_code()
	_rooms[code] = {"peers": [sender], "started": false}
	_peer_rooms[sender] = code
	print("[gw] room %s created by peer %d" % [code, sender])
	_broadcast_room(code)

@rpc("any_peer", "call_remote", "reliable")
func _join_room(code: String, proto_version: int = 0) -> void:
	if Net.mode != Net.Mode.GATEWAY:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _version_ok(sender, proto_version):
		return
	if not _rooms.has(code):
		_error.rpc_id(sender, "room %s not found" % code)
		return
	var room: Dictionary = _rooms[code]
	if room["started"]:
		_error.rpc_id(sender, "match already started")
		return
	if room["peers"].size() >= MAX_PLAYERS:
		_error.rpc_id(sender, "room is full")
		return
	_leave_current_room(sender)
	room["peers"].append(sender)
	_peer_rooms[sender] = code
	print("[gw] peer %d joined room %s (%d players)" % [sender, code, room["peers"].size()])
	_broadcast_room(code)

@rpc("any_peer", "call_remote", "reliable")
func _start_match() -> void:
	if Net.mode != Net.Mode.GATEWAY:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var code: String = _peer_rooms.get(sender, "")
	if code == "" or not _rooms.has(code):
		return
	var room: Dictionary = _rooms[code]
	if room["peers"][0] != sender:
		_error.rpc_id(sender, "only the host can start")
		return
	if room["peers"].size() < MIN_PLAYERS:
		_error.rpc_id(sender, "need at least %d players" % MIN_PLAYERS)
		return
	if room["started"]:
		return
	room["started"] = true

	var port: int = _next_match_port
	_next_match_port += 1
	var match_seed: int = int(_rng.randi())
	# One secret per seat: the match server only seats holders of these, and
	# a reconnecting player re-claims exactly their old tribe.
	var tokens: PackedStringArray = PackedStringArray()
	for _i in range(room["peers"].size()):
		tokens.append("%08x%08x" % [_rng.randi(), _rng.randi()])
	var pid: int = _spawn_match(port, match_seed, tokens)
	if pid < 0:
		room["started"] = false
		_error.rpc_id(sender, "could not start match server")
		return
	print("[gw] room %s -> match on port %d (pid %d, %d players)" % [
		code, port, pid, room["peers"].size()])

	# Give the match process a moment to bind before clients dial in.
	await get_tree().create_timer(MATCH_BOOT_GRACE).timeout
	for i in range(room["peers"].size()):
		_match_ready.rpc_id(room["peers"][i], port, tokens[i])

func _spawn_match(port: int, match_seed: int, tokens: PackedStringArray) -> int:
	var exe: String = OS.get_executable_path()
	var args: PackedStringArray = ["--headless"]
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["++", "--server", "--port=%d" % port,
		"--players=%d" % tokens.size(), "--seed=%d" % match_seed,
		"--tokens=%s" % ",".join(tokens)])
	return OS.create_process(exe, args)

func _version_ok(sender: int, proto_version: int) -> bool:
	if proto_version == Net.PROTOCOL_VERSION:
		return true
	_error.rpc_id(sender, "version mismatch - please refresh the page")
	return false

func _on_peer_disconnected(peer_id: int) -> void:
	_leave_current_room(peer_id)

func _leave_current_room(peer_id: int) -> void:
	var code: String = _peer_rooms.get(peer_id, "")
	_peer_rooms.erase(peer_id)
	if code == "" or not _rooms.has(code):
		return
	var room: Dictionary = _rooms[code]
	room["peers"].erase(peer_id)
	if room["peers"].is_empty():
		_rooms.erase(code)
		print("[gw] room %s closed" % code)
	elif not room["started"]:
		_broadcast_room(code)

func _broadcast_room(code: String) -> void:
	var peers: Array = _rooms[code]["peers"]
	for i in range(peers.size()):
		_room_update.rpc_id(peers[i], code, peers.size(), i)

func _new_code() -> String:
	while true:
		var code: String = ""
		for _i in range(CODE_LENGTH):
			code += CODE_ALPHABET[_rng.randi_range(0, CODE_ALPHABET.length() - 1)]
		if not _rooms.has(code):
			return code
	return ""  # unreachable

# --- Client side ---

@rpc("authority", "call_remote", "reliable")
func _room_update(code: String, player_count: int, my_slot: int) -> void:
	room_updated.emit(code, player_count, my_slot)

@rpc("authority", "call_remote", "reliable")
func _match_ready(port: int, token: String) -> void:
	match_ready.emit(port, token)

@rpc("authority", "call_remote", "reliable")
func _error(reason: String) -> void:
	push_warning("[gw] %s" % reason)
	gateway_error.emit(reason)
