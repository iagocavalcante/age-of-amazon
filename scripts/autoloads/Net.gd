# scripts/autoloads/Net.gd
extends Node

# Multiplayer session state and the join handshake. Transport is WebSockets
# (browser clients can't do UDP). The server owns all game state; identity is
# derived from the connection (peer_players), never from client payloads.

# Which role this process plays. OFFLINE = single-player (local authority).
# SERVER = headless authoritative match server. CLIENT = renders and sends
# commands; never simulates.
enum Mode { OFFLINE, SERVER, CLIENT }

# Bump whenever the command schema or replication contract changes; clients
# with a stale build get a clear "refresh" error instead of silent desyncs.
const PROTOCOL_VERSION: int = 1

signal match_config_received
signal join_refused(reason: String)

var mode: Mode = Mode.OFFLINE

# Server only: connected peer_id -> player_id (0-based tribe slot).
var peer_players: Dictionary = {}
var expected_players: int = 2

func is_authority() -> bool:
	return mode != Mode.CLIENT

func is_headless_server() -> bool:
	return mode == Mode.SERVER

func host(port: int, players: int) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
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
	var err: Error = peer.create_client(url)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	return OK

func _on_connected_to_server() -> void:
	_client_hello.rpc_id(1, PROTOCOL_VERSION)

func _on_peer_disconnected(peer_id: int) -> void:
	if peer_players.has(peer_id):
		print("[net] player %d disconnected (peer %d)" % [peer_players[peer_id], peer_id])
		peer_players.erase(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _client_hello(proto_version: int) -> void:
	if mode != Mode.SERVER:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if proto_version != PROTOCOL_VERSION:
		_refuse.rpc_id(sender, "protocol mismatch - please refresh the page")
		return
	var slot: int = _lowest_free_slot()
	if slot < 0:
		_refuse.rpc_id(sender, "match is full")
		return
	peer_players[sender] = slot
	print("[net] player %d joined (peer %d)" % [slot, sender])
	_match_config.rpc_id(sender, GameManager.map_seed, expected_players, slot)

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
