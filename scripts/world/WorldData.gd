# scripts/world/WorldData.gd
class_name WorldData
extends RefCounted

# The infinite world: a dictionary of lazily generated chunks plus dynamic
# state (building occupancy, resource depletion). All tile queries go
# through here; asking about an ungenerated area generates it on demand.

signal resource_depleted(cell: Vector2i)

# Sentinel player_id meaning "no owner context" for the owner-aware pathing
# variants: gates block everyone, so is_walkable_for/movement_cost_for reduce
# to base walkability. The base is_walkable/movement_cost delegate with this.
const NO_OWNER: int = -1

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

func is_water(cell: Vector2i) -> bool:
	var b: int = get_biome(cell)
	return b == Constants.Biome.WATER_SHALLOW or b == Constants.Biome.WATER_DEEP

# Shore test for water buildings (the dock's requires_adjacent_water gate). True
# if any cell orthogonally adjacent to the base_cell..base_cell+footprint block —
# the ring OUTSIDE the footprint — is water. Shared by CommandRouter._exec_place
# (authority) and GameManager.find_buildable_cell (AI/harness) so the two placement
# paths can never disagree on what "touches water" means.
func footprint_touches_water(base_cell: Vector2i, footprint: Vector2i) -> bool:
	var cells: Dictionary = {}
	for dy in range(footprint.y):
		for dx in range(footprint.x):
			cells[base_cell + Vector2i(dx, dy)] = true
	for cell: Vector2i in cells:
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor: Vector2i = cell + offset
			if cells.has(neighbor):
				continue  # interior edge, not the outer ring
			if is_water(neighbor):
				return true
	return false

func is_walkable(cell: Vector2i) -> bool:
	return is_walkable_for(cell, NO_OWNER)

func is_buildable(cell: Vector2i) -> bool:
	if occupied.has(cell):
		return false
	return Constants.BUILDABLE.get(get_biome(cell), false)

func movement_cost(cell: Vector2i) -> float:
	return movement_cost_for(cell, NO_OWNER)

# --- Owner-aware pathing (palisade gate) ---
# The _for variants are the single source of the occupied/biome logic; the base
# is_walkable/movement_cost above delegate with NO_OWNER, so their "gates block
# everyone" behavior is structural, not merely hand-synced.

# Is this cell walkable FOR a specific player's pathing? Same as is_walkable,
# except the player's OWN constructed palisade gate is passable to them (enemies
# and neutral pathing still see it as blocked). NO_OWNER -> base behavior.
func is_walkable_for(cell: Vector2i, player_id: int, water: bool = false) -> bool:
	if water:
		# Water domain: canoes travel the NAVIGABLE biomes (open water). Buildings
		# still block — there are no water buildings yet, so any occupied cell is
		# impassable regardless of owner (gates are a land-wall concept).
		if occupied.has(cell):
			return false
		return Constants.NAVIGABLE.get(get_biome(cell), false)
	# --- land domain (existing logic, unchanged) ---
	if occupied.has(cell):
		if player_id != NO_OWNER and _is_own_gate(occupied[cell], player_id):
			return true
		return false
	return Constants.WALKABLE.get(get_biome(cell), false)

# Movement cost variant of is_walkable_for: the caller's own constructed gate
# costs the underlying biome (as if unoccupied); everything else matches
# movement_cost. NO_OWNER -> base behavior.
func movement_cost_for(cell: Vector2i, player_id: int, water: bool = false) -> float:
	if water:
		# Water domain: flat WATER_MOVE_COST on navigable cells, INF elsewhere.
		# Buildings block (INF) — see is_walkable_for's water branch.
		if occupied.has(cell):
			return INF
		return Constants.WATER_MOVE_COST if Constants.NAVIGABLE.get(get_biome(cell), false) else INF
	# --- land domain (existing logic, unchanged) ---
	if occupied.has(cell):
		if player_id != NO_OWNER and _is_own_gate(occupied[cell], player_id):
			return Constants.MOVEMENT_COST.get(get_biome(cell), INF)
		return INF
	return Constants.MOVEMENT_COST.get(get_biome(cell), INF)

# True only for a constructed palisade gate owned by player_id. Cheap int
# compare first short-circuits the common non-gate reject before the string test.
func _is_own_gate(b: Node2D, player_id: int) -> bool:
	var building := b as Building
	return building != null and building.player_id == player_id \
		and building.building_type == "palisade_gate" and building.is_constructed

# --- Resources ---

func get_resource_at(cell: Vector2i) -> Dictionary:
	var chunk: ChunkData = get_chunk(Constants.tile_to_chunk(cell))
	return chunk.resources.get(cell, {})

# --- Points of interest ---

func get_poi_at(cell: Vector2i) -> Dictionary:
	var chunk: ChunkData = get_chunk(Constants.tile_to_chunk(cell))
	return chunk.pois.get(cell, {})

# Non-generating variant of get_poi_at: returns {} if the owning chunk has not
# been generated yet (so proximity scanners never force far-off generation —
# same discipline as find_nearest_resource).
func peek_poi_at(cell: Vector2i) -> Dictionary:
	var chunk: ChunkData = chunks.get(Constants.tile_to_chunk(cell))
	if chunk == null:
		return {}
	return chunk.pois.get(cell, {})

# Claimed POIs (one-time rewards already taken). Serialized for save/restore,
# same pattern as resource_deltas — a saved game rebuilds the world from
# (seed + deltas + claimed POIs).
var claimed_pois: Dictionary = {}  # Vector2i cell -> true

func is_poi_claimed(cell: Vector2i) -> bool:
	return claimed_pois.has(cell)

# Marks a POI claimed. Returns true only on the FIRST claim (idempotent);
# false if already claimed or if there is no POI on this cell.
func claim_poi(cell: Vector2i) -> bool:
	if claimed_pois.has(cell):
		return false
	if get_poi_at(cell).is_empty():
		return false
	claimed_pois[cell] = true
	return true

# Unconditionally marks a cell claimed (save-restore only — the POI existence
# check is skipped because the world is rebuilt from the same seed, so the POI
# is guaranteed present). Mirrors set_resource_amount's restore role.
func restore_claimed_poi(cell: Vector2i) -> void:
	claimed_pois[cell] = true

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
