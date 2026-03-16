# scripts/autoloads/Constants.gd
extends Node

# Tile size for isometric grid
const TILE_WIDTH: int = 64
const TILE_HEIGHT: int = 32

# Biome types matching the TS version
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

# Movement costs per biome
const MOVEMENT_COST: Dictionary = {
	Biome.GRASS: 1.0,
	Biome.FOREST_LIGHT: 1.2,
	Biome.FOREST_DENSE: 1.5,
	Biome.WATER_SHALLOW: 2.0,
	Biome.WATER_DEEP: INF,
	Biome.SWAMP: 2.5,
	Biome.CLIFF: INF,
	Biome.HIGH_GROUND: 1.1,
}

# Biome walkability
const WALKABLE: Dictionary = {
	Biome.GRASS: true,
	Biome.FOREST_LIGHT: true,
	Biome.FOREST_DENSE: true,
	Biome.WATER_SHALLOW: true,
	Biome.WATER_DEEP: false,
	Biome.SWAMP: true,
	Biome.CLIFF: false,
	Biome.HIGH_GROUND: true,
}

# Biome colors (placeholder until PixelLab tiles)
const BIOME_COLORS: Dictionary = {
	Biome.GRASS: Color(0.55, 0.76, 0.29),
	Biome.FOREST_LIGHT: Color(0.33, 0.59, 0.24),
	Biome.FOREST_DENSE: Color(0.18, 0.40, 0.14),
	Biome.WATER_SHALLOW: Color(0.40, 0.70, 0.85),
	Biome.WATER_DEEP: Color(0.15, 0.35, 0.60),
	Biome.SWAMP: Color(0.45, 0.50, 0.30),
	Biome.CLIFF: Color(0.50, 0.45, 0.40),
	Biome.HIGH_GROUND: Color(0.60, 0.55, 0.45),
}
