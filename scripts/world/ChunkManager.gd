# scripts/world/ChunkManager.gd
extends Node2D

# Streams chunk visuals around the camera: whatever the camera can see
# (plus a one-chunk margin) gets ground/water textures and doodad sprites;
# everything else is freed. Chunk DATA persists in WorldData forever, so
# revisited areas look identical and gameplay state (resources, occupancy)
# is never lost. Builds are budgeted per frame to avoid hitches.

const BUILDS_PER_FRAME: int = 2

var world: WorldData
var artist: TerrainArtist

# Assigned by Main.
var camera: Camera2D
var doodad_parent: Node2D

var _water_material: ShaderMaterial
var _build_queue: Array[Vector2i] = []
var _loaded: Dictionary = {}  # chunk coords -> true

func setup(p_camera: Camera2D, p_doodad_parent: Node2D) -> void:
	camera = p_camera
	doodad_parent = p_doodad_parent

	world = WorldData.new(GameManager.map_seed)
	artist = TerrainArtist.new(GameManager.map_seed)
	GameManager.world = world
	GameManager.pathfinder = Pathfinder.new(world)

	var shader: Shader = load("res://assets/shaders/water.gdshader")
	_water_material = ShaderMaterial.new()
	_water_material.shader = shader

	world.resource_depleted.connect(_on_resource_depleted)
	EventBus.resource_worked.connect(_on_resource_worked)

func _process(_delta: float) -> void:
	if camera == null:
		return

	var desired: Dictionary = _desired_chunks()

	# Unload visuals that fell out of range.
	for cc: Vector2i in _loaded.keys():
		if not desired.has(cc):
			_unload_visual(world.get_chunk(cc))
			_loaded.erase(cc)

	# Queue missing chunks (nearest first arrives naturally from scan order).
	for cc: Vector2i in desired:
		if not _loaded.has(cc) and not _build_queue.has(cc):
			_build_queue.append(cc)

	var builds: int = 0
	while _build_queue.size() > 0 and builds < BUILDS_PER_FRAME:
		var cc: Vector2i = _build_queue.pop_front()
		if _loaded.has(cc):
			continue
		_build_visual(world.get_chunk(cc))
		_loaded[cc] = true
		builds += 1

# Synchronously load everything the camera currently sees (startup).
func load_now() -> void:
	for cc: Vector2i in _desired_chunks():
		if not _loaded.has(cc):
			_build_visual(world.get_chunk(cc))
			_loaded[cc] = true

func _desired_chunks() -> Dictionary:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var half: Vector2 = vp / (2.0 * camera.zoom.x)
	var center: Vector2 = camera.global_position

	# Grid-space bounding box of the visible world rect's corners.
	var corners: Array[Vector2] = [
		center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
		center + Vector2(-half.x, half.y), center + Vector2(half.x, half.y),
	]
	var min_cell: Vector2i = Vector2i(2147483647, 2147483647)
	var max_cell: Vector2i = Vector2i(-2147483648, -2147483648)
	for corner: Vector2 in corners:
		var cell: Vector2i = Constants.world_to_grid(corner)
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))

	var cc_min: Vector2i = Constants.tile_to_chunk(min_cell) - Vector2i.ONE
	var cc_max: Vector2i = Constants.tile_to_chunk(max_cell) + Vector2i.ONE

	var desired: Dictionary = {}
	for cy in range(cc_min.y, cc_max.y + 1):
		for cx in range(cc_min.x, cc_max.x + 1):
			desired[Vector2i(cx, cy)] = true
	return desired

