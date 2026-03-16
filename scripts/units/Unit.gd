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

# Selection
var is_selected: bool = false

# Node references
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var selection_indicator: Sprite2D = $SelectionIndicator
@onready var health_bar: ProgressBar = $HealthBar

# Colors per player
const PLAYER_COLORS: Array[Color] = [
	Color(0.2, 0.6, 1.0),  # Player 0: Blue
	Color(1.0, 0.3, 0.3),  # Player 1: Red
]

func _ready() -> void:
	add_to_group("units")
	add_to_group("player_%d" % player_id)

	nav_agent.path_desired_distance = 8.0
	nav_agent.target_desired_distance = 8.0
	nav_agent.velocity_computed.connect(_on_velocity_computed)

	sprite.texture = PlaceholderTextures.unit_texture
	selection_indicator.texture = PlaceholderTextures.selection_circle
	_update_color()
	selection_indicator.visible = false
	health_bar.visible = false
	health_bar.max_value = max_hp
	health_bar.value = current_hp

func _physics_process(_delta: float) -> void:
	match current_state:
		State.IDLE:
			pass
		State.MOVING:
			_process_movement()

func _process_movement() -> void:
	if nav_agent.is_navigation_finished():
		current_state = State.IDLE
		return

	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()
	nav_agent.velocity = direction * move_speed

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()

func move_to(target: Vector2) -> void:
	nav_agent.target_position = target
	current_state = State.MOVING

func select() -> void:
	is_selected = true
	selection_indicator.visible = true
	health_bar.visible = true
	EventBus.unit_selected.emit(self)

func deselect() -> void:
	is_selected = false
	selection_indicator.visible = false
	health_bar.visible = false
	EventBus.unit_deselected.emit(self)

func take_damage(amount: int) -> void:
	var actual := maxi(0, amount - armor)
	current_hp = maxi(0, current_hp - actual)
	health_bar.value = current_hp
	if current_hp <= 0:
		_die()

func _die() -> void:
	queue_free()

func _update_color() -> void:
	if player_id < PLAYER_COLORS.size():
		sprite.modulate = PLAYER_COLORS[player_id]
