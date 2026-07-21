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

# Fixed seed for --test-world content assertions. Chosen because it places
# varzea near the origin on both axes and a varzea FOOD cell on the diagonals,
# giving the placement checks a deterministic, reproducible world to run against.
const WORLD_TEST_SEED: int = 3
# Fixed seed for the POI claim test. Ancient ruins are very rare (POI_RARITY),
# so the live random seed can't be relied on to place one near origin; this
# seed is verified to yield at least one ruin within the ±160 claim scan.
const POI_TEST_SEED: int = 3

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
	if "--test-save" in args:
		_run_save_test()
	if "--test-audio" in args:
		_run_audio_test()
	if "--test-monument" in args:
		_run_monument_test()
	if "--test-tactics" in args:
		_run_tactics_test()
	if "--test-daily" in args:
		_run_daily_test()
		return
	if "--test-rank" in args:
		_run_rank_test()
		return
	if "--test-hud" in args:
		_run_hud_test()
		return
	if "--test-fruit" in args:
		_run_fruit_test()
		return
	if "--test-fish" in args:
		_run_fish_test()
	if "--test-victory" in args:
		_run_victory_test()
	if "--test-world" in args:
		_run_world_test()
		return
	if "--test-poi" in args:
		_run_poi_test()
		return
	if "--test-poi-claim" in args:
		_run_poi_claim_test()
		return
	if "--test-era" in args:
		_run_era_test()
		return
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
	if "--capture-world" in args:
		_run_capture_world()
	if "--capture-ruins" in args:
		_run_capture_ruins()
	if "--capture-era" in args:
		_run_capture_era()

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
	# The POI claim harness sweeps the LIVE world for a ruin near origin. Ruins
	# are rare, so pin the world to the seed verified to place one within the
	# scan (same seed --test-poi asserts against) before the world is built.
	if "--test-poi-claim" in args or "--capture-ruins" in args:
		GameManager.map_seed = POI_TEST_SEED
	var resume: Dictionary = {}
	if SaveGame.pending_resume:
		SaveGame.pending_resume = false
		resume = SaveGame.load_data()
	if not resume.is_empty():
		# Terrain rebuilds deterministically; only entities and fog restore.
		GameManager.map_seed = int(resume["seed"])
		GameManager.ai_difficulty = String(resume.get("difficulty", "normal"))
		GameManager.reset_players(int(resume["player_count"]))
		GameManager._next_entity_id = int(resume["next_id"])
		for i in range(GameManager.stockpiles.size()):
			GameManager.stockpiles[i] = SaveGame.stockpile_in(resume["stockpiles"][i])
		# Per-tribe era, with a pre-Phase-2 back-compat guard: a save without the
		# "eras" key (or a shorter array) defaults the missing tribes to Forest.
		# JSON numbers round-trip as floats, so cast each back to int; clamp to a
		# valid era so a corrupted/hand-edited save can't slip past every era gate.
		var saved_eras: Array = resume.get("eras", [])
		for pid: int in range(GameManager.eras.size()):
			GameManager.eras[pid] = clampi(int(saved_eras[pid]), Constants.ERA_FOREST,
				Constants.ERA_DEFS.size() - 1) if pid < saved_eras.size() \
				else Constants.ERA_FOREST

	chunk_manager.setup(camera, doodads)

	if resume.is_empty():
		# Bases sit inside the guaranteed spawn clearings (see WorldGen).
		_place_building("town_center", 0, Vector2i(-1, -1))
		_place_building("town_center", 1, WorldGen.PLAYER_ORIGINS[1] + Vector2i(-1, -1))

		for cell: Vector2i in [Vector2i(2, 2), Vector2i(0, 3), Vector2i(3, 0)]:
			_spawn_unit("villager", 0, cell)
		for cell: Vector2i in [Vector2i(-2, 2), Vector2i(2, -2), Vector2i(-2, -2)]:
			_spawn_unit("warrior", 1, WorldGen.PLAYER_ORIGINS[1] + cell)
		camera.center_on(Constants.grid_to_world(0, 0))
	else:
		_restore_world(resume)

	chunk_manager.load_now()

	fog.setup(camera)
	if not resume.is_empty():
		fog.vision.restore_explored(resume.get("explored", []))
		var ai: Node = get_node_or_null("EnemyAI")
		if ai != null:
			ai.vision.restore_explored(resume.get("ai_explored", []))
	fog.force_update()

	GameManager.game_time_secs = 0.0
	EventBus.world_ready.emit()
	GameManager.change_state(GameManager.GameState.RUNNING)

	# Point-of-interest claiming (ancient ruin loot). Authority-only sim node;
	# it exists here because offline is the authority. Its _process self-gates
	# on Net.is_authority(), so it is inert on any non-authority path.
	_spawn_poi_manager()

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
	if Net.rematch_seed != 0:
		GameManager.map_seed = Net.rematch_seed
		Net.rematch_seed = 0
	GameManager.reset_players(players)
	var tokens: String = _arg_value(args, "--tokens=")
	if tokens != "":
		Net.slot_tokens = tokens.split(",")
	var names: String = _arg_value(args, "--names=", "")
	if names != "":
		Net.player_names = names.split(",")
	Net.report_port = int(_arg_value(args, "--report-port=", "0"))
	Net.report_key = _arg_value(args, "--report-key=", "")

	# Harness hook: end the match automatically (tests the rematch flow).
	var end_after: float = float(_arg_value(args, "--end-after=", "0"))
	if end_after > 0.0:
		get_tree().create_timer(end_after).timeout.connect(
			func() -> void: GameManager.end_game(0))

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

	# Authoritative POI claiming, symmetric across all tribes (see _boot_offline).
	_spawn_poi_manager()

# Headless lobby: no game world at all — just the Gateway autoload's room
# service. The Main scene's world/UI nodes are dropped.
func _boot_gateway(args: PackedStringArray) -> void:
	var port: int = int(_arg_value(args, "--port=", "9000"))
	var base: int = int(_arg_value(args, "--match-port-base=", "9100"))
	var extra: String = _arg_value(args, "--match-args=", "")
	if extra != "":
		Gateway.match_extra_args = extra.split(" ")
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

# Rebuild entities, harvests, and the camera from a save blob.
func _restore_world(data: Dictionary) -> void:
	for delta: Array in data.get("deltas", []):
		GameManager.world.set_resource_amount(
			Vector2i(int(delta[0]), int(delta[1])), int(delta[2]))
	for c: Array in data.get("claimed_pois", []):
		GameManager.world.restore_claimed_poi(Vector2i(int(c[0]), int(c[1])))
	for b: Array in data.get("buildings", []):
		var building: Building = Building.new()
		building.name = String(b[0])
		building.setup(String(b[1]), int(b[2]),
			Vector2i(int(b[3]), int(b[4])), bool(b[6]))
		buildings.add_child(building)
		building.current_hp = int(b[5])
		building.train_queue.assign(b[7])
		building.train_progress = float(b[8])
	for u: Array in data.get("units", []):
		var unit: UnitBase = unit_scene.instantiate() as UnitBase
		unit.name = String(u[0])
		unit.unit_type = String(u[1])
		unit.player_id = int(u[2])
		unit.position = Vector2(float(u[3]), float(u[4]))
		units.add_child(unit)
		unit.current_hp = int(u[5])
	for a: Array in data.get("animals", []):
		var beast: Animal = animals.spawn_at(String(a[0]),
			Constants.world_to_grid(Vector2(float(a[1]), float(a[2]))))
		beast.global_position = Vector2(float(a[1]), float(a[2]))
		beast.current_hp = int(a[3])
	var cam: Array = data.get("camera", [0, 0, 1.2])
	camera.center_on(Vector2(float(cam[0]), float(cam[1])))
	camera.target_zoom = float(cam[2])
	camera.zoom = Vector2(camera.target_zoom, camera.target_zoom)

