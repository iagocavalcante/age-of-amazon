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
