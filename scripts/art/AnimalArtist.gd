# scripts/art/AnimalArtist.gd
class_name AnimalArtist
extends RefCounted

# Procedural side-view quadrupeds (capybara, jaguar), drawn from ellipses and
# ramp-shaded like the doodads. Three frames each — idle, walk A, walk B — with
# the legs shuffled between walk frames to suggest a gait. Sprites face right;
# the Animal flips horizontally to face left. The visual base (feet) sits at the
# bottom of the image so y-sorting reads correctly.

const CAPYBARA_RAMP: Array[Color] = [
	Color8(72, 52, 36), Color8(98, 72, 50), Color8(122, 92, 64), Color8(146, 112, 80),
]
const JAGUAR_RAMP: Array[Color] = [
	Color8(150, 104, 40), Color8(180, 134, 58), Color8(206, 160, 82), Color8(226, 186, 108),
]

func build_capybara_frames() -> Array[ImageTexture]:
	var cfg: Dictionary = {
		"ramp": CAPYBARA_RAMP,
		"body_rx": 8.5, "body_ry": 5.2,
		"head_dx": 8.0, "head_dy": -1.4, "head_rx": 4.6, "head_ry": 4.2,
		"leg_len": 3.4, "ear_dx": 2.4, "salt": 131,
		"tail": false, "tail_len": 0, "spots": false, "spot_color": Color.BLACK,
	}
	return _frames(cfg)

func build_jaguar_frames() -> Array[ImageTexture]:
	var cfg: Dictionary = {
		"ramp": JAGUAR_RAMP,
		"body_rx": 10.0, "body_ry": 4.3,
		"head_dx": 10.0, "head_dy": 0.4, "head_rx": 4.0, "head_ry": 3.6,
		"leg_len": 4.6, "ear_dx": 2.0, "salt": 233,
		"tail": true, "tail_len": 10, "spots": true, "spot_color": Color8(48, 34, 22),
	}
	return _frames(cfg)

func _frames(cfg: Dictionary) -> Array[ImageTexture]:
	var frames: Array[ImageTexture] = []
	for frame in range(3):
		frames.append(_build(cfg, frame))
	return frames

func _build(cfg: Dictionary, frame: int) -> ImageTexture:
	var w: int = 30
	var h: int = 22
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)

	var ramp: Array = cfg["ramp"]
	var cx: float = w * 0.44
	var body_y: float = h * 0.48
	var rx: float = cfg["body_rx"]
	var ry: float = cfg["body_ry"]
	var head_x: float = cx + cfg["head_dx"]
	var head_y: float = body_y + cfg["head_dy"]
	var hrx: float = cfg["head_rx"]
	var hry: float = cfg["head_ry"]
	var feet_y: float = body_y + ry + cfg["leg_len"]

	# Ground contact shadow.
	PixelArt.draw_ellipse(img, cx, feet_y, rx * 0.85, 2.6, Color(0.0, 0.0, 0.0, 0.28), true)

	# Legs behind the body — the outer pair swings with the walk frame.
	var gait: int = 0
	if frame == 1:
		gait = 2
	elif frame == 2:
		gait = -2
	var leg_xs: Array = [cx - rx * 0.62, cx - rx * 0.18, cx + rx * 0.30, cx + rx * 0.66]
	var leg_swing: Array = [gait, -gait, gait, -gait]
	for i in range(4):
		var lx: int = int(leg_xs[i] + leg_swing[i])
		for yy in range(int(body_y + ry * 0.3), int(feet_y)):
			_px(img, lx, yy, ramp[0])
			_px(img, lx + 1, yy, ramp[0])

	# Tail (predators only), curling up behind.
	if cfg["tail"]:
		var tx0: float = cx - rx * 0.95
		for t in range(int(cfg["tail_len"])):
			var tx: int = int(tx0 - float(t) * 0.7)
			var ty: int = int(body_y - float(t) * 0.55)
			_px(img, tx, ty, ramp[1])
			_px(img, tx, ty + 1, ramp[0])

	# Body and head as filled ellipses in the base shade, then dither-shaded.
	PixelArt.draw_ellipse(img, cx, body_y, rx, ry, ramp[1])
	PixelArt.draw_ellipse(img, head_x, head_y, hrx, hry, ramp[1])

	var light: Vector2 = Vector2(cx - rx * 0.4, body_y - ry)
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).is_equal_approx(ramp[1]):
				var lit: float = clampf(1.0 - Vector2(x, y).distance_to(light) / (rx * 2.3), 0.0, 1.0)
				var speckle: float = PixelArt.hash2(x, y, cfg["salt"])
				var value: float = clampf(lit * 0.72 + speckle * 0.32, 0.0, 1.0)
				img.set_pixel(x, y, PixelArt.ramp_shade(ramp, value, x, y))

	# Rosette spots (predators), sprinkled over the body only.
	if cfg["spots"]:
		var spot: Color = cfg["spot_color"]
		for sx in range(int(cx - rx), int(cx + rx) + 1):
			for sy in range(int(body_y - ry), int(body_y + ry) + 1):
				if sx < 0 or sx >= w or sy < 0 or sy >= h:
					continue
				if img.get_pixel(sx, sy).a > 0.0 and PixelArt.hash2(sx, sy, 707) > 0.87:
					img.set_pixel(sx, sy, spot)

	# Ear, eye, nose.
	PixelArt.draw_ellipse(img, head_x + cfg["ear_dx"], head_y - hry * 0.85, 1.8, 2.1, ramp[0])
	_px(img, int(head_x + hrx * 0.55), int(head_y - hry * 0.1), Color8(20, 16, 12))
	_px(img, int(head_x + hrx), int(head_y + hry * 0.25), Color8(32, 22, 18))

	return ImageTexture.create_from_image(img)

func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, img.get_pixel(x, y).blend(c))
