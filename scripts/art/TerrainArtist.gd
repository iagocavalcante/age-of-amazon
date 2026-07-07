# scripts/art/TerrainArtist.gd
class_name TerrainArtist
extends RefCounted

# Renders the generated map into two textures:
#  - ground: dithered pixel-art terrain with per-tile variants and shore foam
#  - water:  a mask the water shader animates (L = shallow flag, A = is water)
#
# Tiles are pre-generated per biome (VARIANTS_PER_BIOME each) and composited
# with Image.blend_rect, which keeps the whole render in fast C++ calls.

const VARIANTS_PER_BIOME: int = 4

var _tile_w: int = Constants.TILE_WIDTH
var _tile_h: int = Constants.TILE_HEIGHT
var _variants: Dictionary = {}  # biome -> Array[Image]
var _foam_edges: Array[Image] = []  # NE, SE, SW, NW diamond edges
var _water_mask_tiles: Dictionary = {}  # biome -> Image (LA8-style data in RGBA)

var _detail: FastNoiseLite

func render_map(map: MapGenerator) -> Dictionary:
	_detail = FastNoiseLite.new()
	_detail.seed = map.seed_val + 9000
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 0.11

	_build_all_variants()
	_build_foam_edges()
	_build_water_mask_tiles()

	var w: int = map.width
	var h: int = map.height
	var img_w: int = (w + h) * _tile_w / 2
	var img_h: int = (w + h) * _tile_h / 2
	# Everything shifts by this offset so grid (0,0) lands inside the image.
	var origin: Vector2i = Vector2i(h * _tile_w / 2, _tile_h / 2)

	var ground: Image = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	ground.fill(Color(0.04, 0.07, 0.05, 1.0))
	var water: Image = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)

	var tile_rect: Rect2i = Rect2i(0, 0, _tile_w, _tile_h)
	var half: Vector2i = Vector2i(_tile_w / 2, _tile_h / 2)

	for y in range(h):
		for x in range(w):
			var biome: int = map.get_biome(x, y)
			var center: Vector2 = Constants.grid_to_world(x, y)
			var dst: Vector2i = Vector2i(int(center.x), int(center.y)) + origin - half

			var variant_idx: int = int(PixelArt.hash2(x, y, 77) * VARIANTS_PER_BIOME) % VARIANTS_PER_BIOME
			var variants: Array = _variants[biome]
			ground.blend_rect(variants[variant_idx], tile_rect, dst)

			if _is_water(biome):
				water.blend_rect(_water_mask_tiles[biome], tile_rect, dst)

	# Shore foam: light dithered line on the water side of each land/water edge.
	for y in range(h):
		for x in range(w):
			if not _is_water(map.get_biome(x, y)):
				continue
			var center: Vector2 = Constants.grid_to_world(x, y)
			var dst: Vector2i = Vector2i(int(center.x), int(center.y)) + origin - half
			# Grid neighbors share diamond edges: +x -> SE, -x -> NW, +y -> SW, -y -> NE.
			var neighbors: Array[Vector2i] = [
				Vector2i(x, y - 1), Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x - 1, y),
			]
			for i in range(4):
				var n: Vector2i = neighbors[i]
				var in_bounds: bool = n.x >= 0 and n.x < w and n.y >= 0 and n.y < h
				if in_bounds and not _is_water(map.get_biome(n.x, n.y)):
					ground.blend_rect(_foam_edges[i], tile_rect, dst)

	return {
		"ground": ImageTexture.create_from_image(ground),
		"water": ImageTexture.create_from_image(water),
		"origin": Vector2(origin),
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

	for y in range(_tile_h):
		for x in range(_tile_w):
			var dx: float = absf(float(x) + 0.5 - cx) / cx
			var dy: float = absf(float(y) + 0.5 - cy) / cy
			if dx + dy > 1.0:
				continue

			# Soft blobs of value noise, salted per variant so tiles differ.
			var n: float = (_detail.get_noise_2d(float(x + variant * 96), float(y + biome * 64)) + 1.0) / 2.0
			var speckle: float = PixelArt.hash2(x, y, salt)
			var value: float = clampf(n * 0.75 + speckle * 0.25, 0.0, 1.0)

			# Subtle relief: upper half slightly lighter, lower slightly darker.
			var relief: float = (cy - float(y)) / _tile_h * 0.18
			value = clampf(value + relief, 0.0, 1.0)

			img.set_pixel(x, y, PixelArt.ramp_shade(ramp, value, x, y))

	return img

# Foam edge overlays in neighbor order: NE (y-1), SE (x+1), SW (y+1), NW (x-1).
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
					# Dither gaps so the foam reads as broken surf, not a stroke.
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
