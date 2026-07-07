# scripts/map/IsometricMap.gd
extends Node2D

var map_generator: MapGenerator

@onready var map_sprite: Sprite2D = $MapSprite
@onready var water_sprite: Sprite2D = $WaterSprite

# Called by Main after all nodes are ready, so every listener is already
# connected when map_generated fires (children _ready runs before the
# parent's, which previously made this signal race and never deliver).
func generate() -> void:
	map_generator = MapGenerator.new(GameManager.map_width, GameManager.map_height, GameManager.map_seed)
	map_generator.generate()

	GameManager.map_generator = map_generator
	GameManager.pathfinder = Pathfinder.new(map_generator)

	_render_map()
	EventBus.map_generated.emit(GameManager.map_width, GameManager.map_height)

func _render_map() -> void:
	var artist: TerrainArtist = TerrainArtist.new()
	var result: Dictionary = artist.render_map(map_generator)
	var origin: Vector2 = result["origin"]

	map_sprite.texture = result["ground"]
	map_sprite.centered = false
	map_sprite.position = -origin

	water_sprite.texture = result["water"]
	water_sprite.centered = false
	water_sprite.position = -origin

	var shader: Shader = load("res://assets/shaders/water.gdshader")
	var material_instance: ShaderMaterial = ShaderMaterial.new()
	material_instance.shader = shader
	water_sprite.material = material_instance

# Scatters y-sorted vegetation/rock sprites into the given container.
# Deterministic for a given map seed.
func populate_doodads(container: Node2D) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = map_generator.seed_val + 12000

	for y in range(map_generator.height):
		for x in range(map_generator.width):
			var biome: int = map_generator.get_biome(x, y)
			var texture: Texture2D = null
			var chance: float = 0.0

			match biome:
				Constants.Biome.FOREST_DENSE:
					chance = 0.45
				Constants.Biome.FOREST_LIGHT:
					chance = 0.16
				Constants.Biome.SWAMP:
					chance = 0.14
				Constants.Biome.CLIFF:
					chance = 0.12
				_:
					continue

			if rng.randf() > chance:
				continue

			match biome:
				Constants.Biome.FOREST_DENSE, Constants.Biome.FOREST_LIGHT:
					texture = AssetLibrary.tree_textures[rng.randi() % AssetLibrary.tree_textures.size()]
				Constants.Biome.SWAMP:
					texture = AssetLibrary.reeds_texture
				Constants.Biome.CLIFF:
					texture = AssetLibrary.rock_texture

			var sprite: Sprite2D = Sprite2D.new()
			sprite.texture = texture
			# Anchor at the visual base so y-sort matches the ground point.
			sprite.offset = Vector2(0, -texture.get_height() / 2.0)
			var jitter: Vector2 = Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-6.0, 6.0))
			sprite.position = Constants.grid_to_world(x, y) + jitter
			container.add_child(sprite)
