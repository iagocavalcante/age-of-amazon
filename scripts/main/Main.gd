# scripts/main/Main.gd
extends Node2D

@onready var chunk_manager: Node2D = $ChunkManager
@onready var fog: FogOfWar = $FogOfWar
@onready var camera: Camera2D = $GameCamera
@onready var doodads: Node2D = $World/Doodads
@onready var buildings: Node2D = $World/Buildings
@onready var units: Node2D = $World/Units
@onready var animals: Node2D = $World/Animals

var unit_scene: PackedScene = preload("res://scenes/units/Unit.tscn")

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()

	if "--server" in args:
		_boot_server(args)
	elif "--gateway" in args:
		_boot_gateway(args)
		return
	elif _arg_value(args, "--join=") != "":
		await _boot_client(_arg_value(args, "--join="))
	elif Net.pending_match_url != "":
		var url: String = Net.pending_match_url
		Net.pending_match_url = ""
		await _boot_client(url)
	else:
		_boot_offline(args)

	if "--test-move" in args:
		_run_move_test()
	if "--test-commands" in args:
		_run_commands_test()
	if "--test-mp-client" in args:
		_run_mp_client_test()
	if "--test-gw-host" in args:
		_run_gw_test(args, true)
	if "--test-gw-join" in args:
		_run_gw_test(args, false)
	if "--test-seat" in args:
		_run_seat_test()
	if "--test-build" in args:
		_run_build_test()
	if "--test-victory" in args:
		_run_victory_test()
	if "--test-systems" in args:
		_run_systems_test()
	if "--test-scout" in args:
		_run_scout_test()
	if "--test-hunt" in args:
		_run_hunt_test()
	if "--capture-help" in args:
		_run_capture_help()
	if "--capture-animals" in args:
		_run_capture_animals()

func _is_harness(args: PackedStringArray) -> bool:
	for arg: String in args:
		if arg.begins_with("--test") or arg.begins_with("--capture"):
			return true
	return false

func _arg_value(args: PackedStringArray, prefix: String, fallback: String = "") -> String:
	for arg: String in args:
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback

# --- Boot modes ---

# Single-player: this process is the authority; the classic asymmetric start
# (player villagers vs AI warriors) and the EnemyAI opponent.
func _boot_offline(args: PackedStringArray) -> void:
	chunk_manager.setup(camera, doodads)

	# Bases sit inside the guaranteed spawn clearings (see WorldGen).
	_place_building("town_center", 0, Vector2i(-1, -1))
	_place_building("town_center", 1, WorldGen.PLAYER_ORIGINS[1] + Vector2i(-1, -1))

	for cell: Vector2i in [Vector2i(2, 2), Vector2i(0, 3), Vector2i(3, 0)]:
		_spawn_unit("villager", 0, cell)
	for cell: Vector2i in [Vector2i(-2, 2), Vector2i(2, -2), Vector2i(-2, -2)]:
		_spawn_unit("warrior", 1, WorldGen.PLAYER_ORIGINS[1] + cell)

	camera.center_on(Constants.grid_to_world(0, 0))
	chunk_manager.load_now()

	fog.setup(camera)
	fog.force_update()

	EventBus.world_ready.emit()
	GameManager.change_state(GameManager.GameState.RUNNING)

	# Ambient wildlife runs in normal play; harnesses seed their own animals
	# (or none) so the simulation stays deterministic.
	if not _is_harness(args):
		animals.setup(camera)

# Headless authoritative match server: symmetric starts for N human tribes,
# no EnemyAI, no wildlife, no rendering concerns.
func _boot_server(args: PackedStringArray) -> void:
	var port: int = int(_arg_value(args, "--port=", "9100"))
	var players: int = clampi(int(_arg_value(args, "--players=", "2")), 2, WorldGen.PLAYER_ORIGINS.size())
	var seed_arg: int = int(_arg_value(args, "--seed=", "0"))
	if seed_arg != 0:
		GameManager.map_seed = seed_arg
	GameManager.reset_players(players)
	var tokens: String = _arg_value(args, "--tokens=")
	if tokens != "":
		Net.slot_tokens = tokens.split(",")

	if Net.host(port, players) != OK:
		push_error("[net] failed to bind port %d" % port)
		get_tree().quit(1)
		return

	$EnemyAI.queue_free()
	$UILayer.queue_free()
	chunk_manager.setup(camera, doodads)

	GameManager.player_visions.clear()
	for pid in range(players):
		GameManager.player_visions.append(PlayerVision.new(pid))
		var origin: Vector2i = WorldGen.PLAYER_ORIGINS[pid]
		_place_building("town_center", pid, origin + Vector2i(-1, -1))
		for cell: Vector2i in [Vector2i(2, 2), Vector2i(0, 3), Vector2i(3, 0)]:
			_spawn_unit("villager", pid, origin + cell)

	chunk_manager.load_now()
	EventBus.world_ready.emit()
	GameManager.change_state(GameManager.GameState.RUNNING)

