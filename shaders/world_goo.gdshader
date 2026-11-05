shader_type spatial;
// WORLD LAYER: goo blobs and droplets on the floor (MultiMesh, colour per instance). Own depth tint (fog_disabled).
render_mode fog_disabled;

uniform float glow = 0.6;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = COLOR.rgb * 0.45;
	EMISSION = COLOR.rgb * (glow + 0.5 * fres);
	ROUGHNESS = 0.12;
	SPECULAR = 0.7;
}
