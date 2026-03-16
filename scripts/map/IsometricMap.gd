# scripts/map/IsometricMap.gd
extends Node2D

var map_generator: MapGenerator
var tile_size := Vector2(64, 32)

@onready var nav_region: NavigationRegion2D = $NavigationRegion2D

func _ready() -> void:
	map_generator = MapGenerator.new(GameManager.map_width, GameManager.map_height, GameManager.map_seed)
	map_generator.generate()
	queue_redraw()
	_bake_navigation()
	EventBus.map_generated.emit(GameManager.map_width, GameManager.map_height)

func _draw() -> void:
	if map_generator == null:
		return

	for y in range(map_generator.height):
		for x in range(map_generator.width):
			var biome := map_generator.get_biome(x, y)
			var color: Color = Constants.BIOME_COLORS.get(biome, Color.MAGENTA)
			_draw_iso_tile(x, y, color)

func _draw_iso_tile(grid_x: int, grid_y: int, color: Color) -> void:
	var screen_pos := grid_to_screen(grid_x, grid_y)
	var half_w := tile_size.x / 2.0
	var half_h := tile_size.y / 2.0

	var points := PackedVector2Array([
		screen_pos + Vector2(0, -half_h),
		screen_pos + Vector2(half_w, 0),
		screen_pos + Vector2(0, half_h),
		screen_pos + Vector2(-half_w, 0),
	])
	draw_colored_polygon(points, color)

func grid_to_screen(grid_x: int, grid_y: int) -> Vector2:
	var screen_x := (grid_x - grid_y) * tile_size.x / 2.0
	var screen_y := (grid_x + grid_y) * tile_size.y / 2.0
	return Vector2(screen_x, screen_y)

func screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var gx := (screen_pos.x / (tile_size.x / 2.0) + screen_pos.y / (tile_size.y / 2.0)) / 2.0
	var gy := (screen_pos.y / (tile_size.y / 2.0) - screen_pos.x / (tile_size.x / 2.0)) / 2.0
	return Vector2i(int(round(gx)), int(round(gy)))

func _bake_navigation() -> void:
	var nav_poly := NavigationPolygon.new()

	for y in range(map_generator.height):
		for x in range(map_generator.width):
			if map_generator.is_walkable(x, y):
				var screen_pos := grid_to_screen(x, y)
				var half_w := tile_size.x / 2.0
				var half_h := tile_size.y / 2.0

				var outline := PackedVector2Array([
					screen_pos + Vector2(0, -half_h),
					screen_pos + Vector2(half_w, 0),
					screen_pos + Vector2(0, half_h),
					screen_pos + Vector2(-half_w, 0),
				])
				nav_poly.add_outline(outline)

	nav_poly.make_polygons_from_outlines()
	nav_region.navigation_polygon = nav_poly
