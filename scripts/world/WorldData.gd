# scripts/world/WorldData.gd
class_name WorldData
extends RefCounted

# The infinite world: a dictionary of lazily generated chunks plus dynamic
# state (building occupancy, resource depletion). All tile queries go
# through here; asking about an ungenerated area generates it on demand.

signal resource_depleted(cell: Vector2i)

var gen: WorldGen
var chunks: Dictionary = {}   # Vector2i chunk coords -> ChunkData
var occupied: Dictionary = {} # Vector2i cell -> building (Node2D)

func _init(p_seed: int) -> void:
	gen = WorldGen.new(p_seed)

func get_chunk(cc: Vector2i) -> ChunkData:
	var chunk: ChunkData = chunks.get(cc)
	if chunk == null:
		chunk = ChunkData.new(cc, gen)
		chunks[cc] = chunk
	return chunk

func get_biome(cell: Vector2i) -> int:
	var cc: Vector2i = Constants.tile_to_chunk(cell)
	var chunk: ChunkData = get_chunk(cc)
	var size: int = Constants.CHUNK_SIZE
	return chunk.get_biome_local(cell.x - cc.x * size, cell.y - cc.y * size)

func is_walkable(cell: Vector2i) -> bool:
	if occupied.has(cell):
		return false
	return Constants.WALKABLE.get(get_biome(cell), false)

func movement_cost(cell: Vector2i) -> float:
	if occupied.has(cell):
		return INF
	return Constants.MOVEMENT_COST.get(get_biome(cell), INF)

# --- Resources ---

func get_resource_at(cell: Vector2i) -> Dictionary:
	var chunk: ChunkData = get_chunk(Constants.tile_to_chunk(cell))
	return chunk.resources.get(cell, {})

# Removes up to `amount` from the node; returns how much was taken.
# Every harvested cell's remaining amount, so a saved game can rebuild the
# world from (seed + deltas) instead of serializing every chunk.
var resource_deltas: Dictionary = {}

# Force amount on a cell (save restore). 0 erases the node.
func set_resource_amount(cell: Vector2i, amount: int) -> void:
	var chunk: ChunkData = get_chunk(Constants.tile_to_chunk(cell))
	if not chunk.resources.has(cell):
		return
	resource_deltas[cell] = amount
	if amount <= 0:
		chunk.resources.erase(cell)
		resource_depleted.emit(cell)
	else:
		chunk.resources[cell]["amount"] = amount

func take_resource(cell: Vector2i, amount: int) -> int:
	var chunk: ChunkData = get_chunk(Constants.tile_to_chunk(cell))
	var node: Dictionary = chunk.resources.get(cell, {})
	if node.is_empty():
		return 0
	var taken: int = mini(amount, node["amount"])
	node["amount"] -= taken
	resource_deltas[cell] = node["amount"]
	if node["amount"] <= 0:
		chunk.resources.erase(cell)
		resource_depleted.emit(cell)
	return taken

# Nearest resource node of a type within a square search radius (in tiles).
# Only searches already-generated chunks — gatherers shouldn't force
# generation of far-off land. Returns Vector2i or (invalid) via has_result.
func find_nearest_resource(from_cell: Vector2i, type: int, max_radius: int = 24) -> Dictionary:
	var best_cell: Vector2i = Vector2i.ZERO
	var best_dist: float = INF
	var found: bool = false

	var cc_min: Vector2i = Constants.tile_to_chunk(from_cell - Vector2i(max_radius, max_radius))
	var cc_max: Vector2i = Constants.tile_to_chunk(from_cell + Vector2i(max_radius, max_radius))
	for cy in range(cc_min.y, cc_max.y + 1):
		for cx in range(cc_min.x, cc_max.x + 1):
			var chunk: ChunkData = chunks.get(Vector2i(cx, cy))
			if chunk == null:
				continue
			for cell: Vector2i in chunk.resources:
				if chunk.resources[cell]["type"] != type:
					continue
				var dist: float = Vector2(cell - from_cell).length()
				if dist < best_dist and dist <= float(max_radius):
					best_dist = dist
					best_cell = cell
					found = true

	return { "found": found, "cell": best_cell }

# --- Buildings ---

func occupy(cells: Array[Vector2i], building: Node2D) -> void:
	for cell: Vector2i in cells:
		occupied[cell] = building

func vacate(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		occupied.erase(cell)

func building_at(cell: Vector2i) -> Node2D:
	return occupied.get(cell)