func _place_building(type: String, player_id: int, base_cell: Vector2i) -> Building:
	var building: Building = Building.new()
	building.name = GameManager.claim_entity_name("B")
	building.setup(type, player_id, base_cell)
	buildings.add_child(building)
	return building

# Instantiate the authority-only POI claim manager in code (no scene visuals;
# rendering is a separate task). Named so harnesses can reach it via
# get_node_or_null("PoiManager").
func _spawn_poi_manager() -> PoiManager:
	var poi_manager: PoiManager = PoiManager.new()
	poi_manager.name = "PoiManager"
	add_child(poi_manager)
	return poi_manager

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
	return GameManager.find_buildable_cell(origin, building_type, player_id)

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

	# Barracks + archer are now Era 1, so player 0 must reach Village Age before
	# the remaining steps can exercise them. Grant the advance cost and stand up
	# a second finished house (Village requires 2; only `site` exists so far).
	GameManager.add_resource(0, Constants.ResourceType.FOOD, 500)
	GameManager.add_resource(0, Constants.ResourceType.WOOD, 300)
	_place_building("house", 0, _find_buildable_cell(Vector2i.ZERO, "house", 0))
	await get_tree().process_frame
	CommandRouter.submit({"type": "advance_era", "player_id": 0})
	await get_tree().process_frame
	print("[test-build] advanced-village ", "OK"
		if GameManager.player_era(0) == Constants.ERA_VILLAGE else "FAILED")

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

# Prove shore fishing: a fish school exists near the shore, a villager can
# work it, and the catch banks as food.
# Prove the daily-challenge core: shared seed, submission validation,
# best-time keeping, and board ordering.
func _run_daily_test() -> void:
	var today: String = GameManager.daily_date()
	var seed_same: bool = GameManager.daily_seed(today) == GameManager.daily_seed(today)
	var seed_diff: bool = GameManager.daily_seed("2026-01-01") != GameManager.daily_seed("2026-01-02")
	print("[test-daily] seed ", "OK" if seed_same and seed_diff else "FAILED")

	Gateway._registry = {}
	Gateway._daily = {}
	Gateway.claim_name("Aracy", "s-a")
	Gateway.claim_name("Boto", "s-b")

	var unknown: Dictionary = Gateway.submit_daily("Nobody", today, 300.0)
	var stale: Dictionary = Gateway.submit_daily("Aracy", "2020-01-01", 300.0)
	var cheat: Dictionary = Gateway.submit_daily("Aracy", today, 5.0)
	print("[test-daily] rejects ", "OK"
		if not unknown["ok"] and not stale["ok"] and not cheat["ok"] else "FAILED")

	var first: Dictionary = Gateway.submit_daily("Aracy", today, 400.0)
	var better: Dictionary = Gateway.submit_daily("Aracy", today, 350.0)
	var worse: Dictionary = Gateway.submit_daily("Aracy", today, 500.0)
	Gateway.submit_daily("Boto", today, 380.0)
	var board: Dictionary = Gateway.daily_board()
	var scores: Array = board["scores"]
	var order_ok: bool = scores.size() == 2 \
		and scores[0]["name"] == "Aracy" and float(scores[0]["seconds"]) == 350.0 \
		and scores[1]["name"] == "Boto"
	print("[test-daily] submit ", "OK" if first["ok"] and better["ok"] and worse["ok"] else "FAILED")
	print("[test-daily] board ", "OK" if order_ok else "FAILED", " ", scores)

	# Persistence roundtrip.
	Gateway._daily = {}
	Gateway._load_daily()
	var kept: bool = float(Gateway.daily_board()["scores"][0]["seconds"]) == 350.0
	print("[test-daily] persistence ", "OK" if kept else "FAILED")
	get_tree().quit()

# Prove the ranking core: name claims, wrong-secret rejection, Elo motion,
# report dedupe, and registry persistence across a reload.
func _run_rank_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Gateway.RANKING_PATH))
	Gateway._registry = {}

	var claim_a: Dictionary = Gateway.claim_name("Aracy", "secret-a")
	var reclaim: Dictionary = Gateway.claim_name("Aracy", "secret-a")
	var thief: Dictionary = Gateway.claim_name("Aracy", "secret-x")
	var bad: Dictionary = Gateway.claim_name("no spaces!", "s")
	print("[test-rank] claim ", "OK" if claim_a["ok"] and reclaim["ok"] else "FAILED")
	print("[test-rank] claim-auth ", "OK" if not thief["ok"] and not bad["ok"] else "FAILED")

	Gateway.claim_name("Boto", "secret-b")
	Gateway.apply_result(PackedStringArray(["Aracy", "Boto"]), 0)
	var elo_a: int = int(Gateway._registry["Aracy"]["elo"])
	var elo_b: int = int(Gateway._registry["Boto"]["elo"])
	print("[test-rank] elo ", "OK" if elo_a == 1016 and elo_b == 984 else "FAILED",
		" a=", elo_a, " b=", elo_b)
	var wl_ok: bool = int(Gateway._registry["Aracy"]["wins"]) == 1 \
		and int(Gateway._registry["Boto"]["losses"]) == 1
	print("[test-rank] win-loss ", "OK" if wl_ok else "FAILED")

	# Persistence: wipe memory, reload from disk.
	Gateway._registry = {}
	Gateway._load_registry()
	print("[test-rank] persistence ", "OK"
		if int(Gateway._registry.get("Aracy", {}).get("elo", 0)) == 1016 else "FAILED")

	Gateway.claim_name("Cacau", "secret-c")  # claimed but never played
	var board: Array = Gateway.leaderboard()
	var board_ok: bool = board.size() == 2 and board[0]["name"] == "Aracy"
	print("[test-rank] leaderboard ", "OK" if board_ok else "FAILED")
	print("[test-rank] unplayed-hidden ", "OK"
		if not board.any(func(r: Dictionary) -> bool: return r["name"] == "Cacau")
		else "FAILED")
	get_tree().quit()

