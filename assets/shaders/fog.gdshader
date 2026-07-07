// Age-of-Empires-style fog of war, drawn as a full-screen overlay.
// fog_tex holds one texel per tile: 0 = unexplored (opaque near-black),
// ~0.55 = explored but not watched (dimmed), 1.0 = currently visible
// (fully transparent). Linear filtering gives the soft fog borders.
shader_type canvas_item;

uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec2 cam_pos = vec2(0.0);
uniform float zoom = 1.0;
uniform vec2 vp_size = vec2(1.0);
uniform vec2 window_origin = vec2(0.0); // tile coords of fog_tex texel (0,0)
uniform vec2 window_tiles = vec2(1.0);  // tiles covered by fog_tex

void fragment() {
	vec2 screen_px = UV * vp_size;
	vec2 world = cam_pos + (screen_px - vp_size * 0.5) / zoom;
	// Inverse isometric projection (TILE_WIDTH/2 = 32, TILE_HEIGHT/2 = 16).
	vec2 grid = vec2(
		world.x / 32.0 + world.y / 16.0,
		world.y / 16.0 - world.x / 32.0
	) * 0.5;

	vec2 uv = (grid - window_origin + vec2(0.5)) / window_tiles;
	float v = 0.0;
	if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
		v = texture(fog_tex, uv).r;
	}
	COLOR = vec4(0.0, 0.02, 0.01, 1.0 - v);
}
