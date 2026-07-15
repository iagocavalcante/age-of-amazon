# scripts/units/Unit.gd
class_name UnitBase
extends CharacterBody2D

# State machine:
#   IDLE       — stands, auto-acquires enemies if aggressive
#   MOVING     — follows a path; on arrival resolves `_intent`
#   GATHERING  — works a resource node on a timer
#   ATTACKING  — strikes a target in range on a cooldown
#
# `_intent` describes what MOVING should do on arrival:
#   {} | {kind:"gather", cell} | {kind:"deposit"} | {kind:"attack", target}
#      | {kind:"build"}
enum State { IDLE, MOVING, GATHERING, ATTACKING, BUILDING }

const WAYPOINT_REACHED_DISTANCE: float = 4.0
const WALK_FRAME_TIME: float = 0.18
const AGGRO_SCAN_INTERVAL: float = 0.6
const REPATH_INTERVAL: float = 0.5
const BODY_RADIUS: float = 10.0

@export var unit_type: String = "villager"
@export var player_id: int = 0

var unit_name: String = "Unit"
var max_hp: int = 40
var current_hp: int = 40
var move_speed: float = 100.0
var attack_power: int = 2
var armor: int = 0
var attack_range: float = 26.0
var attack_cooldown: float = 1.0
var vision_range: float = 200.0
var aggressive: bool = false
var can_gather: bool = false

var current_state: State = State.IDLE
var is_selected: bool = false

# Path following
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0

# Task intent
var _intent: Dictionary = {}

# Construction
var _build_site: Building = null
var _build_timer: float = 0.0

# Gathering
var _gather_cell: Vector2i = Vector2i.ZERO
var _gather_type: int = -1
var _carrying: int = 0
var _gather_timer: float = 0.0

# Combat
var _attack_target: Node2D = null
var _cooldown_left: float = 0.0
var _repath_timer: float = 0.0
var _aggro_timer: float = 0.0

# Animation
var _frames: Array = []
var _anim_time: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: Sprite2D = $Shadow
@onready var selection_ring: Sprite2D = $SelectionRing
@onready var health_bar: ProgressBar = $HealthBar

func _ready() -> void:
	var def: Dictionary = Constants.UNIT_DEFS[unit_type]
	unit_name = unit_type.capitalize()
	max_hp = def["max_hp"]
	current_hp = max_hp
	move_speed = def["move_speed"]
	attack_power = def["attack_power"]
	armor = def["armor"]
	attack_range = def["attack_range"]
	attack_cooldown = def["attack_cooldown"]
	vision_range = def["vision_range"]
	aggressive = def["aggressive"]
	can_gather = def["can_gather"]

	add_to_group("units")
	add_to_group("player_%d" % player_id)

	# Presentation lives client-side only; the headless server never touches
	# textures, styleboxes, or the AssetLibrary.
	if not Net.is_headless_server():
		_frames = AssetLibrary.get_unit_frames(player_id, unit_type)
		sprite.texture = _frames[0]
		sprite.offset = Vector2(0, -sprite.texture.get_height() / 2.0 + 1.0)
		shadow.texture = AssetLibrary.unit_shadow
		selection_ring.texture = AssetLibrary.selection_ring
		selection_ring.visible = false

		health_bar.max_value = max_hp
		health_bar.value = current_hp
		health_bar.add_theme_stylebox_override("background", AssetLibrary.health_bar_bg)
		health_bar.add_theme_stylebox_override("fill", AssetLibrary.health_bar_fill)
		_update_health_bar()

	EventBus.population_changed.emit(player_id)
	EventBus.entity_spawned.emit(self)

func _physics_process(delta: float) -> void:
	if Net.is_authority():
		_sim_step(delta)
	elif Net.mode == Net.Mode.CLIENT:
		_net_step(delta)
	if not Net.is_headless_server():
		_view_step(delta)