# Prove the HUD input chain: select -> hotkey arms attack-move -> click
# commands the march -> stop hotkey drops it -> idle finder sees the unit.
func _run_hud_test() -> void:
	await get_tree().create_timer(0.5).timeout
	var hud: Control = $UILayer/HUD
	var villagers: Array = get_tree().get_nodes_in_group("player_0").filter(
		func(n: Node) -> bool: return n is UnitBase and (n as UnitBase).can_gather)
	var unit: UnitBase = villagers[0]
	SelectionManager.select_only(unit)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[test-hud] panel-shown ", "OK" if hud._sel_panel.visible else "FAILED")
	var rect: Rect2 = hud._sel_panel.get_global_rect()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# On screen AND clear of the bottom-corner overlays (minimap is 144px
	# + margins on the right, idle button on the left).
	var on_screen: bool = rect.position.y >= 0.0 and rect.end.y <= vp.y \
		and rect.position.x >= 170.0 and rect.end.x <= vp.x - 170.0
	print("[test-hud] panel-on-screen ", "OK" if on_screen else "FAILED",
		" rect=", rect, " vp=", vp)
	print("[test-hud] cmd-row ", "OK" if hud._cmd_box.visible else "FAILED")
	print("[test-hud] hotkeys-mapped ", "OK" if hud._hotkeys.has(KEY_G)
		and hud._hotkeys.has(KEY_X) and hud._hotkeys.has(KEY_B) else "FAILED")

	_push_key(KEY_G)
	await get_tree().process_frame
	print("[test-hud] g-arms ", "OK" if SelectionManager.attack_move_armed else "FAILED")

	_push_click(get_viewport().get_visible_rect().size / 2.0 + Vector2(200, -120))
	await get_tree().create_timer(0.5).timeout
	var marching: bool = unit.current_state == UnitBase.State.MOVING
	print("[test-hud] click-marches ", "OK" if marching
		and not SelectionManager.attack_move_armed else "FAILED",
		" state=", unit.current_state)

	_push_key(KEY_X)
	await get_tree().create_timer(0.2).timeout
	print("[test-hud] x-stops ", "OK" if unit.current_state == UnitBase.State.IDLE else "FAILED")

	await get_tree().create_timer(0.6).timeout  # idle refresh tick
	var idle_count: int = hud._idle_villagers().size()
	print("[test-hud] idle-finder ", "OK" if idle_count >= 1 else "FAILED",
		" count=", idle_count)

	# Panel-size flips (building -> unit -> building) are what used to push
	# the panel below the viewport; assert it stays on screen through them.
	var stays: bool = true
	# Exercise size flips at several window shapes — wide, square, narrow —
	# re-selecting through building -> unit -> building at each.
	for win_size: Vector2i in [Vector2i(0, 0), Vector2i(1998, 1142), Vector2i(900, 1200)]:
		if win_size.x > 0:
			get_window().size = win_size
			await get_tree().process_frame
		vp = get_viewport().get_visible_rect().size
		for target: Node2D in [_find_tc(0), unit, _find_tc(0)]:
			if target is Building:
				SelectionManager.clear_selection()
				SelectionManager.selected_building = target
				EventBus.selection_changed.emit()
			else:
				SelectionManager.select_only(target)
			await get_tree().process_frame
			await get_tree().process_frame
			var r: Rect2 = hud._sel_panel.get_global_rect()
			if r.position.y < 0.0 or r.end.y > vp.y \
					or r.position.x < 170.0 or r.end.x > vp.x - 170.0:
				stays = false
				print("  off-screen after ", target.name, " at vp=", vp, " rect=", r)
	print("[test-hud] panel-stays-on-screen ", "OK" if stays else "FAILED")

	# --- Era gate reaches the build menu (Task A6) ---
	# Re-select a villager so the build row is populated + affordability applied.
	SelectionManager.select_only(unit)
	await get_tree().process_frame
	await get_tree().process_frame
	var barracks_btn: Button = null
	for child: Node in hud._build_box.get_children():
		var bb: Button = child as Button
		if bb != null and bb.has_meta("btype") and String(bb.get_meta("btype")) == "barracks":
			barracks_btn = bb
	# Barracks is Era 1 → locked (disabled) while player 0 is still Forest.
	print("[test-hud] barracks-locked-era0 ", "OK" if barracks_btn != null
		and barracks_btn.disabled else "FAILED")
	# Advance player 0 to Village (2 finished houses + funded), via the command path.
	_place_building("house", 0, GameManager.find_buildable_cell(Vector2i.ZERO, "house", 0))
	_place_building("house", 0, GameManager.find_buildable_cell(Vector2i.ZERO, "house", 0))
	GameManager.add_resource(0, Constants.ResourceType.FOOD, 400)
	GameManager.add_resource(0, Constants.ResourceType.WOOD, 300)
	await get_tree().process_frame
	CommandRouter.submit({"type": "advance_era", "player_id": 0})
	await get_tree().process_frame
	print("[test-hud] advanced-village ", "OK" if GameManager.player_era(0)
		== Constants.ERA_VILLAGE else "FAILED")
	# Re-run the affordability pass under the new era + granted resources.
	SelectionManager.select_only(unit)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[test-hud] barracks-unlocked-village ", "OK" if barracks_btn != null
		and not barracks_btn.disabled else "FAILED")
	# The Advance button now points at Chiefdom (the next era) and is disabled
	# (no barracks yet) — proving the indicator + reason reach the top bar.
	print("[test-hud] advance-next-chiefdom ", "OK" if hud._advance_button.text.contains(
		"Chiefdom") and hud._advance_button.disabled else "FAILED text=%s" % hud._advance_button.text)
	print("[test-hud] era-label-village ", "OK" if hud._era_label.text.contains(
		"Village") else "FAILED text=%s" % hud._era_label.text)
	get_tree().quit()

func _push_key(keycode: Key) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	get_viewport().push_input(ev)

