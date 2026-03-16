# scripts/utils/PlaceholderTextures.gd
extends Node

var unit_texture: ImageTexture
var selection_circle: ImageTexture

func _ready() -> void:
	unit_texture = _create_diamond_texture(24, 24, Color.WHITE)
	selection_circle = _create_circle_texture(32, Color(0.2, 1.0, 0.2, 0.5))

func _create_diamond_texture(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := w / 2.0
	var cy := h / 2.0

	for y in range(h):
		for x in range(w):
			var dx := absf(x - cx) / cx
			var dy := absf(y - cy) / cy
			if dx + dy <= 1.0:
				img.set_pixel(x, y, color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(img)

func _create_circle_texture(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := size / 2.0
	var radius := center - 1.0

	for y in range(size):
		for x in range(size):
			var dist := Vector2(x, y).distance_to(Vector2(center, center))
			if dist <= radius and dist >= radius - 2.0:
				img.set_pixel(x, y, color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(img)
