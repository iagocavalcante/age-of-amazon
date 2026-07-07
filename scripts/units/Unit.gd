# scripts/units/Unit.gd
class_name UnitBase
extends CharacterBody2D

# State machine
enum State { IDLE, MOVING, ATTACKING, GATHERING, BUILDING }
var current_state: State = State.IDLE

# Stats
@export var unit_name: String = "Unit"
@export var max_hp: int = 40
@export var current_hp: int = 40
@export var move_speed: float = 100.0
@export var attack_power: int = 3
@export var armor: int = 0
@export var attack_range: float = 32.0
@export var vision_range: float = 128.0
@export var player_id: int = 0

const WAYPOINT_REACHED_DISTANCE: float = 4.0
const WALK_FRAME_TIME: float = 0.18

# Selection
var is_selected: bool = false

# Path following (grid A*; see Pathfinder)
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0

# Walk animation
var _frames: Array = []
var _anim_time: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: Sprite2D = $Shadow
@onready var selection_ring: Sprite2D = $SelectionRing
@onready var health_bar: ProgressBar = $HealthBar

func _ready() -> void:
	add_to_group("units")
	add_to_group("player_%d" % player_id)

	_frames = AssetLibrary.get_villager_frames(player_id)
	sprite.texture = _frames[0]
	# Anchor the sprite at the feet so y-sort works against doodads.
	sprite.offset = Vector2(0, -sprite.texture.get_height() / 2.0 + 1.0)
	shadow.texture = AssetLibrary.unit_shadow
	selection_ring.texture = AssetLibrary.selection_ring
	selection_ring.visible = false

	health_bar.visible = false
	health_bar.max_value = max_hp
	health_bar.value = current_hp
	health_bar.add_theme_stylebox_override("background", AssetLibrary.health_bar_bg)
	health_bar.add_theme_stylebox_override("fill", AssetLibrary.health_bar_fill)

func _physics_process(delta: float) -> void:
	match current_state:
		State.MOVING:
			_process_movement(delta)
		_:
			if sprite.texture != _frames[0]:
				sprite.texture = _frames[0]

func _process_movement(delta: float) -> void:
	if _path_index >= _path.size():
		_stop_moving()
		return

	var target: Vector2 = _path[_path_index]
	var to_target: Vector2 = target - global_position

	if to_target.length() <= WAYPOINT_REACHED_DISTANCE:
		_path_index += 1
		return

	var direction: Vector2 = to_target.normalized()
	velocity = direction * move_speed / _terrain_cost()
	move_and_slide()

	if absf(direction.x) > 0.1:
		sprite.flip_h = direction.x < 0.0

	_anim_time += delta
	var frame: int = 1 + (int(_anim_time / WALK_FRAME_TIME) % 2)
	sprite.texture = _frames[frame]

func _terrain_cost() -> float:
	if GameManager.map_generator == null:
		return 1.0
	var cell: Vector2i = Constants.world_to_grid(global_position)
	var cost: float = GameManager.map_generator.get_movement_cost(cell.x, cell.y)
	if is_inf(cost) or cost <= 0.0:
		return 1.0
	return cost

func _stop_moving() -> void:
	current_state = State.IDLE
	velocity = Vector2.ZERO
	_anim_time = 0.0
	sprite.texture = _frames[0]

func move_to(target: Vector2) -> void:
	if GameManager.pathfinder == null:
		return
	var path: PackedVector2Array = GameManager.pathfinder.find_path_world(global_position, target)
	if path.is_empty():
		return
	_path = path
	_path_index = 0
	current_state = State.MOVING

func select() -> void:
	is_selected = true
	selection_ring.visible = true
	health_bar.visible = true
	EventBus.unit_selected.emit(self)

func deselect() -> void:
	is_selected = false
	selection_ring.visible = false
	health_bar.visible = false
	EventBus.unit_deselected.emit(self)

func take_damage(amount: int) -> void:
	var actual: int = maxi(0, amount - armor)
	current_hp = maxi(0, current_hp - actual)
	health_bar.value = current_hp
	if current_hp <= 0:
		_die()

func _die() -> void:
	queue_free()
