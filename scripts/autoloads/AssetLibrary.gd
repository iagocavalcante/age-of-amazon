# scripts/autoloads/AssetLibrary.gd
extends Node

# Central cache for all procedurally generated art. Built once at startup;
# everything downstream (units, chunks, buildings, HUD) pulls textures here.

# Per player: {"villager": frames, "warrior": frames} (idle, walk A, walk B)
var unit_frames: Array = []
# Neutral wildlife: species -> frames (idle, walk A, walk B)
var animal_frames: Dictionary = {}
var town_center_textures: Array[ImageTexture] = []
var building_textures: Array[Dictionary] = []  # player_id -> {type -> ImageTexture}
var selection_ring: ImageTexture
var unit_shadow: ImageTexture
var tree_textures: Array[ImageTexture] = []
var fruit_tree_texture: ImageTexture
var rock_texture: ImageTexture
var reeds_texture: ImageTexture
var berry_texture: ImageTexture
var jade_texture: ImageTexture
var fish_texture: ImageTexture
var ruins_texture: ImageTexture

var icons: Dictionary = {}  # "food"/"wood"/"jade"/"pop" -> ImageTexture

var health_bar_bg: StyleBoxFlat
var health_bar_fill: StyleBoxFlat

const ICON_FOOD: Array[String] = [
	"...GG.....",
	"..G..G....",
	".RRr.RR...",
	"RRRRrRRR..",
	"RRRRRRRR..",
	".RRRRRR...",
	"..RRRR....",
	"...RR.....",
]

const ICON_WOOD: Array[String] = [
	"..........",
	".BBBBBBBB.",
	"BobbbbbbbB",
	"BoBbbbbbbB",
	"BobbbbbbbB",
	".BBBBBBBB.",
	"..........",
]

const ICON_JADE: Array[String] = [
	"....J.....",
	"...JJJ....",
	"..JJjJJ...",
	".JJjjjJJ..",
	"..JJjJJ...",
	"...JJJ....",
	"....J.....",
]

const ICON_POP: Array[String] = [
	"...WW.....",
	"...WW.....",
	"..WWWW....",
	".WWWWWW...",
	".W.WW.W...",
	"...WW.....",
	"..W..W....",
	"..W..W....",
]

func _ready() -> void:
	var unit_artist: UnitArtist = UnitArtist.new()
	var building_artist: BuildingArtist = BuildingArtist.new()
	for player_id in range(Constants.PLAYER_COLORS.size()):
		var color: Color = Constants.PLAYER_COLORS[player_id]
		var procedural: Dictionary = {
			"villager": unit_artist.build_villager_frames(color),
			"warrior": unit_artist.build_warrior_frames(color),
			"archer": unit_artist.build_archer_frames(color),
			"hunter": unit_artist.build_hunter_frames(color),
			"shaman": unit_artist.build_shaman_frames(color),
		}
		var frame_set: Dictionary = {}
		for unit_type: String in procedural:
			var painted: Array = _override_unit_frames(unit_type, color, player_id)
			frame_set[unit_type] = painted if not painted.is_empty() \
				else procedural[unit_type]
		unit_frames.append(frame_set)
		var proc_buildings: Dictionary = {
			"town_center": building_artist.build_town_center(color),
			"house": building_artist.build_house(color),
			"barracks": building_artist.build_barracks(color),
			"watchtower": building_artist.build_watchtower(color),
			"storehouse": building_artist.build_storehouse(color),
			"palisade": building_artist.build_palisade(color),
			"palisade_gate": building_artist.build_palisade_gate(color),
			"monument": building_artist.build_monument(color),
		}
		var building_set: Dictionary = {}
		for building_type: String in proc_buildings:
			var override: ImageTexture = _override_texture(
				"building_%s" % building_type, color)
			building_set[building_type] = override if override != null \
				else proc_buildings[building_type]
		town_center_textures.append(building_set["town_center"])
		building_textures.append(building_set)
	selection_ring = unit_artist.build_selection_ring()
	unit_shadow = unit_artist.build_shadow()

	var doodad_artist: DoodadArtist = DoodadArtist.new()
	# Painted Amazon species (kapok, brazil nut, acai) win over the
	# procedural blobs; any missing file falls back to the full procedural
	# set so the forest never goes bare.
	var painted_trees: Array[ImageTexture] = []
	for species: String in ["kapok", "brazil_nut", "acai"]:
		var painted: ImageTexture = _override_neutral("tree_" + species)
		if painted != null:
			painted_trees.append(painted)
	tree_textures = painted_trees if painted_trees.size() == 3 \
		else doodad_artist.build_trees()
	fruit_tree_texture = _override_neutral("tree_fruit")
	if fruit_tree_texture == null:
		fruit_tree_texture = doodad_artist.build_fruit_tree()
	rock_texture = doodad_artist.build_rock()
	reeds_texture = doodad_artist.build_reeds()
	berry_texture = doodad_artist.build_berry_bush()
	jade_texture = doodad_artist.build_jade_deposit()
	fish_texture = doodad_artist.build_fish_school()
	ruins_texture = doodad_artist.build_ruins()

	var animal_artist: AnimalArtist = AnimalArtist.new()
	animal_frames["capybara"] = animal_artist.build_capybara_frames()
	animal_frames["jaguar"] = animal_artist.build_jaguar_frames()
	animal_frames["tapir"] = animal_artist.build_tapir_frames()
	animal_frames["bush_dog"] = animal_artist.build_bush_dog_frames()
	animal_frames["caiman"] = animal_artist.build_caiman_frames()
	for species: String in animal_frames:
		var painted: Array = _override_animal_frames(species)
		if not painted.is_empty():
			animal_frames[species] = painted

	_build_icons()

	health_bar_bg = StyleBoxFlat.new()
	health_bar_bg.bg_color = Color(0.08, 0.09, 0.08, 0.85)
	health_bar_bg.border_color = Color(0.05, 0.06, 0.05, 0.9)
	health_bar_bg.set_border_width_all(1)
	health_bar_bg.set_corner_radius_all(1)

	health_bar_fill = StyleBoxFlat.new()
	health_bar_fill.bg_color = Color(0.30, 0.85, 0.35)
	health_bar_fill.set_corner_radius_all(1)

