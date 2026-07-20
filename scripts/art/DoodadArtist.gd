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

# Fallback fruit tree: the variant-0 tree with red fruit speckled through
# the canopy (the painted override is tree_fruit.png).
func build_fruit_tree() -> ImageTexture:
	var base: ImageTexture = _build_tree(0)
	var img: Image = base.get_image()
	var fruit: Color = Color8(206, 58, 60)
	var fruit_light: Color = Color8(238, 108, 96)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var p: Color = img.get_pixel(x, y)
			if p.a > 0.0 and p.g > p.r and p.g > p.b and y < 24 \
					and PixelArt.hash2(x, y, 977) > 0.93:
				img.set_pixel(x, y, fruit)
				if y > 0 and img.get_pixel(x, y - 1).a > 0.0:
					img.set_pixel(x, y - 1, fruit_light)
	return ImageTexture.create_from_image(img)

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

func build_berry_bush() -> ImageTexture:
	var w: int = 22
	var h: int = 18
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var leaf_dark: Color = Color8(38, 84, 40)
	var leaf_mid: Color = Color8(56, 108, 50)
	var leaf_light: Color = Color8(76, 128, 60)
	var berry: Color = Color8(196, 48, 72)
	var berry_light: Color = Color8(228, 88, 108)

	PixelArt.draw_ellipse(img, w / 2.0, h - 3.0, 9.0, 3.0, Color(0.0, 0.0, 0.0, 0.25), true)
	PixelArt.draw_ellipse(img, w / 2.0, h - 8.0, 9.0, 6.0, leaf_dark)
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).is_equal_approx(leaf_dark):
				var lit: float = clampf(1.0 - (Vector2(x, y).distance_to(Vector2(w / 2.0 - 3.0, h - 12.0)) / 12.0), 0.0, 1.0)
				var speckle: float = PixelArt.hash2(x, y, 777)
				var value: float = clampf(lit * 0.7 + speckle * 0.4, 0.0, 1.0)
				img.set_pixel(x, y, PixelArt.ramp_shade([leaf_dark, leaf_mid, leaf_light], value, x, y))

	# Berries sprinkled over the canopy.
	for i in range(7):
		var bx: int = 4 + int(PixelArt.hash2(i, 3, 555) * (w - 8))
		var by: int = h - 12 + int(PixelArt.hash2(i, 9, 556) * 6.0)
		if img.get_pixel(bx, by).a > 0.0:
			img.set_pixel(bx, by, berry)
			if bx + 1 < w and img.get_pixel(bx + 1, by).a > 0.0:
				img.set_pixel(bx + 1, by, berry_light)

	return ImageTexture.create_from_image(img)

# Shore fish school: ripple rings and darting silver fish.
func build_fish_school() -> ImageTexture:
	var w: int = 34
	var h: int = 18
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var ripple: Color = Color(0.85, 0.95, 1.0, 0.5)
	var fish: Color = Color8(214, 218, 224)
	var fin: Color = Color8(150, 160, 175)
	PixelArt.draw_ellipse_ring(img, 12.0, 9.0, 9.0, 4.0, 1.1, ripple)
	PixelArt.draw_ellipse_ring(img, 23.0, 12.0, 6.0, 2.8, 1.0, Color(ripple, 0.35))
	for f: Array in [[10, 8, 1], [16, 11, -1], [22, 6, 1]]:
		var fx: int = f[0]
		var fy: int = f[1]
		var dir: int = f[2]
		for i in range(4):
			img.set_pixel(fx + i * dir, fy, fish)
		img.set_pixel(fx - dir, fy, fin)
		img.set_pixel(fx + 4 * dir, fy - 1, fin)
	return ImageTexture.create_from_image(img)

