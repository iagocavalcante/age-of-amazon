# scripts/map/IsometricMap.gd
extends Node2D

var map_generator: MapGenerator
var tile_size: Vector2 = Vector2(64, 32)
var map_texture: ImageTexture

@onready var nav_region: NavigationRegion2D = $NavigationRegion2D
@onready var map_sprite: Sprite2D = $MapSprite

func _ready() -> void:
	map_generator = MapGenerator.new(GameManager.map_width, GameManager.map_height, GameManager.map_seed)
	map_generator.generate()
	_render_map_to_texture()
	_bake_navigation()
	EventBus.map_generated.emit(GameManager.map_width, GameManager.map_height)

func _render_map_to_texture() -> void:
	var w: int = map_generator.width
	var h: int = map_generator.height

	var img_width: int = int((w + h) * tile_size.x / 2.0) + 2
	var img_height: int = int((w + h) * tile_size.y / 2.0) + 2

	var offset: Vector2 = Vector2((h - 1) * tile_size.x / 2.0 + 1, 1 + tile_size.y / 2.0)

	var img: Image = Image.create(img_width, img_height, false, Image.FORMAT_RGB8)
	img.fill(Color(0.1, 0.1, 0.1))

	for y in range(h):
		for x in range(w):
			var biome: int = map_generator.get_biome(x, y)
			var color: Color = Constants.BIOME_COLORS.get(biome, Color.MAGENTA)
			var screen_pos: Vector2 = grid_to_screen(x, y) + offset

			var half_w: int = int(tile_size.x / 2.0)
			var half_h: int = int(tile_size.y / 2.0)

			for py in range(-half_h, half_h + 1):
				var row_width: float = half_w * (1.0 - absf(float(py)) / float(half_h))
				var row_w: int = int(row_width)
				for px in range(-row_w, row_w + 1):
					var ix: int = int(screen_pos.x) + px
					var iy: int = int(screen_pos.y) + py
					if ix >= 0 and ix < img_width and iy >= 0 and iy < img_height:
						img.set_pixel(ix, iy, color)

	map_texture = ImageTexture.create_from_image(img)
	map_sprite.texture = map_texture
	map_sprite.position = -offset
	map_sprite.centered = false

func grid_to_screen(grid_x: int, grid_y: int) -> Vector2:
	var screen_x: float = (grid_x - grid_y) * tile_size.x / 2.0
	var screen_y: float = (grid_x + grid_y) * tile_size.y / 2.0
	return Vector2(screen_x, screen_y)

func screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var gx: float = (screen_pos.x / (tile_size.x / 2.0) + screen_pos.y / (tile_size.y / 2.0)) / 2.0
	var gy: float = (screen_pos.y / (tile_size.y / 2.0) - screen_pos.x / (tile_size.x / 2.0)) / 2.0
	return Vector2i(int(round(gx)), int(round(gy)))

func _bake_navigation() -> void:
	var nav_poly: NavigationPolygon = NavigationPolygon.new()

	var w: int = map_generator.width
	var h: int = map_generator.height
	var corners: PackedVector2Array = PackedVector2Array([
		grid_to_screen(0, 0) + Vector2(0, -tile_size.y / 2.0),
		grid_to_screen(w - 1, 0) + Vector2(tile_size.x / 2.0, 0),
		grid_to_screen(w - 1, h - 1) + Vector2(0, tile_size.y / 2.0),
		grid_to_screen(0, h - 1) + Vector2(-tile_size.x / 2.0, 0),
	])
	nav_poly.add_outline(corners)

	var visited: Dictionary = {}
	for y in range(h):
		for x in range(w):
			if not map_generator.is_walkable(x, y) and not visited.has(Vector2i(x, y)):
				var region: Array[Vector2i] = _flood_fill_unwalkable(x, y, visited)
				if region.size() >= 2:
					var hull: PackedVector2Array = _get_region_outline(region)
					if hull.size() >= 3:
						nav_poly.add_outline(hull)

	nav_poly.make_polygons_from_outlines()
	nav_region.navigation_polygon = nav_poly

func _flood_fill_unwalkable(start_x: int, start_y: int, visited: Dictionary) -> Array[Vector2i]:
	var region: Array[Vector2i] = []
	var queue: Array[Vector2i] = [Vector2i(start_x, start_y)]

	while queue.size() > 0:
		var pos: Vector2i = queue.pop_back()
		if visited.has(pos):
			continue
		if not map_generator._is_in_bounds(pos.x, pos.y):
			continue
		if map_generator.is_walkable(pos.x, pos.y):
			continue

		visited[pos] = true
		region.append(pos)

		queue.append(Vector2i(pos.x + 1, pos.y))
		queue.append(Vector2i(pos.x - 1, pos.y))
		queue.append(Vector2i(pos.x, pos.y + 1))
		queue.append(Vector2i(pos.x, pos.y - 1))

	return region

func _get_region_outline(region: Array[Vector2i]) -> PackedVector2Array:
	var points: PackedVector2Array = []
	var half_w: float = tile_size.x / 2.0
	var half_h: float = tile_size.y / 2.0

	for tile: Vector2i in region:
		var center: Vector2 = grid_to_screen(tile.x, tile.y)
		points.append(center + Vector2(0, -half_h))
		points.append(center + Vector2(half_w, 0))
		points.append(center + Vector2(0, half_h))
		points.append(center + Vector2(-half_w, 0))

	if points.size() < 3:
		return PackedVector2Array()

	var hull: PackedVector2Array = Geometry2D.convex_hull(points)
	return hull