# Simulation: runs only where authority lives (offline client / match server).
func _sim_step(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)

	match current_state:
		State.IDLE:
			velocity = Vector2.ZERO
			if aggressive:
				_aggro_timer -= delta
				if _aggro_timer <= 0.0:
					_aggro_timer = AGGRO_SCAN_INTERVAL
					var enemy: Node2D = _find_enemy_in_range(vision_range)
					if enemy != null:
						command_attack(enemy)
		State.MOVING:
			if _follow_path(delta):
				_on_arrival()
		State.GATHERING:
			velocity = Vector2.ZERO
			_process_gathering(delta)
		State.ATTACKING:
			_process_attacking(delta)
		State.BUILDING:
			velocity = Vector2.ZERO
			_process_building(delta)

# Multiplayer client: the unit is a puppet — the server's 10 Hz state ticks
# land in net_apply(), and _net_step eases the rendered position toward the
# latest snapshot so movement looks continuous between ticks.

const NET_SNAP_DISTANCE: float = 96.0
const NET_LERP_RATE: float = 12.0

var _net_pos: Vector2 = Vector2.ZERO

func net_snap(world_pos: Vector2) -> void:
	_net_pos = world_pos
	global_position = world_pos

func net_apply(world_pos: Vector2, net_velocity: Vector2, hp: int, state: int) -> void:
	_net_pos = world_pos
	velocity = net_velocity
	current_state = state as State
	if hp != current_hp:
		current_hp = hp
		_update_health_bar()
	if global_position.distance_to(_net_pos) > NET_SNAP_DISTANCE:
		global_position = _net_pos

func _net_step(delta: float) -> void:
	global_position = global_position.lerp(_net_pos, minf(1.0, delta * NET_LERP_RATE))

# Presentation: derives animation purely from replicable state (velocity,
# current_state), so a multiplayer client renders correctly from sync alone.
func _view_step(delta: float) -> void:
	if velocity.length() > 1.0:
		if absf(velocity.x) > 0.1:
			sprite.flip_h = velocity.x < 0.0
		_anim_time += delta
		var frame: int = 1 + (int(_anim_time / WALK_FRAME_TIME) % 2)
		sprite.texture = _frames[frame]
		return
	if current_state == State.ATTACKING \
			and _attack_target != null and is_instance_valid(_attack_target):
		sprite.flip_h = _attack_target.global_position.x < global_position.x
	_set_idle_frame()

# --- Commands (issued by SelectionManager / AI) ---

func move_to(target: Vector2) -> void:
	_intent = {}
	_attack_target = null
	if _start_path_to(target):
		current_state = State.MOVING
	else:
		current_state = State.IDLE

func command_gather(cell: Vector2i) -> void:
	if not can_gather:
		move_to(Constants.grid_to_world(cell.x, cell.y))
		return
	var node: Dictionary = GameManager.world.get_resource_at(cell)
	if node.is_empty():
		return
	_gather_cell = cell
	_gather_type = node["type"]
	_attack_target = null
	_go_to_gather_site()

