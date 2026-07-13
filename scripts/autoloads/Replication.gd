# scripts/autoloads/Replication.gd
extends Node

# Server->client entity replication with explicit ordering. The engine's
# MultiplayerSpawner replicates on peer connect, which can arrive before a
# client has built its world (Building.setup touches WorldData). Instead the
# protocol here is pull-ordered:
#   1. client joins, receives the match config, generates its world
#   2. client says "world ready"; only then does the server send a snapshot
#   3. afterwards the client receives spawn/despawn events and 10 Hz ticks
# Identity/authority: everything in this file flows server -> client except
# _client_world_ready.

const SYNC_INTERVAL: float = 0.1     # 10 Hz state ticks
const VISION_INTERVAL: float = 1.0   # server-side per-player fog refresh

var _unit_scene: PackedScene = preload("res://scenes/units/Unit.tscn")

# Server: peers that finished building their world (receive events + ticks).
var _live_peers: Array[int] = []
var _accum: float = 0.0
var _vision_accum: float = VISION_INTERVAL  # first update on the first frame
# Server: every cell whose resource ran out, so late (re)joiners don't see
# ghost trees from the initial seed generation.
var _depleted_cells: Array[Vector2i] = []

# Client: name -> entity, so ticks don't scan groups.
var _entities: Dictionary = {}
var _first_tick_logged: bool = false

func _ready() -> void:
	EventBus.world_ready.connect(_on_world_ready)

# Called by Net.reset() so a later match starts from a clean slate.
func reset_client() -> void:
	_entities.clear()
	_first_tick_logged = false

func _on_world_ready() -> void:
	match Net.mode:
		Net.Mode.SERVER:
			EventBus.entity_spawned.connect(_on_entity_spawned)
			EventBus.unit_died.connect(_on_entity_gone)
			EventBus.building_destroyed.connect(_on_entity_gone)
			GameManager.world.resource_depleted.connect(_on_resource_depleted)
			multiplayer.peer_disconnected.connect(
				func(peer_id: int) -> void: _live_peers.erase(peer_id))
		Net.Mode.CLIENT:
			_client_world_ready.rpc_id(1)

# --- Server side ---

@rpc("any_peer", "call_remote", "reliable")
func _client_world_ready() -> void:
	if Net.mode != Net.Mode.SERVER:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not Net.peer_players.has(sender) or sender in _live_peers:
		return
	_live_peers.append(sender)
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		_spawn_building.rpc_id(sender, _building_data(node as Building))
	for node: Node in get_tree().get_nodes_in_group("units"):
		_spawn_unit.rpc_id(sender, _unit_data(node as UnitBase))
	for cell: Vector2i in _depleted_cells:
		_deplete_resource.rpc_id(sender, cell)
	GameManager.push_stockpile_to_peer(sender)
	print("[net] snapshot sent to player %d" % Net.peer_players[sender])

func _on_entity_spawned(entity: Node2D) -> void:
	var building: Building = entity as Building
	for peer: int in _live_peers:
		if building != null:
			_spawn_building.rpc_id(peer, _building_data(building))
		elif entity is UnitBase:
			_spawn_unit.rpc_id(peer, _unit_data(entity as UnitBase))

func _on_entity_gone(entity: Node2D) -> void:
	for peer: int in _live_peers:
		_despawn.rpc_id(peer, String(entity.name))

func _on_resource_depleted(cell: Vector2i) -> void:
	_depleted_cells.append(cell)
	for peer: int in _live_peers:
		_deplete_resource.rpc_id(peer, cell)

func _process(delta: float) -> void:
	if Net.mode != Net.Mode.SERVER:
		return

	# Per-player fog on the server: powers gather-retarget parity with
	# offline play and filters enemy positions out of the state ticks.
	_vision_accum += delta
	if _vision_accum >= VISION_INTERVAL and GameManager.world != null:
		_vision_accum = 0.0
		for vision: PlayerVision in GameManager.player_visions:
			vision.update(get_tree(), GameManager.world)
			vision.changed_chunks.clear()

	if _live_peers.is_empty():
		return
	_accum += delta
	if _accum < SYNC_INTERVAL:
		return
	_accum = 0.0

	var units: Array[UnitBase] = []
	for node: Node in get_tree().get_nodes_in_group("units"):
		var unit: UnitBase = node as UnitBase
		if unit != null:
			units.append(unit)
	var building_states: Array = []
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var building: Building = node as Building
		if building != null:
			building_states.append([String(building.name), building.current_hp,
				building.train_queue.duplicate(), building.train_progress])

	for peer: int in _live_peers:
		var player_id: int = Net.peer_players.get(peer, -1)
		var unit_states: Array = []
		for unit: UnitBase in units:
			# A tribe receives live state for its own units and for enemies
			# inside its vision. Everything else stays frozen at last-known —
			# which local fog hides anyway — so a modified client can't track
			# live positions through the fog.
			if unit.player_id != player_id and not _visible_to(player_id, unit):
				continue
			unit_states.append([String(unit.name), unit.global_position.x,
				unit.global_position.y, unit.velocity.x, unit.velocity.y,
				unit.current_hp, unit.current_state])
		_tick.rpc_id(peer, unit_states, building_states)
	if not _first_tick_logged:
		_first_tick_logged = true
		print("[net] state ticks flowing (%d units)" % units.size())

