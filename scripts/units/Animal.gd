# scripts/units/Animal.gd
class_name Animal
extends CharacterBody2D

# Neutral wildlife (see ADR 14). Prey wander and flee from any unit that comes
# close; predators wander and hunt the nearest unit of any player. Hunting is
# just the normal combat command against this body; on death the killer's player
# is paid a one-time food bounty. Animals live in the `animals` group only —
# deliberately NOT in `units`, so player/AI warriors don't auto-wander to hunt.

enum State { WANDER, FLEE, ATTACK }

const THINK_INTERVAL: float = 0.4
const REPATH_INTERVAL: float = 0.6
const WAYPOINT_REACHED_DISTANCE: float = 5.0
const WALK_FRAME_TIME: float = 0.16
const BODY_RADIUS: float = 9.0
const WANDER_RADIUS: int = 6      # tiles
const FLEE_DISTANCE: float = 240.0

var species: String = "capybara"
var player_id: int = Constants.ANIMAL_NEUTRAL_ID

var max_hp: int = 40
var current_hp: int = 40
var armor: int = 0
var move_speed: float = 52.0
var flee_speed: float = 130.0
var predator: bool = false
var flee_radius: float = 148.0
var aggro_radius: float = 0.0
var attack_power: int = 0
var attack_range: float = 0.0
var attack_cooldown: float = 1.1
var food_bounty: int = 100

var _state: State = State.WANDER
var _dead: bool = false

var _frames: Array = []
var _anim_time: float = 0.0

var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _repath_timer: float = 0.0
var _think_timer: float = 0.0
var _wander_cooldown: float = 0.0
var _cooldown_left: float = 0.0

var _target: Node2D = null   # predator's prey
var _threat: Node2D = null   # what a prey animal is fleeing

var _sprite: Sprite2D
var _shadow: Sprite2D
var _health_bar: ProgressBar

# Called before the node enters the tree.
func setup(p_species: String) -> void:
	species = p_species
	var def: Dictionary = Constants.ANIMAL_DEFS[species]
	max_hp = def["max_hp"]
	current_hp = max_hp
	armor = def["armor"]
	move_speed = def["move_speed"]
	flee_speed = def["flee_speed"]
	predator = def["predator"]
	flee_radius = def.get("flee_radius", 0.0)
	aggro_radius = def.get("aggro_radius", 0.0)
	attack_power = def.get("attack_power", 0)
	attack_range = def.get("attack_range", 0.0)
	attack_cooldown = def.get("attack_cooldown", 1.1)
	food_bounty = def["food"]

func _ready() -> void:
	add_to_group("animals")
	_frames = AssetLibrary.get_animal_frames(species)

	_shadow = Sprite2D.new()
	_shadow.texture = AssetLibrary.unit_shadow
	add_child(_shadow)

	_sprite = Sprite2D.new()
	_sprite.texture = _frames[0]
	_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0 + 1.0)
	add_child(_sprite)

	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.max_value = max_hp
	_health_bar.value = current_hp
	_health_bar.size = Vector2(28, 4)
	_health_bar.position = Vector2(-14, -_sprite.texture.get_height() - 2.0)
	_health_bar.add_theme_stylebox_override("background", AssetLibrary.health_bar_bg)
	_health_bar.add_theme_stylebox_override("fill", AssetLibrary.health_bar_fill)
	_health_bar.visible = false
	add_child(_health_bar)

	# Stagger thinking/wandering so a herd doesn't move in lockstep.
	_think_timer = randf() * THINK_INTERVAL
	_wander_cooldown = randf() * 2.0

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = THINK_INTERVAL
		_think()

	match _state:
		State.WANDER:
			_do_wander(delta)
		State.FLEE:
			_do_flee(delta)
		State.ATTACK:
			_do_attack(delta)

# --- Decision ---

