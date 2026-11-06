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

void fragment() {
	vec3 tex = texture(albedo_tex, UV).rgb;
	vec3 hsv = rgb2hsv(tex);
	hsv.x = fract(hsv.x + hue_shift);
	vec2 tm = texture(tint_tex, UV).rg;
	ALBEDO = mix(hsv2rgb(hsv) * albedo_gain, tint_color, tm.r * tint_mix);
	vec3 base = ALBEDO;
	vec3 mr = texture(mr_tex, UV).rgb;
	ROUGHNESS = mix(0.3, mr.g, use_mr);
	METALLIC = mr.b * use_mr;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = accent * rim * rim_gain + base * self_glow * (1.0 - tm.r)   // self_glow: classic units read bright on a dark board
			+ tint_color * tm.r * tint_glow + tex * tm.g * eye_glow;
}