func _visible_to(player_id: int, unit: UnitBase) -> bool:
	if player_id < 0 or player_id >= GameManager.player_visions.size():
		return true
	return GameManager.player_visions[player_id].can_see_entity(unit)

func _building_data(building: Building) -> Dictionary:
	return {
		"n": String(building.name), "t": building.building_type,
		"p": building.player_id, "c": building.footprint_cells[0],
		"hp": building.current_hp,
	}

func _unit_data(unit: UnitBase) -> Dictionary:
	return {
		"n": String(unit.name), "t": unit.unit_type, "p": unit.player_id,
		"x": unit.global_position.x, "y": unit.global_position.y,
		"hp": unit.current_hp,
	}

# --- Client side ---

@rpc("authority", "call_remote", "reliable")
func _spawn_unit(data: Dictionary) -> void:
	if Net.mode != Net.Mode.CLIENT or _entities.has(data["n"]):
		return
	var containers: Array = get_tree().get_nodes_in_group("unit_container")
	if containers.is_empty():
		return
	var unit: UnitBase = _unit_scene.instantiate() as UnitBase
	unit.name = data["n"]
	unit.unit_type = data["t"]
	unit.player_id = data["p"]
	unit.position = Vector2(data["x"], data["y"])
	containers[0].add_child(unit)
	unit.current_hp = data["hp"]
	unit.net_snap(unit.position)
	_entities[data["n"]] = unit

@rpc("authority", "call_remote", "reliable")
func _spawn_building(data: Dictionary) -> void:
	if Net.mode != Net.Mode.CLIENT or _entities.has(data["n"]):
		return
	var containers: Array = get_tree().get_nodes_in_group("building_container")
	if containers.is_empty():
		return
	var building: Building = Building.new()
	building.name = data["n"]
	building.setup(data["t"], data["p"], data["c"])
	containers[0].add_child(building)
	building.current_hp = data["hp"]
	_entities[data["n"]] = building

@rpc("authority", "call_remote", "reliable")
func _despawn(entity_name: String) -> void:
	if Net.mode != Net.Mode.CLIENT:
		return
	var entity: Node = _entities.get(entity_name)
	_entities.erase(entity_name)
	if entity == null or not is_instance_valid(entity):
		return
	var building: Building = entity as Building
	if building != null:
		GameManager.world.vacate(building.footprint_cells)
		EventBus.building_destroyed.emit(building)
	else:
		EventBus.unit_died.emit(entity)
		EventBus.population_changed.emit(entity.get("player_id"))
	entity.queue_free()

@rpc("authority", "call_remote", "reliable")
func _deplete_resource(cell: Vector2i) -> void:
	if Net.mode == Net.Mode.CLIENT and GameManager.world != null:
		GameManager.world.take_resource(cell, 1 << 30)

@rpc("authority", "call_remote", "unreliable")
func _tick(unit_states: Array, building_states: Array) -> void:
	if Net.mode != Net.Mode.CLIENT or GameManager.world == null:
		return
	if not _first_tick_logged:
		_first_tick_logged = true
		print("[net] receiving state ticks (%d units)" % unit_states.size())
	for s: Array in unit_states:
		var unit: UnitBase = _entities.get(s[0]) as UnitBase
		if unit != null and is_instance_valid(unit):
			unit.net_apply(Vector2(s[1], s[2]), Vector2(s[3], s[4]), s[5], s[6])
	for s: Array in building_states:
		var building: Building = _entities.get(s[0]) as Building
		if building != null and is_instance_valid(building):
			building.net_apply(s[1], s[2], s[3])