func _think() -> void:
	if GameManager.world == null:
		return
	if predator:
		var prey: Node2D = _nearest_unit(aggro_radius)
		if prey != null:
			_target = prey
			if _state != State.ATTACK:
				_enter_attack()
	else:
		var threat: Node2D = _nearest_unit(flee_radius)
		if threat != null:
			_threat = threat
			if _state != State.FLEE:
				_state = State.FLEE
				_pick_flee_target()
		elif _state == State.FLEE:
			_state = State.WANDER
			_path = PackedVector2Array()

func _nearest_unit(radius: float) -> Node2D:
	if radius <= 0.0:
		return null
	var best: Node2D = null
	var best_dist: float = radius
	for node: Node in get_tree().get_nodes_in_group("units"):
		var unit: Node2D = node as Node2D
		if unit == null:
			continue
		var dist: float = unit.global_position.distance_to(global_position)
		if dist < best_dist:
			best_dist = dist
			best = unit
	return best

# --- Wander ---

func _do_wander(delta: float) -> void:
	if _path_index >= _path.size():
		velocity = Vector2.ZERO
		_set_idle_frame()
		_wander_cooldown -= delta
		if _wander_cooldown <= 0.0:
			_wander_cooldown = 1.5 + randf() * 2.5
			_pick_wander_target()
		return
	_follow_path(delta, move_speed)

func _pick_wander_target() -> void:
	var here: Vector2i = Constants.world_to_grid(global_position)
	for _attempt in range(6):
		var cell: Vector2i = here + Vector2i(
			randi_range(-WANDER_RADIUS, WANDER_RADIUS),
			randi_range(-WANDER_RADIUS, WANDER_RADIUS))
		if GameManager.world.is_walkable(cell) and _start_path_to(Constants.grid_to_world(cell.x, cell.y)):
			return

# --- Flee ---

func _do_flee(delta: float) -> void:
	if _threat == null or not is_instance_valid(_threat):
		_state = State.WANDER
		return
	_repath_timer -= delta
	if _path_index >= _path.size() or _repath_timer <= 0.0:
		_repath_timer = REPATH_INTERVAL
		_pick_flee_target()
	if _path_index < _path.size():
		_follow_path(delta, flee_speed)
	else:
		# No route away — sprint directly away from the threat.
		var away: Vector2 = (global_position - _threat.global_position).normalized()
		velocity = away * flee_speed / _terrain_cost()
		move_and_slide()
		if absf(away.x) > 0.1:
			_sprite.flip_h = away.x < 0.0
		_animate(delta)

func _pick_flee_target() -> void:
	if _threat == null or not is_instance_valid(_threat):
		return
	var away: Vector2 = (global_position - _threat.global_position).normalized()
	var dest: Vector2i = Constants.world_to_grid(global_position + away * FLEE_DISTANCE)
	for radius in range(0, 4):
		for _attempt in range(4):
			var cell: Vector2i = dest + Vector2i(randi_range(-radius, radius), randi_range(-radius, radius))
			if GameManager.world.is_walkable(cell) and _start_path_to(Constants.grid_to_world(cell.x, cell.y)):
				return

# --- Attack (predators) ---

func _enter_attack() -> void:
	_state = State.ATTACK
	if _target != null and not _in_attack_range(_target):
		_start_path_to(_target.global_position)

