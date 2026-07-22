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
	HIGH_GROUND,
	VARZEA,
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
# Fruit trees pay a food bonus alongside the wood haul: each deposit banks
# carrying * this ratio as food (10 wood -> +5 food).
const FRUIT_FOOD_RATIO: float = 0.5

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
		"era": 0,
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
		"era": 0,
		"max_hp": 70,
		"move_speed": 90.0,
		"attack_power": 7,
		"armor": 1,
		"attack_range": 28.0,
		"attack_cooldown": 1.0,
		"vision_range": 260.0,
		"aggressive": true,
		"can_gather": false,
		"military": true,  # combat unit: eligible for the Chiefdom armor buff
		"cost": { ResourceType.FOOD: 40, ResourceType.WOOD: 20 },
		"train_time": 9.0,
	},
	# Villager-line hunter: gathers and builds like a villager, but specializes
	# in wildlife — deals 2x to animals and banks 1.5x the food bounty on a kill.
	# Both bonuses are data-keyed (anti_animal_mult / hunt_food_mult) so only the
	# hunter benefits; every other unit defaults to 1.0 and is unaffected.
	"hunter": {
		"era": 1,
		"max_hp": 45,
		"move_speed": 100.0,
		"attack_power": 4,
		"armor": 0,
		"attack_range": 26.0,
		"attack_cooldown": 1.2,
		"vision_range": 200.0,
		"aggressive": false,
		"can_gather": true,
		"cost": { ResourceType.FOOD: 55, ResourceType.WOOD: 10 },
		"train_time": 6.0,
		"anti_animal_mult": 2.0,   # damage multiplier vs units in the `animals` group
		"hunt_food_mult": 1.5,     # food bounty multiplier when a hunter lands the kill
	},
	# Glass cannon: outranges everything, melts if anything reaches it.
	"archer": {
		"era": 1,
		"max_hp": 45,
		"move_speed": 95.0,
		"attack_power": 8,
		"armor": 0,
		"attack_range": 110.0,
		"attack_cooldown": 1.6,
		"vision_range": 300.0,
		"aggressive": true,
		"can_gather": false,
		"military": true,  # combat unit: eligible for the Chiefdom armor buff
		"cost": { ResourceType.FOOD: 50, ResourceType.WOOD: 30 },
		"train_time": 10.0,
	},
	# Chiefdom support caster: no attack, a passive heal aura that mends nearby
	# wounded allies over time. NOT `military` — support units skip the Chiefdom
	# armor buff (which is warriors/archers only). The heal is data-keyed
	# (heal_aura) so only the shaman heals; every other unit lacks the key and is
	# unaffected (see Unit._tick_heal_aura, a no-op without it).
	"shaman": {
		"era": 2,
		"max_hp": 50,
		"move_speed": 90.0,
		"attack_power": 0,
		"armor": 0,
		"attack_range": 26.0,
		"attack_cooldown": 1.0,
		"vision_range": 200.0,
		"aggressive": false,
		"can_gather": false,
		"cost": { ResourceType.FOOD: 80 },
		"train_time": 12.0,
		# radius world units, heal HP applied every interval seconds to nearby
		# wounded non-shaman allies.
		"heal_aura": { "radius": 96.0, "heal": 3, "interval": 1.0 },
	},
	# Chiefdom water raider: a fast, ranged dugout that rules the rivers. `water`
	# makes it a water unit — it paths on NAVIGABLE biomes only (blocked on land)
	# and launches from the Dock onto an adjacent water cell (see Unit.is_water_unit
	# / Building._spawn_unit). Being ranged (attack_range 110, distance-based combat)
	# it bombards land units on the shore and other canoes WITHOUT ever pathing onto
	# land. `military` earns it the Chiefdom armor buff, like the warrior/archer.
	"war_canoe": {
		"era": 2,
		"water": true,
		"max_hp": 90,
		"move_speed": 110.0,
		"attack_power": 10,
		"armor": 1,
		"attack_range": 110.0,
		"attack_cooldown": 1.6,
		"vision_range": 300.0,
		"aggressive": true,
		"can_gather": false,
		"military": true,  # combat unit: eligible for the Chiefdom armor buff
		"cost": { ResourceType.WOOD: 60, ResourceType.FOOD: 20 },
		"train_time": 14.0,
	},
}

