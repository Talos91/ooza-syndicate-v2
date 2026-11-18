shader_type spatial;
// ROUND 44 B4 REAL 3D PIT (bg-44b4 job c, pit_3d.gd): the pit's walls + floor in ONE mesh, one draw. Steep irregular crust walls
// from the painted shoreline down to the river bed; crust greys (sampled from the painted crust round the hole), one small noise
// texture applied triplanar, darker with depth (COLOR.r = 0 at the rim .. 1 at the floor), the floor a little wetter / darker.
// Clipped by the painted crust and under the painted rim (pit_frame.gdshaderinc).
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;
#include "res://shaders/pit_frame.gdshaderinc"

uniform sampler2D grain : repeat_enable, filter_linear_mipmap;   // one small seamless noise (generated at run time, not in the pck)
uniform vec3 crust_col : source_color = vec3(0.42, 0.42, 0.42);  // the painted crust's mean grey round the hole
uniform vec3 deep_col : source_color = vec3(0.13, 0.13, 0.14);
uniform float tex_scale = 0.11;              // 1 / m
uniform float depth_dark = 0.62;             // share of the way to deep_col at the floor
uniform float level_y = 0.0;                 // the goo surface now: the wall is wet (darker, glossier) just over it
varying vec3 wpos;
varying vec3 wnrm;
varying float depth;
varying float is_floor;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	depth = COLOR.r;
	is_floor = COLOR.g;
}

void fragment() {
	float ca;
	vec4 r = pf_rim(SCREEN_UV, ca);
	if (ca > clip_alpha) {
		discard;
	}
	vec3 b = pow(abs(wnrm), vec3(4.0));
	b /= (b.x + b.y + b.z + 1e-4);
	float g = texture(grain, wpos.zy * tex_scale).r * b.x + texture(grain, wpos.xz * tex_scale).r * b.y
			+ texture(grain, wpos.xy * tex_scale).r * b.z;
	float g2 = texture(grain, wpos.xz * tex_scale * 3.7 + vec2(0.31, 0.77)).r;
	vec3 col = crust_col * (0.62 + 0.55 * g) * (0.85 + 0.3 * g2);
	float strata = 0.5 + 0.5 * sin(wpos.y * 2.3 + g * 3.0);          // faint layered bands on the walls
	col *= mix(1.0, 0.86 + 0.14 * strata, 1.0 - is_floor);
	col = mix(col, deep_col, depth_dark * pow(depth, 0.85));
	float wet = smoothstep(1.6, 0.0, wpos.y - level_y);              // just over the goo: wet and dark
	col *= mix(1.0, 0.62, wet * (1.0 - is_floor));
	col *= mix(1.0, 0.92, is_floor);
	col = mix(col, r.rgb, r.a);
	ALBEDO = pf_inv_post(clamp(col, vec3(0.0), vec3(1.0)));
}