# Headless lobby: no game world at all — just the Gateway autoload's room
# service. The Main scene's world/UI nodes are dropped.
func _boot_gateway(args: PackedStringArray) -> void:
	var port: int = int(_arg_value(args, "--port=", "9000"))
	var base: int = int(_arg_value(args, "--match-port-base=", "9100"))
	$EnemyAI.queue_free()
	$UILayer.queue_free()
	if Gateway.host(port, base) != OK:
		push_error("[gw] failed to bind port %d" % port)
		get_tree().quit(1)

# Multiplayer client: connect first, build the world from the replicated
# seed once the match config arrives. Entities come from the server via the
# spawners — nothing is spawned locally.
func _boot_client(url: String) -> void:
	$EnemyAI.queue_free()
	if Net.join(url) != OK:
		push_error("[net] failed to open connection")
		get_tree().quit(1)
		return
	await Net.match_config_received

	chunk_manager.setup(camera, doodads)
	var origin: Vector2i = WorldGen.PLAYER_ORIGINS[GameManager.local_player_id]
	camera.center_on(Constants.grid_to_world(origin.x, origin.y))
	chunk_manager.load_now()

	fog.setup(camera)
	fog.force_update()

	EventBus.world_ready.emit()
	GameManager.change_state(GameManager.GameState.RUNNING)

func _place_building(type: String, player_id: int, base_cell: Vector2i) -> Building:
	var building: Building = Building.new()
	building.name = GameManager.claim_entity_name("B")
	building.setup(type, player_id, base_cell)
	buildings.add_child(building)
	return building

func _spawn_unit(unit_type: String, player_id: int, cell: Vector2i) -> UnitBase:
	var unit: UnitBase = unit_scene.instantiate() as UnitBase
	unit.name = GameManager.claim_entity_name("U")
	unit.unit_type = unit_type
	unit.player_id = player_id
	unit.position = Constants.grid_to_world(cell.x, cell.y)
	units.add_child(unit)
	return unit

# --- Verification harnesses (run with `++ --test-move` / `++ --test-systems`) ---

func _run_move_test() -> void:
	await get_tree().create_timer(0.5).timeout
	var target_world: Vector2 = Constants.grid_to_world(8, 8)
	var target_screen: Vector2 = get_viewport().get_canvas_transform() * target_world
	var test_units: Array = get_tree().get_nodes_in_group("player_0")
	print("[test-move] commanding units via SelectionManager to ", target_world)
	SelectionManager.selected_units.assign(test_units.filter(
		func(n: Node) -> bool: return n.is_in_group("units")))
	SelectionManager._command_at(target_screen)
	await get_tree().create_timer(3.0).timeout
	for u: Node2D in SelectionManager.selected_units:
		print("[test-move] unit after 3s: ", u.global_position, " state=", u.current_state)
	get_tree().quit()

# Find a cell near origin where a building of this type may legally go —
# the same checks the authority applies, so harnesses don't flake on the
# random scatter of trees.
func _find_buildable_cell(origin: Vector2i, building_type: String, player_id: int) -> Vector2i:
	var footprint: Vector2i = Constants.BUILDING_DEFS[building_type]["footprint"]
	for radius in range(3, 9):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var base: Vector2i = origin + Vector2i(dx, dy)
				var ok: bool = true
				for fy in range(footprint.y):
					for fx in range(footprint.x):
						var cell: Vector2i = base + Vector2i(fx, fy)
						if not GameManager.world.is_walkable(cell) \
								or GameManager.world.building_at(cell) != null \
								or not GameManager.world.get_resource_at(cell).is_empty() \
								or not GameManager.has_explored(player_id, cell):
							ok = false
							break
					if not ok:
						break
				if ok:
					return base
	return Vector2i(9999, 9999)

