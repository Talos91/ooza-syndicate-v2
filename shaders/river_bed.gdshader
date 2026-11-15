shader_type spatial;
// RIVER WORLD (Daniele 2026-11-15, "the new setting"): the canyon's walls and bed, one generated heightfield (world_river.gd).
// Solidified goo crust, layered gray-green and slightly glassy (decision A); tide marks left on whatever the draining river
// has uncovered (thin pale lines every tide_step m under the river's start level); a dark glossy wet band just above the
// current level; dried mud-crack plates on the flat bars once they are exposed. Procedural (no texture: no pck cost).
render_mode cull_disabled;

uniform float level = -5.0;          // the river's surface now (world y)
uniform float top = -5.0;            // the river's level at 0:00 (the highest tide mark)
uniform float tide_step = 0.85;
uniform vec3 crust_dark : source_color = vec3(0.15, 0.175, 0.165);
uniform vec3 crust_mid : source_color = vec3(0.20, 0.235, 0.215);
uniform vec3 crust_light : source_color = vec3(0.245, 0.28, 0.255);
uniform vec3 tide_col : source_color = vec3(0.52, 0.56, 0.51);
uniform vec3 wet_col : source_color = vec3(0.16, 0.17, 0.19);
uniform vec3 old_crust : source_color = vec3(0.40, 0.42, 0.38);   // the walls above the river's start: older, drier

varying vec3 wp;
varying vec3 wn;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 h22(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s / 0.875;
}
// distance to the nearest edge of a cell (mud-crack network)
float cracks(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = h22(i + g) * 0.8 + 0.1;
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = fbm(wp.xz * 0.16);
	float flat_k = smoothstep(0.80, 0.95, wn.y);               // bars and banks (flat) vs walls (steep)
	// layered strata: bands in world y, wobbled by noise (steeper = the layers read as lines on the wall)
	float sy = wp.y * 0.62 + (n - 0.5) * 1.3 + fbm(wp.xz * 0.05 + 3.0) * 0.8;
	float band = fract(sy);
	vec3 c = mix(mix(crust_dark, crust_mid, 0.5), crust_mid, smoothstep(0.0, 0.3, band));
	c = mix(c, crust_light, smoothstep(0.62, 0.86, band) * (1.0 - smoothstep(0.9, 1.0, band)));
	c *= 0.9 + 0.2 * n;
	// above the river's start: the old dry canyon rim (no tide, paler)
	float old = smoothstep(top + 0.2, top + 1.6, wp.y);
	c = mix(c, old_crust * (0.9 + 0.2 * n), old);
	c *= mix(1.0, 0.82, (1.0 - flat_k) * (1.0 - old) * step(level, wp.y));   // the drained wall band: a step darker than the dry top
	float exposed = step(level, wp.y) * (1.0 - old);
	// dried mud-crack plates on the flat ground the river has left
	float ck = cracks(wp.xz * 0.3 + n * 0.6);
	float crack_line = 1.0 - smoothstep(0.03, 0.10, ck);
	float dry = smoothstep(0.6, 2.2, wp.y - level);              // fresh mud near the water is not cracked yet
	c = mix(c, c * 0.84, crack_line * flat_k * exposed * dry);
	c = mix(c, c * 1.12, (1.0 - crack_line) * flat_k * exposed * dry * 0.3);   // the plates' tops a touch paler
	// tide marks: every tide_step m under the start level, only where the river has gone
	float k = (top - wp.y + (n - 0.5) * 0.18) / tide_step;
	float fk = fract(k);
	float line = 1.0 - smoothstep(0.015, 0.06 + 0.05 * flat_k, min(fk, 1.0 - fk));
	line *= step(0.5, k) * exposed;
	c = mix(c, tide_col, line * 0.38);
	// the wet band just above the surface: dark, glossy
	float wet = (1.0 - smoothstep(0.0, 0.8, wp.y - level)) * step(level - 0.05, wp.y);
	c = mix(c, wet_col, wet * 0.75);
	ALBEDO = c;
	float glint = step(0.965, h21(floor(wp.xz * 9.0)));       // glassy crust: scattered glints
	ROUGHNESS = mix(mix(0.42, 0.62, old), 0.08, max(wet, glint * 0.8 * (1.0 - old)));
	SPECULAR = 0.55;
}
