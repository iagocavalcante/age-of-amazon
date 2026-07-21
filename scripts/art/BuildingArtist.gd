# scripts/art/BuildingArtist.gd
class_name BuildingArtist
extends RefCounted

# Procedural building sprites. The Town Center is a stepped stone temple
# (2x2 tile footprint) with a banner in the owner's color.

func build_town_center(player_color: Color) -> ImageTexture:
	var w: int = 120
	var h: int = 96
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)

	var stone_dark: Color = Color8(120, 96, 62)
	var stone_mid: Color = Color8(160, 130, 84)
	var stone_light: Color = Color8(196, 164, 108)
	var stone_top: Color = Color8(214, 184, 128)
	var door_color: Color = Color8(42, 30, 18)
	var outline: Color = Color8(52, 38, 22)

	var cx: float = w / 2.0
	var base_y: int = h - 8

	# Ground contact shadow (isometric ellipse roughly matching 2x2 tiles).
	PixelArt.draw_ellipse(img, cx, float(base_y), 56.0, 20.0, Color(0.0, 0.0, 0.0, 0.30), true)

	# Three stepped tiers, drawn as flat-top "iso-ish" slabs.
	var tiers: Array = [
		# [half_width, top_y, bottom_y]
		[52, base_y - 26, base_y],
		[38, base_y - 48, base_y - 22],
		[24, base_y - 68, base_y - 44],
	]
	for tier: Array in tiers:
		var half_w: int = tier[0]
		var top_y: int = tier[1]
		var bottom_y: int = tier[2]
		for y in range(top_y, bottom_y + 1):
			# Slight taper toward the top of each tier.
			var t: float = float(y - top_y) / float(bottom_y - top_y)
			var row_half: int = int(half_w * (0.86 + 0.14 * t))
			for x in range(int(cx) - row_half, int(cx) + row_half + 1):
				var speckle: float = PixelArt.hash2(x, y, 991)
				var shade: Color
				if y <= top_y + 3:
					shade = stone_top
				elif x < int(cx) - row_half + 4:
					shade = stone_light
				elif x > int(cx) + row_half - 5:
					shade = stone_dark
				else:
					shade = PixelArt.ramp_shade([stone_dark, stone_mid, stone_light], 0.35 + speckle * 0.4, x, y)
				img.set_pixel(clampi(x, 0, w - 1), clampi(y, 0, h - 1), shade)
			# Tier outline edges.
			img.set_pixel(clampi(int(cx) - row_half, 0, w - 1), y, outline)
			img.set_pixel(clampi(int(cx) + row_half, 0, w - 1), y, outline)

	# Central stairway.
	for y in range(base_y - 66, base_y + 1):
		var stair_half: int = 7 + int(float(y - (base_y - 66)) * 0.12)
		for x in range(int(cx) - stair_half, int(cx) + stair_half + 1):
			var step: bool = (y % 4) < 2
			img.set_pixel(x, y, stone_light if step else stone_mid)

	# Doorway at the base of the stairs.
	for y in range(base_y - 14, base_y - 1):
		for x in range(int(cx) - 5, int(cx) + 6):
			img.set_pixel(x, y, door_color)

	# Banner poles with player-color flags on the second tier.
	for side: int in [-1, 1]:
		var px: int = int(cx) + side * 34
		for y in range(base_y - 62, base_y - 40):
			img.set_pixel(px, y, outline)
		for fy in range(base_y - 62, base_y - 54):
			for fx in range(1, 9):
				var fx_pos: int = px + side * fx
				if fx_pos >= 0 and fx_pos < w:
					img.set_pixel(fx_pos, fy, player_color if (fx + fy) % 5 != 0 else player_color.darkened(0.25))

	# Top shrine block.
	for y in range(base_y - 78, base_y - 66):
		for x in range(int(cx) - 10, int(cx) + 11):
			img.set_pixel(x, y, stone_top if y < base_y - 70 else door_color)

	return ImageTexture.create_from_image(img)