# Prove construction: rejections (occupied, unscouted), a villager-built
# house that raises the pop cap, and a barracks that trains once finished.
func _run_build_test() -> void:
	await get_tree().create_timer(0.5).timeout
	var villagers: Array = get_tree().get_nodes_in_group("player_0").filter(
		func(n: Node) -> bool: return n is UnitBase and (n as UnitBase).can_gather)
	var names: Array = villagers.map(func(u: Node2D) -> String: return String(u.name))
	var wood_start: int = GameManager.get_resource(0, Constants.ResourceType.WOOD)
	var cap_before: int = GameManager.population_cap(0)

	CommandRouter.submit({"type": "place", "player_id": 0, "building_type": "house",
		"cell": Vector2i(-1, -1), "actor_names": names})
	await get_tree().process_frame
	print("[test-build] reject-occupied ", "OK"
		if GameManager.get_resource(0, Constants.ResourceType.WOOD) == wood_start else "FAILED")

	CommandRouter.submit({"type": "place", "player_id": 0, "building_type": "house",
		"cell": Vector2i(120, 120), "actor_names": names})
	await get_tree().process_frame
	print("[test-build] reject-fog ", "OK"
		if GameManager.get_resource(0, Constants.ResourceType.WOOD) == wood_start else "FAILED")

	var house_cell: Vector2i = _find_buildable_cell(Vector2i.ZERO, "house", 0)
	CommandRouter.submit({"type": "place", "player_id": 0, "building_type": "house",
		"cell": house_cell, "actor_names": names})
	await get_tree().process_frame
	var site: Building = GameManager.world.building_at(house_cell) as Building
	var placed: bool = site != null and not site.is_constructed \
		and GameManager.get_resource(0, Constants.ResourceType.WOOD) == wood_start - 30
	print("[test-build] place-house ", "OK" if placed else "FAILED")
	if site == null:
		get_tree().quit(1)
		return
	print("[test-build] train-guard ", "OK" if not site.queue_train("villager") else "FAILED")

	var elapsed: float = 0.0
	while not site.is_constructed and elapsed < 30.0:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
	print("[test-build] constructed ", "OK" if site.is_constructed else "FAILED",
		" in ", elapsed, "s")
	print("[test-build] pop-cap ", "OK"
		if GameManager.population_cap(0) == cap_before + 5 else "FAILED")

	GameManager.add_resource(0, Constants.ResourceType.WOOD, 100)
	var barracks_cell: Vector2i = _find_buildable_cell(Vector2i.ZERO, "barracks", 0)
	CommandRouter.submit({"type": "place", "player_id": 0, "building_type": "barracks",
		"cell": barracks_cell, "actor_names": names})
	await get_tree().process_frame
	var barracks: Building = GameManager.world.building_at(barracks_cell) as Building
	elapsed = 0.0
	while barracks != null and not barracks.is_constructed and elapsed < 40.0:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
	var trains: bool = barracks != null and barracks.is_constructed \
		and barracks.queue_train("warrior")
	print("[test-build] barracks-trains ", "OK" if trains else "FAILED")
	GameManager.add_resource(0, Constants.ResourceType.FOOD, 100)
	GameManager.add_resource(0, Constants.ResourceType.WOOD, 100)
	var archer_ok: bool = barracks != null and barracks.queue_train("archer") \
		and not _find_tc(0).queue_train("archer")
	print("[test-build] archer-at-barracks-only ", "OK" if archer_ok else "FAILED")

	# Repair: damage the finished house, send villagers, watch hp return at
	# the cost of wood.
	site.take_damage(120)
	var wood_before_repair: int = GameManager.get_resource(0, Constants.ResourceType.WOOD)
	CommandRouter.submit({"type": "build", "player_id": 0,
		"building_name": String(site.name), "actor_names": names})
	elapsed = 0.0
	while site.current_hp < site.max_hp and elapsed < 30.0:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
	print("[test-build] repair ", "OK" if site.current_hp == site.max_hp else "FAILED")
	var wood_spent: int = wood_before_repair - GameManager.get_resource(0, Constants.ResourceType.WOOD)
	print("[test-build] repair-cost ", "OK" if wood_spent > 0 else "FAILED",
		" (wood spent: ", wood_spent, ")")
	get_tree().quit()

