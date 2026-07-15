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

const WARRIOR_IDLE_ROWS: Array[String] = [
	"....OOOO......",
	"...OEEEEO..V..",
	"..OHHHHHHO.P..",
	"..OHSSSSHO.P..",
	"..OSSsSSsO.P..",
	"...OSSSsO..P..",
	"..OOTTTTOOsP..",
	".OGGOTTTTOsP..",
	".OGGOTTTTOOP..",
	".OGGOtTTtO.P..",
	".OGGOttttO.P..",
	"..OOttttOO.P..",
	"...OTtTtO..P..",
	"...OL.OLO.....",
	"...OL.OLO.....",
	"...OL.OLO.....",
	"..OFF.OFFO....",
	"..............",
]

const WARRIOR_WALK_A_ROWS: Array[String] = [
	"....OOOO......",
	"...OEEEEO..V..",
	"..OHHHHHHO.P..",
	"..OHSSSSHO.P..",
	"..OSSsSSsO.P..",
	"...OSSSsO..P..",
	"..OOTTTTOOsP..",
	".OGGOTTTTOsP..",
	".OGGOTTTTOOP..",
	".OGGOtTTtO.P..",
	"..OOttttOO.P..",
	"...OTtTtO..P..",
	"..OL..OLO.....",
	"..OL...OLO....",
	".OFF...OLO....",
	".......OFFO...",
	"..............",
	"..............",
]

const WARRIOR_WALK_B_ROWS: Array[String] = [
	"....OOOO......",
	"...OEEEEO..V..",
	"..OHHHHHHO.P..",
	"..OHSSSSHO.P..",
	"..OSSsSSsO.P..",
	"...OSSSsO..P..",
	"..OOTTTTOOsP..",
	".OGGOTTTTOsP..",
	".OGGOTTTTOOP..",
	".OGGOtTTtO.P..",
	"..OOttttOO.P..",
	"...OTtTtO..P..",
	"...OLO..LO....",
	"..OLO...LO....",
	"..OLO...FFO...",
	".OFFO.........",
	"..............",
	"..............",
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

func build_warrior_frames(player_color: Color) -> Array[ImageTexture]:
	var palette: Dictionary = {
		"O": Color8(24, 18, 14),
		"H": Color8(38, 28, 20),
		"S": Color8(196, 144, 100),
		"s": Color8(164, 116, 78),
		"L": Color8(150, 106, 72),
		"T": player_color,
		"t": player_color.darkened(0.35),
		"F": Color8(70, 48, 30),
		"E": Color8(230, 186, 66),            # feather crest
		"V": Color8(190, 195, 200),           # spear tip
		"P": Color8(122, 86, 48),             # spear shaft
		"G": player_color.darkened(0.15),     # shield
	}
	var frames: Array[ImageTexture] = []
	var sources: Array = [WARRIOR_IDLE_ROWS, WARRIOR_WALK_A_ROWS, WARRIOR_WALK_B_ROWS]
	for source in sources:
		frames.append(PixelArt.sprite_from_rows(source, palette))
	return frames

# Archer: the villager silhouette carrying a strung bow on the right —
# built by overlaying the bow onto the villager rows so the gait matches.
func build_archer_frames(player_color: Color) -> Array[ImageTexture]:
	var palette: Dictionary = {
		"O": Color8(24, 18, 14),
		"H": Color8(38, 28, 20),
		"S": Color8(196, 144, 100),
		"s": Color8(164, 116, 78),
		"L": Color8(150, 106, 72),
		"T": player_color,
		"t": player_color.darkened(0.35),
		"F": Color8(70, 48, 30),
		"P": Color8(122, 86, 48),      # bow limb
		"B": Color8(224, 216, 196),    # bowstring
	}
	var frames: Array[ImageTexture] = []
	for source: Array in [IDLE_ROWS, WALK_A_ROWS, WALK_B_ROWS]:
		frames.append(PixelArt.sprite_from_rows(_with_bow(source), palette))
	return frames

# Widens each row and draws a curved bow limb plus a straight string.
func _with_bow(rows: Array) -> Array[String]:
	var out: Array[String] = []
	var top: int = 2
	var bottom: int = 12
	for i in range(rows.size()):
		var chars: PackedStringArray = String(rows[i] + "....").split("")
		if i >= top and i <= bottom:
			var mid: float = (top + bottom) / 2.0
			var span: float = (bottom - top) / 2.0
			var bulge: int = int(round(1.6 * (1.0 - pow(absf(i - mid) / span, 2.0))))
			chars[12 + bulge] = "P"
			chars[12] = "B" if bulge > 0 else "P"
		out.append("".join(chars))
	return out

func build_selection_ring() -> ImageTexture:
	var img: Image = Image.create(40, 20, false, Image.FORMAT_RGBA8)
	PixelArt.draw_ellipse_ring(img, 20.0, 10.0, 17.0, 8.0, 1.6, Color(0.35, 1.0, 0.45, 0.9))
	return ImageTexture.create_from_image(img)

func build_shadow() -> ImageTexture:
	var img: Image = Image.create(20, 10, false, Image.FORMAT_RGBA8)
	PixelArt.draw_ellipse(img, 10.0, 5.0, 8.0, 3.5, Color(0.0, 0.0, 0.0, 0.35), true)
	return ImageTexture.create_from_image(img)
