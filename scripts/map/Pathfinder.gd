# scripts/map/Pathfinder.gd
class_name Pathfinder
extends RefCounted

# A* over the infinite chunked world. AStarGrid2D needs a fixed region, so
# this is a hand-rolled implementation with a binary heap, octile heuristic,
# per-biome movement costs, and an expansion budget that degrades gracefully
# to a best-effort partial path (closest reachable point to the target).

const MAX_EXPANSIONS: int = 4000
const SQRT2: float = 1.41421356

var _world: WorldData

func _init(world: WorldData) -> void:
	_world = world

func is_walkable(cell: Vector2i) -> bool:
	return _world.is_walkable(cell)

# World-space waypoints (tile centers). Empty if start has no walkable spot.
func find_path_world(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	var from_cell: Vector2i = _nearest_walkable(Constants.world_to_grid(from_world))
	var to_cell: Vector2i = _nearest_walkable(Constants.world_to_grid(to_world))

	var result: PackedVector2Array = PackedVector2Array()
	if from_cell == Vector2i(2147483647, 2147483647) or to_cell == Vector2i(2147483647, 2147483647):
		return result

	var cells: Array[Vector2i] = _astar(from_cell, to_cell)
	for cell: Vector2i in cells:
		result.append(Constants.grid_to_world(cell.x, cell.y))
	return result

func _astar(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if start == goal:
		return [start]

	# Binary heap of [f, tie, cell]; parallel dictionaries for scores.
	var heap: Array = []
	var g_score: Dictionary = { start: 0.0 }
	var came_from: Dictionary = {}
	var closed: Dictionary = {}
	var tie: int = 0

	var best_cell: Vector2i = start
	var best_h: float = _heuristic(start, goal)

	_heap_push(heap, [best_h, tie, start])

	var expansions: int = 0
	while heap.size() > 0 and expansions < MAX_EXPANSIONS:
		var entry: Array = _heap_pop(heap)
		var current: Vector2i = entry[2]
		if closed.has(current):
			continue
		closed[current] = true
		expansions += 1

		if current == goal:
			return _reconstruct(came_from, current)

		var h_current: float = _heuristic(current, goal)
		if h_current < best_h:
			best_h = h_current
			best_cell = current

		for neighbor_info: Array in _neighbors(current):
			var neighbor: Vector2i = neighbor_info[0]
			var step_mult: float = neighbor_info[1]
			if closed.has(neighbor):
				continue

			var step_cost: float = _world.movement_cost(neighbor) * step_mult
			if is_inf(step_cost):
				continue

			var tentative: float = g_score[current] + step_cost
			if tentative < g_score.get(neighbor, INF):
				g_score[neighbor] = tentative
				came_from[neighbor] = current
				tie += 1
				_heap_push(heap, [tentative + _heuristic(neighbor, goal), tie, neighbor])

	# Budget exhausted or unreachable: best-effort partial path.
	if best_cell == start:
		return []
	return _reconstruct(came_from, best_cell)

# 8-connected neighbors; diagonals only when both orthogonals are walkable
# (no corner cutting). Each entry: [cell, distance multiplier].
func _neighbors(cell: Vector2i) -> Array:
	var result: Array = []
	var n: bool = _world.is_walkable(cell + Vector2i(0, -1))
	var s: bool = _world.is_walkable(cell + Vector2i(0, 1))
	var w: bool = _world.is_walkable(cell + Vector2i(-1, 0))
	var e: bool = _world.is_walkable(cell + Vector2i(1, 0))

	if n: result.append([cell + Vector2i(0, -1), 1.0])
	if s: result.append([cell + Vector2i(0, 1), 1.0])
	if w: result.append([cell + Vector2i(-1, 0), 1.0])
	if e: result.append([cell + Vector2i(1, 0), 1.0])
	if n and w and _world.is_walkable(cell + Vector2i(-1, -1)):
		result.append([cell + Vector2i(-1, -1), SQRT2])
	if n and e and _world.is_walkable(cell + Vector2i(1, -1)):
		result.append([cell + Vector2i(1, -1), SQRT2])
	if s and w and _world.is_walkable(cell + Vector2i(-1, 1)):
		result.append([cell + Vector2i(-1, 1), SQRT2])
	if s and e and _world.is_walkable(cell + Vector2i(1, 1)):
		result.append([cell + Vector2i(1, 1), SQRT2])
	return result

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx: float = absf(float(a.x - b.x))
	var dy: float = absf(float(a.y - b.y))
	return maxf(dx, dy) + (SQRT2 - 1.0) * minf(dx, dy)

func _reconstruct(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path

# --- Binary min-heap on [f, tie, cell] arrays ---

func _heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) >> 1
		if _heap_less(heap[i], heap[parent]):
			var tmp: Array = heap[i]
			heap[i] = heap[parent]
			heap[parent] = tmp
			i = parent
		else:
			break

func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.size() > 0:
		heap[0] = last
		var i: int = 0
		var size: int = heap.size()
		while true:
			var smallest: int = i
			var l: int = i * 2 + 1
			var r: int = i * 2 + 2
			if l < size and _heap_less(heap[l], heap[smallest]):
				smallest = l
			if r < size and _heap_less(heap[r], heap[smallest]):
				smallest = r
			if smallest == i:
				break
			var tmp: Array = heap[i]
			heap[i] = heap[smallest]
			heap[smallest] = tmp
			i = smallest
	return top

func _heap_less(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	return a[1] < b[1]

# --- Placement helpers ---

# Up to `count` distinct walkable cells around a target (formation spread).
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

# Nearest walkable cell adjacent to any of the given footprint cells.
func adjacent_walkable(footprint: Array[Vector2i], near_cell: Vector2i) -> Dictionary:
	var best: Vector2i = Vector2i.ZERO
	var best_dist: float = INF
	var found: bool = false
	for cell: Vector2i in footprint:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var candidate: Vector2i = cell + Vector2i(dx, dy)
				if candidate in footprint or not is_walkable(candidate):
					continue
				var dist: float = Vector2(candidate - near_cell).length()
				if dist < best_dist:
					best_dist = dist
					best = candidate
					found = true
	return { "found": found, "cell": best }

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

# Sentinel Vector2i(2147483647, 2147483647) when nothing found nearby.
func _nearest_walkable(cell: Vector2i) -> Vector2i:
	if is_walkable(cell):
		return cell
	for radius in range(1, 16):
		for offset: Vector2i in _ring_offsets(radius):
			var candidate: Vector2i = cell + offset
			if is_walkable(candidate):
				return candidate
	return Vector2i(2147483647, 2147483647)
