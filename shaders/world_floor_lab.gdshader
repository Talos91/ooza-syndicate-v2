shader_type spatial;
// WORLD COMPLETE LAB (world dressing, 2026-11-07): the lab biome's R5 floor (world_floor.gdshader's lab5 path, same
// texture, gain, haze) with the DISTRICT ENDING a little beyond the board: a rounded box around the board's footprint
// (its own margin per side: x sides, far (-z) top, near (+z) bottom) with a noisy edge, past which the floor fades out
// and the side backdrop (LAB-SIDE A / B on the sky layer) shows through - its crust edges, tanks and pipes frame the
// board. Just inside the edge the floor darkens a touch (a worn lip) so the hand-over to the backdrop has no seam.
render_mode fog_disabled, unshaded, blend_mix, depth_draw_opaque, cull_disabled;

uniform vec3 abyss : source_color = vec3(0.2, 0.17, 0.37);
uniform vec2 centre = vec2(0.0);
uniform float r0 = 40.0;
uniform float r1 = 90.0;
uniform float haze = 0.03;
uniform sampler2D t_lab5 : source_color, hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float lab5_m = 32.0;
uniform float lab5_gain = 1.0;
// the district: xmin, xmax, zmin (far), zmax (near) in world metres - full floor inside, gone fade metres past it
uniform vec4 district = vec4(-60.0, 60.0, -50.0, 60.0);
uniform float corner = 14.0;     // rounded corners (m)
uniform float fade = 12.0;       // metres from full floor to none
uniform float edge_noise = 4.0;  // metres the edge wanders
uniform float lip = 0.22;        // how much darker the floor gets toward its end
uniform vec3 lip_col : source_color = vec3(0.13, 0.15, 0.19);   // the backdrop's middle (LAB_FAR) the lip melts toward

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float district_d(vec2 p) {
	// signed distance to the rounded district box (< 0 inside)
	vec2 c = vec2(district.x + district.y, district.z + district.w) * 0.5;
	vec2 h = vec2(district.y - district.x, district.w - district.z) * 0.5;
	vec2 q = abs(p - c) - h + corner;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 c = texture(t_lab5, p / lab5_m).rgb * lab5_gain;
	float d = district_d(p);
	float n = vnoise(p * 0.09) * 0.65 + vnoise(p * 0.31) * 0.35;
	d += (n - 0.5) * 2.0 * edge_noise;
	float k = smoothstep(-fade * 1.6, 0.0, d);                 // toward the end: the lip
	c = mix(c, lip_col, k * lip);
	float r = length(p - centre);
	c = mix(c, abyss * 0.6, haze + (haze > 0.0 ? (1.0 - haze) * 0.7 * smoothstep(r0 * 0.4, r1, r) : 0.0));
	ALBEDO = c;
	ALPHA = (1.0 - smoothstep(-fade, 0.0, d)) * (1.0 - smoothstep(r0, r1, r));
}
