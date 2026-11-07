// VAT COLUMN (Daniele, 2026-11-07): the BLUEPRINT hologram an upgrading vat's whole column becomes (entrance, tube,
// platform, the new tier's vat) - filled bottom to top in world space; the build is done when the fill reaches the top.
// Our own look in the HUD palette (cyan #14d3e4 lines, the seat colour in the filled part): additive, unshaded, no
// textures; a depth prepass so only the front faces show (no stacking) - one material shared by every piece of one column.
shader_type spatial;
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_back, shadows_disabled, fog_disabled;

uniform vec4 line_col : source_color = vec4(0.078, 0.827, 0.894, 1.0);   // UiKit.CYAN
uniform vec4 fill_col : source_color = vec4(0.078, 0.827, 0.894, 1.0);   // the owner's colour (set per column)
uniform float y_bot = -16.0;      // the floor under the entrance
uniform float y_top = 4.0;        // the top of the new tier's vat
uniform float fill_y = -16.0;     // world height the fill has reached (vat_column.gd maps progress to it)
uniform float done = 0.0;         // 1: the fill reached the top (no front band)
uniform float grid = 0.5;         // m between blueprint lines
uniform float t = 0.0;            // seconds (scan shimmer)
uniform float strength = 1.0;     // fades the whole column in / out (start, dock)

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float gridline(float v, float w) {
	float f = abs(fract(v / grid + 0.5) - 0.5) * grid;
	return 1.0 - smoothstep(w * 0.5, w, f);
}

void fragment() {
	float fy = fill_y;
	float below = step(wp.y, fy);
	// edges: the rim of every face toward the camera (fresnel) = the blueprint outline
	float rim = pow(1.0 - abs(dot(normalize(wn), normalize(CAMERA_POSITION_WORLD - wp))), 2.2);
	// blueprint lines: height rings every `grid` m on the walls, a sparse 1 m floor-plan grid on flat tops
	float ring = gridline(wp.y, 0.05);
	float plan = 0.45 * max(gridline(wp.x * 0.5, 0.05), gridline(wp.z * 0.5, 0.05));
	float scan = 0.5 + 0.5 * sin(wp.y * 9.0 - t * 6.0);
	float lines = clamp(max(ring, plan) + 1.2 * rim, 0.0, 1.0);
	// unbuilt part: nearly clear - outline, rings, a faint shimmer
	vec3 ghost = mix(line_col.rgb, vec3(1.0), 0.15 * lines);
	float ghost_a = (0.03 + 0.6 * lines) * (0.75 + 0.25 * scan);
	// built part: the owner's colour, solid-ish, thin bands, the outline brighter
	float bands = 0.85 + 0.15 * step(0.5, fract(wp.y * 4.0));
	vec3 built = fill_col.rgb * 0.8 * bands + vec3(0.35) * rim;
	float built_a = 0.7 + 0.25 * lines;
	// the fill front: a bright band at the fill height
	float front = (1.0 - smoothstep(0.0, 0.18, abs(wp.y - fy))) * (1.0 - done);
	vec3 c = mix(ghost, built, below);
	c = mix(c, mix(line_col.rgb, vec3(1.0), 0.5), front);
	ALBEDO = c * max(strength, 1.0);          // (> 1: the dock flash)
	ALPHA = clamp(mix(ghost_a, built_a, below) + front * 0.8, 0.0, 1.0) * clamp(strength, 0.0, 1.0);
}