# Prove the persisted seat (refresh-rejoin) file layer: save/load roundtrip,
# TTL expiry, and clearing.
func _run_seat_test() -> void:
	Net.clear_seat()
	print("[test-seat] empty ", "OK" if Net.load_seat().is_empty() else "FAILED")

	Net.save_seat("ws://example:9101", "tok123")
	var seat: Dictionary = Net.load_seat()
	var roundtrip: bool = seat.get("url", "") == "ws://example:9101" \
		and seat.get("token", "") == "tok123"
	print("[test-seat] roundtrip ", "OK" if roundtrip else "FAILED")

	# A stale seat must expire.
	var file: FileAccess = FileAccess.open(Net.SEAT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"url": "ws://x", "token": "t",
		"ts": Time.get_unix_time_from_system() - Net.SEAT_TTL_SECS - 60.0}))
	file = null
	print("[test-seat] ttl-expiry ", "OK" if Net.load_seat().is_empty() else "FAILED")

	Net.save_seat("ws://x", "t")
	Net.clear_seat()
	print("[test-seat] clear ", "OK" if Net.load_seat().is_empty() else "FAILED")
	get_tree().quit()

# Gateway lobby harness (driven by tools/test_gateway.sh). The host creates a
# room and prints its code; the script feeds that code to the joiner. Both
# then ride the lobby into a gateway-spawned match and assert the match
# config handshake completes.
func _run_gw_test(args: PackedStringArray, is_host: bool) -> void:
	$EnemyAI.queue_free()
	Net.auto_return_to_menu = false
	var role: String = "host" if is_host else "join"
	var match_template: String = _arg_value(args, "--match-template=", "ws://127.0.0.1:{port}")
	var updates: Array = []
	var ports: Array = []
	Gateway.room_updated.connect(func(code: String, count: int, slot: int) -> void:
		updates.append([code, count, slot]))
	Gateway.match_ready.connect(func(port: int, token: String) -> void:
		ports.append([port, token]))

	var connected: Array = [false]
	multiplayer.connected_to_server.connect(
		func() -> void: connected[0] = true, CONNECT_ONE_SHOT)
	Gateway.connect_to_gateway(_arg_value(args, "--gateway-url="))
	await _until(func() -> bool: return connected[0], 10.0)
	if not connected[0]:
		print("[test-gw] %s gateway-connect FAILED" % role)
		get_tree().quit(1)
		return

	if is_host:
		Gateway.create_room()
		await _until(func() -> bool: return not updates.is_empty(), 10.0)
		if updates.is_empty():
			print("[test-gw] host room FAILED")
			get_tree().quit(1)
			return
		print("[test-gw] code=", updates[0][0])
		var joiner_window: float = 300.0 if "--patient" in args else 30.0
		await _until(func() -> bool: return updates.back()[1] >= 2, joiner_window)
		if updates.back()[1] < 2:
			print("[test-gw] host waiting-for-joiner FAILED (still connected: %s)"
				% str(multiplayer.multiplayer_peer.get_connection_status()
					== MultiplayerPeer.CONNECTION_CONNECTED))
			get_tree().quit(1)
			return
		Gateway.start_match()
	else:
		Gateway.join_room(_arg_value(args, "--room="))
		await _until(func() -> bool: return not updates.is_empty(), 10.0)

	# --patient: wait for a human host instead of harness pacing.
	var ready_window: float = 300.0 if "--patient" in args else 30.0
	await _until(func() -> bool: return not ports.is_empty(), ready_window)
	if ports.is_empty():
		print("[test-gw] %s match-ready FAILED" % role)
		get_tree().quit(1)
		return
	print("[test-gw] %s match port=%d" % [role, ports[0][0]])

	# A stranger without a seat token must be refused.
	if is_host:
		var refused: Array = [false]
		Net.join_refused.connect(
			func(_r: String) -> void: refused[0] = true, CONNECT_ONE_SHOT)
		Net.pending_token = "not-a-real-token"
		Net.join(match_template.replace("{port}", str(ports[0][0])))
		await _until(func() -> bool: return refused[0], 10.0)
		print("[test-gw] stranger-refused ", "OK" if refused[0] else "FAILED")

	var got_config: Array = [false]
	Net.match_config_received.connect(
		func() -> void: got_config[0] = true, CONNECT_ONE_SHOT)
	Net.pending_token = ports[0][1]
	Net.join(match_template.replace("{port}", str(ports[0][0])))
	await _until(func() -> bool: return got_config[0], 10.0)
	print("[test-gw] %s config %s me=%d" % [
		role, "OK" if got_config[0] else "FAILED", GameManager.local_player_id])

	# Simulate a page refresh: a brand-new connection presenting the same
	# seat token, while the old socket is still open, must take over the
	# seat and receive a fresh match config.
	if is_host and got_config[0]:
		var re_config: Array = [false]
		Net.match_config_received.connect(
			func() -> void: re_config[0] = true, CONNECT_ONE_SHOT)
		Net.join(match_template.replace("{port}", str(ports[0][0])))
		await _until(func() -> bool: return re_config[0], 10.0)
		print("[test-gw] rejoin-takeover ", "OK" if re_config[0] else "FAILED")
	get_tree().quit()

