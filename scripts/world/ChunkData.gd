# scripts/world/ChunkData.gd
class_name ChunkData
extends RefCounted

# Persistent data for one CHUNK_SIZE x CHUNK_SIZE block of tiles.
# Generated once, never discarded (only the visuals are streamed).

var coords: Vector2i
var biomes: PackedInt32Array = PackedInt32Array()
var resources: Dictionary = {}  # Vector2i cell -> {type, amount}
var decor: Dictionary = {}      # Vector2i cell -> decor id (String)
var pois: Dictionary = {}       # Vector2i cell -> {type, ...} (see WorldGen.poi_at)

# Visual nodes currently in the scene tree, or null when unloaded.
var visual: Node2D = null          # ground + water sprites
var doodad_visual: Node2D = null   # y-sorted trees/bushes/rocks
# Sprites for resource nodes, so depletion can remove them: cell -> Sprite2D
var resource_sprites: Dictionary = {}
# Sprites for POI landmarks (ancient ruins), so claiming can remove them:
# cell -> Sprite2D
var poi_sprites: Dictionary = {}

func _init(p_coords: Vector2i, gen: WorldGen) -> void:
	coords = p_coords
	var size: int = Constants.CHUNK_SIZE
	biomes.resize(size * size)

	var base_x: int = coords.x * size
	var base_y: int = coords.y * size
	for ly in range(size):
		for lx in range(size):
			var x: int = base_x + lx
			var y: int = base_y + ly
			var biome: int = gen.biome_at(x, y)
			biomes[ly * size + lx] = biome

			# POIs are independent of the resource/decor branch below (a tile
			# with a resource still `continue`s past decor), so populate here.
			var poi: Dictionary = gen.poi_at(x, y, biome)
			if not poi.is_empty():
				pois[Vector2i(x, y)] = poi

			if Constants.WALKABLE.get(biome, false):
				var res: Dictionary = gen.resource_at(x, y, biome)
				if not res.is_empty():
					resources[Vector2i(x, y)] = res
					continue
			var d: String = gen.decor_at(x, y, biome)
			if d != "":
				decor[Vector2i(x, y)] = d

func get_biome_local(lx: int, ly: int) -> int:
	return biomes[ly * Constants.CHUNK_SIZE + lx]