# 1x1 hut: timber walls under a layered palm roof, player-color door banner.
func build_house(player_color: Color) -> ImageTexture:
	var w: int = 56
	var h: int = 52
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)

	var wood_dark: Color = Color8(96, 68, 42)
	var wood_mid: Color = Color8(130, 94, 58)
	var wood_light: Color = Color8(158, 118, 74)
	var leaf_dark: Color = Color8(56, 88, 44)
	var leaf_mid: Color = Color8(84, 122, 58)
	var leaf_light: Color = Color8(112, 150, 72)
	var outline: Color = Color8(52, 38, 22)
	var door_color: Color = Color8(40, 28, 16)

	var cx: float = w / 2.0
	var base_y: int = h - 6

	PixelArt.draw_ellipse(img, cx, float(base_y), 24.0, 9.0, Color(0, 0, 0, 0.30), true)

	# Walls: vertical timber planks with speckle.
	for y in range(base_y - 18, base_y + 1):
		for x in range(int(cx) - 16, int(cx) + 17):
			var plank: float = PixelArt.hash2(int(x / 3), 0, 41)
			var speckle: float = PixelArt.hash2(x, y, 42)
			img.set_pixel(x, y, PixelArt.ramp_shade(
				[wood_dark, wood_mid, wood_light], 0.3 + plank * 0.3 + speckle * 0.2, x, y))
		img.set_pixel(int(cx) - 16, y, outline)
		img.set_pixel(int(cx) + 16, y, outline)

	# Layered thatch roof, widest at the eaves.
	for y in range(base_y - 34, base_y - 16):
		var t: float = float(y - (base_y - 34)) / 18.0
		var half: int = int(4.0 + t * 20.0)
		for x in range(int(cx) - half, int(cx) + half + 1):
			var band: float = PixelArt.hash2(0, int(y / 3), 43)
			var speckle: float = PixelArt.hash2(x, y, 44)
			img.set_pixel(x, y, PixelArt.ramp_shade(
				[leaf_dark, leaf_mid, leaf_light], 0.25 + band * 0.35 + speckle * 0.25, x, y))
		img.set_pixel(clampi(int(cx) - half, 0, w - 1), y, outline)
		img.set_pixel(clampi(int(cx) + half, 0, w - 1), y, outline)

	# Door with a player-color lintel banner.
	for y in range(base_y - 12, base_y + 1):
		for x in range(int(cx) - 4, int(cx) + 5):
			img.set_pixel(x, y, door_color)
	for x in range(int(cx) - 5, int(cx) + 6):
		img.set_pixel(x, base_y - 13, player_color)
		img.set_pixel(x, base_y - 14, player_color.darkened(0.25))

	return ImageTexture.create_from_image(img)

# 2x2 longhouse: a wide ridge-roofed hall with a spear rack and a
# player-color shield beside the door.
func build_barracks(player_color: Color) -> ImageTexture:
	var w: int = 116
	var h: int = 78
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)

	var wood_dark: Color = Color8(88, 60, 38)
	var wood_mid: Color = Color8(120, 86, 52)
	var wood_light: Color = Color8(150, 110, 68)
	var thatch_dark: Color = Color8(122, 98, 48)
	var thatch_mid: Color = Color8(152, 126, 62)
	var thatch_light: Color = Color8(180, 152, 80)
	var outline: Color = Color8(52, 38, 22)
	var door_color: Color = Color8(38, 26, 15)

	var cx: float = w / 2.0
	var base_y: int = h - 8

	PixelArt.draw_ellipse(img, cx, float(base_y), 52.0, 18.0, Color(0, 0, 0, 0.30), true)

	# Long walls.
	for y in range(base_y - 22, base_y + 1):
		for x in range(int(cx) - 42, int(cx) + 43):
			var plank: float = PixelArt.hash2(int(x / 4), 0, 51)
			var speckle: float = PixelArt.hash2(x, y, 52)
			img.set_pixel(x, y, PixelArt.ramp_shade(
				[wood_dark, wood_mid, wood_light], 0.3 + plank * 0.3 + speckle * 0.2, x, y))
		img.set_pixel(int(cx) - 42, y, outline)
		img.set_pixel(int(cx) + 42, y, outline)

	# Ridged thatch roof.
	for y in range(base_y - 44, base_y - 20):
		var t: float = float(y - (base_y - 44)) / 24.0
		var half: int = int(8.0 + t * 40.0)
		for x in range(int(cx) - half, int(cx) + half + 1):
			var band: float = PixelArt.hash2(0, int(y / 3), 53)
			var speckle: float = PixelArt.hash2(x, y, 54)
			img.set_pixel(x, y, PixelArt.ramp_shade(
				[thatch_dark, thatch_mid, thatch_light], 0.25 + band * 0.35 + speckle * 0.25, x, y))
		img.set_pixel(clampi(int(cx) - half, 0, w - 1), y, outline)
		img.set_pixel(clampi(int(cx) + half, 0, w - 1), y, outline)
	# Ridge pole.
	for x in range(int(cx) - 10, int(cx) + 11):
		img.set_pixel(x, base_y - 45, outline)

	# Doorway.
	for y in range(base_y - 16, base_y + 1):
		for x in range(int(cx) - 7, int(cx) + 8):
			img.set_pixel(x, y, door_color)

	# Player-color shield by the door.
	PixelArt.draw_ellipse(img, cx - 18.0, float(base_y - 9), 5.0, 7.0, player_color, false)
	PixelArt.draw_ellipse(img, cx - 18.0, float(base_y - 9), 2.0, 3.0, player_color.darkened(0.35), false)

	# Spear rack on the right: leaning shafts with stone tips.
	for i in range(4):
		var sx: int = int(cx) + 22 + i * 5
		for y in range(base_y - 20, base_y + 1):
			var lean: int = int(float(base_y - y) * 0.15)
			img.set_pixel(sx + lean, y, wood_light if (y % 5) != 0 else wood_dark)
		img.set_pixel(sx + int(20.0 * 0.15), base_y - 21, Color8(190, 190, 180))

	return ImageTexture.create_from_image(img)

