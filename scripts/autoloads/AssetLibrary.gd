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
var rock_texture: ImageTexture
var reeds_texture: ImageTexture
var berry_texture: ImageTexture
var jade_texture: ImageTexture

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
	for color: Color in Constants.PLAYER_COLORS:
		unit_frames.append({
			"villager": unit_artist.build_villager_frames(color),
			"warrior": unit_artist.build_warrior_frames(color),
		})
		town_center_textures.append(building_artist.build_town_center(color))
		building_textures.append({
			"town_center": town_center_textures.back(),
			"house": building_artist.build_house(color),
			"barracks": building_artist.build_barracks(color),
			"watchtower": building_artist.build_watchtower(color),
		})
	selection_ring = unit_artist.build_selection_ring()
	unit_shadow = unit_artist.build_shadow()

	var doodad_artist: DoodadArtist = DoodadArtist.new()
	tree_textures = doodad_artist.build_trees()
	rock_texture = doodad_artist.build_rock()
	reeds_texture = doodad_artist.build_reeds()
	berry_texture = doodad_artist.build_berry_bush()
	jade_texture = doodad_artist.build_jade_deposit()

	var animal_artist: AnimalArtist = AnimalArtist.new()
	animal_frames["capybara"] = animal_artist.build_capybara_frames()
	animal_frames["jaguar"] = animal_artist.build_jaguar_frames()

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
