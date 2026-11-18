shader_type spatial;
// ROUND 44 B4 REAL 3D PIT (bg-44b4 job c, pit_3d.gd): the river's goo surface at its draining level. The painted goo tile in
// world space, drifting slowly and swirling toward the drain point, darker toward the centre, a wet sheen, and a meniscus ring at
// every drill column it touches (cols: x, z, radius; n_cols). Clipped by the painted crust, under the painted rim.
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;
#include "res://shaders/pit_frame.gdshaderinc"

uniform sampler2D goo_tile : source_color, repeat_enable, filter_linear_mipmap;
uniform vec2 drain = vec2(0.0);              // world xz the goo swirls to
uniform float tile_m = 40.0;                 // m per goo tile (the painted period at the start view)
uniform float reach = 60.0;                  // m: the pit's half size (darkening toward the centre)
uniform float swirl = 0.05;                  // rad / s near the drain
uniform float drift = 0.15;                  // m / s
uniform float t0 = 0.0;                      // drain progress 0..1 (the centre darkens as it drains)
uniform vec3 cols[16];
uniform int n_cols = 0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ca;
	vec4 rr = pf_rim(SCREEN_UV, ca);
	if (ca > clip_alpha) {
		discard;
	}
	vec2 q = wpos.xz - drain;
	float d = length(q);
	float a = TIME * swirl * (1.0 + 6.0 / (1.0 + d * 0.15));        // faster round the drain
	vec2 qs = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * q;
	qs -= normalize(q + vec2(1e-3)) * TIME * drift * 0.2;           // and a slow pull inward
	vec3 col = texture(goo_tile, (qs + drain) / tile_m + vec2(TIME * drift / tile_m, 0.0)).rgb;
	float l0 = dot(texture(goo_tile, (qs + drain) / tile_m + vec2(0.01, 0.0)).rgb, vec3(0.333));
	float l1 = dot(texture(goo_tile, (qs + drain) / tile_m + vec2(0.0, 0.01)).rgb, vec3(0.333));
	float lc = dot(col, vec3(0.333));
	vec3 nrm = normalize(vec3((lc - l0) * 6.0, 1.0, (lc - l1) * 6.0));
	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 h = normalize(v + normalize(vec3(-0.3, 1.0, 0.5)));
	float sheen = pow(max(dot(nrm, h), 0.0), 60.0) * 0.35 + pow(1.0 - max(v.y, 0.0), 4.0) * 0.08;
	col *= mix(1.0, 0.55 + 0.2 * (1.0 - t0), smoothstep(reach, 0.0, d));
	col += vec3(sheen) * vec3(0.8, 0.85, 0.9);
	for (int i = 0; i < n_cols; i++) {                               // the meniscus: a raised bright lip round each column
		float e = length(wpos.xz - cols[i].xy) - cols[i].z;
		float m = smoothstep(0.55, 0.0, e) * step(-0.05, e);
		col = mix(col, col * 1.6 + vec3(0.05), m * 0.7);
	}
	col = mix(col, rr.rgb, rr.a);
	ALBEDO = pf_inv_post(clamp(col, vec3(0.0), vec3(1.0)));
}
