shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;
// WORLD FOG, centre layers: the same two roaming layers as lab_backdrop.gdshader (cloud_amt on top, fog_amt under it), drawn as
// one big plane between the decks and the floor so the CENTRE of the picture is covered too, not only the side bands.
// 0 = absent, 1 = fully opaque where present; cloud 0.9 x fog 0.6 overlapping = 96 % cover.
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float cloud_amt = 0.0;
uniform float fog_amt = 0.0;
uniform float cloud_density = 0.55;
uniform float fog_density = 0.55;
uniform vec4 cloud_col : source_color = vec4(0.27, 0.31, 0.38, 1.0);
uniform vec4 fog_col : source_color = vec4(0.2, 0.24, 0.31, 1.0);
uniform vec4 fog_col_b : source_color = vec4(0.2, 0.24, 0.31, 1.0);   // the second faction's fog colour
uniform float fog_split = 1.0;        // share of the fog that is fog_col (the rest is fog_col_b): patches, not a blend
uniform float scale = 0.011;
uniform vec2 zone_c = vec2(0.0);       // the centre switcher's domain: the board's footprint (world x z)
uniform vec2 zone_h = vec2(1000.0);    // half extents; outside it the layers fade to nothing (the SIDES switcher owns that)
uniform float zone_fade = 0.35;        // fade width as a share of the half extent
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 q = wpos.xz * scale;
	float nf = texture(noise_tex, q * 0.9 + vec2(TIME * 0.006, TIME * -0.003)).r;
	float nc = texture(noise_tex, q * 0.6 + vec2(TIME * -0.009, TIME * 0.004) + 0.37).r;
	float af = fog_amt * smoothstep(mix(0.62, -0.1, fog_density), mix(0.62, -0.1, fog_density) + 0.28, nf);
	float ac = cloud_amt * smoothstep(mix(0.62, -0.1, cloud_density), mix(0.62, -0.1, cloud_density) + 0.3, nc);
	float nm = texture(noise_tex, q * 0.33 + vec2(TIME * 0.004, TIME * 0.0025) + 0.71).r;
	float um = clamp(smoothstep(0.3, 0.7, nm), 0.0, 1.0) * 0.56 + 0.22;
	vec3 fcol = mix(fog_col_b.rgb, fog_col.rgb, smoothstep(-0.2, 0.2, fog_split - um));   // patches of each faction's colour, by its share
	float e = length((wpos.xz - zone_c) / zone_h);
	float zone = 1.0 - smoothstep(1.0, 1.0 + zone_fade, e);
	af *= zone;
	ac *= zone;
	float a = 1.0 - (1.0 - af) * (1.0 - ac);
	vec3 col = (fcol * af * (1.0 - ac) + cloud_col.rgb * ac) / max(a, 0.0001);
	ALBEDO = col;
	ALPHA = a;
}
