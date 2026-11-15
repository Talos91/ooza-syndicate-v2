shader_type spatial;
// RIVER WORLD: the crack in the canyon bed a platform's drill plugs into (Daniele 2026-11-15: "the tubes simply plugged in
// the floor via some crack"). A quad on the bed under each drill (one MultiMesh): a dark hole, a broken crust lip and
// fissures running out. INSTANCE_CUSTOM.x = a seed.
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform vec3 lip : source_color = vec3(0.44, 0.48, 0.44);
uniform vec3 hole : source_color = vec3(0.03, 0.035, 0.04);
uniform float hole_r = 0.30;        // in the quad's half size (the drill fills r 0.0 .. ~0.22)

varying float seed;

float h11(float x) { return fract(sin(x * 127.1) * 43758.5453); }

void vertex() {
	seed = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float jag = 0.04 * sin(a * 7.0 + seed * 20.0) + 0.03 * sin(a * 13.0 + seed * 7.0);
	float in_hole = 1.0 - smoothstep(hole_r + jag - 0.02, hole_r + jag + 0.02, r);
	float lip_k = (1.0 - smoothstep(hole_r + jag + 0.02, hole_r + jag + 0.12, r)) * (1.0 - in_hole);
	float fis = 0.0;
	for (int i = 0; i < 6; i++) {
		float ai = (float(i) + h11(seed * 10.0 + float(i))) * 6.2832 / 6.0;
		float len = 0.55 + 0.4 * h11(seed * 3.0 + float(i) * 1.7);
		float da = abs(mod(a - ai + 3.1416, 6.2832) - 3.1416);
		float w = 0.035 * (1.0 - r / len);
		fis = max(fis, (1.0 - smoothstep(w * 0.5, w, da * r)) * step(r, len) * step(hole_r, r));
	}
	vec3 c = mix(lip, hole, max(in_hole, fis * 0.9));
	ALBEDO = c;
	ROUGHNESS = 0.6;
	ALPHA = max(max(in_hole, fis), lip_k * 0.85) * (1.0 - smoothstep(0.9, 1.0, r));
}
