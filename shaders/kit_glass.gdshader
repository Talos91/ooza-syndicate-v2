shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
// Kit glass (0.18.7 look pass, Daniele: "the vats are hard to see visually"): the tank and ring glass
// reads as a lit capsule instead of a grey film - clear in the middle so the liquid and the residents
// show, a bright rim at the silhouette (fresnel) and one vertical highlight, tinted by the owner's
// colour on vats (Scenery) so even an empty tank says whose it is. Cheap: no textures, no screen reads.
uniform vec4 tint : source_color = vec4(0.66, 0.72, 0.78, 1.0);
uniform float rim_glow = 0.9;        // emission at the silhouette
uniform float body_alpha = 0.08;     // alpha straight on
varying vec3 lpos;
void vertex() {
	lpos = VERTEX;
}
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = f * f * f;
	float streak = smoothstep(0.93, 1.0, 1.0 - abs(dot(NORMAL, normalize(vec3(0.55, 0.0, 0.83)))));   // one soft highlight
	ALBEDO = mix(vec3(0.05), tint.rgb, 0.35);
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
	EMISSION = tint.rgb * (rim * rim_glow + streak * 0.35);
	ALPHA = clamp(body_alpha + rim * 0.6 + streak * 0.18, 0.0, 0.85);
}