# 2x2 granary: a fat barrel-bodied store hut with woven hoop bands, a conical
# thatch cap, an open storage bay, and stacked grain sacks (one player-color) —
# a squat, rounded silhouette distinct from the longhouse barracks.
func build_storehouse(player_color: Color) -> ImageTexture:
	var w: int = 112
	var h: int = 84
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)

	var wall_dark: Color = Color8(150, 118, 66)
	var wall_mid: Color = Color8(184, 150, 88)
	var wall_light: Color = Color8(212, 182, 116)
	var hoop: Color = Color8(96, 66, 40)
	var thatch_dark: Color = Color8(122, 98, 48)
	var thatch_mid: Color = Color8(152, 126, 62)
	var thatch_light: Color = Color8(180, 152, 80)
	var outline: Color = Color8(52, 38, 22)
	var bay_color: Color = Color8(40, 30, 18)

	var cx: float = w / 2.0
	var base_y: int = h - 8
	var body_top: int = base_y - 40

	PixelArt.draw_ellipse(img, cx, float(base_y), 44.0, 15.0, Color(0, 0, 0, 0.30), true)

	# Barrel body: half-width bulges toward the middle for a rounded silhouette.
	for y in range(body_top, base_y + 1):
		var t: float = float(y - body_top) / float(base_y - body_top)
		var bulge: float = sin(t * PI)  # 0 at top/bottom, 1 at the waist
		var half: int = int(26.0 + bulge * 8.0)
		for x in range(int(cx) - half, int(cx) + half + 1):
			var speckle: float = PixelArt.hash2(x, y, 61)
			var band: float = PixelArt.hash2(0, int(y / 4), 62)
			img.set_pixel(x, y, PixelArt.ramp_shade(
				[wall_dark, wall_mid, wall_light], 0.3 + band * 0.25 + speckle * 0.2, x, y))
		img.set_pixel(clampi(int(cx) - half, 0, w - 1), y, outline)
		img.set_pixel(clampi(int(cx) + half, 0, w - 1), y, outline)

	# Woven hoop bands wrapping the barrel.
	for hy: int in [body_top + 8, body_top + 20, body_top + 32]:
		var ht: float = float(hy - body_top) / float(base_y - body_top)
		var hhalf: int = int(26.0 + sin(ht * PI) * 8.0)
		for x in range(int(cx) - hhalf + 1, int(cx) + hhalf):
			img.set_pixel(x, hy, hoop if (x % 3) != 0 else hoop.darkened(0.25))

	# Conical thatch cap, overhanging the barrel top.
	for y in range(body_top - 26, body_top + 3):
		var ct: float = float(y - (body_top - 26)) / 29.0
		var chalf: int = int(2.0 + ct * 34.0)
		for x in range(int(cx) - chalf, int(cx) + chalf + 1):
			var band: float = PixelArt.hash2(0, int(y / 3), 63)
			var speckle: float = PixelArt.hash2(x, y, 64)
			img.set_pixel(x, y, PixelArt.ramp_shade(
				[thatch_dark, thatch_mid, thatch_light], 0.25 + band * 0.35 + speckle * 0.25, x, y))
		img.set_pixel(clampi(int(cx) - chalf, 0, w - 1), y, outline)
		img.set_pixel(clampi(int(cx) + chalf, 0, w - 1), y, outline)
	# Cap finial with a player-color pennant.
	for y in range(body_top - 34, body_top - 24):
		img.set_pixel(int(cx), y, outline)
	for fy in range(body_top - 34, body_top - 27):
		for fx in range(1, 9):
			img.set_pixel(clampi(int(cx) + fx, 0, w - 1), fy,
				player_color if (fx + fy) % 5 != 0 else player_color.darkened(0.25))

	# Open storage bay (arched dark mouth) where the sacks go in and out.
	for y in range(base_y - 18, base_y + 1):
		var bt: float = float(y - (base_y - 18)) / 18.0
		var bhalf: int = int(10.0 * (1.0 - bt * 0.25))
		for x in range(int(cx) - bhalf, int(cx) + bhalf + 1):
			img.set_pixel(x, y, bay_color)

	# Stacked grain sacks by the bay; the front one carries the tribe color.
	PixelArt.draw_ellipse(img, cx - 24.0, float(base_y - 6), 7.0, 8.0, wall_mid, false)
	PixelArt.draw_ellipse(img, cx - 24.0, float(base_y - 6), 7.0, 8.0, outline, false)
	PixelArt.draw_ellipse(img, cx + 22.0, float(base_y - 7), 8.0, 9.0, player_color, false)
	PixelArt.draw_ellipse(img, cx + 22.0, float(base_y - 4), 4.0, 4.0, player_color.darkened(0.3), true)

	return ImageTexture.create_from_image(img)