func _until(condition: Callable, timeout: float) -> void:
	var elapsed: float = 0.0
	while elapsed < timeout and not condition.call():
		await get_tree().create_timer(0.25).timeout
		elapsed += 0.25

# Multiplayer client harness (run with --join=ws://... by tools/test_mp.sh):
# proves the snapshot lands, a command round-trips through the server and the
# unit's replicated position moves, and foreign units can't be commanded.
func _run_mp_client_test() -> void:
	Net.auto_return_to_menu = false
	print("[test-mp] me=", GameManager.local_player_id)

	var own_group: String = "player_%d" % GameManager.local_player_id
	var deadline: float = 10.0
	while deadline > 0.0 and get_tree().get_nodes_in_group(own_group).size() < 4:
		await get_tree().create_timer(0.5).timeout
		deadline -= 0.5
	var mine: Array = get_tree().get_nodes_in_group(own_group).filter(
		func(n: Node) -> bool: return n is UnitBase)
	print("[test-mp] snapshot ", "OK" if mine.size() == 3 else "FAILED",
		" units=", mine.size())
	if mine.is_empty():
		get_tree().quit(1)
		return

	var mover: UnitBase = mine[0]
	var start: Vector2 = mover.global_position
	var origin: Vector2i = WorldGen.PLAYER_ORIGINS[GameManager.local_player_id]
	CommandRouter.submit({
		"type": "move", "player_id": GameManager.local_player_id,
		"actor_names": [String(mover.name)],
		"target": Constants.grid_to_world(origin.x + 8, origin.y + 8),
	})
	await get_tree().create_timer(5.0).timeout
	var moved: bool = mover.global_position.distance_to(start) > 40.0
	print("[test-mp] move-sync ", "OK" if moved else "FAILED")

	# Spoof a command for another tribe's unit; the server derives identity
	# from the connection, so nothing may happen.
	var other_id: int = (GameManager.local_player_id + 1) % GameManager.player_count
	var theirs: Array = get_tree().get_nodes_in_group("player_%d" % other_id).filter(
		func(n: Node) -> bool: return n is UnitBase)
	if theirs.is_empty():
		print("[test-mp] foreign-command FAILED (no foreign units replicated)")
	else:
		var victim: UnitBase = theirs[0]
		var far: Vector2i = WorldGen.PLAYER_ORIGINS[other_id] + Vector2i(20, 20)
		var before: Vector2 = victim.global_position
		CommandRouter.submit({
			"type": "move", "player_id": other_id,
			"actor_names": [String(victim.name)],
			"target": Constants.grid_to_world(far.x, far.y),
		})
		await get_tree().create_timer(4.0).timeout
		var unmoved: bool = victim.global_position.distance_to(before) < 60.0
		print("[test-mp] foreign-command ", "OK" if unmoved else "FAILED")

	# Construction replicates: place a house, watch its site spawn locally.
	var my_origin: Vector2i = WorldGen.PLAYER_ORIGINS[GameManager.local_player_id]
	var house_cell: Vector2i = _find_buildable_cell(
		my_origin, "house", GameManager.local_player_id)
	CommandRouter.submit({
		"type": "place", "player_id": GameManager.local_player_id,
		"building_type": "house", "cell": house_cell,
		"actor_names": mine.map(func(u: Node2D) -> String: return String(u.name)),
	})
	var built: Array = [false]
	var check: Callable = func() -> bool:
		var b: Building = GameManager.world.building_at(house_cell) as Building
		return b != null and b.building_type == "house"
	await _until(check, 8.0)
	print("[test-mp] build-sync ", "OK" if check.call() else "FAILED")
	get_tree().quit()

