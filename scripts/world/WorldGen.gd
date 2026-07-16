# scripts/world/WorldGen.gd
class_name WorldGen
extends RefCounted

# Pure, deterministic per-tile world function. Valid for ANY integer
# coordinate, which is what makes the world infinite: chunks can be generated
# lazily in any order and always agree with their neighbors (no global passes).

# Fixed player bases (up to 4 tribes). Spawn clearings are carved around
# these; matches use the first N origins.
const PLAYER_ORIGINS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(44, 44), Vector2i(44, 0), Vector2i(0, 44),
]
const CLEARING_RADIUS: float = 9.0
const CLEARING_CORE_RADIUS: float = 5.0

var seed_val: int

var _elevation: FastNoiseLite
var _moisture: FastNoiseLite
var _forest: FastNoiseLite
var _detail: FastNoiseLite
var _river: FastNoiseLite
var _berry: FastNoiseLite

func _init(p_seed: int) -> void:
	seed_val = p_seed

	_elevation = FastNoiseLite.new()
	_elevation.seed = seed_val
	_elevation.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_elevation.frequency = 0.016
	_elevation.fractal_type = FastNoiseLite.FRACTAL_FBM
	_elevation.fractal_octaves = 4

	_moisture = FastNoiseLite.new()
	_moisture.seed = seed_val + 1000
	_moisture.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_moisture.frequency = 0.03
	_moisture.fractal_type = FastNoiseLite.FRACTAL_FBM
	_moisture.fractal_octaves = 3

	_forest = FastNoiseLite.new()
	_forest.seed = seed_val + 2000
	_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest.frequency = 0.045
	_forest.fractal_type = FastNoiseLite.FRACTAL_FBM
	_forest.fractal_octaves = 4

	_detail = FastNoiseLite.new()
	_detail.seed = seed_val + 3000
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 0.12

	# Winding rivers: tiles where |noise| dips near zero form channels.
	_river = FastNoiseLite.new()
	_river.seed = seed_val + 4000
	_river.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_river.frequency = 0.009
	_river.fractal_type = FastNoiseLite.FRACTAL_FBM
	_river.fractal_octaves = 2

	_berry = FastNoiseLite.new()
	_berry.seed = seed_val + 5000
	_berry.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_berry.frequency = 0.07

func _n01(noise: FastNoiseLite, x: int, y: int) -> float:
	return (noise.get_noise_2d(float(x), float(y)) + 1.0) / 2.0

func biome_at(x: int, y: int) -> int:
	var clearing: float = _clearing_factor(x, y)

	# Inside a spawn core everything is buildable grass.
	if clearing >= 1.0:
		return Constants.Biome.GRASS

	var e: float = _n01(_elevation, x, y)
	var m: float = _n01(_moisture, x, y)

	# Rivers and lakes (suppressed inside clearings; fords via detail noise).
	var water: int = _water_at(x, y, e)
	if water != -1:
		if clearing > 0.0:
			return Constants.Biome.WATER_SHALLOW if Constants.WALKABLE[water] else Constants.Biome.GRASS
		return water

	if e > 0.86:
		return Constants.Biome.CLIFF
	if e > 0.76:
		return Constants.Biome.HIGH_GROUND
	if m > 0.68 and e < 0.42:
		return Constants.Biome.SWAMP

	var f: float = _n01(_forest, x, y) * 0.75 + _n01(_detail, x, y) * 0.25
	if clearing > 0.0:
		# Outer clearing ring thins the forest out.
		f -= clearing * 0.5

	if f > 0.62:
		return Constants.Biome.FOREST_DENSE
	if f > 0.47:
		return Constants.Biome.FOREST_LIGHT
	return Constants.Biome.GRASS

# Returns a water biome or -1.
func _water_at(x: int, y: int, e: float) -> int:
	# Lakes in low basins.
	if e < 0.155:
		return Constants.Biome.WATER_DEEP if e < 0.105 else Constants.Biome.WATER_SHALLOW

	# Rivers: |river noise| near zero. High ground pinches them off.
	if e < 0.72:
		var r: float = absf(_river.get_noise_2d(float(x), float(y)))
		if r < 0.042:
			var ford: bool = _n01(_detail, x, y) > 0.62
			if r < 0.018 and not ford:
				return Constants.Biome.WATER_DEEP
			return Constants.Biome.WATER_SHALLOW

	return -1

# 1.0 inside a spawn core, fading to 0.0 at CLEARING_RADIUS.
func _clearing_factor(x: int, y: int) -> float:
	var best: float = 0.0
	for origin: Vector2i in PLAYER_ORIGINS:
		var dist: float = Vector2(x - origin.x, y - origin.y).length()
		if dist <= CLEARING_CORE_RADIUS:
			return 1.0
		if dist < CLEARING_RADIUS:
			best = maxf(best, 1.0 - (dist - CLEARING_CORE_RADIUS) / (CLEARING_RADIUS - CLEARING_CORE_RADIUS))
	return best

# Harvestable resource for a tile, or empty Dictionary.
# {type: ResourceType, amount: int}
func resource_at(x: int, y: int, biome: int) -> Dictionary:
	# Keep spawn cores free for buildings and early movement.
	if _clearing_factor(x, y) >= 1.0:
		return {}

	var h: float = PixelArt.hash2(x, y, seed_val)
	match biome:
		Constants.Biome.FOREST_DENSE:
			if h < 0.02:
				return { "type": Constants.ResourceType.WOOD, "amount": 100,
					"bonus_type": Constants.ResourceType.FOOD }
			if h < 0.30:
				return { "type": Constants.ResourceType.WOOD, "amount": 120 }
		Constants.Biome.FOREST_LIGHT:
			if h < 0.025:
				return { "type": Constants.ResourceType.WOOD, "amount": 100,
					"bonus_type": Constants.ResourceType.FOOD }
			if h < 0.12:
				return { "type": Constants.ResourceType.WOOD, "amount": 100 }
		Constants.Biome.GRASS:
			# Berry patches: gated by a slow noise so bushes cluster.
			if h < 0.16 and _n01(_berry, x, y) > 0.64:
				return { "type": Constants.ResourceType.FOOD, "amount": 100 }
		Constants.Biome.HIGH_GROUND:
			if h < 0.055:
				return { "type": Constants.ResourceType.JADE, "amount": 80 }
		Constants.Biome.WATER_SHALLOW:
			# Fish school along the shore: rivers become worth fighting over
			# (and the caimans agree).
			if h < 0.11 and _has_land_neighbor(x, y):
				return { "type": Constants.ResourceType.FOOD, "amount": 130, "fish": true }
	return {}

func _has_land_neighbor(x: int, y: int) -> bool:
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var biome: int = biome_at(x + offset.x, y + offset.y)
		if biome != Constants.Biome.WATER_SHALLOW and biome != Constants.Biome.WATER_DEEP \
				and Constants.WALKABLE.get(biome, false):
			return true
	return false

# Pure decoration (not harvestable): reeds on swamp, rocks on cliffs.
# Returns "" or a decor id.
func decor_at(x: int, y: int, biome: int) -> String:
	var h: float = PixelArt.hash2(x, y, seed_val + 7)
	match biome:
		Constants.Biome.SWAMP:
			if h < 0.14:
				return "reeds"
		Constants.Biome.CLIFF:
			if h < 0.12:
				return "rock"
		Constants.Biome.HIGH_GROUND:
			if h < 0.04:
				return "rock"
	return ""
