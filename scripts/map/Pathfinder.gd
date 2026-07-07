# scripts/map/Pathfinder.gd
class_name Pathfinder
extends RefCounted

# Grid-native A* pathfinding over the generated map. Replaces the previous
# NavigationRegion2D approach, whose convex-hull obstacle outlines over-blocked
# concave river bends and their shallow fords.

var _astar: AStarGrid2D
var _map: MapGenerator

func _init(map: MapGenerator) -> void:
	_map = map
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, map.width, map.height)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()

	for y in range(map.height):
		for x in range(map.width):
			var pos: Vector2i = Vector2i(x, y)
			if not map.is_walkable(x, y):
				_astar.set_point_solid(pos, true)
			else:
				var cost: float = _map.get_movement_cost(x, y)
				_astar.set_point_weight_scale(pos, cost)

func is_walkable(cell: Vector2i) -> bool:
	return _in_region(cell) and not _astar.is_point_solid(cell)

# Returns world-space waypoints (tile centers). Empty if no path exists.
func find_path_world(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	var from_cell: Vector2i = _nearest_walkable(Constants.world_to_grid(from_world))
	var to_cell: Vector2i = _nearest_walkable(Constants.world_to_grid(to_world))

	var result: PackedVector2Array = PackedVector2Array()
	if from_cell == Vector2i(-1, -1) or to_cell == Vector2i(-1, -1):
		return result

	var id_path: Array[Vector2i] = _astar.get_id_path(from_cell, to_cell, true)
	for cell: Vector2i in id_path:
		result.append(Constants.grid_to_world(cell.x, cell.y))
	return result

# Finds up to `count` distinct walkable destination cells around a target,
# so grouped units fan out into a formation instead of stacking.
func formation_cells(target_world: Vector2, count: int) -> Array[Vector2i]:
	var center: Vector2i = Constants.world_to_grid(target_world)
	var cells: Array[Vector2i] = []
	var radius: int = 0

	while cells.size() < count and radius <= 8:
		for offset: Vector2i in _ring_offsets(radius):
			var cell: Vector2i = center + offset
			if is_walkable(cell):
				cells.append(cell)
				if cells.size() >= count:
					break
		radius += 1

	return cells

func _ring_offsets(radius: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	if radius == 0:
		offsets.append(Vector2i.ZERO)
		return offsets
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dy)) == radius:
				offsets.append(Vector2i(dx, dy))
	return offsets

# Returns Vector2i(-1, -1) when nothing walkable is found nearby.
func _nearest_walkable(cell: Vector2i) -> Vector2i:
	var clamped: Vector2i = Vector2i(
		clampi(cell.x, 0, _map.width - 1),
		clampi(cell.y, 0, _map.height - 1)
	)
	if is_walkable(clamped):
		return clamped

	for radius in range(1, 16):
		for offset: Vector2i in _ring_offsets(radius):
			var candidate: Vector2i = clamped + offset
			if is_walkable(candidate):
				return candidate

	return Vector2i(-1, -1)

func _in_region(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < _map.width and cell.y >= 0 and cell.y < _map.height
