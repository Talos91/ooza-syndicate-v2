shader_type spatial;
// RIVER WORLD: the goo river's surface - GRAY native goo (Daniele 2026-11-15: never a faction hue), kept alive by motion:
// flow along the channel, a sheen, rising bubbles that pop, and a core glow in veins under it. Opaque: the canyon bed
// pokes through wherever it is higher than the level (bars and banks surface first). Procedural (no texture).
render_mode cull_disabled;

uniform vec3 goo : source_color = vec3(0.22, 0.225, 0.245);
uniform vec3 deep : source_color = vec3(0.13, 0.135, 0.15);
uniform vec3 vein : source_color = vec3(0.58, 0.68, 0.66);
uniform vec2 dir = vec2(1.0, 0.0);      // the channel's direction (world xz)
uniform float flow = 1.0;
uniform float glow = 0.25;
uniform float t0 = 0.0;                  // the drain's progress 0..1: the goo thickens / dulls as it goes

varying vec3 wp;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
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
		p = p * 2.07 + vec2(5.3, 1.1);
		a *= 0.5;
	}
	return s / 0.875;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += (sin(wp.x * 0.31 + TIME * 0.8) + sin(wp.z * 0.43 - TIME * 0.6)) * 0.04;
}

void fragment() {
	// designer 9 FIX 1: a dark goo body (luma ~70-90 so the board pops), slow streaks moving along the channel, a soft sheen,
	// a few slow swells / bubbles; neutral gray, never a faction hue.
	vec2 side = vec2(-dir.y, dir.x);
	vec2 p = wp.xz;
	float tt = TIME * flow;
	float along = dot(p, dir);
	float across = dot(p, side);
	float n1 = fbm(p * 0.05 + vec2(tt * 0.01));
	float streak = fbm(vec2(along * 0.035 - tt * 0.09, across * 0.42 + n1 * 2.0));
	float streak2 = fbm(vec2(along * 0.08 - tt * 0.16, across * 0.9 + 7.0));
	vec3 c = mix(deep, goo, smoothstep(0.25, 0.8, streak * 0.7 + streak2 * 0.3));
	// swells: a broad slow height field for the sheen
	float sw = fbm(p * 0.06 - dir * tt * 0.04);
	float e = 1.2;
	float swx = fbm((p + vec2(e, 0.0)) * 0.06 - dir * tt * 0.04);
	float swz = fbm((p + vec2(0.0, e)) * 0.06 - dir * tt * 0.04);
	vec3 wn = normalize(vec3((sw - swx) * 1.2 + (streak2 - 0.5) * 0.08, 1.0, (sw - swz) * 1.2));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	// a faint core glow deep in the slowest streaks
	float v = pow(1.0 - abs(streak * 2.0 - 1.0), 14.0);
	float pulse = 0.75 + 0.25 * sin(TIME * 0.9 + n1 * 6.0);
	// slow bubbles: few cells, swell then pop
	vec2 g = (p - dir * tt * 0.3) * 0.32;
	vec2 id = floor(g);
	vec2 fr = fract(g) - 0.5;
	float hb = h21(id);
	float life = fract(TIME * 0.12 + hb * 7.0);
	vec2 off = (vec2(h21(id + 3.1), h21(id + 7.7)) - 0.5) * 0.4;
	float rad = 0.04 + 0.16 * life;
	float on = step(0.8, hb);
	float dd = length(fr - off);
	float dome = on * (1.0 - smoothstep(rad - 0.04, rad, dd)) * (1.0 - smoothstep(0.88, 1.0, life));
	float ring = on * (1.0 - smoothstep(0.0, 0.025, abs(dd - rad))) * smoothstep(0.86, 1.0, life);
	c = mix(c, goo * 1.15, dome * 0.45);
	c += vec3(0.05) * ring;
	c *= 1.0 - 0.12 * t0;
	ALBEDO = c;
	EMISSION = vein * v * glow * pulse * (1.0 - 0.35 * t0);
	ROUGHNESS = mix(0.42, 0.55, sw);
	SPECULAR = 0.28;
}
