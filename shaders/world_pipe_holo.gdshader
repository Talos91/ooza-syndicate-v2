shader_type spatial;
// v2 BUILD HOLOGRAM of a transport tube (Daniele 2026-11-09: "it should have the equivalent of the same building hologram
// animation"): next pass of world_pipe.gdshader. A slot that a vat upgrade is building (row 1 of `state`, r = progress
// 0..1) shows its whole run as the vat BLUEPRINT ghost (vat_blueprint.gdshader: UiKit cyan outline, rings every `grid` m,
// a faint scan shimmer, fading in over the first second); the real tube is revealed from the column end as the build
// completes (world_pipe.gdshader draws that part), so this pass draws only the share of the run still ahead of it.
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_back, shadows_disabled, fog_disabled;

uniform sampler2D state : filter_nearest, repeat_disable;
uniform float slots = 1.0;
uniform vec4 line_col : source_color = vec4(0.078, 0.827, 0.894, 1.0);   // UiKit.CYAN (the vat's blueprint line)
uniform float grid = 0.5;        // m between blueprint rings along the run

varying vec4 st;
varying float bp;

void vertex() {
	st = texture(state, vec2(UV2.x / slots, 0.25));
	bp = texture(state, vec2(UV2.x / slots, 0.75)).r;
	if (st.a < 0.0 || bp < 0.0) {
		VERTEX = vec3(0.0);                           // no tube, or not building: degenerate
	} else {
		VERTEX += NORMAL * 0.012;                     // a hair proud of the glass (no fighting at the front)
	}
}

float gridline(float v, float g, float w) {
	float f = abs(fract(v / g + 0.5) - 0.5) * g;
	return 1.0 - smoothstep(w * 0.5, w, f);
}

void fragment() {
	if (UV2.y < bp) {
		discard;                                      // built: the real tube shows there
	}
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
	float ring = gridline(UV.y, grid, 0.05);
	float seam = 0.5 * max(gridline(UV.x, 1.0 / 6.0, 0.03), 0.0);
	float scan = 0.5 + 0.5 * sin(UV.y * 3.0 - TIME * 6.0);
	float lines = clamp(max(ring, seam) + 1.2 * rim, 0.0, 1.0);
	vec3 ghost = mix(line_col.rgb, vec3(1.0), 0.15 * lines);
	float a = (0.05 + 0.6 * lines) * (0.75 + 0.25 * scan);
	float front = 1.0 - smoothstep(0.0, 0.03, UV2.y - bp);
	ghost = mix(ghost, mix(st.rgb, vec3(1.0), 0.35), front);
	float strength = clamp(bp * 12.0, 0.35, 1.0);    // fades in over the first second, like the vat's ghost
	ALBEDO = ghost;
	ALPHA = clamp(a + front * 0.8, 0.0, 1.0) * strength;
}