# 2x2 jade monument: a carved green monolith on a stone base with gold
# inlays and a jade capstone — the endgame made visible.
func build_monument(player_color: Color) -> ImageTexture:
	var w: int = 96
	var h: int = 120
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)

	var stone_dark: Color = Color8(96, 104, 96)
	var stone_mid: Color = Color8(128, 138, 126)
	var jade_dark: Color = Color8(38, 120, 96)
	var jade_mid: Color = Color8(56, 158, 126)
	var jade_light: Color = Color8(96, 200, 164)
	var gold: Color = Color8(228, 180, 92)
	var outline: Color = Color8(30, 44, 38)

	var cx: float = w / 2.0
	var base_y: int = h - 10

	PixelArt.draw_ellipse(img, cx, float(base_y), 42.0, 15.0, Color(0, 0, 0, 0.3), true)

	# Stone plinth (two steps).
	for step: Array in [[40, base_y - 10, base_y], [30, base_y - 18, base_y - 8]]:
		for y in range(int(step[1]), int(step[2]) + 1):
			for x in range(int(cx) - int(step[0]), int(cx) + int(step[0]) + 1):
				var speckle: float = PixelArt.hash2(x, y, 811)
				img.set_pixel(x, y, stone_dark if speckle < 0.4 else stone_mid)
			img.set_pixel(int(cx) - int(step[0]), y, outline)
			img.set_pixel(int(cx) + int(step[0]), y, outline)

	# The monolith, tapering upward.
	for y in range(base_y - 86, base_y - 16):
		var t: float = float(y - (base_y - 86)) / 70.0
		var half: int = int(10.0 + t * 12.0)
		for x in range(int(cx) - half, int(cx) + half + 1):
			var speckle: float = PixelArt.hash2(x, y, 813)
			var value: float = clampf(0.3 + speckle * 0.4 + (1.0 - t) * 0.25, 0.0, 1.0)
			img.set_pixel(x, y, PixelArt.ramp_shade(
				[jade_dark, jade_mid, jade_light], value, x, y))
		img.set_pixel(int(cx) - half, y, outline)
		img.set_pixel(int(cx) + half, y, outline)
	# Gold inlay bands + carved glyph column.
	for band_y: int in [base_y - 30, base_y - 50, base_y - 70]:
		var t2: float = float(band_y - (base_y - 86)) / 70.0
		var half2: int = int(10.0 + t2 * 12.0)
		for x in range(int(cx) - half2 + 1, int(cx) + half2):
			img.set_pixel(x, band_y, gold)
	for y in range(base_y - 80, base_y - 20, 4):
		img.set_pixel(int(cx), y, jade_dark)
		img.set_pixel(int(cx) + 1, y + 1, jade_dark)

	# Jade capstone with a gold tip, plus the owner's pennant.
	PixelArt.draw_ellipse(img, cx, float(base_y - 88), 7.0, 5.0, jade_light)
	img.set_pixel(int(cx), base_y - 93, gold)
	img.set_pixel(int(cx), base_y - 94, gold)
	for fy in range(base_y - 104, base_y - 96):
		for fx in range(1, 10):
			img.set_pixel(clampi(int(cx) + fx, 0, w - 1), fy,
				player_color if (fx + fy) % 5 != 0 else player_color.darkened(0.25))
	for y in range(base_y - 104, base_y - 88):
		img.set_pixel(int(cx), y, outline)

	return ImageTexture.create_from_image(img)