func build_jade_deposit() -> ImageTexture:
	var w: int = 20
	var h: int = 16
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var stone_dark: Color = Color8(84, 78, 70)
	var stone_mid: Color = Color8(112, 104, 92)
	var jade_dark: Color = Color8(24, 128, 92)
	var jade_light: Color = Color8(64, 190, 140)

	PixelArt.draw_ellipse(img, w / 2.0, h - 3.0, 8.5, 3.0, Color(0.0, 0.0, 0.0, 0.25), true)
	PixelArt.draw_ellipse(img, w / 2.0, h - 7.0, 8.0, 5.5, stone_mid)
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).is_equal_approx(stone_mid):
				var value: float = clampf(0.5 + (PixelArt.hash2(x, y, 888) - 0.5) * 0.8, 0.0, 1.0)
				img.set_pixel(x, y, PixelArt.ramp_shade([stone_dark, stone_mid], value, x, y))

	# Jade crystal veins poking out of the rock.
	var veins: Array = [[7, 6], [12, 5], [10, 9], [14, 8]]
	for vein: Array in veins:
		var vx: int = vein[0]
		var vy: int = vein[1]
		img.set_pixel(vx, vy, jade_light)
		img.set_pixel(vx, vy + 1, jade_dark)
		if vx + 1 < w:
			img.set_pixel(vx + 1, vy + 1, jade_dark)

	return ImageTexture.create_from_image(img)

# Ancient ruins landmark: a low crumbling slab with a few broken pale-grey
# stone pillars of varying heights — a weathered monument, distinct from the
# single boulder of build_rock and the vein-flecked rock of build_jade_deposit.
func build_ruins() -> ImageTexture:
	var w: int = 26
	var h: int = 22
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var stone_dark: Color = Color8(120, 116, 104)
	var stone_mid: Color = Color8(168, 162, 148)
	var stone_light: Color = Color8(206, 200, 184)
	var moss: Color = Color8(96, 128, 78)

	var cx: float = w / 2.0
	var base_y: float = h - 3.0

	# Ground contact shadow.
	PixelArt.draw_ellipse(img, cx, base_y, 11.0, 3.5, Color(0.0, 0.0, 0.0, 0.28), true)

	# Crumbling base slab the pillars stand on.
	var slab_top: int = h - 7
	for y in range(slab_top, h - 2):
		for x in range(3, w - 3):
			var value: float = clampf(0.55 + (PixelArt.hash2(x, y, 611) - 0.5) * 0.7, 0.0, 1.0)
			img.set_pixel(x, y, PixelArt.ramp_shade([stone_dark, stone_mid, stone_light], value, x, y))

	# Broken pillars: [base_x, width, height], deterministic heights.
	var pillars: Array = [
		[5, 3, 14],
		[11, 4, 18],
		[18, 3, 11],
	]
	for pillar: Array in pillars:
		var px: int = pillar[0]
		var pw: int = pillar[1]
		var ph: int = pillar[2]
		var top: int = slab_top - ph
		for y in range(maxi(top, 0), slab_top):
			for dx in range(pw):
				var x: int = px + dx
				if x >= w:
					continue
				# Jagged crown: crumble a bite out of the top rows.
				if y < top + 2 and PixelArt.hash2(x, y, 733) > 0.6:
					continue
				# Lit from the upper-left, dithered for weathered texture.
				var lit: float = 1.0 - float(dx) / float(pw)
				var value: float = clampf(0.4 + lit * 0.5 + (PixelArt.hash2(x, y, 421) - 0.5) * 0.4, 0.0, 1.0)
				img.set_pixel(x, y, PixelArt.ramp_shade([stone_dark, stone_mid, stone_light], value, x, y))

	# Moss speckles clinging to the old stone.
	for i in range(6):
		var mx: int = 4 + int(PixelArt.hash2(i, 5, 271) * (w - 8))
		var my: int = slab_top - 2 - int(PixelArt.hash2(i, 8, 272) * 8.0)
		if my >= 0 and my < h and img.get_pixel(mx, my).a > 0.0:
			img.set_pixel(mx, my, moss)

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
