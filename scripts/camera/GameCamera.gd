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

# Edge scrolling stays off until the mouse actually moves, otherwise the
# camera drifts toward (0,0) from the moment the game launches.
var _mouse_seen: bool = false

func _ready() -> void:
	zoom = Vector2(target_zoom, target_zoom)
	is_mobile = OS.has_feature("mobile")
	EventBus.map_generated.connect(_on_map_generated)

func _on_map_generated(w: int, h: int) -> void:
	# Isometric extents: x spans [-(h*TW/2), w*TW/2], y spans [0, (w+h)*TH/2].
	var left: float = -h * Constants.TILE_WIDTH / 2.0
	var right: float = w * Constants.TILE_WIDTH / 2.0
	var bottom: float = (w + h) * Constants.TILE_HEIGHT / 2.0
	var margin: float = 200.0
	map_bounds = Rect2(
		left - margin, -margin,
		(right - left) + margin * 2.0, bottom + margin * 2.0
	)

func _process(delta: float) -> void:
	var direction: Vector2 = Vector2.ZERO
	direction.x = Input.get_axis("camera_left", "camera_right")
	direction.y = Input.get_axis("camera_up", "camera_down")

	# Edge scrolling (desktop only)
	if _edge_scroll_active():
		var mouse: Vector2 = get_viewport().get_mouse_position()
		var vp_size: Vector2 = get_viewport_rect().size

		if mouse.x < edge_scroll_margin:
			direction.x -= 1.0
		elif mouse.x > vp_size.x - edge_scroll_margin:
			direction.x += 1.0
		if mouse.y < edge_scroll_margin:
			direction.y -= 1.0
		elif mouse.y > vp_size.y - edge_scroll_margin:
			direction.y += 1.0

	if direction != Vector2.ZERO:
		position += direction.limit_length(1.0) * pan_speed * delta / zoom.x

	# Smooth zoom
	zoom = zoom.lerp(Vector2(target_zoom, target_zoom), 10.0 * delta)

	# Clamp to bounds
	position.x = clampf(position.x, map_bounds.position.x, map_bounds.end.x)
	position.y = clampf(position.y, map_bounds.position.y, map_bounds.end.y)

# Edge scrolling requires: desktop, no active drag, the mouse has actually
# moved since launch, the window is focused, and the cursor is inside the
# viewport. Disabled under the "movie" feature tag (offline frame capture).
func _edge_scroll_active() -> bool:
	if is_mobile or is_dragging or not _mouse_seen:
		return false
	if OS.has_feature("movie"):
		return false
	if not get_window().has_focus():
		return false
	var mouse: Vector2 = get_viewport().get_mouse_position()
	return get_viewport_rect().has_point(mouse)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(mb.position, zoom_speed)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(mb.position, -zoom_speed)
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
	if event is InputEventMouseMotion:
		_mouse_seen = true
		if is_dragging:
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

# Zooms while keeping the world point under the cursor fixed.
func _zoom_at(screen_pos: Vector2, delta_zoom: float) -> void:
	var old_target: float = target_zoom
	target_zoom = clampf(target_zoom + delta_zoom, min_zoom, max_zoom)
	if is_equal_approx(old_target, target_zoom):
		return

	var vp_size: Vector2 = get_viewport_rect().size
	var mouse_offset: Vector2 = screen_pos - vp_size / 2.0
	var world_before: Vector2 = position + mouse_offset / old_target
	var world_after: Vector2 = position + mouse_offset / target_zoom
	position += world_before - world_after

func _start_pinch() -> void:
	var points: Array = touch_points.values()
	pinch_start_distance = (points[0] as Vector2).distance_to(points[1] as Vector2)
	pinch_start_zoom = target_zoom

func _handle_pinch() -> void:
	var points: Array = touch_points.values()
	var current_distance: float = (points[0] as Vector2).distance_to(points[1] as Vector2)

	if pinch_start_distance > 0:
		var scale_factor: float = current_distance / pinch_start_distance
		target_zoom = clampf(pinch_start_zoom * scale_factor, min_zoom, max_zoom)

func center_on(world_pos: Vector2) -> void:
	position = world_pos
