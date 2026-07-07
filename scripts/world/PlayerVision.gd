# scripts/world/PlayerVision.gd
class_name PlayerVision
extends RefCounted

# Fog-of-war knowledge for ONE player: which tiles they have ever seen
# (explored) and which they are watching right now (visible). The fog
# renderer uses an instance for the local player; the enemy AI uses its own
# instance, so both sides play under the same information rules.

var player_id: int

var visible_cells: Dictionary = {}  # Vector2i -> true (current vision)
var explored: Dictionary = {}       # Vector2i -> true (persists forever)
# Chunks whose visible/explored content changed since last consumed;
# the fog renderer uses this to rebuild only affected fog images.
var changed_chunks: Dictionary = {}

func _init(p_player_id: int) -> void:
	player_id = p_player_id

# Recomputes current vision from the player's units and buildings.
func update(tree: SceneTree, world: WorldData) -> void:
	# Receding vision: chunks that had visible cells must repaint too.
	for cell: Vector2i in visible_cells:
		changed_chunks[Constants.tile_to_chunk(cell)] = true
	visible_cells.clear()

	for node: Node in tree.get_nodes_in_group("player_%d" % player_id):
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

func _reveal_circle(world: WorldData, center: Vector2i, radius: int) -> void:
	var r2: int = radius * radius
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > r2:
				continue
			var cell: Vector2i = center + Vector2i(dx, dy)
			visible_cells[cell] = true

			var cc: Vector2i = Constants.tile_to_chunk(cell)
			if not explored.has(cell):
				explored[cell] = true
				# Seeing terrain implies it exists: generate lazily.
				world.get_chunk(cc)
			changed_chunks[cc] = true

func is_visible(cell: Vector2i) -> bool:
	return visible_cells.has(cell)

func is_explored(cell: Vector2i) -> bool:
	return explored.has(cell)

func can_see_entity(entity: Node2D) -> bool:
	return visible_cells.has(Constants.world_to_grid(entity.global_position))

func has_discovered_building(building: Building) -> bool:
	for cell: Vector2i in building.footprint_cells:
		if explored.has(cell):
			return true
	return false