func _build_icons() -> void:
	var palette: Dictionary = {
		"R": Color8(200, 52, 76), "r": Color8(232, 96, 116),
		"G": Color8(70, 130, 58),
		"B": Color8(88, 60, 34), "b": Color8(130, 92, 52), "o": Color8(170, 130, 84),
		"J": Color8(28, 138, 98), "j": Color8(84, 206, 152),
		"W": Color8(232, 230, 220),
	}
	icons["food"] = PixelArt.sprite_from_rows(ICON_FOOD, palette)
	icons["wood"] = PixelArt.sprite_from_rows(ICON_WOOD, palette)
	icons["jade"] = PixelArt.sprite_from_rows(ICON_JADE, palette)
	icons["pop"] = PixelArt.sprite_from_rows(ICON_POP, palette)

# Painted sprite overrides (see docs/art/ai-sprite-generation.md): magenta
# masters in assets/sprites/ are preferred over procedural art when every
# frame of a unit exists; magenta remaps to the tribe color at load. The
# procedural builders remain the permanent fallback — a missing or deleted
# file can never break the game.
const SPRITE_DIR: String = "res://assets/sprites/"

func _override_unit_frames(unit_type: String, player_color: Color,
		player_id: int) -> Array:
	var frames: Array = []
	for frame: String in ["idle", "walk_a", "walk_b"]:
		# A per-tribe motif file wins over the shared master.
		var tribe_path: String = SPRITE_DIR + "unit_%s_%s_t%d.png" % [
			unit_type, frame, player_id]
		var generic_path: String = SPRITE_DIR + "unit_%s_%s.png" % [unit_type, frame]
		var path: String = tribe_path if ResourceLoader.exists(tribe_path) \
			else generic_path
		if not ResourceLoader.exists(path):
			return []
		frames.append(_load_tinted(path, player_color))
	return frames

func _override_texture(name: String, player_color: Color) -> ImageTexture:
	var path: String = SPRITE_DIR + name + ".png"
	if not ResourceLoader.exists(path):
		return null
	return _load_tinted(path, player_color)

# Untinted override for neutral world art (trees, doodads) — no magenta
# remap, the file is used as painted.
func _override_neutral(name: String) -> ImageTexture:
	var path: String = SPRITE_DIR + name + ".png"
	if not ResourceLoader.exists(path):
		return null
	var texture: Texture2D = load(path)
	var img: Image = texture.get_image()
	img.convert(Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)

func _override_animal_frames(species: String) -> Array:
	var frames: Array = []
	for frame: String in ["idle", "walk_a", "walk_b"]:
		var path: String = SPRITE_DIR + "animal_%s_%s.png" % [species, frame]
		if not ResourceLoader.exists(path):
			return []
		var texture: Texture2D = load(path)
		var img: Image = texture.get_image()
		img.convert(Image.FORMAT_RGBA8)
		frames.append(ImageTexture.create_from_image(img))
	return frames

func _load_tinted(path: String, player_color: Color) -> ImageTexture:
	var texture: Texture2D = load(path)
	var img: Image = texture.get_image()
	img.convert(Image.FORMAT_RGBA8)
	_tint_magenta(img, player_color)
	return ImageTexture.create_from_image(img)

# Magenta-family pixels take the tribe color, keeping their shading value.
# Thresholds match the validated pipeline (quantization darkens magenta).
func _tint_magenta(img: Image, color: Color) -> void:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var p: Color = img.get_pixel(x, y)
			if p.a > 0.0 and p.r8 > 140 and p.b8 > 90 and p.g8 < 110:
				var value: float = (p.r + p.b) / 2.0
				img.set_pixel(x, y, Color(
					color.r * value, color.g * value, color.b * value, p.a))

func get_unit_frames(player_id: int, unit_type: String) -> Array:
	var idx: int = clampi(player_id, 0, unit_frames.size() - 1)
	return unit_frames[idx][unit_type]

func get_town_center_texture(player_id: int) -> ImageTexture:
	return town_center_textures[clampi(player_id, 0, town_center_textures.size() - 1)]

func get_building_texture(building_type: String, player_id: int) -> ImageTexture:
	return building_textures[clampi(player_id, 0, building_textures.size() - 1)][building_type]

func get_animal_frames(species: String) -> Array:
	return animal_frames.get(species, [])

func resource_icon(type: int) -> ImageTexture:
	return icons[Constants.RESOURCE_NAMES[type]]
