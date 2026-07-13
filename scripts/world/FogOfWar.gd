# scripts/world/FogOfWar.gd
class_name FogOfWar
extends CanvasLayer

# Age-of-Empires-style fog-of-war RENDERER for the local player.
#
# Three tile states:
#   unexplored — never seen: opaque black
#   explored   — seen before, nobody watching now: dimmed (terrain remembered)
#   visible    — inside the vision radius of an own unit/building: clear
#
# The knowledge itself lives in a PlayerVision (the enemy AI keeps its own
# instance — fog is symmetric). Every UPDATE_INTERVAL the vision recomputes,
# changed chunks get their 16x16 fog images rebuilt, and the images are
# blitted into one window texture that a full-screen shader maps back onto
# the isometric grid. Enemy units are hidden unless currently visible;
# enemy buildings stay visible once their ground has been explored.

const UPDATE_INTERVAL: float = 0.25
const VISIBLE_VALUE: int = 255
const EXPLORED_VALUE: int = 140  # -> ~45% black in the shader

var camera: Camera2D
# Re-created in setup(): on multiplayer clients local_player_id is only known
# after the match config arrives, which is later than this node's init.
var vision: PlayerVision = PlayerVision.new(GameManager.local_player_id)

var _rect: ColorRect
var _material: ShaderMaterial
var _accum: float = 0.0
var _fog_images: Dictionary = {}  # Vector2i chunk coords -> Image

func _ready() -> void:
	layer = 5  # above the world, below the HUD (layer 10)

	_material = ShaderMaterial.new()
	_material.shader = load("res://assets/shaders/fog.gdshader")

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	add_child(_rect)

func setup(p_camera: Camera2D) -> void:
	camera = p_camera
	vision = PlayerVision.new(GameManager.local_player_id)
	GameManager.fog = self

func _process(delta: float) -> void:
	if camera == null or GameManager.world == null:
		return

	var vp: Vector2 = _rect.get_viewport_rect().size
	_material.set_shader_parameter("cam_pos", camera.global_position)
	_material.set_shader_parameter("zoom", camera.zoom.x)
	_material.set_shader_parameter("vp_size", vp)

	_accum += delta
	if _accum >= UPDATE_INTERVAL:
		_accum = 0.0
		force_update()

# --- Queries (local player's knowledge) ---

func is_cell_visible(cell: Vector2i) -> bool:
	return vision.is_visible(cell)

func is_explored(cell: Vector2i) -> bool:
	return vision.is_explored(cell)

# --- Update pass ---

func force_update() -> void:
	var world: WorldData = GameManager.world
	if world == null:
		return

	vision.update(get_tree(), world)

	# Rebuild fog images for chunks whose knowledge changed (all near own
	# units, so this stays small no matter how much world exists).
	for cc: Vector2i in vision.changed_chunks:
		_rebuild_chunk_fog(cc)
	vision.changed_chunks.clear()

	_compose_window(world)
	_cull_entities()

func _rebuild_chunk_fog(cc: Vector2i) -> void:
	var size: int = Constants.CHUNK_SIZE
	var img: Image = _fog_images.get(cc)
	if img == null:
		img = Image.create(size, size, false, Image.FORMAT_R8)
		_fog_images[cc] = img

	var base_x: int = cc.x * size
	var base_y: int = cc.y * size
	for ly in range(size):
		for lx in range(size):
			var cell: Vector2i = Vector2i(base_x + lx, base_y + ly)
			var value: int = 0
			if vision.visible_cells.has(cell):
				value = VISIBLE_VALUE
			elif vision.explored.has(cell):
				value = EXPLORED_VALUE
			img.set_pixel(lx, ly, Color8(value, 0, 0))

func _compose_window(world: WorldData) -> void:
	var size: int = Constants.CHUNK_SIZE
	var vp: Vector2 = _rect.get_viewport_rect().size
	var half: Vector2 = vp / (2.0 * camera.zoom.x)
	var center: Vector2 = camera.global_position

	var min_cell: Vector2i = Vector2i(2147483647, 2147483647)
	var max_cell: Vector2i = Vector2i(-2147483648, -2147483648)
	for corner: Vector2 in [
		center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
		center + Vector2(-half.x, half.y), center + Vector2(half.x, half.y),
	]:
		var cell: Vector2i = Constants.world_to_grid(corner)
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))

	var cc_min: Vector2i = Constants.tile_to_chunk(min_cell) - Vector2i.ONE
	var cc_max: Vector2i = Constants.tile_to_chunk(max_cell) + Vector2i.ONE
	var span: Vector2i = cc_max - cc_min + Vector2i.ONE

	var img: Image = Image.create(span.x * size, span.y * size, false, Image.FORMAT_R8)
	var src_rect: Rect2i = Rect2i(0, 0, size, size)
	for cy in range(cc_min.y, cc_max.y + 1):
		for cx in range(cc_min.x, cc_max.x + 1):
			var fog_img: Image = _fog_images.get(Vector2i(cx, cy))
			if fog_img != null:
				img.blit_rect(fog_img, src_rect, Vector2i((cx - cc_min.x) * size, (cy - cc_min.y) * size))

	_material.set_shader_parameter("fog_tex", ImageTexture.create_from_image(img))
	_material.set_shader_parameter("window_origin", Vector2(cc_min * size))
	_material.set_shader_parameter("window_tiles", Vector2(span * size))

func _cull_entities() -> void:
	for node: Node in get_tree().get_nodes_in_group("units"):
		var unit: Node2D = node as Node2D
		if unit == null or unit.get("player_id") == GameManager.local_player_id:
			continue
		unit.visible = vision.can_see_entity(unit)

	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var building: Building = node as Building
		if building == null or building.player_id == GameManager.local_player_id:
			continue
		# Buildings can't move: once their ground is explored, remember them.
		building.visible = vision.has_discovered_building(building)

	# Neutral wildlife hides in the fog just like enemy units.
	for node: Node in get_tree().get_nodes_in_group("animals"):
		var animal: Node2D = node as Node2D
		if animal != null:
			animal.visible = vision.can_see_entity(animal)
