shader_type spatial;
// Horde creature: the approved texture hue-shifted to the owner's seat colour, with the race
// colour as a thin rim accent (GAME-RULES §5). Per-part accent masks come later.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float hue_shift = 0.0;              // in turns
uniform vec3 accent : source_color = vec3(1.0);
uniform float rim_power = 4.0;
uniform float rim_gain = 2.2;
uniform float self_glow = 0.0;

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
	vec3 hsv = rgb2hsv(texture(albedo_tex, UV).rgb);
	hsv.x = fract(hsv.x + hue_shift);
	ALBEDO = hsv2rgb(hsv);
	vec3 base = ALBEDO;
	ROUGHNESS = 0.3;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = accent * rim * rim_gain + base * self_glow;   // self_glow: classic units read bright on a dark board
}
