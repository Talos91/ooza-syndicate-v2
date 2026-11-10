shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;
// WORLD FOG, centre layers: the same two roaming layers as lab_backdrop.gdshader (cloud_amt on top, fog_amt under it), drawn as
// one big plane between the decks and the floor so the CENTRE of the picture is covered too, not only the side bands.
// 0 = absent, 1 = fully opaque where present; cloud 0.9 x fog 0.6 overlapping = 96 % cover.
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float cloud_amt = 0.0;
uniform float fog_amt = 0.0;
uniform vec4 cloud_col : source_color = vec4(0.27, 0.31, 0.38, 1.0);
uniform vec4 fog_col : source_color = vec4(0.2, 0.24, 0.31, 1.0);
uniform float scale = 0.011;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 q = wpos.xz * scale;
	float nf = texture(noise_tex, q * 0.9 + vec2(TIME * 0.006, TIME * -0.003)).r;
	float nc = texture(noise_tex, q * 0.6 + vec2(TIME * -0.009, TIME * 0.004) + 0.37).r;
	float af = fog_amt * smoothstep(0.22, 0.5, nf);
	float ac = cloud_amt * smoothstep(0.25, 0.55, nc);
	float a = 1.0 - (1.0 - af) * (1.0 - ac);
	vec3 col = (fog_col.rgb * af * (1.0 - ac) + cloud_col.rgb * ac) / max(a, 0.0001);
	ALBEDO = col;
	ALPHA = a;
}
