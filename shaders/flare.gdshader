shader_type spatial;
// Glow sprites for CombatFx. mode 0: a star flare (camera-facing: muzzle flash, impact burst); mode 1: a
// flickering ground glow (the laser's scorch, flat on a PlaneMesh); mode 2: a shock ring (flat on a
// PlaneMesh: the tier-down's dust wave). Additive, unshaded.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform float intensity = 1.0;
uniform int mode = 0;
uniform float spin = 0.0;
uniform float thickness = 0.12;
uniform float seed = 0.0;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	if (mode == 0) {                                                  // billboard, keeping the scale
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
				vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
				vec4(0.0, 0.0, 0.0, 1.0));
	}
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	vec3 c = vec3(0.0);
	if (mode == 0) {
		float cs = cos(spin);
		float sn = sin(spin);
		vec2 p = vec2(cs * q.x - sn * q.y, sn * q.x + cs * q.y);
		vec2 p2 = vec2(0.7071 * (p.x - p.y), 0.7071 * (p.x + p.y));
		float rays = exp(-abs(p.x) * 26.0) * exp(-abs(p.y) * 2.4) + exp(-abs(p.y) * 26.0) * exp(-abs(p.x) * 2.4);
		rays += 0.45 * (exp(-abs(p2.x) * 38.0) * exp(-abs(p2.y) * 4.0) + exp(-abs(p2.y) * 38.0) * exp(-abs(p2.x) * 4.0));
		float g = exp(-r * r * 5.5);
		float core = exp(-r * r * 38.0);
		c = color.rgb * (g * 1.2 + rays * 1.1) + vec3(1.0) * (core * 1.7 + rays * 0.3);
		c *= 1.0 - smoothstep(0.8, 1.0, r);
	} else if (mode == 1) {
		float g = exp(-r * r * 3.5) * (1.0 - smoothstep(0.75, 1.0, r));
		float n = noise2(q * 5.0 + vec2(seed, TIME * 3.0)) * 0.6 + noise2(q * 11.0 - vec2(TIME * 5.0, seed)) * 0.4;
		float embers = smoothstep(0.55, 0.9, n) * g;
		c = color.rgb * (g * 0.6 + embers * 1.6) * (0.75 + 0.25 * sin(TIME * 23.0 + seed));
	} else {
		float band = exp(-pow((r - 0.82) / max(thickness, 0.01), 2.0));
		c = color.rgb * band * 1.3 + vec3(1.0) * pow(band, 6.0) * 0.8;
		c *= 1.0 - smoothstep(0.95, 1.0, r);
	}
	ALBEDO = c * intensity;
	ALPHA = 1.0;
}