func _build_visual(chunk: ChunkData) -> void:
	if chunk.visual != null:
		return

	var render: Dictionary = artist.render_chunk(world.gen, chunk)
	var origin: Vector2 = render["origin"]

	var terrain: Node2D = Node2D.new()
	terrain.name = "Chunk_%d_%d" % [chunk.coords.x, chunk.coords.y]

	var ground: Sprite2D = Sprite2D.new()
	ground.texture = render["ground"]
	ground.centered = false
	ground.position = origin
	terrain.add_child(ground)

	if render["water"] != null:
		var water: Sprite2D = Sprite2D.new()
		water.texture = render["water"]
		water.centered = false
		water.position = origin
		# Per-chunk material carrying the sprite's world origin, so the
		# animated pattern lines up across chunk borders.
		var mat: ShaderMaterial = _water_material.duplicate() as ShaderMaterial
		mat.set_shader_parameter("world_origin", origin)
		water.material = mat
		terrain.add_child(water)

	add_child(terrain)
	chunk.visual = terrain

	# Doodads: harvestable resource nodes + pure decoration, y-sorted.
	var doodads: Node2D = Node2D.new()
	doodads.name = "Doodads_%d_%d" % [chunk.coords.x, chunk.coords.y]
	doodads.y_sort_enabled = true

	chunk.resource_sprites.clear()
	for cell: Vector2i in chunk.resources:
		var node: Dictionary = chunk.resources[cell]
		var sprite: Sprite2D = _doodad_sprite(_resource_texture(node, cell), cell)
		doodads.add_child(sprite)
		chunk.resource_sprites[cell] = sprite

	for cell: Vector2i in chunk.decor:
		var texture: Texture2D = AssetLibrary.reeds_texture if chunk.decor[cell] == "reeds" else AssetLibrary.rock_texture
		doodads.add_child(_doodad_sprite(texture, cell))

	doodad_parent.add_child(doodads)
	chunk.doodad_visual = doodads

func _resource_texture(node: Dictionary, cell: Vector2i) -> Texture2D:
	if node.get("fish", false):
		return AssetLibrary.fish_texture
	match int(node["type"]):
		Constants.ResourceType.WOOD:
			var idx: int = int(PixelArt.hash2(cell.x, cell.y, 31) * AssetLibrary.tree_textures.size())
			return AssetLibrary.tree_textures[idx % AssetLibrary.tree_textures.size()]
		Constants.ResourceType.FOOD:
			return AssetLibrary.berry_texture
		_:
			return AssetLibrary.jade_texture

func _doodad_sprite(texture: Texture2D, cell: Vector2i) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.offset = Vector2(0, -texture.get_height() / 2.0)
	# Deterministic jitter keeps the grid from reading as a lattice.
	var jx: float = (PixelArt.hash2(cell.x, cell.y, 41) - 0.5) * 16.0
	var jy: float = (PixelArt.hash2(cell.x, cell.y, 43) - 0.5) * 6.0
	sprite.position = Constants.grid_to_world(cell.x, cell.y) + Vector2(jx, jy)
	return sprite

func _unload_visual(chunk: ChunkData) -> void:
	if chunk.visual != null:
		chunk.visual.queue_free()
		chunk.visual = null
	if chunk.doodad_visual != null:
		chunk.doodad_visual.queue_free()
		chunk.doodad_visual = null
	chunk.resource_sprites.clear()

# A swing landed: give the resource sprite a little shake so chopping a
# tree looks like chopping a tree.
func _on_resource_worked(cell: Vector2i) -> void:
	var chunk: ChunkData = world.get_chunk(Constants.tile_to_chunk(cell))
	var sprite: Sprite2D = chunk.resource_sprites.get(cell)
	if sprite == null or not is_instance_valid(sprite):
		return
	var tween: Tween = sprite.create_tween()
	tween.tween_property(sprite, "offset:x", 2.0, 0.05)
	tween.tween_property(sprite, "offset:x", -1.5, 0.06)
	tween.tween_property(sprite, "offset:x", 0.0, 0.06)

func _on_resource_depleted(cell: Vector2i) -> void:
	var chunk: ChunkData = world.get_chunk(Constants.tile_to_chunk(cell))
	var sprite: Sprite2D = chunk.resource_sprites.get(cell)
	if sprite != null and is_instance_valid(sprite):
		sprite.queue_free()
	chunk.resource_sprites.erase(cell)