# Neutral wildlife. `food` is the one-time bounty paid to whoever lands the
# killing blow (see ADR 14). Prey flee; predators attack units of any player.
const ANIMAL_NEUTRAL_ID: int = -1
const WILDLIFE_COLOR: Color = Color(0.88, 0.80, 0.44)  # minimap dot
const RUINS_MINIMAP_COLOR: Color = Color(0.85, 0.80, 0.55)  # pale stone/gold dot

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
	# The Amazon's 'elephant': huge, placid, and worth a feast.
	"tapir": {
		"max_hp": 120,
		"armor": 1,
		"move_speed": 44.0,
		"flee_speed": 58.0,
		"predator": false,
		"flee_radius": 130.0,
		"food": 250,
	},
	# Pack hunter — individually weak, dangerous in numbers.
	"bush_dog": {
		"max_hp": 45,
		"armor": 0,
		"move_speed": 80.0,
		"flee_speed": 80.0,
		"predator": true,
		"aggro_radius": 150.0,
		"attack_power": 4,
		"attack_range": 26.0,
		"attack_cooldown": 0.9,
		"food": 60,
	},
	# Water-edge ambusher: barely moves, hits like a log trap.
	"caiman": {
		"max_hp": 130,
		"armor": 3,
		"move_speed": 30.0,
		"flee_speed": 30.0,
		"predator": true,
		"aggro_radius": 90.0,
		"attack_power": 12,
		"attack_range": 30.0,
		"attack_cooldown": 1.4,
		"food": 220,
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
		"era": 0,
		"max_hp": 600,
		"footprint": Vector2i(2, 2),
		"trains": ["villager", "warrior", "hunter"],
		"vision_tiles": 9,
	},
	"house": {
		"era": 0,
		"max_hp": 200,
		"footprint": Vector2i(1, 1),
		"trains": [],
		"vision_tiles": 5,
		"cost": {ResourceType.WOOD: 30},
		"pop_bonus": 5,
	},
	"barracks": {
		"era": 1,
		"max_hp": 400,
		"footprint": Vector2i(2, 2),
		"trains": ["warrior", "archer", "shaman"],
		"vision_tiles": 7,
		"cost": {ResourceType.WOOD: 60, ResourceType.FOOD: 20},
	},
	"watchtower": {
		"era": 0,
		"max_hp": 250,
		"footprint": Vector2i(1, 1),
		"trains": [],
		"vision_tiles": 16,
		"cost": {ResourceType.WOOD: 40},
	},
	# Forward resource drop-off: villagers deposit here when it's nearer than the
	# town center, shortening gather routes. See DROP_OFF_TYPES / Unit._go_deposit.
	"storehouse": {
		"era": 1,
		"max_hp": 250,
		"footprint": Vector2i(2, 2),
		"trains": [],
		"vision_tiles": 6,
		"cost": {ResourceType.WOOD: 50},
	},
	# Cheap Era-1 defensive wall: a 1x1 building whose occupied cell becomes
	# unwalkable, so the pathfinder routes around it (no pathfinder change — see
	# WorldData.is_walkable / occupy). Low cost so players fence long lines; a
	# stake has little sight (vision_tiles 2). Blocks all pathing (occupies its
	# cell); see `palisade_gate` below for the owner-passable variant.
	"palisade": {
		"era": 1,
		"max_hp": 300,
		"footprint": Vector2i(1, 1),
		"trains": [],
		"vision_tiles": 2,
		"cost": {ResourceType.WOOD: 5},
	},
	# Owner-passable wall segment: your units path through it, enemies are blocked
	# (see WorldData.is_walkable_for). A gap in the palisade line you can defend.
	"palisade_gate": {
		"era": 1,
		"max_hp": 250,
		"footprint": Vector2i(1, 1),
		"trains": [],
		"vision_tiles": 2,
		"cost": {ResourceType.WOOD: 10},
	},
	# Shore building: a normal land structure with a placement constraint — its
	# footprint must touch water (requires_adjacent_water), so it sits on the coast.
	# Its trained water units launch onto the adjacent navigable cell rather than
	# onto land (see Building._spawn_unit). Chiefdom-era gateway to the water game.
	"dock": {
		"era": 2,
		"max_hp": 350,
		"footprint": Vector2i(2, 2),
		"trains": ["war_canoe"],
		"vision_tiles": 6,
		"cost": {ResourceType.WOOD: 80},
		"requires_adjacent_water": true,
	},
	# The jade endgame: finish it, defend it for MONUMENT_VICTORY_SECS, win.
	"monument": {
		"era": 2,
		"max_hp": 800,
		"footprint": Vector2i(2, 2),
		"trains": [],
		"vision_tiles": 6,
		"cost": {ResourceType.JADE: 40, ResourceType.WOOD: 100},
	},
}

