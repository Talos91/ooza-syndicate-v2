shader_type canvas_item;
// RIVER WORLD: the small sky band at the top of the screen (Daniele 2026-11-15: "the sky is just a tiny backdrop of the top
// part of the screen"; its content barely matters). Drawn on the background canvas layer, so it shows only where the canyon
// does not cover it (world_river.gd ends the canyon's far wall where the screen's top band starts). Placeholder painting,
// procedural: a dusk gradient, soft cloud streaks, a few stars and a distant orbital station (where the platforms go).

uniform vec3 top_col : source_color = vec3(0.13, 0.15, 0.25);
uniform vec3 mid_col : source_color = vec3(0.36, 0.38, 0.47);
uniform vec3 low_col : source_color = vec3(0.62, 0.62, 0.60);
uniform float band = 0.2;          // the share of the screen height the gradient spans (below it: low_col)
uniform float aspect = 2.165;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float y = clamp(uv.y / band, 0.0, 1.0);
	vec3 c = mix(top_col, mid_col, smoothstep(0.0, 0.7, y));
	c = mix(c, low_col, smoothstep(0.55, 1.0, y));
	// cloud streaks
	vec2 q = vec2(uv.x * aspect * 3.0 + TIME * 0.004, uv.y * 26.0);
	float cl = vnoise(q) * 0.6 + vnoise(q * 2.3 + 4.0) * 0.4;
	c = mix(c, low_col * 1.08, smoothstep(0.55, 0.85, cl) * smoothstep(0.15, 0.6, y) * 0.45);
	// stars
	vec2 sg = floor(vec2(uv.x * aspect, uv.y) * 180.0);
	float st = step(0.996, h21(sg)) * (1.0 - smoothstep(0.0, 0.55, y));
	c += vec3(0.8) * st * (0.6 + 0.4 * sin(TIME * 2.0 + h21(sg + 1.0) * 30.0));
	// the station (designer 9 FIX 4: no outline, a soft distant silhouette, left of the score bar, away from the keys)
	vec2 sp = vec2((uv.x - 0.27) * aspect, (uv.y - 0.06) * 2.4);
	float r = length(sp);
	float ring = 1.0 - smoothstep(0.004, 0.016, abs(r - 0.05));
	float hub = 1.0 - smoothstep(0.008, 0.022, r);
	float sil = max(ring, hub) * 0.35;
	c = mix(c, mid_col * 0.8, sil);
	COLOR = vec4(c, 1.0);
}