# Prove N-player victory: with three tribes, losing one town center does NOT
# end the game; the game ends when a single tribe's TC remains.
func _run_victory_test() -> void:
	await get_tree().create_timer(0.5).timeout
	GameManager.reset_players(3)
	var tc2: Building = _place_building(
		"town_center", 2, WorldGen.PLAYER_ORIGINS[2] + Vector2i(-1, -1))
	var winner_seen: Array[int] = [-1]
	EventBus.game_over.connect(func(w: int) -> void: winner_seen[0] = w)

	_find_tc(1).take_damage(999999)
	await get_tree().process_frame
	var still_running: bool = GameManager.state != GameManager.GameState.GAME_OVER
	print("[test-victory] three-way continues ", "OK" if still_running else "FAILED")

	tc2.take_damage(999999)
	await get_tree().process_frame
	var over: bool = GameManager.state == GameManager.GameState.GAME_OVER
	print("[test-victory] last-standing ",
		"OK" if over and winner_seen[0] == 0 else "FAILED",
		" winner=", winner_seen[0])
	get_tree().quit()

# Prove commands flow through CommandRouter: a move command relocates units,
# a spoofed player_id is rejected, training queues via command.
func _run_commands_test() -> void:
	await get_tree().create_timer(0.5).timeout
	var villagers: Array = get_tree().get_nodes_in_group("player_0").filter(
		func(n: Node) -> bool: return n is UnitBase)
	var mover: UnitBase = villagers[0]
	var start: Vector2 = mover.global_position
	CommandRouter.submit({
		"type": "move", "player_id": 0,
		"actor_names": [String(mover.name)],
		"target": Constants.grid_to_world(8, 8),
	})
	await get_tree().create_timer(3.0).timeout
	var moved: bool = mover.global_position.distance_to(start) > 40.0
	print("[test-commands] move ", "OK" if moved else "FAILED")

	# Ownership: player 1 may not command player 0's unit away.
	CommandRouter.submit({
		"type": "move", "player_id": 1,
		"actor_names": [String(mover.name)],
		"target": Constants.grid_to_world(-8, -8),
	})
	await get_tree().create_timer(1.5).timeout
	var rejected: bool = mover.global_position.distance_to(
		Constants.grid_to_world(-8, -8)) > 200.0
	print("[test-commands] ownership ", "OK" if rejected else "FAILED")

	# Training through the router (player TC is named at spawn).
	var tc: Building = _find_tc(0)
	var queue_before: int = tc.train_queue.size()
	CommandRouter.submit({
		"type": "train", "player_id": 0,
		"building_name": String(tc.name), "unit_type": "villager",
	})
	await get_tree().process_frame
	var queued: bool = tc.train_queue.size() == queue_before + 1
	print("[test-commands] train ", "OK" if queued else "FAILED")

	# Foreign training rejected.
	CommandRouter.submit({
		"type": "train", "player_id": 1,
		"building_name": String(tc.name), "unit_type": "villager",
	})
	await get_tree().process_frame
	var foreign_rejected: bool = tc.train_queue.size() == queue_before + 1
	print("[test-commands] foreign-train ", "OK" if foreign_rejected else "FAILED")
	get_tree().quit()