# Building types that accept gatherer deposits. A villager banks its load at the
# nearest CONSTRUCTED building of one of these types (see Unit._nearest_own_dropoff).
const DROP_OFF_TYPES: Array[String] = ["town_center", "storehouse"]

# Point-of-interest type ids (see WorldGen.poi_at). Kept as string ids — POIs
# are a separate taxonomy from ResourceType/Biome enums and are meant to grow.
const POI_ANCIENT_RUINS: String = "ancient_ruins"

# Per-POI-type data, mirroring UNIT_DEFS / ANIMAL_DEFS / BUILDING_DEFS. A new POI
# type is a data entry here plus a placement rule in WorldGen.poi_at.
const POI_DEFS: Dictionary = {
	POI_ANCIENT_RUINS: {
		"loot": { ResourceType.JADE: 40, ResourceType.WOOD: 60 },
	},
}

# --- Eras (Phase 2) --------------------------------------------------------
# Ascending ages. `advance_cost` is paid to ENTER this era from the previous;
# era 0 has none. `requires_buildings` is a {building_type: count} map of
# buildings that must be FINISHED before advancing INTO this era. `buff` applies
# tribe-wide and is CUMULATIVE via a fold in GameManager.era_buff: each entry
# lists only what its era introduces or changes (later eras override earlier
# keys), so a tunable lives in exactly one place. TUNABLE — grounded in the
# current economy (start 100 food/50 wood; villager 50 food; monument 40 jade).
const ERA_FOREST: int = 0
const ERA_VILLAGE: int = 1
const ERA_CHIEFDOM: int = 2

const ERA_DEFS: Dictionary = {
	ERA_FOREST: {
		"name": "Forest Age",
		"advance_cost": {},
		"requires_buildings": {},
		"buff": {},
	},
	ERA_VILLAGE: {
		"name": "Village Age",
		"advance_cost": { ResourceType.FOOD: 200, ResourceType.WOOD: 100 },
		"requires_buildings": { "house": 2 },
		# What Village introduces: the tribe-wide gather speed buff.
		"buff": { "gather_mult": 1.15 },
	},
	ERA_CHIEFDOM: {
		"name": "Chiefdom Age",
		"advance_cost": { ResourceType.FOOD: 300, ResourceType.WOOD: 200, ResourceType.JADE: 100 },
		"requires_buildings": { "barracks": 1 },
		# Only what Chiefdom introduces: the military armor bonus. gather_mult is
		# inherited from Village via the fold in GameManager.era_buff.
		"buff": { "armor_bonus": 1 },
	},
}

const MONUMENT_VICTORY_SECS: float = 90.0

# Movement costs per biome (keyed by int)
var MOVEMENT_COST: Dictionary = {}
var WALKABLE: Dictionary = {}
var BUILDABLE: Dictionary = {}
# The water domain's inverse of WALKABLE: which biomes a WATER unit (canoe) can
# travel. Built in _ready alongside WALKABLE.
var NAVIGABLE: Dictionary = {}

# Flat cost a water unit pays per navigable cell — canoes glide, so open water is
# cheaper for them than the land MOVEMENT_COST treats shallow water for walkers.
const WATER_MOVE_COST: float = 1.0

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
		Biome.VARZEA: 2.2,
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
		Biome.VARZEA: true,
	}

	# Can a building's footprint occupy this biome? Defaults to WALKABLE, but
	# wetland and shallow water reject construction while still allowing movement.
	BUILDABLE = WALKABLE.duplicate()
	BUILDABLE[Biome.VARZEA] = false
	BUILDABLE[Biome.WATER_SHALLOW] = false

	# Which biomes a WATER unit can travel — the inverse domain of WALKABLE.
	# Only open water (deep + shallow); everything else is not navigable.
	NAVIGABLE = {
		Biome.WATER_DEEP: true,
		Biome.WATER_SHALLOW: true,
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
		Biome.VARZEA: [
			Color8(40, 70, 58), Color8(52, 88, 70),
			Color8(64, 104, 82), Color8(80, 120, 96), Color8(98, 138, 112),
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
