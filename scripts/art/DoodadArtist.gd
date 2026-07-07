# scripts/art/DoodadArtist.gd
class_name DoodadArtist
extends RefCounted

# Generates vegetation and rock textures placed as y-sorted sprites so units
# walk in front of / behind them correctly. All textures put their visual
# "base" (trunk foot, rock bottom) at the bottom-center of the image.

const TREE_VARIANTS: int = 3

func build_trees() -> Array[ImageTexture]:
	var trees: Array[ImageTexture] = []
	for v in range(TREE_VARIANTS):
		trees.append(_build_tree(v))
	return trees

func _build_tree(variant: int) -> ImageTexture:
	var w: int = 34
	var h: int = 44
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)

	var canopy_dark: Color = Color8(26, 66, 32)
	var canopy_mid: Color = Color8(40, 92, 42)
	var canopy_light: Color = Color8(62, 118, 54)
	var canopy_glow: Color = Color8(88, 142, 66)
	var trunk_dark: Color = Color8(58, 40, 26)
	var trunk_mid: Color = Color8(84, 60, 38)

	var cx: float = w / 2.0
	var base_y: float = h - 2.0

	# Ground contact shadow.
	PixelArt.draw_ellipse(img, cx, base_y, 10.0, 3.5, Color(0.0, 0.0, 0.0, 0.30), true)

	# Trunk.
	var trunk_top: int = 18
	for y in range(trunk_top, int(base_y)):
		var lean: int = int(sin(float(variant) * 2.1 + float(y) * 0.12) * 1.5)
		for dx in range(-1, 2):
			var px: int = int(cx) + dx + lean
			img.set_pixel(px, y, trunk_dark if dx < 1 else trunk_mid)

	# Canopy: stacked blobs, lit from the upper-left.
	var blobs: Array = [
		[cx, 14.0, 13.0, 9.0],
		[cx - 7.0, 18.0, 8.0, 6.0],
		[cx + 7.0, 18.0, 8.0, 6.0],
		[cx + (2.0 if variant % 2 == 0 else -3.0), 8.0, 8.0, 6.0],
	]
	for blob: Array in blobs:
		PixelArt.draw_ellipse(img, blob[0], blob[1], blob[2], blob[3], canopy_dark)

	# Dithered inner shading.
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).is_equal_approx(canopy_dark):
				var lit: float = clampf(1.0 - (Vector2(x, y).distance_to(Vector2(cx - 6.0, 8.0)) / 22.0), 0.0, 1.0)
				var speckle: float = PixelArt.hash2(x, y, variant * 311)
				var value: float = clampf(lit * 0.8 + speckle * 0.35, 0.0, 1.0)
				var shade: Color = PixelArt.ramp_shade([canopy_dark, canopy_mid, canopy_light, canopy_glow], value, x, y)
				img.set_pixel(x, y, shade)

	return ImageTexture.create_from_image(img)

func build_rock() -> ImageTexture:
	var w: int = 18
	var h: int = 14
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var dark: Color = Color8(80, 72, 66)
	var mid: Color = Color8(110, 100, 90)
	var light: Color = Color8(140, 128, 114)

	PixelArt.draw_ellipse(img, w / 2.0, h - 3.0, 7.5, 3.0, Color(0.0, 0.0, 0.0, 0.25), true)
	PixelArt.draw_ellipse(img, w / 2.0, h - 6.0, 7.0, 5.0, mid)
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).is_equal_approx(mid):
				var value: float = clampf(0.9 - float(x + y * 2) / float(w + h * 2) * 1.4 + PixelArt.hash2(x, y, 555) * 0.3, 0.0, 1.0)
				img.set_pixel(x, y, PixelArt.ramp_shade([dark, mid, light], 1.0 - value, x, y))
	return ImageTexture.create_from_image(img)

func build_reeds() -> ImageTexture:
	var w: int = 16
	var h: int = 18
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var stem_dark: Color = Color8(76, 92, 40)
	var stem_light: Color = Color8(120, 138, 62)
	var tip: Color = Color8(158, 158, 84)

	PixelArt.draw_ellipse(img, w / 2.0, h - 2.0, 6.0, 2.5, Color(0.0, 0.0, 0.0, 0.20), true)

	for i in range(5):
		var bx: int = 3 + i * 2 + (i % 2)
		var stem_h: int = 9 + int(PixelArt.hash2(i, 0, 99) * 6.0)
		for j in range(stem_h):
			var y: int = h - 3 - j
			var sway: int = int(sin(float(i) * 1.7 + float(j) * 0.35) * 1.2)
			var x: int = clampi(bx + sway, 0, w - 1)
			var c: Color = stem_dark
			if j > stem_h - 3:
				c = tip
			elif j > int(stem_h / 2.0):
				c = stem_light
			img.set_pixel(x, y, c)

	return ImageTexture.create_from_image(img)