# Accelerated AI pacing: prove the AI scouts, discovers the player base
# through its own fog, and then attacks it.
func _run_scout_test() -> void:
	var ai: Node = $EnemyAI
	ai.scout_interval = 2.0
	ai.wave_interval = 8.0
	print("[test-scout] accelerated AI; waiting for discovery")

	var elapsed: int = 0
	var discovered: bool = false
	while elapsed < 180:
		await get_tree().create_timer(10.0).timeout
		elapsed += 10
		var enemy_tc: Building = _find_tc(1)
		if enemy_tc == null:
			break
		var known: Node2D = ai._known_player_target(enemy_tc)
		print("[test-scout] t=", elapsed, "s known_target=", known)
		if known != null:
			discovered = true
			break
	print("[test-scout] discovery ", "OK" if discovered else "FAILED")

	await get_tree().create_timer(45.0).timeout
	var player_tc: Building = _find_tc(0)
	if player_tc == null:
		print("[test-scout] player TC destroyed (attack OK)")
	else:
		print("[test-scout] player TC hp=", player_tc.current_hp, "/", player_tc.max_hp,
			" (attack ", "OK" if player_tc.current_hp < player_tc.max_hp else "NOT YET", ")")
	get_tree().quit()

# Renders the help overlay and saves a screenshot so the layout can be
# reviewed. Run windowed (or in movie mode) — not headless — so the frame
# actually draws.
func _run_capture_help() -> void:
	var help: Control = $UILayer/HelpScreen
	await get_tree().process_frame
	help.open()
	for _i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "user://help_capture.png"
	img.save_png(path)
	print("[capture-help] saved ", ProjectSettings.globalize_path(path), " size=", img.get_size())
	get_tree().quit()

# Prove hunting: a warrior kills a capybara for food, and a jaguar preys on a
# lone villager.
func _run_hunt_test() -> void:
	await get_tree().create_timer(0.5).timeout
	var food_before: int = GameManager.get_resource(0, Constants.ResourceType.FOOD)

	var prey: Animal = animals.spawn_at("capybara", Vector2i(4, 4))
	var hunter: UnitBase = _spawn_unit("warrior", 0, Vector2i(2, 2))
	await get_tree().process_frame
	hunter.command_attack(prey)

	var elapsed: float = 0.0
	while is_instance_valid(prey) and elapsed < 28.0:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
	var killed: bool = not is_instance_valid(prey)
	var food_after: int = GameManager.get_resource(0, Constants.ResourceType.FOOD)
	print("[test-hunt] capybara killed=", killed, " food ", food_before, "->", food_after,
		" (hunt ", "OK" if killed and food_after > food_before else "FAILED", ")")

	# New species: spawn one of each and make sure they live and behave.
	for species: String in ["tapir", "bush_dog", "caiman"]:
		var beast: Animal = animals.spawn_at(species, Vector2i(6, 6))
		print("[test-hunt] spawn-%s " % species,
			"OK" if is_instance_valid(beast) and beast.max_hp > 0 else "FAILED")
		beast.queue_free()

	var victim: UnitBase = _spawn_unit("villager", 0, Vector2i(-3, -3))
	var vhp_before: int = victim.current_hp
	animals.spawn_at("jaguar", Vector2i(-1, -3))
	await get_tree().create_timer(6.0).timeout
	var vhp_after: int = victim.current_hp if is_instance_valid(victim) else 0
	print("[test-hunt] villager hp ", vhp_before, "->", vhp_after,
		" (predator ", "OK" if vhp_after < vhp_before else "FAILED", ")")
	get_tree().quit()

# Renders a couple of animals up close so the procedural art can be reviewed.
func _run_capture_animals() -> void:
	await get_tree().process_frame
	animals.spawn_at("capybara", Vector2i(2, 2))
	animals.spawn_at("capybara", Vector2i(4, 1))
	animals.spawn_at("jaguar", Vector2i(3, 4))
	animals.spawn_at("tapir", Vector2i(1, 4))
	animals.spawn_at("bush_dog", Vector2i(5, 3))
	animals.spawn_at("caiman", Vector2i(2, 6))
	_spawn_unit("archer", 0, Vector2i(4, 5))
	camera.global_position = Constants.grid_to_world(3, 3)
	camera.target_zoom = 1.9
	camera.zoom = Vector2(1.9, 1.9)
	fog.force_update()
	for _i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "user://animals_capture.png"
	img.save_png(path)
	print("[capture-animals] saved ", ProjectSettings.globalize_path(path), " size=", img.get_size())
	get_tree().quit()

