# scripts/art/UnitArtist.gd
class_name UnitArtist
extends RefCounted

# Villager sprites as ASCII pixel maps (12x18), tinted per player.
# Three frames: idle, walk A (left leg forward), walk B (right leg forward).
#
# Palette keys:
#   O outline   H hair   S skin   s skin shadow
#   T tunic     t tunic shadow    F feet

const IDLE_ROWS: Array[String] = [
	"....OOOO....",
	"...OHHHHO...",
	"..OHHHHHHO..",
	"..OHSSSSHO..",
	"..OSSsSSsO..",
	"...OSSSsO...",
	"..OOTTTTOO..",
	".OSOTTTTOsO.",
	".OSOTTTtOsO.",
	".OsOtTTtOsO.",
	"..OOttttOO..",
	"...OttttO...",
	"...OTtTtO...",
	"...OL.OLO...",
	"...OL.OLO...",
	"...OL.OLO...",
	"..OFF.OFFO..",
	"............",
]

const WALK_A_ROWS: Array[String] = [
	"....OOOO....",
	"...OHHHHO...",
	"..OHHHHHHO..",
	"..OHSSSSHO..",
	"..OSSsSSsO..",
	"...OSSSsO...",
	"..OOTTTTOO..",
	".OSOTTTTOsO.",
	".OsOTTTtOSO.",
	"..OOtTTtOO..",
	"...OttttO...",
	"...OttttO...",
	"...OTtTtO...",
	"..OL..OLO...",
	"..OL...OLO..",
	".OFF...OLO..",
	".......OFFO.",
	"............",
]

const WALK_B_ROWS: Array[String] = [
	"....OOOO....",
	"...OHHHHO...",
	"..OHHHHHHO..",
	"..OHSSSSHO..",
	"..OSSsSSsO..",
	"...OSSSsO...",
	"..OOTTTTOO..",
	".OsOTTTTOSO.",
	".OSOTTTtOsO.",
	"..OOtTTtOO..",
	"...OttttO...",
	"...OttttO...",
	"...OTtTtO...",
	"...OLO..LO..",
	"..OLO...LO..",
	"..OLO...FFO.",
	".OFFO.......",
	"............",
]

func build_villager_frames(player_color: Color) -> Array[ImageTexture]:
	var palette: Dictionary = {
		"O": Color8(24, 18, 14),
		"H": Color8(38, 28, 20),
		"S": Color8(196, 144, 100),
		"s": Color8(164, 116, 78),
		"L": Color8(150, 106, 72),
		"T": player_color,
		"t": player_color.darkened(0.35),
		"F": Color8(70, 48, 30),
	}
	var frames: Array[ImageTexture] = []
	var sources: Array = [IDLE_ROWS, WALK_A_ROWS, WALK_B_ROWS]
	for source in sources:
		frames.append(PixelArt.sprite_from_rows(source, palette))
	return frames

func build_selection_ring() -> ImageTexture:
	var img: Image = Image.create(40, 20, false, Image.FORMAT_RGBA8)
	PixelArt.draw_ellipse_ring(img, 20.0, 10.0, 17.0, 8.0, 1.6, Color(0.35, 1.0, 0.45, 0.9))
	return ImageTexture.create_from_image(img)

func build_shadow() -> ImageTexture:
	var img: Image = Image.create(20, 10, false, Image.FORMAT_RGBA8)
	PixelArt.draw_ellipse(img, 10.0, 5.0, 8.0, 3.5, Color(0.0, 0.0, 0.0, 0.35), true)
	return ImageTexture.create_from_image(img)