# 1x1 stilted lookout: long legs, a railed platform, thatch cap, and a tall
# player-color pennant — reads far vision at a glance.
func build_watchtower(player_color: Color) -> ImageTexture:
	var w: int = 52
	var h: int = 92
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)

	var wood_dark: Color = Color8(96, 68, 42)
	var wood_mid: Color = Color8(126, 92, 56)
	var wood_light: Color = Color8(156, 116, 72)
	var leaf_dark: Color = Color8(56, 88, 44)
	var leaf_mid: Color = Color8(84, 122, 58)
	var outline: Color = Color8(52, 38, 22)

	var cx: float = w / 2.0
	var base_y: int = h - 6

	PixelArt.draw_ellipse(img, cx, float(base_y), 20.0, 8.0, Color(0, 0, 0, 0.30), true)

	# Four stilt legs with cross-bracing.
	for side: int in [-1, 1]:
		for leg: int in [10, 16]:
			var lx: int = int(cx) + side * leg
			for y in range(base_y - 40, base_y + 1):
				img.set_pixel(lx, y, wood_mid if (y % 7) != 0 else wood_dark)
	for y in range(base_y - 30, base_y - 8):
		var t: float = float(y - (base_y - 30)) / 22.0
		img.set_pixel(int(cx) - 16 + int(t * 32.0), y, wood_light)
		img.set_pixel(int(cx) + 16 - int(t * 32.0), y, wood_light)

	# Platform with railing.
	for y in range(base_y - 46, base_y - 39):
		for x in range(int(cx) - 20, int(cx) + 21):
			img.set_pixel(x, y, PixelArt.ramp_shade(
				[wood_dark, wood_mid, wood_light],
				0.35 + PixelArt.hash2(x, y, 61) * 0.35, x, y))
	for x in range(int(cx) - 20, int(cx) + 21):
		img.set_pixel(x, base_y - 46, outline)
		img.set_pixel(x, base_y - 39, outline)
	for side: int in [-1, 1]:
		var rx: int = int(cx) + side * 20
		for y in range(base_y - 54, base_y - 45):
			img.set_pixel(rx, y, wood_light)

	# Thatch cap.
	for y in range(base_y - 64, base_y - 52):
		var t: float = float(y - (base_y - 64)) / 12.0
		var half: int = int(3.0 + t * 19.0)
		for x in range(int(cx) - half, int(cx) + half + 1):
			var band: float = PixelArt.hash2(0, int(y / 2), 62)
			img.set_pixel(x, y, leaf_dark if band < 0.5 else leaf_mid)
		img.set_pixel(clampi(int(cx) - half, 0, w - 1), y, outline)
		img.set_pixel(clampi(int(cx) + half, 0, w - 1), y, outline)

	# Player pennant above everything.
	var px: int = int(cx)
	for y in range(base_y - 84, base_y - 62):
		img.set_pixel(px, y, outline)
	for fy in range(base_y - 84, base_y - 76):
		for fx in range(1, 12):
			img.set_pixel(clampi(px + fx, 0, w - 1), fy,
				player_color if (fx + fy) % 5 != 0 else player_color.darkened(0.25))

	return ImageTexture.create_from_image(img)
