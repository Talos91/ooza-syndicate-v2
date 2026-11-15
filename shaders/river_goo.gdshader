shader_type spatial;
// RIVER WORLD: the goo river's surface - GRAY native goo (Daniele 2026-11-15: never a faction hue), kept alive by motion:
// flow along the channel, a sheen, rising bubbles that pop, and a core glow in veins under it. Opaque: the canyon bed
// pokes through wherever it is higher than the level (bars and banks surface first). Procedural (no texture).
render_mode cull_disabled;

uniform vec3 goo : source_color = vec3(0.37, 0.38, 0.42);
uniform vec3 deep : source_color = vec3(0.25, 0.26, 0.29);
uniform vec3 vein : source_color = vec3(0.58, 0.68, 0.66);
uniform vec2 dir = vec2(1.0, 0.0);      // the channel's direction (world xz)
uniform float flow = 1.0;
uniform float glow = 0.8;
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
	vec2 side = vec2(-dir.y, dir.x);
	vec2 p = wp.xz;
	float tt = TIME * flow;
	float n1 = fbm(p * 0.11 - dir * tt * 0.05);
	float n2 = fbm(p * 0.13 - dir * tt * 0.08 + side * n1 * 1.6);
	vec3 c = mix(deep, goo, smoothstep(0.2, 0.8, n2));
	// sheen: a slope from the flow noise
	float e = 0.6;
	float nx = fbm((p + vec2(e, 0.0)) * 0.13 - dir * tt * 0.08 + side * n1 * 1.6);
	float nz = fbm((p + vec2(0.0, e)) * 0.13 - dir * tt * 0.08 + side * n1 * 1.6);
	vec3 wn = normalize(vec3((n2 - nx) * 0.7, 1.0, (n2 - nz) * 0.7));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	// core glow in veins under the skin (ridged noise, slow)
	float r = 1.0 - abs(fbm(p * 0.07 - dir * tt * 0.02 + n1 * 0.7) * 2.0 - 1.0);
	float v = pow(r, 10.0);
	float pulse = 0.75 + 0.25 * sin(TIME * 1.4 + n1 * 7.0);
	// bubbles: a few per cell rise, swell and pop
	vec2 g = (p - dir * tt * 0.4) * 0.55;
	vec2 id = floor(g);
	vec2 fr = fract(g) - 0.5;
	float hb = h21(id);
	float life = fract(TIME * 0.22 + hb * 7.0);
	vec2 off = (vec2(h21(id + 3.1), h21(id + 7.7)) - 0.5) * 0.45;
	float rad = 0.05 + 0.17 * life;
	float on = step(0.72, hb);
	float dd = length(fr - off);
	float dome = on * (1.0 - smoothstep(rad - 0.03, rad, dd)) * (1.0 - smoothstep(0.85, 1.0, life));
	float ring = on * (1.0 - smoothstep(0.0, 0.03, abs(dd - rad))) * smoothstep(0.8, 1.0, life);
	c = mix(c, goo * 1.18, dome * 0.5);
	c += vec3(0.08) * ring;
	c *= 1.0 - 0.15 * t0;
	ALBEDO = c;
	EMISSION = vein * v * glow * pulse * (1.0 - 0.35 * t0) + vec3(0.05) * dome;
	ROUGHNESS = mix(0.32, 0.5, n2);
	SPECULAR = 0.45;
}
