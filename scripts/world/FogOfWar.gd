# scripts/world/FogOfWar.gd
class_name FogOfWar
extends CanvasLayer

# Age-of-Empires-style fog of war for the local player.
#
# Three tile states:
#   unexplored — never seen: opaque black
#   explored   — seen before, nobody watching now: dimmed (terrain remembered)
#   visible    — inside the vision radius of an own unit/building: clear
#
# Explored bits persist per chunk (ChunkData.explored). Every UPDATE_INTERVAL
# the visible set is recomputed from own units/buildings, dirty chunks get
# their 16x16 fog images rebuilt, and the images are blitted into one window
# texture that a full-screen shader maps back onto the isometric grid.
# Enemy units are hidden unless currently visible; enemy buildings stay
# visible once their ground has been explored (they can't move).

const UPDATE_INTERVAL: float = 0.25
const VISIBLE_VALUE: int = 255
const EXPLORED_VALUE: int = 140  # -> ~45% black in the shader

var camera: Camera2D

var _rect: ColorRect
var _material: ShaderMaterial
var _accum: float = 0.0
var _visible_cells: Dictionary = {}  # Vector2i -> true
var _dirty_chunks: Dictionary = {}   # Vector2i chunk coords -> true

func _ready() -> void:
	layer = 5  # above the world, below the HUD (layer 10)

	_material = ShaderMaterial.new()
	_material.shader = load("res://assets/shaders/fog.gdshader")

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	# Fully hidden until the first fog update runs.
	_rect.color = Color.WHITE
	add_child(_rect)

func setup(p_camera: Camera2D) -> void:
	camera = p_camera
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

# --- Queries ---

func is_cell_visible(cell: Vector2i) -> bool:
	return _visible_cells.has(cell)

func is_explored(cell: Vector2i) -> bool:
	var cc: Vector2i = Constants.tile_to_chunk(cell)
	var chunk: ChunkData = GameManager.world.chunks.get(cc)
	if chunk == null:
		return false
	var size: int = Constants.CHUNK_SIZE
	return chunk.explored[(cell.y - cc.y * size) * size + (cell.x - cc.x * size)] == 1

# --- Update pass ---

func force_update() -> void:
	var world: WorldData = GameManager.world
	if world == null:
		return

	# Chunks that HAD visible cells must be repainted (visibility receding).
	for cell: Vector2i in _visible_cells:
		_dirty_chunks[Constants.tile_to_chunk(cell)] = true
	_visible_cells.clear()

	# Vision circles of own units and buildings.
	for node: Node in get_tree().get_nodes_in_group("player_%d" % GameManager.LOCAL_PLAYER_ID):
		var entity: Node2D = node as Node2D
		if entity == null or not is_instance_valid(entity):
			continue
		var radius: int = 6
		if entity is UnitBase:
			# vision_range is world px; ~32 px per tile step in grid space.
			radius = maxi(4, int(round((entity as UnitBase).vision_range / 32.0)))
		elif entity is Building:
			radius = Constants.BUILDING_DEFS[(entity as Building).building_type]["vision_tiles"]
		_reveal_circle(world, Constants.world_to_grid(entity.global_position), radius)

	# Rebuild fog images for every dirty chunk (they're all near own units,
	# so this stays small regardless of how much world exists).
	for cc: Vector2i in _dirty_chunks:
		var chunk: ChunkData = world.chunks.get(cc)
		if chunk != null:
			_rebuild_chunk_fog(chunk)
	_dirty_chunks.clear()

	_compose_window(world)
	_cull_entities()

func _reveal_circle(world: WorldData, center: Vector2i, radius: int) -> void:
	var size: int = Constants.CHUNK_SIZE
	var r2: int = radius * radius
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > r2:
				continue
			var cell: Vector2i = center + Vector2i(dx, dy)
			_visible_cells[cell] = true

			var cc: Vector2i = Constants.tile_to_chunk(cell)
			var chunk: ChunkData = world.get_chunk(cc)
			var idx: int = (cell.y - cc.y * size) * size + (cell.x - cc.x * size)
			if chunk.explored[idx] == 0:
				chunk.explored[idx] = 1
			_dirty_chunks[cc] = true

func _rebuild_chunk_fog(chunk: ChunkData) -> void:
	var size: int = Constants.CHUNK_SIZE
	if chunk.fog_image == null:
		chunk.fog_image = Image.create(size, size, false, Image.FORMAT_R8)

	var base_x: int = chunk.coords.x * size
	var base_y: int = chunk.coords.y * size
	for ly in range(size):
		for lx in range(size):
			var value: int = 0
			if _visible_cells.has(Vector2i(base_x + lx, base_y + ly)):
				value = VISIBLE_VALUE
			elif chunk.explored[ly * size + lx] == 1:
				value = EXPLORED_VALUE
			chunk.fog_image.set_pixel(lx, ly, Color8(value, 0, 0))

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
			var chunk: ChunkData = world.chunks.get(Vector2i(cx, cy))
			if chunk != null and chunk.fog_image != null:
				img.blit_rect(chunk.fog_image, src_rect, Vector2i((cx - cc_min.x) * size, (cy - cc_min.y) * size))

	_material.set_shader_parameter("fog_tex", ImageTexture.create_from_image(img))
	_material.set_shader_parameter("window_origin", Vector2(cc_min * size))
	_material.set_shader_parameter("window_tiles", Vector2(span * size))

func _cull_entities() -> void:
	for node: Node in get_tree().get_nodes_in_group("units"):
		var unit: Node2D = node as Node2D
		if unit == null or unit.get("player_id") == GameManager.LOCAL_PLAYER_ID:
			continue
		unit.visible = _visible_cells.has(Constants.world_to_grid(unit.global_position))

	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var building: Building = node as Building
		if building == null or building.player_id == GameManager.LOCAL_PLAYER_ID:
			continue
		# Buildings can't move: once their ground is explored, remember them.
		var seen: bool = false
		for cell: Vector2i in building.footprint_cells:
			if is_explored(cell):
				seen = true
				break
		building.visible = seen
