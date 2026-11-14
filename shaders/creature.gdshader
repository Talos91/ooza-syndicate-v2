shader_type spatial;
// Horde creature: the approved texture hue-shifted to the owner's seat colour, with the race
// colour as a thin rim accent (GAME-RULES §5).
// ALPHA 24 UNITS v4 (Models/2.0/factions-v4): a v4 unit ships a tint mask (assets/units/<faction>_tint.png, same UVs):
// R = the apparatus neon edges + logo -> painted and lit in the PLAYER colour (tint_color), G = the eye glow; and its
// glTF metallic-roughness map (goo glossy, steel metallic). Mats.creature sets them; the defaults are today's look.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float hue_shift = 0.0;              // in turns
uniform vec3 accent : source_color = vec3(1.0);
uniform float rim_power = 4.0;
uniform float rim_gain = 2.2;
uniform float self_glow = 0.0;
uniform sampler2D tint_tex : hint_default_black, filter_linear_mipmap;
uniform vec3 tint_color : source_color = vec3(1.0);
uniform float tint_mix = 0.0;               // albedo -> tint_color under the mask (0 = no mask)
uniform float tint_glow = 0.0;              // emission of the masked neon (0 = not a v4 unit)
uniform float eye_glow = 0.0;
uniform sampler2D mr_tex : hint_default_white, filter_linear_mipmap;
uniform float use_mr = 0.0;                 // 1 = roughness / metallic from the glTF map (G / B)
uniform float albedo_gain = 1.0;            // v4 goo textures are brighter than the classic ones

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// WALK (Daniele 2026-11-15: "just them moving their tiny legs"): the feet region (low, outside radius leg_r.x..leg_r.y of the body
// axis) sways along the model's forward axis in diagonal pairs, the cycle driven by the DISTANCE the body has travelled along its
// heading (world position), so a unit that stops stands still. leg_amp = 0 turns it off (every other creature).
uniform float leg_amp = 0.0;                // model units (a Rodin unit is ~1.9 tall)
uniform float leg_h = 0.22;                 // feet region height
uniform vec2 leg_r = vec2(0.3, 0.45);       // radius range where the feet are fully weighted
uniform float leg_stride = 0.55;            // metres of travel per leg cycle

void vertex() {
	if (leg_amp > 0.0) {
		float w = (1.0 - smoothstep(0.03, leg_h, VERTEX.y)) * smoothstep(leg_r.x, leg_r.y, length(VERTEX.xz));
		vec3 fwd = normalize(MODEL_MATRIX[2].xyz);
		float ph = dot(MODEL_MATRIX[3].xz, fwd.xz) / leg_stride * 6.2831853 + (VERTEX.x * VERTEX.z > 0.0 ? 0.0 : 3.1415927);
		VERTEX.z += sin(ph) * leg_amp * w;
		VERTEX.y += max(0.0, cos(ph)) * leg_amp * 0.6 * w;
	}
}

void fragment() {
	vec3 tex = texture(albedo_tex, UV).rgb;
	vec3 hsv = rgb2hsv(tex);
	hsv.x = fract(hsv.x + hue_shift);
	vec2 tm = texture(tint_tex, UV).rg;
	ALBEDO = mix(hsv2rgb(hsv) * albedo_gain, tint_color * 0.25, tm.r * tint_mix);   // albedo kept dark: board light lifts it to pastel; the colour rides on the emission
	vec3 base = ALBEDO;
	vec3 mr = texture(mr_tex, UV).rgb;
	ROUGHNESS = mix(0.3, mr.g, use_mr);
	METALLIC = mr.b * use_mr * (1.0 - tm.r);
	ROUGHNESS = mix(ROUGHNESS, 0.9, tm.r);           // lit neon is matte: a glossy steel / goo highlight would whiten the seat colour
	SPECULAR = mix(0.5, 0.0, tm.r);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = accent * rim * rim_gain + base * self_glow * (1.0 - tm.r)   // self_glow: classic units read bright on a dark board
			+ max(mix(vec3(dot(tint_color, vec3(0.333))), tint_color, 1.45), vec3(0.0)) * tm.r * tint_glow + tex * tm.g * eye_glow;
}
