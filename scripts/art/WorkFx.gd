# scripts/art/WorkFx.gd
class_name WorkFx
extends RefCounted

# Tiny, purely cosmetic feedback for work actions: pixel chips that burst
# from a swing, and floating bonus text. Never runs on the headless server;
# nothing here touches the simulation.

const CHIP_COLORS: Dictionary = {
	Constants.ResourceType.WOOD: [Color8(122, 86, 48), Color8(158, 118, 74)],
	Constants.ResourceType.FOOD: [Color8(200, 52, 76), Color8(96, 152, 60)],
	Constants.ResourceType.JADE: [Color8(64, 190, 160), Color8(120, 220, 196)],
}
const DUST: Array = [Color8(180, 152, 80), Color8(146, 112, 80)]

static func chips_for_resource(parent: Node, pos: Vector2, resource_type: int) -> void:
	chips(parent, pos, CHIP_COLORS.get(resource_type, DUST))

static func dust(parent: Node, pos: Vector2) -> void:
	chips(parent, pos, DUST)

# A small burst of 2px squares that arc out and fade.
static func chips(parent: Node, pos: Vector2, colors: Array) -> void:
	if Net.is_headless_server() or parent == null:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for _i in range(5):
		var chip: ColorRect = ColorRect.new()
		chip.color = colors[rng.randi_range(0, colors.size() - 1)]
		chip.size = Vector2(2, 2)
		chip.position = pos + Vector2(rng.randf_range(-3, 3), rng.randf_range(-6, 0))
		chip.z_index = 30
		parent.add_child(chip)
		var drift: Vector2 = Vector2(rng.randf_range(-9, 9), rng.randf_range(-14, -5))
		var tween: Tween = chip.create_tween()
		tween.set_parallel(true)
		tween.tween_property(chip, "position", chip.position + drift, 0.32) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(chip, "modulate:a", 0.0, 0.32)
		tween.chain().tween_callback(chip.queue_free)

# Floating bonus text ("+10 wood"), drifting up and fading.
static func float_text(parent: Node, pos: Vector2, text: String,
		color: Color = Color(1.0, 0.92, 0.6)) -> void:
	if Net.is_headless_server() or parent == null:
		return
	var label: Label = Label.new()
	label.text = text
	label.position = pos + Vector2(-22, -34)
	label.z_index = 40
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)
	var tween: Tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector2(0, -22), 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)
