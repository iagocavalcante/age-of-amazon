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

	var args: PackedStringArray = OS.get_cmdline_user_args()

	# Ambient wildlife runs in normal play; harnesses seed their own animals
	# (or none) so the simulation stays deterministic.
	if not _is_harness(args):
		animals.setup(camera)

	if "--test-move" in args:
		_run_move_test()
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
