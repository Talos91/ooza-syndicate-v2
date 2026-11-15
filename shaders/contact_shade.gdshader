shader_type spatial;
// READABILITY D (0.24.5): soft contact shading on flat quads (ContactShade). mode 0 = a soft disc (floor drop shadow under
// a platform, or the seat plate on an owned node), 1 = a band soft across its width and at its two ends (a bridge's floor
// shadow), 2 = a soft ring (the grounding ring under a building). No textures.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float strength = 0.5;
uniform float inner = 0.45;
uniform int mode = 0;
uniform vec4 col : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = mode == 1 ? abs(q.y) : length(q);
	float a = 1.0 - smoothstep(inner, 1.0, r);
	if (mode == 1) {
		a *= 1.0 - smoothstep(0.85, 1.0, abs(q.x));
	}
	if (mode == 2) {
		a = smoothstep(0.30, 0.42, r) * (1.0 - smoothstep(0.42, 0.62, r));
	}
	ALBEDO = col.rgb;
	ALPHA = a * strength;
}
