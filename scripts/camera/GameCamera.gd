# scripts/camera/GameCamera.gd
extends Camera2D

# Pan
@export var pan_speed: float = 600.0
@export var edge_scroll_margin: int = 30
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var camera_drag_start: Vector2 = Vector2.ZERO

# Zoom
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.3
@export var max_zoom: float = 2.0
var target_zoom: float = 0.7

# Pinch zoom
var touch_points: Dictionary = {}
var pinch_start_distance: float = 0.0
var pinch_start_zoom: float = 0.0

# Bounds
var map_bounds: Rect2 = Rect2(-5000, -5000, 10000, 10000)

# Mobile detection
var is_mobile: bool = false

func _ready() -> void:
	zoom = Vector2(target_zoom, target_zoom)
	is_mobile = OS.has_feature("mobile")
	EventBus.map_generated.connect(_on_map_generated)

func _on_map_generated(w: int, _h: int) -> void:
	var half_w := w * 64.0 / 2.0
	var total_h := w * 32.0
	map_bounds = Rect2(-half_w - 200, -200, half_w * 2.0 + 400, total_h + 400)

func _process(delta: float) -> void:
	var direction := Vector2.ZERO

	if Input.is_action_pressed("ui_up"):
		direction.y -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_right"):
		direction.x += 1

	# Edge scrolling (desktop only)
	if not is_mobile and not is_dragging:
		var mouse := get_viewport().get_mouse_position()
		var vp_size := get_viewport_rect().size

		if mouse.x < edge_scroll_margin:
			direction.x -= 1
		elif mouse.x > vp_size.x - edge_scroll_margin:
			direction.x += 1
		if mouse.y < edge_scroll_margin:
			direction.y -= 1
		elif mouse.y > vp_size.y - edge_scroll_margin:
			direction.y += 1

	if direction != Vector2.ZERO:
		position += direction.normalized() * pan_speed * delta / zoom.x

	# Smooth zoom
	zoom = zoom.lerp(Vector2(target_zoom, target_zoom), 10.0 * delta)

	# Clamp to bounds
	position.x = clampf(position.x, map_bounds.position.x, map_bounds.end.x)
	position.y = clampf(position.y, map_bounds.position.y, map_bounds.end.y)

func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_zoom = clampf(target_zoom + zoom_speed, min_zoom, max_zoom)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				target_zoom = clampf(target_zoom - zoom_speed, min_zoom, max_zoom)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_MIDDLE:
				is_dragging = true
				drag_start = mb.position
				camera_drag_start = position
				get_viewport().set_input_as_handled()
		else:
			if mb.button_index == MOUSE_BUTTON_MIDDLE:
				is_dragging = false

	# Mouse drag pan (middle button)
	if event is InputEventMouseMotion and is_dragging:
		var mm := event as InputEventMouseMotion
		position = camera_drag_start + (drag_start - mm.position) / zoom.x
		get_viewport().set_input_as_handled()

	# Touch events for mobile
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			touch_points[st.index] = st.position
			if touch_points.size() == 2:
				_start_pinch()
		else:
			touch_points.erase(st.index)

	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		touch_points[sd.index] = sd.position

		if touch_points.size() == 1:
			position -= sd.relative / zoom.x
		elif touch_points.size() == 2:
			_handle_pinch()

func _start_pinch() -> void:
	var points := touch_points.values()
	pinch_start_distance = (points[0] as Vector2).distance_to(points[1] as Vector2)
	pinch_start_zoom = target_zoom

func _handle_pinch() -> void:
	var points := touch_points.values()
	var current_distance := (points[0] as Vector2).distance_to(points[1] as Vector2)

	if pinch_start_distance > 0:
		var scale_factor := current_distance / pinch_start_distance
		target_zoom = clampf(pinch_start_zoom * scale_factor, min_zoom, max_zoom)

func center_on(world_pos: Vector2) -> void:
	position = world_pos
