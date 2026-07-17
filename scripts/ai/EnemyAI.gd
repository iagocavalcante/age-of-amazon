# scripts/ai/EnemyAI.gd
extends Node

# Opponent that plays under the SAME fog-of-war rules as the player: it keeps
# its own PlayerVision and only acts on what its units have scouted.
#
# Behavior loop:
#  - trickle income (it fields no economy — the one remaining concession)
#  - keeps training warriors at its Town Center
#  - while the player is undiscovered, a scout sweeps compass directions
#  - once a player building is discovered (or a unit is spotted), attack
#    waves target it
#  - attacks on its own buildings are answered by idle warriors (being hit
#    reveals the attacker — same rule the player enjoys)

const ENEMY_ID: int = 1
const TICK_INTERVAL: float = 1.0
const WAVE_MIN_WARRIORS: int = 3

# Filled from DIFFICULTY_PRESETS in _ready.
var max_military: int = 8
var archer_ratio: float = 0.3
var builds: bool = true

# Tuned 2026-07-17 after player feedback that normal was brutal: the AI's
# trickle is a faucet economy the player cannot raid, so it must stay well
# below what a real villager line produces. "grace" holds the first wave
# back long enough to establish an economy; "wave_size" caps how many
# warriors leave home at once (hard sends everyone).
const DIFFICULTY_PRESETS: Dictionary = {
	"easy": {"wave": 130.0, "max": 4, "archers": 0.0, "builds": false,
		"grace": 300.0, "wave_size": 3,
		"trickle": {Constants.ResourceType.FOOD: 1, Constants.ResourceType.WOOD: 1}},
	"normal": {"wave": 95.0, "max": 6, "archers": 0.2, "builds": true,
		"grace": 210.0, "wave_size": 5,
		"trickle": {Constants.ResourceType.FOOD: 2, Constants.ResourceType.WOOD: 1}},
	"hard": {"wave": 55.0, "max": 14, "archers": 0.4, "builds": true,
		"grace": 60.0, "wave_size": 999,
		"trickle": {Constants.ResourceType.FOOD: 5, Constants.ResourceType.WOOD: 3}},
}
const SCOUT_DISTANCE_STEP: int = 12
const SCOUT_DISTANCE_MAX: int = 80
const HUNT_RANGE_TILES: int = 26

# Tunable pacing (the test harness shortens these).
@export var wave_interval: float = 75.0
@export var scout_interval: float = 18.0
@export var hunt_interval: float = 22.0
@export var wave_grace: float = 210.0  # no waves before this game time
var wave_size: int = 5
var _elapsed: float = 0.0

var trickle: Dictionary = {
	Constants.ResourceType.FOOD: 3,
	Constants.ResourceType.WOOD: 2,
}

var vision: PlayerVision = PlayerVision.new(ENEMY_ID)

var _tick_accum: float = 0.0
var _wave_accum: float = 0.0
var _scout_accum: float = 0.0
var _scout_direction: int = 0
var _scout_distance: int = 34
var _hunt_accum: float = 0.0

func _ready() -> void:
	EventBus.building_damaged.connect(_on_building_damaged)
	var preset: Dictionary = DIFFICULTY_PRESETS.get(
		GameManager.ai_difficulty, DIFFICULTY_PRESETS["normal"])
	wave_interval = preset["wave"]
	max_military = preset["max"]
	archer_ratio = preset["archers"]
	builds = preset["builds"]
	trickle = preset["trickle"]
	wave_grace = preset["grace"]
	wave_size = preset["wave_size"]

func _process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.RUNNING:
		return
	_tick_accum += delta
	if _tick_accum < TICK_INTERVAL:
		return
	_tick_accum = 0.0
	_wave_accum += TICK_INTERVAL
	_scout_accum += TICK_INTERVAL
	_hunt_accum += TICK_INTERVAL
	_elapsed += TICK_INTERVAL
	_tick()

