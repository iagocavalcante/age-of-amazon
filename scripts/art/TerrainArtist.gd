# scripts/art/TerrainArtist.gd
class_name TerrainArtist
extends RefCounted

# Renders one chunk into two textures:
#  - ground: dithered pixel-art terrain with per-tile variants and shore foam
#  - water:  a mask the water shader animates (R = shallow flag, A = is water)
#
# Tile variants are picked by ABSOLUTE tile coordinates and foam looks up
# neighbor biomes through WorldGen (a pure function), so adjacent chunks are
# rendered independently yet always match seamlessly.
#
# Create ONE instance and reuse it: the per-biome variant tiles are built
# once and cached.

const VARIANTS_PER_BIOME: int = 4

var _tile_w: int = Constants.TILE_WIDTH
var _tile_h: int = Constants.TILE_HEIGHT
var _variants: Dictionary = {}  # biome -> Array[Image]
var _foam_edges: Array[Image] = []  # NE, SE, SW, NW diamond edges
var _water_mask_tiles: Dictionary = {}

var _detail: FastNoiseLite

func _init(p_seed: int) -> void:
	_detail = FastNoiseLite.new()
	_detail.seed = p_seed + 9000
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 0.11

	_build_all_variants()
	_build_foam_edges()
	_build_water_mask_tiles()

# Returns {ground: ImageTexture, water: ImageTexture or null, origin: Vector2}
# where origin is the world position of the image's top-left pixel.
func render_chunk(gen: WorldGen, chunk: ChunkData) -> Dictionary:
	var size: int = Constants.CHUNK_SIZE
	var base_x: int = chunk.coords.x * size
	var base_y: int = chunk.coords.y * size

	var img_w: int = size * _tile_w
	var img_h: int = size * _tile_h
	# Top-left pixel of the chunk's bounding box in world coordinates.
	var origin: Vector2 = Vector2(
		(base_x - (base_y + size - 1)) * _tile_w / 2.0 - _tile_w / 2.0,
		(base_x + base_y) * _tile_h / 2.0 - _tile_h / 2.0
	)

	var ground: Image = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	var water: Image = null

	var tile_rect: Rect2i = Rect2i(0, 0, _tile_w, _tile_h)
	var half: Vector2 = Vector2(_tile_w / 2.0, _tile_h / 2.0)

	# The -1/+1 border ring paints the neighbor tiles whose diamonds overlap
	# this chunk's bounding box; without it, chunk borders show seams.
	for ly in range(-1, size + 1):
		for lx in range(-1, size + 1):
			var x: int = base_x + lx
			var y: int = base_y + ly
			var in_chunk: bool = lx >= 0 and lx < size and ly >= 0 and ly < size
			var biome: int = chunk.get_biome_local(lx, ly) if in_chunk else gen.biome_at(x, y)
			var center: Vector2 = Constants.grid_to_world(x, y)
			var dst: Vector2i = Vector2i((center - origin - half).round())

			var variant_idx: int = int(PixelArt.hash2(x, y, 77) * VARIANTS_PER_BIOME) % VARIANTS_PER_BIOME
			var variants: Array = _variants[biome]
			ground.blend_rect(variants[variant_idx], tile_rect, dst)

			if _is_water(biome):
				# The animated mask only covers in-chunk tiles: adjacent
				# chunks' water sprites would otherwise double-draw overlaps.
				if in_chunk:
					if water == null:
						water = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
					water.blend_rect(_water_mask_tiles[biome], tile_rect, dst)

				# Shore foam on the water side of land/water edges.
				# Neighbor order: -y -> NE, +x -> SE, +y -> SW, -x -> NW.
				var neighbors: Array[Vector2i] = [
					Vector2i(x, y - 1), Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x - 1, y),
				]
				for i in range(4):
					var n: Vector2i = neighbors[i]
					if not _is_water(gen.biome_at(n.x, n.y)):
						ground.blend_rect(_foam_edges[i], tile_rect, dst)

	return {
		"ground": ImageTexture.create_from_image(ground),
		"water": ImageTexture.create_from_image(water) if water != null else null,
		"origin": origin,
	}

