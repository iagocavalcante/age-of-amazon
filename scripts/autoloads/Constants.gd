# scripts/autoloads/Constants.gd
extends Node

# Tile size for isometric grid
const TILE_WIDTH: int = 64
const TILE_HEIGHT: int = 32

# Chunk streaming
const CHUNK_SIZE: int = 16  # tiles per chunk side

enum Biome {
	GRASS,
	FOREST_DENSE,
	FOREST_LIGHT,
	WATER_DEEP,
	WATER_SHALLOW,
	SWAMP,
	CLIFF,
	HIGH_GROUND
}

enum ResourceType { FOOD, WOOD, JADE }

const RESOURCE_NAMES: Dictionary = {
	ResourceType.FOOD: "food",
	ResourceType.WOOD: "wood",
	ResourceType.JADE: "jade",
}

# Gathering
const GATHER_INTERVAL: float = 1.2  # seconds per resource unit
const CARRY_CAPACITY: int = 10

# Population: every tribe starts at the base cap; each finished house adds
# HOUSE_POP_BONUS, up to the hard ceiling.
const POPULATION_CAP: int = 20
const HOUSE_POP_BONUS: int = 5
const POPULATION_CEILING: int = 50

# Construction
const BUILD_INTERVAL: float = 0.5      # seconds between a builder's swings
const BUILD_HP_PER_SWING: int = 6      # hp added per swing per villager
const SITE_STARTING_HP_FRACTION: float = 0.1

# Unit definitions
const UNIT_DEFS: Dictionary = {
	"villager": {
		"max_hp": 40,
		"move_speed": 100.0,
		"attack_power": 2,
		"armor": 0,
		"attack_range": 26.0,
		"attack_cooldown": 1.2,
		"vision_range": 200.0,
		"aggressive": false,
		"can_gather": true,
		"cost": { ResourceType.FOOD: 50 },
		"train_time": 6.0,
	},
	"warrior": {
		"max_hp": 70,
		"move_speed": 90.0,
		"attack_power": 7,
		"armor": 1,
		"attack_range": 28.0,
		"attack_cooldown": 1.0,
		"vision_range": 260.0,
		"aggressive": true,
		"can_gather": false,
		"cost": { ResourceType.FOOD: 40, ResourceType.WOOD: 20 },
		"train_time": 9.0,
	},
}

# Neutral wildlife. `food` is the one-time bounty paid to whoever lands the
# killing blow (see ADR 14). Prey flee; predators attack units of any player.
const ANIMAL_NEUTRAL_ID: int = -1
const WILDLIFE_COLOR: Color = Color(0.88, 0.80, 0.44)  # minimap dot

const ANIMAL_DEFS: Dictionary = {
	"capybara": {
		"max_hp": 40,
		"armor": 0,
		"move_speed": 50.0,        # relaxed wander
		"flee_speed": 74.0,        # panicked sprint — slower than a unit, so a
		                           # hunter catches it after a short chase
		"predator": false,
		"flee_radius": 150.0,      # bolts when a unit comes this close
		"food": 100,
	},
	"jaguar": {
		"max_hp": 95,
		"armor": 1,
		"move_speed": 74.0,
		"flee_speed": 74.0,        # predators don't flee
		"predator": true,
		"aggro_radius": 176.0,     # hunts units within this range
		"attack_power": 9,
		"attack_range": 30.0,
		"attack_cooldown": 1.1,
		"food": 200,
	},
}

# Building definitions (footprint in tiles)
# Buildings with a "cost" are player-constructable (villagers build them);
# the town center exists only from the match start.
const BUILDING_DEFS: Dictionary = {
	"town_center": {
		"max_hp": 600,
		"footprint": Vector2i(2, 2),
		"trains": ["villager", "warrior"],
		"vision_tiles": 9,
	},
	"house": {
		"max_hp": 200,
		"footprint": Vector2i(1, 1),
		"trains": [],
		"vision_tiles": 5,
		"cost": {ResourceType.WOOD: 30},
		"pop_bonus": 5,
	},
	"barracks": {
		"max_hp": 400,
		"footprint": Vector2i(2, 2),
		"trains": ["warrior"],
		"vision_tiles": 7,
		"cost": {ResourceType.WOOD: 60, ResourceType.FOOD: 20},
	},
	"watchtower": {
		"max_hp": 250,
		"footprint": Vector2i(1, 1),
		"trains": [],
		"vision_tiles": 16,
		"cost": {ResourceType.WOOD: 40},
	},
}

