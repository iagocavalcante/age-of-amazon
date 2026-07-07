# scripts/art/PixelArt.gd
class_name PixelArt
extends RefCounted

# Shared helpers for the procedural pixel-art pipeline.

# 4x4 Bayer matrix, normalized to 0..1. Used for ordered dithering between
# ramp shades so gradients read as hand-pixelled texture instead of banding.
const BAYER_4X4: Array[float] = [
	0.0 / 16.0, 8.0 / 16.0, 2.0 / 16.0, 10.0 / 16.0,
	12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0, 6.0 / 16.0,
	3.0 / 16.0, 11.0 / 16.0, 1.0 / 16.0, 9.0 / 16.0,
	15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0, 5.0 / 16.0,
]

static func bayer(x: int, y: int) -> float:
	return BAYER_4X4[(y % 4) * 4 + (x % 4)]

# Deterministic 2D hash -> 0..1. Cheap stand-in for per-pixel noise.
static func hash2(x: int, y: int, salt: int = 0) -> float:
	var n: int = x * 374761393 + y * 668265263 + salt * 1442695041
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65535.0

# Picks a shade from a ramp using a 0..1 value plus ordered dithering.
static func ramp_shade(ramp: Array, value: float, x: int, y: int) -> Color:
	var scaled: float = clampf(value, 0.0, 0.999) * ramp.size()
	var idx: int = int(scaled)
	var frac: float = scaled - float(idx)
	if frac > bayer(x, y) and idx < ramp.size() - 1:
		idx += 1
	return ramp[idx] as Color

# Builds a texture from ASCII rows and a char -> Color palette.
# Any char missing from the palette is transparent.
static func sprite_from_rows(rows: Array[String], palette: Dictionary) -> ImageTexture:
	var h: int = rows.size()
	var w: int = 0
	for row: String in rows:
		w = maxi(w, row.length())

	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var row: String = rows[y]
		for x in range(row.length()):
			var ch: String = row[x]
			if palette.has(ch):
				img.set_pixel(x, y, palette[ch])
	return ImageTexture.create_from_image(img)

# Draws a filled ellipse with optional per-pixel alpha falloff at the rim.
static func draw_ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, color: Color, soft: bool = false) -> void:
	var x0: int = maxi(0, int(cx - rx - 1.0))
	var x1: int = mini(img.get_width() - 1, int(cx + rx + 1.0))
	var y0: int = maxi(0, int(cy - ry - 1.0))
	var y1: int = mini(img.get_height() - 1, int(cy + ry + 1.0))

	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx: float = (float(x) - cx) / rx
			var dy: float = (float(y) - cy) / ry
			var d: float = dx * dx + dy * dy
			if d <= 1.0:
				var c: Color = color
				if soft:
					c.a = color.a * clampf(1.0 - d, 0.0, 1.0)
				_blend_pixel(img, x, y, c)

# Draws an anti-aliased ellipse ring (for selection indicators).
static func draw_ellipse_ring(img: Image, cx: float, cy: float, rx: float, ry: float, thickness: float, color: Color) -> void:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var dx: float = (float(x) - cx) / rx
			var dy: float = (float(y) - cy) / ry
			var d: float = sqrt(dx * dx + dy * dy)
			# Distance from the ring in approximate pixel units.
			var px_dist: float = absf(d - 1.0) * minf(rx, ry)
			if px_dist < thickness:
				var alpha: float = clampf(1.0 - (px_dist / thickness), 0.0, 1.0)
				var c: Color = color
				c.a = color.a * alpha
				_blend_pixel(img, x, y, c)

static func _blend_pixel(img: Image, x: int, y: int, c: Color) -> void:
	var dst: Color = img.get_pixel(x, y)
	img.set_pixel(x, y, dst.blend(c))