func _push_click(pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = pos
		ev.global_position = pos
		ev.pressed = pressed
		get_viewport().push_input(ev)

# Prove fruit trees bank food alongside the wood haul.
func _run_fruit_test() -> void:
	await get_tree().create_timer(0.5).timeout
	var fruit_cell: Vector2i = Vector2i(9999, 9999)
	var radius: int = 4
	while radius <= 80 and fruit_cell.x == 9999:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue  # ring only — keeps the scan linear
				var cell: Vector2i = Vector2i(dx, dy)
				var node: Dictionary = GameManager.world.get_resource_at(cell)
				if node.has("bonus_type"):
					fruit_cell = cell
					break
			if fruit_cell.x != 9999:
				break
		radius += 2
	print("[test-fruit] tree-found ", "OK" if fruit_cell.x != 9999 else "FAILED",
		" at ", fruit_cell)
	if fruit_cell.x == 9999:
		get_tree().quit(1)
		return

	var villagers: Array = get_tree().get_nodes_in_group("player_0").filter(
		func(n: Node) -> bool: return n is UnitBase and (n as UnitBase).can_gather)
	var wood_before: int = GameManager.get_resource(0, Constants.ResourceType.WOOD)
	var food_before: int = GameManager.get_resource(0, Constants.ResourceType.FOOD)
	var picker: UnitBase = villagers[0]
	picker.global_position = Constants.grid_to_world(fruit_cell.x, fruit_cell.y) \
		+ Vector2(0, 40)  # start nearby; pathing over distance isn't the point
	picker.command_gather(fruit_cell)
	var elapsed: float = 0.0
	while GameManager.get_resource(0, Constants.ResourceType.FOOD) <= food_before \
			and elapsed < 60.0:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
	var wood_after: int = GameManager.get_resource(0, Constants.ResourceType.WOOD)
	var food_after: int = GameManager.get_resource(0, Constants.ResourceType.FOOD)
	print("[test-fruit] wood-banked ", "OK" if wood_after > wood_before else "FAILED",
		" wood ", wood_before, "->", wood_after)
	print("[test-fruit] food-bonus ", "OK" if food_after > food_before else "FAILED",
		" food ", food_before, "->", food_after)
	get_tree().quit(0 if wood_after > wood_before and food_after > food_before else 1)

func _run_fish_test() -> void:
	await get_tree().create_timer(0.5).timeout
	var fish_cell: Vector2i = Vector2i(9999, 9999)
	var radius: int = 8
	while radius <= 60 and fish_cell.x == 9999:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue  # ring only — keeps the scan linear
				var cell: Vector2i = Vector2i(dx, dy)
				var node: Dictionary = GameManager.world.get_resource_at(cell)
				if node.get("fish", false):
					fish_cell = cell
					break
			if fish_cell.x != 9999:
				break
		radius += 2
	print("[test-fish] school-found ", "OK" if fish_cell.x != 9999 else "FAILED",
		" at ", fish_cell)
	if fish_cell.x == 9999:
		get_tree().quit(1)
		return

	var villagers: Array = get_tree().get_nodes_in_group("player_0").filter(
		func(n: Node) -> bool: return n is UnitBase and (n as UnitBase).can_gather)
	var food_before: int = GameManager.get_resource(0, Constants.ResourceType.FOOD)
	var fisher: UnitBase = villagers[0]
	fisher.global_position = Constants.grid_to_world(fish_cell.x, fish_cell.y) \
		+ Vector2(0, 40)  # start nearby; pathing over distance isn't the point
	fisher.command_gather(fish_cell)
	var elapsed: float = 0.0
	while GameManager.get_resource(0, Constants.ResourceType.FOOD) <= food_before \
			and elapsed < 45.0:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
	var food_after: int = GameManager.get_resource(0, Constants.ResourceType.FOOD)
	print("[test-fish] catch-banked ", "OK" if food_after > food_before else "FAILED",
		" food ", food_before, "->", food_after)
	get_tree().quit()

# Prove rally points and attack-move.
func _run_tactics_test() -> void:
	await get_tree().create_timer(0.5).timeout
	# Rally: set one on the TC, train a villager, expect it to march there.
	var tc: Building = _find_tc(0)
	CommandRouter.submit({"type": "rally", "player_id": 0,
		"building_name": String(tc.name), "cell": Vector2i(7, 7)})
	await get_tree().process_frame
	print("[test-tactics] rally-set ",
		"OK" if tc.rally_cell == Vector2i(7, 7) else "FAILED")
	GameManager.add_resource(0, Constants.ResourceType.FOOD, 200)
	tc.queue_train("villager")
	var rally_world: Vector2 = Constants.grid_to_world(7, 7)
	var arrived: bool = false
	var elapsed: float = 0.0
	while not arrived and elapsed < 20.0:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
		for node: Node in get_tree().get_nodes_in_group("player_0"):
			if node is UnitBase and (node as Node2D).global_position.distance_to(rally_world) < 60.0:
				arrived = true
	print("[test-tactics] rally-march ", "OK" if arrived else "FAILED")

	# Attack-move: a warrior ordered past an enemy stops to kill it.
	var warrior: UnitBase = _spawn_unit("warrior", 0, Vector2i(-4, -4))
	var bait: UnitBase = _spawn_unit("villager", 1, Vector2i(-4, 2))
	await get_tree().process_frame
	CommandRouter.submit({"type": "attack_move", "player_id": 0,
		"actor_names": [String(warrior.name)],
		"target": Constants.grid_to_world(-4, 8)})
	elapsed = 0.0
	while is_instance_valid(bait) and elapsed < 25.0:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
	print("[test-tactics] attack-move ", "OK" if not is_instance_valid(bait) else "FAILED")
	get_tree().quit()

# Prove the jade endgame: a constructed monument counts down and wins for
# its owner; destroying it stops the clock.
func _run_monument_test() -> void:
	await get_tree().create_timer(0.5).timeout
	GameManager.add_resource(0, Constants.ResourceType.JADE, 100)
	GameManager.add_resource(0, Constants.ResourceType.WOOD, 200)
	var villagers: Array = get_tree().get_nodes_in_group("player_0").filter(
		func(n: Node) -> bool: return n is UnitBase and (n as UnitBase).can_gather)
	var names: Array = villagers.map(func(u: Node2D) -> String: return String(u.name))
	var cell: Vector2i = _find_buildable_cell(Vector2i.ZERO, "monument", 0)
	CommandRouter.submit({"type": "place", "player_id": 0,
		"building_type": "monument", "cell": cell, "actor_names": names})
	await get_tree().process_frame
	var monument: Building = GameManager.world.building_at(cell) as Building
	print("[test-monument] placed ", "OK" if monument != null else "FAILED")
	var elapsed: float = 0.0
	while monument != null and not monument.is_constructed and elapsed < 60.0:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
	print("[test-monument] constructed ", "OK" if monument.is_constructed else "FAILED")

	# Fast-forward the countdown to its final seconds.
	monument.monument_timer = Constants.MONUMENT_VICTORY_SECS - 2.0
	var winner: Array = [-1]
	EventBus.game_over.connect(func(w: int) -> void: winner[0] = w, CONNECT_ONE_SHOT)
	await get_tree().create_timer(3.0).timeout
	print("[test-monument] victory ", "OK" if winner[0] == 0 else "FAILED",
		" winner=", winner[0])
	get_tree().quit()

# Prove the procedural audio bank: every stream synthesized non-empty, the
# player pool plays without errors, and settings round-trip.
func _run_audio_test() -> void:
	await get_tree().process_frame
	var all_ok: bool = true
	for name: String in ["chop", "tick", "hammer", "bow", "hit", "die",
			"click", "built", "victory", "defeat", "ambience"]:
		var stream: AudioStreamWAV = Sfx._streams.get(name)
		if stream == null or stream.data.size() == 0:
			all_ok = false
			print("[test-audio] stream %s MISSING" % name)
	print("[test-audio] streams ", "OK" if all_ok else "FAILED")
	Sfx.play("chop", Vector2.ZERO)
	Sfx.play("built")
	Sfx.ambience_start()
	await get_tree().create_timer(0.3).timeout
	Sfx.ambience_stop()
	print("[test-audio] playback OK")
	Sfx.set_volume(0.5)
	Sfx.set_muted(true)
	Sfx._load_settings()
	print("[test-audio] settings ",
		"OK" if Sfx.muted and absf(Sfx.volume - 0.5) < 0.01 else "FAILED")
	Sfx.set_muted(false)
	Sfx.set_volume(0.8)
	get_tree().quit()

# Prove save/resume: play a moment, save, reload the scene as a resume, and
# check the world came back identical (stockpile, entities, fog, harvests).
func _run_save_test() -> void:
	if SaveGame.has_meta("save_test_expected"):
		_run_save_test_phase2()
		return
	await get_tree().create_timer(0.5).timeout
	# Change some state: chop a tree and move a villager.
	var villagers: Array = get_tree().get_nodes_in_group("player_0").filter(
		func(n: Node) -> bool: return n is UnitBase and (n as UnitBase).can_gather)
	var tree_node: Dictionary = GameManager.world.find_nearest_resource(
		Vector2i.ZERO, Constants.ResourceType.WOOD)
	if tree_node["found"]:
		(villagers[0] as UnitBase).command_gather(tree_node["cell"])
	await get_tree().create_timer(6.0).timeout

	# Advance player 0 to Village so save/reload must preserve per-tribe era state.
	# Place the two finished houses Village requires (find_buildable_cell keeps the
	# footprints from colliding) and grant the advance cost, then advance via the
	# command path.
	_place_building("house", 0, GameManager.find_buildable_cell(Vector2i.ZERO, "house", 0))
	_place_building("house", 0, GameManager.find_buildable_cell(Vector2i.ZERO, "house", 0))
	GameManager.add_resource(0, Constants.ResourceType.FOOD, 500)
	GameManager.add_resource(0, Constants.ResourceType.WOOD, 300)
	await get_tree().process_frame
	CommandRouter.submit({"type": "advance_era", "player_id": 0})
	await get_tree().process_frame
	print("[test-save] era-advanced ", "OK"
		if GameManager.player_era(0) == Constants.ERA_VILLAGE else "FAILED")

	SaveGame.save_now()
	var expected: Dictionary = {
		"wood": GameManager.get_resource(0, Constants.ResourceType.WOOD),
		"units": get_tree().get_nodes_in_group("units").size(),
		"buildings": get_tree().get_nodes_in_group("buildings").size(),
		"explored": GameManager.fog.vision.explored.size(),
		"deltas": GameManager.world.resource_deltas.size(),
		"unit_name": String(villagers[0].name),
		"era": GameManager.player_era(0),
	}
	print("[test-save] saved (deltas=", expected["deltas"], ")")
	SaveGame.set_meta("save_test_expected", expected)
	SaveGame.pending_resume = true
	Net.reset()
	get_tree().reload_current_scene()

func _run_save_test_phase2() -> void:
	await get_tree().create_timer(1.0).timeout
	var expected: Dictionary = SaveGame.get_meta("save_test_expected")
	var wood_ok: bool = GameManager.get_resource(0, Constants.ResourceType.WOOD) == expected["wood"]
	print("[test-save] stockpile ", "OK" if wood_ok else "FAILED")
	var units_ok: bool = get_tree().get_nodes_in_group("units").size() == expected["units"]
	print("[test-save] units ", "OK" if units_ok else "FAILED")
	var buildings_ok: bool = get_tree().get_nodes_in_group("buildings").size() == expected["buildings"]
	print("[test-save] buildings ", "OK" if buildings_ok else "FAILED")
	var explored_ok: bool = GameManager.fog.vision.explored.size() >= expected["explored"]
	print("[test-save] fog ", "OK" if explored_ok else "FAILED")
	var named: bool = false
	for node: Node in get_tree().get_nodes_in_group("units"):
		if String(node.name) == expected["unit_name"]:
			named = true
	print("[test-save] identity ", "OK" if named else "FAILED")
	print("[test-save] era ", "OK"
		if GameManager.player_era(0) == expected["era"] else "FAILED")
	SaveGame.clear()
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
	Gateway.room_updated.connect(
		func(code: String, count: int, slot: int, names: PackedStringArray) -> void:
			updates.append([code, count, slot, names]))
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

	# The lobby requires a claimed name before any room action.
	var hello: Array = []
	Gateway.hello_result.connect(
		func(ok: bool, reason: String, _e: int, _w: int, _l: int) -> void:
			hello.append([ok, reason]))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var gw_name: String = ("GwH%05d" if is_host else "GwJ%05d") % rng.randi_range(0, 99999)
	Gateway.send_hello(gw_name, "%08x%08x" % [rng.randi(), rng.randi()])
	await _until(func() -> bool: return not hello.is_empty(), 10.0)
	if hello.is_empty() or not hello[0][0]:
		print("[test-gw] %s hello FAILED %s" % [role, hello])
		get_tree().quit(1)
		return
	print("[test-gw] %s hello OK name=%s" % [role, gw_name])

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
	if Net.has_meta("mp_rematch_phase2"):
		_run_mp_rematch_phase2()
		return
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

	# Rematch: wait for the harness server's scripted game over, vote, and
	# let the reconnect flow run — phase 2 asserts the fresh world.
	await _until(func() -> bool:
		return GameManager.state == GameManager.GameState.GAME_OVER, 40.0)
	if GameManager.state != GameManager.GameState.GAME_OVER:
		print("[test-mp] rematch FAILED (no game over)")
		get_tree().quit(1)
		return
	Net.set_meta("mp_rematch_phase2", true)
	Net.request_rematch()
	# The scene reloads via the rematch reconnect; phase 2 takes over.

func _run_mp_rematch_phase2() -> void:
	var own_group: String = "player_%d" % GameManager.local_player_id
	await _until(func() -> bool:
		return get_tree().get_nodes_in_group(own_group).size() >= 4, 15.0)
	var mine: Array = get_tree().get_nodes_in_group(own_group).filter(
		func(n: Node) -> bool: return n is UnitBase)
	print("[test-mp] rematch ", "OK" if mine.size() == 3 \
		and GameManager.state == GameManager.GameState.RUNNING else "FAILED")
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

# Prove the era data model: every tribe starts in Era 0, ERA_DEFS has exactly
# three ages, and every unit/building def carries an era gate.
func _run_era_test() -> void:
	# Every player starts in Era 0 (Forest Age).
	print("[test-era] start-era-0: %s" % ("OK" if GameManager.player_era(0) == 0 and GameManager.player_era(1) == 0 else "FAILED"))
	# ERA_DEFS defines exactly 3 eras.
	print("[test-era] three-eras: %s" % ("OK" if Constants.ERA_DEFS.size() == 3 else "FAILED"))
	# Every unit/building def carries an era gate.
	var all_gated := true
	for t: String in Constants.UNIT_DEFS:
		if not Constants.UNIT_DEFS[t].has("era"): all_gated = false
	for t: String in Constants.BUILDING_DEFS:
		if not Constants.BUILDING_DEFS[t].has("era"): all_gated = false
	print("[test-era] defs-gated: %s" % ("OK" if all_gated else "FAILED"))

	# --- advance_era ---
	# Give the world a moment to settle so find_buildable_cell has scouted cells.
	await get_tree().create_timer(0.5).timeout
	# Fresh player 0 has no houses → cannot advance to Village.
	print("[test-era] advance-requires-houses: %s" % ("OK" if not GameManager.can_advance_era(0) else "FAILED"))
	# Place the two finished houses the Village era requires. _place_building
	# constructs the building finished (is_constructed defaults true); use
	# find_buildable_cell so the two footprints don't collide.
	var house_a: Vector2i = GameManager.find_buildable_cell(Vector2i.ZERO, "house", 0)
	_place_building("house", 0, house_a)
	var house_b: Vector2i = GameManager.find_buildable_cell(Vector2i.ZERO, "house", 0)
	_place_building("house", 0, house_b)
	await get_tree().process_frame
	print("[test-era] requirements-met: %s" % ("OK" if GameManager.can_advance_era(0) else "FAILED"))
	# Grant enough resources and advance via the COMMAND path (not by calling
	# advance_era directly — exercise CommandRouter).
	GameManager.add_resource(0, Constants.ResourceType.FOOD, 500)
	GameManager.add_resource(0, Constants.ResourceType.WOOD, 300)
	var food_before: int = GameManager.get_resource(0, Constants.ResourceType.FOOD)
	CommandRouter.submit({"type": "advance_era", "player_id": 0})
	await get_tree().process_frame
	print("[test-era] advanced: %s" % ("OK" if GameManager.player_era(0) == Constants.ERA_VILLAGE else "FAILED"))
	print("[test-era] charged: %s" % ("OK" if GameManager.get_resource(0, Constants.ResourceType.FOOD) == food_before - 200 else "FAILED"))
	# Idempotent-ish: advancing again to Village must fail (already there); and it
	# should not double-charge.
	var food_after: int = GameManager.get_resource(0, Constants.ResourceType.FOOD)
	CommandRouter.submit({"type": "advance_era", "player_id": 0})
	await get_tree().process_frame
	print("[test-era] no-recharge: %s" % ("OK" if GameManager.get_resource(0, Constants.ResourceType.FOOD) == food_after else "FAILED"))

	# --- era gates on the authoritative build path ---
	# Barracks is Era 1. Player 1 is still Era 0 → placement must be refused even
	# when perfectly affordable (proving the block is the era gate, not cost).
	GameManager.add_resource(1, Constants.ResourceType.WOOD, 200)
	GameManager.add_resource(1, Constants.ResourceType.FOOD, 200)
	var p1_builds_before: int = _count_buildings(1)
	var cell1: Vector2i = GameManager.find_buildable_cell(WorldGen.PLAYER_ORIGINS[1], "barracks", 1)
	CommandRouter.submit({"type": "place", "player_id": 1, "building_type": "barracks",
		"cell": cell1, "actor_names": []})
	await get_tree().process_frame
	print("[test-era] barracks-locked-era0: %s" % ("OK" if _count_buildings(1) == p1_builds_before else "FAILED"))
	# Player 0 was advanced to Village (Era 1) above → barracks placement allowed.
	GameManager.add_resource(0, Constants.ResourceType.WOOD, 200)
	GameManager.add_resource(0, Constants.ResourceType.FOOD, 200)
	var p0_builds_before: int = _count_buildings(0)
	var p0_villagers: Array = get_tree().get_nodes_in_group("player_0").filter(
		func(n: Node) -> bool: return n is UnitBase and (n as UnitBase).can_gather)
	var p0_names: Array = p0_villagers.map(func(u: Node2D) -> String: return String(u.name))
	var cell0: Vector2i = GameManager.find_buildable_cell(Vector2i.ZERO, "barracks", 0)
	CommandRouter.submit({"type": "place", "player_id": 0, "building_type": "barracks",
		"cell": cell0, "actor_names": p0_names})
	await get_tree().process_frame
	print("[test-era] barracks-ok-era1: %s" % ("OK" if _count_buildings(0) > p0_builds_before else "FAILED"))

	# --- era buffs (Task A4) ---
	# Gather buff: an Era-1+ player's gather_mult exceeds 1.0. (player 0 is Village by now.)
	print("[test-era] gather-buff-value: %s" % ("OK" if GameManager.era_buff(0, "gather_mult", 1.0) > 1.0 else "FAILED"))
	# Armor buff WIRING: a warrior owned by a Chiefdom player takes 1 less damage
	# than an identical warrior owned by a Forest player. Advance player 0 to
	# Chiefdom first (finished barracks meets the requirement; grant resources).
	_place_building("barracks", 0, GameManager.find_buildable_cell(Vector2i.ZERO, "barracks", 0))
	GameManager.add_resource(0, Constants.ResourceType.FOOD, 400)
	GameManager.add_resource(0, Constants.ResourceType.WOOD, 300)
	GameManager.add_resource(0, Constants.ResourceType.JADE, 200)
	await get_tree().process_frame
	CommandRouter.submit({"type": "advance_era", "player_id": 0})
	await get_tree().process_frame
	print("[test-era] chiefdom: %s" % ("OK" if GameManager.player_era(0) == Constants.ERA_CHIEFDOM else "FAILED"))
	var w_chief: UnitBase = _spawn_unit("warrior", 0, Vector2i(6, 6))
	var w_forest: UnitBase = _spawn_unit("warrior", 1, WorldGen.PLAYER_ORIGINS[1] + Vector2i(3, 3))
	await get_tree().process_frame
	var chief_hp0: int = w_chief.current_hp
	var forest_hp0: int = w_forest.current_hp
	w_chief.take_damage(10, null)
	w_forest.take_damage(10, null)
	var chief_loss: int = chief_hp0 - w_chief.current_hp
	var forest_loss: int = forest_hp0 - w_forest.current_hp
	print("[test-era] armor-buff-wired: %s" % ("OK" if forest_loss - chief_loss == 1 else "FAILED (chief_loss=%d forest_loss=%d)" % [chief_loss, forest_loss]))
	get_tree().quit()

# Count buildings owned by a player: the `node as Building` cast drops any
# non-building member of the group, and the player_id filter scopes the count
# to a single owner.
func _count_buildings(player_id: int) -> int:
	var n: int = 0
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var building: Building = node as Building
		if building != null and building.player_id == player_id:
			n += 1
	return n

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

	# Stop: a fresh march is dropped on the spot.
	CommandRouter.submit({
		"type": "move", "player_id": 0,
		"actor_names": [String(mover.name)],
		"target": Constants.grid_to_world(30, 30),
	})
	await get_tree().create_timer(0.5).timeout
	CommandRouter.submit({
		"type": "stop", "player_id": 0,
		"actor_names": [String(mover.name)],
	})
	await get_tree().process_frame
	var stopped: bool = mover.current_state == UnitBase.State.IDLE
	print("[test-commands] stop ", "OK" if stopped else "FAILED")

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
	ai.wave_grace = 0.0
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
	_spawn_unit("warrior", 0, Vector2i(5, 4))
	_spawn_unit("warrior", 1, Vector2i(1, 5))
	# One of each unit per tribe, in tribe rows, plus the painted buildings.
	for pid in range(4):
		_spawn_unit("villager", pid, Vector2i(-2 + pid * 2, 6))
		_spawn_unit("warrior", pid, Vector2i(-2 + pid * 2, 7))
		_spawn_unit("archer", pid, Vector2i(-2 + pid * 2, 8))
	_place_building("house", 0, Vector2i(-5, 2))
	_place_building("barracks", 1, Vector2i(-6, 4))
	_place_building("watchtower", 2, Vector2i(-4, 7))
	_place_building("monument", 3, Vector2i(7, 6))
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

func _run_capture_world() -> void:
	await get_tree().process_frame
	# Scan outward from the origin for the nearest varzea cell. The playable
	# world uses a random seed, so we locate it dynamically rather than assume.
	var target := Vector2i(0, 0)
	var found := false
	for r in range(2, 120):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := Vector2i(dx, dy)
				if GameManager.world.get_biome(c) == Constants.Biome.VARZEA:
					target = c
					found = true
					break
			if found: break
		if found: break
	print("[capture-world] varzea near origin: ", found, " at ", target)
	# Drop units on the varzea cell to prove it is walkable land, not water.
	_spawn_unit("villager", 0, target + Vector2i(1, 0))
	_spawn_unit("warrior", 0, target + Vector2i(0, 1))
	camera.global_position = Constants.grid_to_world(target.x, target.y)
	camera.target_zoom = 1.9
	camera.zoom = Vector2(1.9, 1.9)
	fog.force_update()
	for _i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "user://world_capture.png"
	img.save_png(path)
	print("[capture-world] saved ", ProjectSettings.globalize_path(path), " size=", img.get_size())
	get_tree().quit()

# Pan to an unclaimed ancient ruin (POI_TEST_SEED pins one near origin) and
# screenshot it so the coordinator can eyeball the landmark sprite.
func _run_capture_ruins() -> void:
	await get_tree().process_frame
	var w: WorldData = GameManager.world
	var ruin := Vector2i(999999, 999999)
	for r in range(0, 161):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue  # ring only
				var c := Vector2i(dx, dy)
				if w.get_poi_at(c).get("type") == Constants.POI_ANCIENT_RUINS and not w.is_poi_claimed(c):
					ruin = c; break
			if ruin.x != 999999: break
		if ruin.x != 999999: break
	if ruin.x == 999999:
		print("[capture-ruins] setup: FAILED (no ruin found within r=160)")
		get_tree().quit(); return
	# Reveal the ruin without claiming it: a scout 2 tiles away sits inside unit
	# vision (radius >= 4) but outside the claim radius (1), so the fog lifts and
	# the unclaimed landmark renders under the fog shader.
	_spawn_unit("villager", 0, ruin + Vector2i(2, 0))
	camera.global_position = Constants.grid_to_world(ruin.x, ruin.y)
	camera.target_zoom = 1.9
	camera.zoom = Vector2(1.9, 1.9)
	chunk_manager.load_now()
	fog.force_update()
	for _i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "user://ruins_capture.png"
	img.save_png(path)
	print("[capture-ruins] saved ", ProjectSettings.globalize_path(path), " ruin at ", ruin)
	get_tree().quit()

# Screenshot the era HUD for visual review: advance player 0 to Village so the
# capture shows a non-Forest indicator, an enabled/updated Advance button, and a
# now-unlocked barracks in the build menu. Self-quits after saving (no
# --quit-after, which raced the save in a prior task).
func _run_capture_era() -> void:
	await get_tree().create_timer(0.5).timeout
	# Meet the Village requirement (2 finished houses) and fund the advance, then
	# drive it through the authoritative command path — the HUD reacts via signals.
	_place_building("house", 0, GameManager.find_buildable_cell(Vector2i.ZERO, "house", 0))
	_place_building("house", 0, GameManager.find_buildable_cell(Vector2i.ZERO, "house", 0))
	GameManager.add_resource(0, Constants.ResourceType.FOOD, 400)
	GameManager.add_resource(0, Constants.ResourceType.WOOD, 300)
	await get_tree().process_frame
	CommandRouter.submit({"type": "advance_era", "player_id": 0})
	await get_tree().process_frame
	# Select a villager so the era-gated build menu is on screen in the shot.
	var villagers: Array = get_tree().get_nodes_in_group("player_0").filter(
		func(n: Node) -> bool: return n is UnitBase and (n as UnitBase).can_gather)
	if not villagers.is_empty():
		SelectionManager.select_only(villagers[0])
	camera.center_on(Constants.grid_to_world(0, 0))
	camera.target_zoom = 1.4
	camera.zoom = Vector2(1.4, 1.4)
	fog.force_update()
	for _i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "user://era_capture.png"
	img.save_png(path)
	print("[capture-era] saved ", ProjectSettings.globalize_path(path),
		" era=", Constants.ERA_DEFS[GameManager.player_era(0)]["name"])
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

func _run_world_test() -> void:
	var b: int = Constants.Biome.VARZEA
	var tables := {
		"MOVEMENT_COST": Constants.MOVEMENT_COST,
		"WALKABLE": Constants.WALKABLE,
		"BUILDABLE": Constants.BUILDABLE,
		"BIOME_RAMPS": Constants.BIOME_RAMPS,
		"BIOME_COLORS": Constants.BIOME_COLORS,
	}
	for table_name: String in tables:
		var present: bool = tables[table_name].has(b)
		print("[test-world] %s has VARZEA: %s" % [table_name, "OK" if present else "FAILED"])
	print("[test-world] varzea walkable=%s buildable=%s" % [
		Constants.WALKABLE.get(b, false), Constants.BUILDABLE.get(b, false)])
	# A cell known to be varzea: walkable-for-move but not buildable.
	# The playable world (GameManager.world) uses a random seed, so near-origin
	# content is unpredictable. WorldGen is a pure function of the seed, so we
	# assert varzea placement against a fixed-seed world for a deterministic,
	# reproducible regression guard (a placement regression still fails here).
	var w := WorldData.new(WORLD_TEST_SEED)
	var found := false
	for r in range(4, 60):
		for c: Vector2i in [Vector2i(r, 0), Vector2i(0, r), Vector2i(-r, 0), Vector2i(0, -r)]:
			if w.get_biome(c) == Constants.Biome.VARZEA:
				print("[test-world] varzea cell %s walkable=%s buildable=%s" % [
					c, w.is_walkable(c), w.is_buildable(c)])
				found = true
				break
		if found: break
	print("[test-world] found-varzea: %s" % ("OK" if found else "FAILED"))
	var food_on_varzea := false
	for r in range(4, 80):
		for c: Vector2i in [Vector2i(r, r), Vector2i(-r, r), Vector2i(r, -r), Vector2i(-r, -r)]:
			if w.get_biome(c) == Constants.Biome.VARZEA:
				var res: Dictionary = w.gen.resource_at(c.x, c.y, Constants.Biome.VARZEA)
				if res.get("type") == Constants.ResourceType.FOOD:
					food_on_varzea = true
					break
		if food_on_varzea: break
	print("[test-world] varzea-food: %s" % ("OK" if food_on_varzea else "FAILED"))
	get_tree().quit()

func _run_poi_test() -> void:
	var w: WorldData = GameManager.world
	# Determinism: same coords -> same POI, twice.
	var a: Dictionary = w.gen.poi_at(1234, -567, w.gen.biome_at(1234, -567))
	var b: Dictionary = w.gen.poi_at(1234, -567, w.gen.biome_at(1234, -567))
	print("[test-poi] deterministic: %s" % ("OK" if a == b else "FAILED"))
	# Rarity + placement: scan a wide area, expect a handful, all on buildable land.
	var count := 0
	var on_bad := 0
	for y in range(-120, 120):
		for x in range(-120, 120):
			var biome: int = w.gen.biome_at(x, y)
			var p: Dictionary = w.gen.poi_at(x, y, biome)
			if p.is_empty():
				continue
			count += 1
			if not Constants.BUILDABLE.get(biome, false):
				on_bad += 1
	print("[test-poi] found %d POIs in 240x240; on-unbuildable=%d" % [count, on_bad])
	print("[test-poi] rarity: %s" % ("OK" if count >= 1 and count <= 40 else "FAILED"))
	print("[test-poi] placement: %s" % ("OK" if on_bad == 0 else "FAILED"))
	# Stored on the chunk that owns the tile.
	var cc: Vector2i = Constants.tile_to_chunk(Vector2i(0, 0))
	var chunk: ChunkData = w.get_chunk(cc)
	print("[test-poi] chunk store is Dictionary: %s" % ("OK" if chunk.pois is Dictionary else "FAILED"))
	# Claim semantics + save round-trip, against a FIXED seed so a ruin is
	# guaranteed present near origin (ruins are rare; the live seed is random).
	var fw: WorldData = WorldData.new(POI_TEST_SEED)
	var ruin := Vector2i(999999, 999999)
	for yy in range(-160, 160):
		for xx in range(-160, 160):
			if fw.get_poi_at(Vector2i(xx, yy)).get("type") == Constants.POI_ANCIENT_RUINS:
				ruin = Vector2i(xx, yy); break
		if ruin.x != 999999: break
	if ruin.x == 999999:
		print("[test-poi] claim-setup: FAILED (no ruin for POI_TEST_SEED — pick another seed)")
	else:
		print("[test-poi] pre-claim: %s" % ("OK" if not fw.is_poi_claimed(ruin) else "FAILED"))
		var first: bool = fw.claim_poi(ruin)
		var second: bool = fw.claim_poi(ruin)
		print("[test-poi] claim-once: %s" % ("OK" if first and not second else "FAILED"))
		print("[test-poi] now-claimed: %s" % ("OK" if fw.is_poi_claimed(ruin) else "FAILED"))
		# Save round-trip: serialize (as SaveGame does) then restore into a fresh
		# same-seed world (as Main._restore_world does). Must survive.
		var serialized: Array = []
		for cell: Vector2i in fw.claimed_pois:
			serialized.append([cell.x, cell.y])
		var restored: WorldData = WorldData.new(POI_TEST_SEED)
		for arr: Array in serialized:
			restored.restore_claimed_poi(Vector2i(int(arr[0]), int(arr[1])))
		print("[test-poi] claim-roundtrip: %s" % ("OK" if restored.is_poi_claimed(ruin) else "FAILED"))
	get_tree().quit()

# Prove ancient ruins are looted on proximity: a unit reaching an unclaimed ruin
# banks its loot for that unit's player, once and only once. Runs on the live
# (authority) world, which _boot_offline pins to POI_TEST_SEED so a ruin sits
# within the scan below.
func _run_poi_claim_test() -> void:
	await get_tree().create_timer(0.5).timeout
	var w: WorldData = GameManager.world
	# Nearest unclaimed ancient ruin by outward ring scan. r goes to 160 to cover
	# the same ±160 region --test-poi verifies a ruin exists in for this seed.
	var ruin := Vector2i(999999, 999999)
	for r in range(0, 161):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue  # ring only — skip interior already scanned
				var c := Vector2i(dx, dy)
				if w.get_poi_at(c).get("type") == Constants.POI_ANCIENT_RUINS and not w.is_poi_claimed(c):
					ruin = c; break
			if ruin.x != 999999: break
		if ruin.x != 999999: break
	if ruin.x == 999999:
		print("[test-poi-claim] setup: FAILED (no ruin found within r=160)")
		get_tree().quit(); return
	print("[test-poi-claim] ruin at ", ruin)

	# Render-wiring: build the ruin's chunk visual near the camera and confirm
	# an unclaimed ruin gets a landmark sprite (Sprite2D nodes exist headlessly).
	var ruin_chunk: ChunkData = w.get_chunk(Constants.tile_to_chunk(ruin))
	camera.global_position = Constants.grid_to_world(ruin.x, ruin.y)
	chunk_manager.load_now()
	await get_tree().process_frame
	print("[test-poi-claim] sprite-built: %s" % ("OK" if ruin_chunk.poi_sprites.has(ruin) else "FAILED"))

	var pm: PoiManager = get_node_or_null("PoiManager")
	print("[test-poi-claim] manager-present: %s" % ("OK" if pm != null else "FAILED"))

	var jade_before: int = GameManager.get_resource(0, Constants.ResourceType.JADE)
	var wood_before: int = GameManager.get_resource(0, Constants.ResourceType.WOOD)

	# Spawn a player-0 unit ON the ruin cell (ruins sit on buildable, hence
	# walkable, land) and sweep.
	_spawn_unit("warrior", 0, ruin)
	await get_tree().process_frame
	if pm != null:
		pm.check_claims()
	await get_tree().process_frame

	var jade_after: int = GameManager.get_resource(0, Constants.ResourceType.JADE)
	var wood_after: int = GameManager.get_resource(0, Constants.ResourceType.WOOD)
	print("[test-poi-claim] looted-jade: %s" % ("OK" if jade_after == jade_before + 40 else "FAILED (%d->%d)" % [jade_before, jade_after]))
	print("[test-poi-claim] looted-wood: %s" % ("OK" if wood_after == wood_before + 60 else "FAILED (%d->%d)" % [wood_before, wood_after]))
	print("[test-poi-claim] claimed: %s" % ("OK" if w.is_poi_claimed(ruin) else "FAILED"))
	# The poi_claimed signal must have removed the landmark sprite.
	print("[test-poi-claim] sprite-removed: %s" % ("OK" if not ruin_chunk.poi_sprites.has(ruin) else "FAILED"))

	# No double-claim: sweeping again must not credit more.
	if pm != null:
		pm.check_claims()
	await get_tree().process_frame
	var jade_after2: int = GameManager.get_resource(0, Constants.ResourceType.JADE)
	print("[test-poi-claim] no-double: %s" % ("OK" if jade_after2 == jade_after else "FAILED"))
	get_tree().quit()