func _is_water(biome: int) -> bool:
	return biome == Constants.Biome.WATER_DEEP or biome == Constants.Biome.WATER_SHALLOW

func _build_all_variants() -> void:
	for biome: int in Constants.BIOME_RAMPS:
		var list: Array = []
		for v in range(VARIANTS_PER_BIOME):
			list.append(_build_tile(biome, v))
		_variants[biome] = list

func _build_tile(biome: int, variant: int) -> Image:
	var img: Image = Image.create(_tile_w, _tile_h, false, Image.FORMAT_RGBA8)
	var ramp: Array = Constants.BIOME_RAMPS[biome]
	var cx: float = _tile_w / 2.0
	var cy: float = _tile_h / 2.0
	var salt: int = biome * 131 + variant * 17
	# Slightly fat diamonds: adjacent tiles overlap by ~1px, closing the
	# pinholes exact rasterization leaves at tile-corner junctions.
	var fat: float = 1.0 + 1.5 / cx

	for y in range(_tile_h):
		for x in range(_tile_w):
			var dx: float = absf(float(x) + 0.5 - cx) / cx
			var dy: float = absf(float(y) + 0.5 - cy) / cy
			if dx + dy > fat:
				continue

			var n: float = (_detail.get_noise_2d(float(x + variant * 96), float(y + biome * 64)) + 1.0) / 2.0
			var speckle: float = PixelArt.hash2(x, y, salt)
			var value: float = clampf(n * 0.75 + speckle * 0.25, 0.0, 1.0)
			var relief: float = (cy - float(y)) / _tile_h * 0.18
			value = clampf(value + relief, 0.0, 1.0)

			img.set_pixel(x, y, PixelArt.ramp_shade(ramp, value, x, y))

	return img

func _build_foam_edges() -> void:
	_foam_edges.clear()
	var foam: Color = Color(0.92, 0.97, 0.98, 0.85)
	var foam_soft: Color = Color(0.85, 0.94, 0.96, 0.45)

	for edge in range(4):
		var img: Image = Image.create(_tile_w, _tile_h, false, Image.FORMAT_RGBA8)
		var cx: float = _tile_w / 2.0
		var cy: float = _tile_h / 2.0

		for y in range(_tile_h):
			for x in range(_tile_w):
				var fx: float = float(x) + 0.5 - cx
				var fy: float = float(y) + 0.5 - cy
				var dx: float = absf(fx) / cx
				var dy: float = absf(fy) / cy
				if dx + dy > 1.0:
					continue

				var on_edge: bool = false
				match edge:
					0: on_edge = fx >= 0.0 and fy < 0.0 and dx + dy > 0.80  # NE
					1: on_edge = fx >= 0.0 and fy >= 0.0 and dx + dy > 0.80  # SE
					2: on_edge = fx < 0.0 and fy >= 0.0 and dx + dy > 0.80  # SW
					3: on_edge = fx < 0.0 and fy < 0.0 and dx + dy > 0.80  # NW

				if on_edge:
					var speckle: float = PixelArt.hash2(x, y, edge * 883)
					if dx + dy > 0.90:
						if speckle > 0.25:
							img.set_pixel(x, y, foam)
					elif speckle > 0.6:
						img.set_pixel(x, y, foam_soft)

		_foam_edges.append(img)

func _build_water_mask_tiles() -> void:
	for biome: int in [Constants.Biome.WATER_DEEP, Constants.Biome.WATER_SHALLOW]:
		var img: Image = Image.create(_tile_w, _tile_h, false, Image.FORMAT_RGBA8)
		var shallow: float = 1.0 if biome == Constants.Biome.WATER_SHALLOW else 0.0
		var cx: float = _tile_w / 2.0
		var cy: float = _tile_h / 2.0
		for y in range(_tile_h):
			for x in range(_tile_w):
				var dx: float = absf(float(x) + 0.5 - cx) / cx
				var dy: float = absf(float(y) + 0.5 - cy) / cy
				if dx + dy <= 1.0:
					img.set_pixel(x, y, Color(shallow, 0.0, 0.0, 1.0))
		_water_mask_tiles[biome] = img