func _do_attack(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = null
		_state = State.WANDER
		return
	if not _in_attack_range(_target):
		_repath_timer -= delta
		if _path_index >= _path.size() or _repath_timer <= 0.0:
			_repath_timer = REPATH_INTERVAL
			_start_path_to(_target.global_position)
		if _path_index < _path.size():
			_follow_path(delta, move_speed)
		return
	velocity = Vector2.ZERO
	_set_idle_frame()
	_sprite.flip_h = _target.global_position.x < global_position.x
	if _cooldown_left <= 0.0:
		_cooldown_left = attack_cooldown
		_strike(_target)

func _strike(target: Node2D) -> void:
	var toward: Vector2 = (target.global_position - global_position).normalized() * 4.0
	var tween: Tween = create_tween()
	tween.tween_property(_sprite, "position", toward, 0.08)
	tween.tween_property(_sprite, "position", Vector2.ZERO, 0.10)
	if target.has_method("take_damage"):
		target.take_damage(attack_power, self)

func _in_attack_range(target: Node2D) -> bool:
	var target_radius: float = BODY_RADIUS
	if target.has_method("body_radius"):
		target_radius = target.body_radius()
	return global_position.distance_to(target.global_position) <= attack_range + target_radius

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

func _follow_path(delta: float, speed: float) -> void:
	if _path_index >= _path.size():
		velocity = Vector2.ZERO
		_set_idle_frame()
		return
	var target: Vector2 = _path[_path_index]
	var to_target: Vector2 = target - global_position
	if to_target.length() <= WAYPOINT_REACHED_DISTANCE:
		_path_index += 1
		return
	var direction: Vector2 = to_target.normalized()
	velocity = direction * speed / _terrain_cost()
	move_and_slide()
	if absf(direction.x) > 0.1:
		_sprite.flip_h = direction.x < 0.0
	_animate(delta)

func _animate(delta: float) -> void:
	_anim_time += delta
	var frame: int = 1 + (int(_anim_time / WALK_FRAME_TIME) % 2)
	_sprite.texture = _frames[frame]

func _set_idle_frame() -> void:
	if _sprite.texture != _frames[0]:
		_sprite.texture = _frames[0]

func _terrain_cost() -> float:
	if GameManager.world == null:
		return 1.0
	var cost: float = GameManager.world.movement_cost(Constants.world_to_grid(global_position))
	if is_inf(cost) or cost <= 0.0:
		return 1.0
	return cost

# --- Combat interface ---

func body_radius() -> float:
	return BODY_RADIUS

func take_damage(amount: int, attacker: Node2D = null) -> void:
	if _dead:
		return
	var actual: int = maxi(1, amount - armor)
	current_hp = maxi(0, current_hp - actual)
	_health_bar.value = current_hp
	_health_bar.visible = current_hp < max_hp
	_flash()

	if current_hp <= 0:
		_die(attacker)
		return

	# Being struck: prey bolts from the attacker; a predator turns to fight it.
	if attacker != null and is_instance_valid(attacker):
		if predator:
			if _state != State.ATTACK:
				_target = attacker
				_enter_attack()
		else:
			_threat = attacker
			_state = State.FLEE
			_pick_flee_target()

func _flash() -> void:
	_sprite.modulate = Color(1.6, 1.2, 1.2)
	var tween: Tween = create_tween()
	tween.tween_property(_sprite, "modulate", Color.WHITE, 0.18)

func _die(killer: Node2D) -> void:
	_dead = true
	velocity = Vector2.ZERO
	_health_bar.visible = false

	if killer != null and is_instance_valid(killer):
		var pid: Variant = killer.get("player_id")
		if pid != null and int(pid) >= 0:
			GameManager.add_resource(int(pid), Constants.ResourceType.FOOD, food_bounty)
			EventBus.animal_hunted.emit(self, killer, food_bounty)
			if int(pid) == GameManager.local_player_id:
				_spawn_food_popup(food_bounty)

	EventBus.animal_died.emit(self)

	# Brief death fade, then remove.
	var tween: Tween = create_tween()
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.22)
	tween.parallel().tween_property(_sprite, "scale", Vector2(0.7, 0.7), 0.22)
	tween.tween_callback(queue_free)

func _spawn_food_popup(amount: int) -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var label: Label = Label.new()
	label.text = "+%d food" % amount
	label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.5))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", 13)
	label.z_index = 200
	parent.add_child(label)
	label.global_position = global_position + Vector2(-18.0, -34.0)
	var tween: Tween = label.create_tween()
	tween.tween_property(label, "global_position", label.global_position + Vector2(0.0, -22.0), 0.9)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9)
	tween.tween_callback(label.queue_free)