func _tick() -> void:
	if GameManager.world == null:
		return
	vision.update(get_tree(), GameManager.world)
	vision.changed_chunks.clear()  # only the fog renderer needs these

	for type: int in trickle:
		GameManager.add_resource(ENEMY_ID, type, trickle[type])

	var tc: Building = _own_town_center()
	if tc == null:
		return

	var warriors: Array[UnitBase] = _own_warriors()

	# The AI has no builders, so it raises its own sites at one-villager pace
	# — the same concession as its trickle economy.
	_advance_sites()
	if builds:
		_consider_building(tc)

	var barracks: Building = _own_constructed("barracks")
	var queued: int = tc.train_queue.size() \
		+ (barracks.train_queue.size() if barracks != null else 0)
	if warriors.size() + queued < max_military:
		var want_archer: bool = barracks != null \
			and PixelArt.hash2(int(_wave_accum), warriors.size(), 77) < archer_ratio
		var unit_type: String = "archer" if want_archer else "warrior"
		var trainer: Building = barracks if want_archer else tc
		if GameManager.can_afford(ENEMY_ID, Constants.UNIT_DEFS[unit_type]["cost"]):
			CommandRouter.submit({
				"type": "train", "player_id": ENEMY_ID,
				"building_name": String(trainer.name), "unit_type": unit_type,
			})

	# Opportunistic hunting for extra food, under the AI's own fog.
	_maybe_hunt(tc, warriors)

	var target: Node2D = _known_player_target(tc)

	if target == null:
		# Nothing discovered yet: sweep scouts through the compass directions.
		if _scout_accum >= scout_interval:
			_scout_accum = 0.0
			_send_scout(tc, warriors)
		return

	if _elapsed >= wave_grace and _wave_accum >= wave_interval:
		var idle: Array[UnitBase] = _idle_of(warriors)
		if idle.size() >= WAVE_MIN_WARRIORS:
			_wave_accum = 0.0
			CommandRouter.submit({
				"type": "attack", "player_id": ENEMY_ID,
				"actor_names": _names_of(idle.slice(0, wave_size)),
				"target_name": String(target.name),
			})

func _advance_sites() -> void:
	for node: Node in get_tree().get_nodes_in_group("player_%d" % ENEMY_ID):
		var site: Building = node as Building
		if site != null and not site.is_constructed:
			site.build_tick(Constants.BUILD_HP_PER_SWING * 2)

func _own_constructed(building_type: String) -> Building:
	for node: Node in get_tree().get_nodes_in_group("player_%d" % ENEMY_ID):
		var building: Building = node as Building
		if building != null and building.building_type == building_type \
				and building.is_constructed:
			return building
	return null

func _has_any(building_type: String) -> Building:
	for node: Node in get_tree().get_nodes_in_group("player_%d" % ENEMY_ID):
		var building: Building = node as Building
		if building != null and building.building_type == building_type:
			return building
	return null

# Economy goals, in priority order: a barracks, then houses whenever the
# army is near the cap, then one watchtower.
func _consider_building(tc: Building) -> void:
	var home: Vector2i = Constants.world_to_grid(tc.global_position)
	if _has_any("barracks") == null:
		_try_place("barracks", home)
		return
	if GameManager.get_population(ENEMY_ID) >= GameManager.population_cap(ENEMY_ID) - 1:
		_try_place("house", home)
		return
	if _has_any("watchtower") == null and GameManager.ai_difficulty == "hard":
		_try_place("watchtower", home)

func _try_place(building_type: String, origin: Vector2i) -> void:
	var def: Dictionary = Constants.BUILDING_DEFS[building_type]
	if not GameManager.can_afford(ENEMY_ID, def["cost"]):
		return
	var cell: Vector2i = GameManager.find_buildable_cell(origin, building_type, ENEMY_ID)
	if cell.x == 9999:
		return
	CommandRouter.submit({
		"type": "place", "player_id": ENEMY_ID, "building_type": building_type,
		"cell": cell, "actor_names": [],
	})

