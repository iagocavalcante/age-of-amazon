# scripts/autoloads/AssetLibrary.gd
extends Node

# Central cache for all procedurally generated art. Built once at startup;
# everything downstream (units, map, doodads) pulls textures from here.

var villager_frames: Array = []  # per player: Array[ImageTexture] (idle, walk A, walk B)
var selection_ring: ImageTexture
var unit_shadow: ImageTexture
var tree_textures: Array[ImageTexture] = []
var rock_texture: ImageTexture
var reeds_texture: ImageTexture

var health_bar_bg: StyleBoxFlat
var health_bar_fill: StyleBoxFlat

func _ready() -> void:
	var unit_artist: UnitArtist = UnitArtist.new()
	for color: Color in Constants.PLAYER_COLORS:
		villager_frames.append(unit_artist.build_villager_frames(color))
	selection_ring = unit_artist.build_selection_ring()
	unit_shadow = unit_artist.build_shadow()

	var doodad_artist: DoodadArtist = DoodadArtist.new()
	tree_textures = doodad_artist.build_trees()
	rock_texture = doodad_artist.build_rock()
	reeds_texture = doodad_artist.build_reeds()

	health_bar_bg = StyleBoxFlat.new()
	health_bar_bg.bg_color = Color(0.08, 0.09, 0.08, 0.85)
	health_bar_bg.border_color = Color(0.05, 0.06, 0.05, 0.9)
	health_bar_bg.set_border_width_all(1)
	health_bar_bg.set_corner_radius_all(1)

	health_bar_fill = StyleBoxFlat.new()
	health_bar_fill.bg_color = Color(0.30, 0.85, 0.35)
	health_bar_fill.set_corner_radius_all(1)

func get_villager_frames(player_id: int) -> Array:
	var idx: int = clampi(player_id, 0, villager_frames.size() - 1)
	return villager_frames[idx]