func command_attack(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_attack_target = target
	_intent = { "kind": "attack" }
	if _in_attack_range(target):
		current_state = State.ATTACKING
	elif _start_path_to(target.global_position):
		current_state = State.MOVING
	else:
		current_state = State.IDLE

# Walk to a construction site and hammer it up. Villagers only.
func command_build(site: Building) -> void:
	if not can_gather or site == null or not is_instance_valid(site):
		return
	if site.current_hp >= site.max_hp:
		return  # nothing to build or repair
	_build_site = site
	_attack_target = null
	var spot: Dictionary = GameManager.pathfinder.adjacent_walkable(
		site.footprint_cells, Constants.world_to_grid(global_position))
	if not spot["found"]:
		current_state = State.IDLE
		return
	_intent = { "kind": "build" }
	var cell: Vector2i = spot["cell"]
	if _start_path_to(Constants.grid_to_world(cell.x, cell.y)):
		current_state = State.MOVING
	else:
		current_state = State.IDLE

func _process_building(delta: float) -> void:
	if _build_site == null or not is_instance_valid(_build_site) \
			or _build_site.current_hp >= _build_site.max_hp:
		_build_site = null
		current_state = State.IDLE
		return
	_build_timer += delta
	if _build_timer < Constants.BUILD_INTERVAL:
		return
	_build_timer = 0.0
	_build_site.build_tick(Constants.BUILD_HP_PER_SWING)

# --- Movement ---

func _start_path_to(target: Vector2) -> bool:
	if GameManager.pathfinder == null:
		return false
	var path: PackedVector2Array = GameManager.pathfinder.find_path_world(global_position, target)
	if path.is_empty():
		return false
	_path = path
	_path_index = 0
	return true

# Returns true when the path is finished. Pure simulation — animation is
# derived from `velocity` in _view_step.
func _follow_path(_delta: float) -> bool:
	if _path_index >= _path.size():
		velocity = Vector2.ZERO
		return true

	var target: Vector2 = _path[_path_index]
	var to_target: Vector2 = target - global_position
	if to_target.length() <= WAYPOINT_REACHED_DISTANCE:
		_path_index += 1
		if _path_index >= _path.size():
			velocity = Vector2.ZERO
			return true
		return false

	var direction: Vector2 = to_target.normalized()
	velocity = direction * move_speed / _terrain_cost()
	move_and_slide()
	return false

func _terrain_cost() -> float:
	if GameManager.world == null:
		return 1.0
	var cost: float = GameManager.world.movement_cost(Constants.world_to_grid(global_position))
	if is_inf(cost) or cost <= 0.0:
		return 1.0
	return cost

func _on_arrival() -> void:
	match _intent.get("kind", ""):
		"gather":
			if GameManager.world.get_resource_at(_gather_cell).is_empty():
				_find_next_resource_node()
			else:
				current_state = State.GATHERING
				_gather_timer = 0.0
		"deposit":
			_deposit()
		"build":
			if _build_site != null and is_instance_valid(_build_site) \
					and _build_site.current_hp < _build_site.max_hp:
				current_state = State.BUILDING
				_build_timer = 0.0
			else:
				current_state = State.IDLE
		"attack":
			if _attack_target != null and is_instance_valid(_attack_target):
				if _in_attack_range(_attack_target):
					current_state = State.ATTACKING
				else:
					# Target moved while we walked; chase again.
					command_attack(_attack_target)
			else:
				current_state = State.IDLE
		_:
			current_state = State.IDLE

# --- Gathering ---

func _go_to_gather_site() -> void:
	var spot: Dictionary = GameManager.pathfinder.adjacent_walkable([_gather_cell], Constants.world_to_grid(global_position))
	if not spot["found"]:
		current_state = State.IDLE
		return
	_intent = { "kind": "gather" }
	var cell: Vector2i = spot["cell"]
	if _start_path_to(Constants.grid_to_world(cell.x, cell.y)):
		current_state = State.MOVING
	else:
		current_state = State.IDLE

func _process_gathering(delta: float) -> void:
	_gather_timer += delta
	if _gather_timer < Constants.GATHER_INTERVAL:
		return
	_gather_timer = 0.0

	var taken: int = GameManager.world.take_resource(_gather_cell, 1)
	if taken > 0:
		_carrying += taken

	var node_gone: bool = GameManager.world.get_resource_at(_gather_cell).is_empty()
	if _carrying >= Constants.CARRY_CAPACITY or (node_gone and _carrying > 0):
		_go_deposit()
	elif node_gone:
		_find_next_resource_node()

func _go_deposit() -> void:
	var tc: Node2D = _nearest_own_town_center()
	if tc == null:
		current_state = State.IDLE
		return
	var spot: Dictionary = GameManager.pathfinder.adjacent_walkable(tc.footprint_cells, Constants.world_to_grid(global_position))
	if not spot["found"]:
		current_state = State.IDLE
		return
	_intent = { "kind": "deposit" }
	var cell: Vector2i = spot["cell"]
	if _start_path_to(Constants.grid_to_world(cell.x, cell.y)):
		current_state = State.MOVING
	else:
		current_state = State.IDLE

func _deposit() -> void:
	if _carrying > 0 and _gather_type >= 0:
		GameManager.add_resource(player_id, _gather_type, _carrying)
		_carrying = 0
	# Resume the cycle: same node if alive, otherwise a nearby one.
	if not GameManager.world.get_resource_at(_gather_cell).is_empty():
		_go_to_gather_site()
	else:
		_find_next_resource_node()

func _find_next_resource_node() -> void:
	if _gather_type < 0:
		current_state = State.IDLE
		return
	var result: Dictionary = GameManager.world.find_nearest_resource(_gather_cell, _gather_type)
	# Only auto-retarget nodes this tribe has scouted — no gathering in fog.
	if result["found"] and GameManager.has_explored(player_id, result["cell"]):
		_gather_cell = result["cell"]
		_go_to_gather_site()
	else:
		current_state = State.IDLE

func _nearest_own_town_center() -> Node2D:
	var best: Node2D = null
	var best_dist: float = INF
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var building: Node2D = node as Node2D
		if building == null or building.get("player_id") != player_id:
			continue
		if building.get("building_type") != "town_center":
			continue
		var dist: float = building.global_position.distance_to(global_position)
		if dist < best_dist:
			best_dist = dist
			best = building
	return best

# --- Combat ---

func _process_attacking(delta: float) -> void:
	if _attack_target == null or not is_instance_valid(_attack_target):
		_attack_target = null
		current_state = State.IDLE
		return

	if not _in_attack_range(_attack_target):
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath_timer = REPATH_INTERVAL
			command_attack(_attack_target)
		return

	velocity = Vector2.ZERO

	if _cooldown_left <= 0.0:
		_cooldown_left = attack_cooldown
		_strike(_attack_target)

func _strike(target: Node2D) -> void:
	if not Net.is_headless_server():
		# Lunge toward the victim for readability.
		var toward: Vector2 = (target.global_position - global_position).normalized() * 4.0
		var tween: Tween = create_tween()
		tween.tween_property(sprite, "position", Vector2(toward), 0.08)
		tween.tween_property(sprite, "position", Vector2.ZERO, 0.10)

	if target.has_method("take_damage"):
		target.take_damage(attack_power, self)

func _in_attack_range(target: Node2D) -> bool:
	var target_radius: float = BODY_RADIUS
	if target.has_method("body_radius"):
		target_radius = target.body_radius()
	return global_position.distance_to(target.global_position) <= attack_range + target_radius

func _find_enemy_in_range(radius: float) -> Node2D:
	var best: Node2D = null
	var best_dist: float = INF
	for group: String in ["units", "buildings"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var other: Node2D = node as Node2D
			if other == null or other == self:
				continue
			if other.get("player_id") == player_id:
				continue
			var dist: float = other.global_position.distance_to(global_position)
			if dist <= radius and dist < best_dist:
				best_dist = dist
				best = other
	return best

func take_damage(amount: int, attacker: Node2D = null) -> void:
	var actual: int = maxi(1, amount - armor)
	current_hp = maxi(0, current_hp - actual)
	_update_health_bar()
	_flash_hit()

	if current_hp <= 0:
		_die()
		return

	# Retaliate if not already busy fighting.
	if attacker != null and is_instance_valid(attacker) and current_state != State.ATTACKING:
		if aggressive or current_state == State.IDLE:
			command_attack(attacker)

func _flash_hit() -> void:
	if Net.is_headless_server():
		return
	sprite.modulate = Color(1.6, 1.2, 1.2)
	var tween: Tween = create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.18)

func _die() -> void:
	EventBus.unit_died.emit(self)
	EventBus.population_changed.emit(player_id)
	queue_free()

# --- Selection / misc ---

func body_radius() -> float:
	return BODY_RADIUS

func select() -> void:
	is_selected = true
	selection_ring.visible = true
	_update_health_bar()
	EventBus.unit_selected.emit(self)

func deselect() -> void:
	is_selected = false
	selection_ring.visible = false
	_update_health_bar()
	EventBus.unit_deselected.emit(self)

func _update_health_bar() -> void:
	if Net.is_headless_server():
		return
	health_bar.value = current_hp
	health_bar.visible = is_selected or current_hp < max_hp

func _set_idle_frame() -> void:
	if sprite.texture != _frames[0]:
		sprite.texture = _frames[0]