# Movement costs per biome (keyed by int)
var MOVEMENT_COST: Dictionary = {}
var WALKABLE: Dictionary = {}

# Per-biome color ramps: [shadow, dark, base, light, highlight]
var BIOME_RAMPS: Dictionary = {}

# Flat representative color per biome (minimap, fallbacks)
var BIOME_COLORS: Dictionary = {}

const PLAYER_COLORS: Array[Color] = [
	Color(0.25, 0.55, 0.95),  # Player 0: Blue
	Color(0.90, 0.30, 0.25),  # Player 1: Red
	Color(0.95, 0.80, 0.20),  # Player 2: Yellow
	Color(0.60, 0.35, 0.85),  # Player 3: Purple
]

func _ready() -> void:
	MOVEMENT_COST = {
		Biome.GRASS: 1.0,
		Biome.FOREST_LIGHT: 1.2,
		Biome.FOREST_DENSE: 1.5,
		Biome.WATER_SHALLOW: 2.0,
		Biome.WATER_DEEP: INF,
		Biome.SWAMP: 2.5,
		Biome.CLIFF: INF,
		Biome.HIGH_GROUND: 1.1,
	}

	WALKABLE = {
		Biome.GRASS: true,
		Biome.FOREST_LIGHT: true,
		Biome.FOREST_DENSE: true,
		Biome.WATER_SHALLOW: true,
		Biome.WATER_DEEP: false,
		Biome.SWAMP: true,
		Biome.CLIFF: false,
		Biome.HIGH_GROUND: true,
	}

	BIOME_RAMPS = {
		Biome.GRASS: [
			Color8(74, 120, 44), Color8(96, 148, 54),
			Color8(118, 172, 62), Color8(138, 190, 74), Color8(160, 206, 92),
		],
		Biome.FOREST_LIGHT: [
			Color8(44, 92, 38), Color8(60, 114, 44),
			Color8(78, 134, 52), Color8(96, 152, 60), Color8(116, 168, 72),
		],
		Biome.FOREST_DENSE: [
			Color8(22, 56, 28), Color8(32, 72, 34),
			Color8(42, 88, 40), Color8(54, 102, 48), Color8(68, 116, 56),
		],
		Biome.WATER_SHALLOW: [
			Color8(52, 128, 158), Color8(66, 148, 176),
			Color8(84, 168, 192), Color8(104, 186, 204), Color8(130, 202, 214),
		],
		Biome.WATER_DEEP: [
			Color8(18, 54, 96), Color8(24, 68, 114),
			Color8(30, 82, 130), Color8(38, 96, 144), Color8(48, 110, 156),
		],
		Biome.SWAMP: [
			Color8(58, 66, 36), Color8(74, 84, 44),
			Color8(90, 100, 52), Color8(106, 116, 62), Color8(120, 130, 74),
		],
		Biome.CLIFF: [
			Color8(74, 66, 60), Color8(94, 84, 76),
			Color8(114, 102, 92), Color8(134, 121, 108), Color8(154, 140, 126),
		],
		Biome.HIGH_GROUND: [
			Color8(112, 100, 64), Color8(132, 118, 76),
			Color8(150, 136, 88), Color8(166, 152, 102), Color8(182, 168, 118),
		],
	}

	for biome: int in BIOME_RAMPS:
		var ramp: Array = BIOME_RAMPS[biome]
		BIOME_COLORS[biome] = ramp[2]

# --- Isometric grid <-> world conversion (single source of truth) ---

func grid_to_world(grid_x: int, grid_y: int) -> Vector2:
	var wx: float = (grid_x - grid_y) * TILE_WIDTH / 2.0
	var wy: float = (grid_x + grid_y) * TILE_HEIGHT / 2.0
	return Vector2(wx, wy)

func world_to_grid(world_pos: Vector2) -> Vector2i:
	var gx: float = (world_pos.x / (TILE_WIDTH / 2.0) + world_pos.y / (TILE_HEIGHT / 2.0)) / 2.0
	var gy: float = (world_pos.y / (TILE_HEIGHT / 2.0) - world_pos.x / (TILE_WIDTH / 2.0)) / 2.0
	return Vector2i(int(round(gx)), int(round(gy)))

# Chunk coordinate for a tile (floor division, correct for negatives)
func tile_to_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(cell.x) / CHUNK_SIZE)),
		int(floor(float(cell.y) / CHUNK_SIZE))
	)
