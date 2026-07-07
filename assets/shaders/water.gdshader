// Animated water overlay. The sprite's texture is a mask rendered by
// TerrainArtist: alpha = water, red = 1.0 on shallow water.
// Draws pixel-quantized drifting wave bands plus sparse glints on top of the
// baked water pixels in the ground texture.
shader_type canvas_item;

uniform float wave_strength : hint_range(0.0, 0.5) = 0.10;
uniform float sparkle_strength : hint_range(0.0, 1.0) = 0.55;
// World position of the sprite's top-left pixel; keeps the wave pattern
// continuous across independently-rendered chunk sprites.
uniform vec2 world_origin = vec2(0.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	if (mask.a < 0.5) {
		discard;
	}

	// Work in world pixel space, quantized to 2px blocks to stay pixel-art.
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 p = floor((world_origin + UV * tex_size) / 2.0);

	// Two drifting diagonal wave bands.
	float band_a = sin(p.x * 0.18 + p.y * 0.36 + TIME * 1.4);
	float band_b = sin(p.x * 0.07 - p.y * 0.21 - TIME * 0.9);
	float wave = (band_a * 0.6 + band_b * 0.4) * 0.5 + 0.5;

	// Sparse glints that re-roll a few times per second.
	float t = floor(TIME * 5.0);
	float n = hash21(p + t * 17.0);
	float glint = step(0.994, n);

	float shallow_boost = 0.6 + 0.4 * mask.r;
	float brightness = wave * wave_strength + glint * sparkle_strength;
	COLOR = vec4(0.85, 0.95, 1.0, brightness * shallow_boost);
}