# Only targets this AI has legitimately discovered through its own vision.
func _known_player_target(tc: Building) -> Node2D:
	# Discovered player buildings (remembered once seen — they can't move).
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var building: Building = node as Building
		if building == null or building.player_id != GameManager.local_player_id:
			continue
		if vision.has_discovered_building(building):
			return building

	# Player units currently inside the AI's vision; nearest to home.
	var best: Node2D = null
	var best_dist: float = INF
	for node: Node in get_tree().get_nodes_in_group("player_%d" % GameManager.local_player_id):
		var unit: UnitBase = node as UnitBase
		if unit == null or not vision.can_see_entity(unit):
			continue
		var dist: float = unit.global_position.distance_to(tc.global_position)
		if dist < best_dist:
			best_dist = dist
			best = unit
	return best

func _send_scout(tc: Building, warriors: Array[UnitBase]) -> void:
	var idle: Array[UnitBase] = _idle_of(warriors)
	if idle.is_empty():
		return
	var home: Vector2i = Constants.world_to_grid(tc.global_position)
	var directions: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
		Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
	]
	var dir: Vector2i = directions[_scout_direction % directions.size()]
	_scout_direction += 1
	# Each completed compass round pushes the sweep farther out, so any base
	# is eventually found no matter the distance.
	if _scout_direction % directions.size() == 0:
		_scout_distance = mini(_scout_distance + SCOUT_DISTANCE_STEP, SCOUT_DISTANCE_MAX)
	var target_cell: Vector2i = home + dir * _scout_distance
	CommandRouter.submit({
		"type": "move", "player_id": ENEMY_ID,
		"actor_names": [String(idle[0].name)],
		"target": Constants.grid_to_world(target_cell.x, target_cell.y),
	})

# Send one idle warrior after an animal the AI can currently see near home.
func _maybe_hunt(tc: Building, warriors: Array[UnitBase]) -> void:
	if _hunt_accum < hunt_interval:
		return
	var animal: Node2D = _visible_animal_near(tc)
	if animal == null:
		return
	var idle: Array[UnitBase] = _idle_of(warriors)
	if idle.is_empty():
		return
	_hunt_accum = 0.0
	CommandRouter.submit({
		"type": "attack", "player_id": ENEMY_ID,
		"actor_names": [String(idle[0].name)], "target_name": String(animal.name),
	})

func _visible_animal_near(tc: Building) -> Node2D:
	var home: Vector2 = tc.global_position
	var best: Node2D = null
	var best_dist: float = float(HUNT_RANGE_TILES * Constants.TILE_WIDTH)
	for node: Node in get_tree().get_nodes_in_group("animals"):
		var animal: Node2D = node as Node2D
		if animal == null or not vision.can_see_entity(animal):
			continue
		var dist: float = animal.global_position.distance_to(home)
		if dist < best_dist:
			best_dist = dist
			best = animal
	return best

# Being attacked reveals the attacker: rally idle warriors to defend.
func _on_building_damaged(building: Node2D, attacker: Node2D) -> void:
	var mine: Building = building as Building
	if mine == null or mine.player_id != ENEMY_ID:
		return
	if attacker == null or not is_instance_valid(attacker):
		return
	var idle: Array[UnitBase] = _idle_of(_own_warriors())
	if idle.is_empty():
		return
	CommandRouter.submit({
		"type": "attack", "player_id": ENEMY_ID,
		"actor_names": _names_of(idle), "target_name": String(attacker.name),
	})

func _names_of(units: Array[UnitBase]) -> Array:
	return units.map(func(u: UnitBase) -> String: return String(u.name))

func _idle_of(warriors: Array[UnitBase]) -> Array[UnitBase]:
	var idle: Array[UnitBase] = []
	for warrior: UnitBase in warriors:
		if warrior.current_state == UnitBase.State.IDLE:
			idle.append(warrior)
	return idle

func _own_town_center() -> Building:
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var building: Building = node as Building
		if building != null and building.player_id == ENEMY_ID and building.building_type == "town_center":
			return building
	return null

func _own_warriors() -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for node: Node in get_tree().get_nodes_in_group("player_%d" % ENEMY_ID):
		var unit: UnitBase = node as UnitBase
		if unit != null and (unit.unit_type == "warrior" or unit.unit_type == "archer"):
			result.append(unit)
	return result