func _find_tc(player_id: int) -> Building:
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var building: Building = node as Building
		if building != null and building.player_id == player_id and building.building_type == "town_center":
			return building
	return null

func _run_systems_test() -> void:
	await get_tree().create_timer(0.5).timeout

	# 1. Gathering: send a villager at the nearest tree, watch the stockpile.
	var wood_before: int = GameManager.get_resource(0, Constants.ResourceType.WOOD)
	var villagers: Array = get_tree().get_nodes_in_group("player_0").filter(
		func(n: Node) -> bool: return n is UnitBase and n.unit_type == "villager")
	var tree_node: Dictionary = GameManager.world.find_nearest_resource(Vector2i.ZERO, Constants.ResourceType.WOOD)
	print("[test-systems] tree found=", tree_node["found"], " cell=", tree_node.get("cell"))
	if tree_node["found"] and villagers.size() > 0:
		(villagers[0] as UnitBase).command_gather(tree_node["cell"])

	# Symmetric fog: after the AI's first vision tick it must know its own
	# base but NOT ours (checked before the hostile test warrior spawns
	# beside our base, which would legitimately reveal it).
	await get_tree().create_timer(1.5).timeout
	var ai: Node = $EnemyAI
	var ai_knows_own: bool = ai.vision.is_explored(WorldGen.PLAYER_ORIGINS[1])
	var ai_knows_player: bool = ai.vision.is_explored(Vector2i.ZERO)
	print("[test-systems] AI explored own base=", ai_knows_own, " player base=", ai_knows_player,
		" (symmetric fog ", "OK" if ai_knows_own and not ai_knows_player else "FAILED", ")")

	# 2. Combat: spawn a hostile warrior next to our town center.
	var enemy_warrior: UnitBase = _spawn_unit("warrior", 1, Vector2i(3, 3))
	var player_tc: Building = null
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if (node as Building).player_id == 0:
			player_tc = node as Building
	var tc_hp_before: int = player_tc.current_hp
	enemy_warrior.command_attack(player_tc)

	# 3. Training: queue a villager at our town center.
	var queued: bool = player_tc.queue_train("villager")
	print("[test-systems] queued villager=", queued)

	# 4. Chunk streaming: teleport the camera far away.
	var chunks_before: int = GameManager.world.chunks.size()

	await get_tree().create_timer(20.0).timeout

	var wood_after: int = GameManager.get_resource(0, Constants.ResourceType.WOOD)
	print("[test-systems] wood before=", wood_before, " after=", wood_after, " (gathering ", "OK" if wood_after > wood_before else "FAILED", ")")
	print("[test-systems] tc hp before=", tc_hp_before, " after=", player_tc.current_hp, " (combat ", "OK" if player_tc.current_hp < tc_hp_before else "FAILED", ")")
	print("[test-systems] population=", GameManager.get_population(0))

	camera.global_position = Constants.grid_to_world(300, 300)
	await get_tree().create_timer(3.0).timeout
	var chunks_after: int = GameManager.world.chunks.size()
	print("[test-systems] chunks before=", chunks_before, " after far pan=", chunks_after, " (streaming ", "OK" if chunks_after > chunks_before else "FAILED", ")")

	# 5. Fog of war: home is explored, far land is not, distant enemies hidden.
	var home_explored: bool = fog.is_explored(Vector2i(0, 0))
	var far_explored: bool = fog.is_explored(Vector2i(200, 200))
	print("[test-systems] fog home explored=", home_explored, " far explored=", far_explored,
		" (fog ", "OK" if home_explored and not far_explored else "FAILED", ")")
	var hidden_enemies: int = 0
	var visible_enemies: int = 0
	for node: Node in get_tree().get_nodes_in_group("player_1"):
		if node is UnitBase:
			if (node as Node2D).visible:
				visible_enemies += 1
			else:
				hidden_enemies += 1
	print("[test-systems] enemy units hidden=", hidden_enemies, " visible=", visible_enemies,
		" (culling ", "OK" if hidden_enemies > 0 else "CHECK", ")")
	get_tree().quit()
