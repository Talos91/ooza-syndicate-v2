shader_type spatial;
// Skills 2.0 effects (SkillFx, skill_fx.gd). Additive, unshaded glows in the caster's colour.
// Deck strips (SkillFx._strip_mesh): UV.x 0..1 across the deck, UV.y metres along it, UV2.x 0..1 along,
// UV2.y the deck's length. Walls / domes: UV.x 0..1 round, UV.y 0..1 up. Planes: UV 0..1.
//   mode 0 FIRE     a deck on fire (Scorch)
//   mode 1 CRACKS   glowing cracks spreading over a deck (Demolish warning); heat 0..1 = how close it is
//   mode 2 LOCK     bolted rails and rivets along both edges of a deck (Anchor, Relay Aegis)
//   mode 3 HOLO     scanline hologram over a deck (Bypass: both states at once; a missing deck's outline)
//   mode 4 HEX      hexagon shield (Fortify wall, Relay Aegis dome); `left` drains it round the circle
//   mode 5 GLITCH   blocky static over a relay or node (Relay Hack fire, Echo Split disruption)
//   mode 6 CLAMP    a bolted lock ring (Anchor's relay, Relay Hack jam, Aegis relay lock); `left` drains it
//   mode 7 ARC      a time-left band on an annulus (UV.x round, UV.y across the band)
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform vec4 color2 : source_color = vec4(1.0, 0.5, 0.12, 1.0);
uniform float intensity = 1.0;
uniform int mode = 0;
uniform float left = 1.0;          // 0..1 of the effect still to run (drains the ring / wall)
uniform float heat = 0.0;          // mode 1: 0..1 toward the collapse; mode 5: density
uniform float fill = 1.0;          // strips: 0..1 spread out from the middle of the deck
uniform float seed = 0.0;
uniform vec2 tiles = vec2(48.0, 6.0);   // mode 4: hexagons round and up

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	return noise2(p) * 0.55 + noise2(p * 2.1 + 3.7) * 0.3 + noise2(p * 4.3 + 7.1) * 0.15;
}
float voronoi_edge(vec2 p) {
	// F2 - F1: small along the cell borders (the cracks)
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash2(i + g + seed), hash2(i + g + seed + 19.3));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}
float hex_edge(vec2 p) {
	// distance to the nearest hexagon border (0 on it)
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	return 0.5 - max(dot(q, normalize(vec2(1.0, 1.7320508))), q.x);
}

void fragment() {
	vec3 c = vec3(0.0);
	float u = UV2.x;
	float spread = 1.0 - smoothstep(fill - 0.06, fill, abs(u - 0.5) * 2.0);   // strips grow out of the middle
	float across = abs(UV.x * 2.0 - 1.0);
	if (mode == 0) {
		vec2 p = vec2(UV.x * 2.6, UV.y * 0.55 - TIME * 1.7) + seed;
		float n = fbm(p);
		float n2 = noise2(vec2(UV.x * 7.0, UV.y * 1.6 - TIME * 3.2) + seed * 1.3);
		float flame = smoothstep(0.5, 0.85, n * 0.8 + n2 * 0.35 + (1.0 - across) * 0.2);
		vec3 hot = mix(color2.rgb * vec3(1.0, 0.7, 0.6), vec3(1.0, 0.85, 0.45), smoothstep(0.7, 1.0, n2) * flame);
		c = hot * flame * 1.6 + mix(color.rgb, color2.rgb, 0.7) * 0.16 * (1.0 - across);
		c *= (1.0 - smoothstep(0.82, 1.0, across)) * (0.85 + 0.15 * sin(TIME * 19.0 + UV.y));
		c *= spread;
	} else if (mode == 1) {
		vec2 p = vec2(UV.x * 2.4, UV.y * 0.8);
		float e = voronoi_edge(p);
		float e2 = voronoi_edge(p * 2.3 + 5.0);
		float grow = smoothstep(0.0, 1.0, heat);
		float crack = 1.0 - smoothstep(0.0, 0.05 + 0.05 * grow, e);
		crack = max(crack, (1.0 - smoothstep(0.0, 0.03, e2)) * grow);
		float flick = 0.55 + 0.45 * step(0.5, fract(TIME * (3.0 + 9.0 * grow)));
		vec3 hot = mix(color2.rgb, vec3(1.0, 0.95, 0.8), crack * grow);
		c = hot * crack * (0.9 + 1.8 * grow) * flick + color2.rgb * 0.12 * (0.4 + grow) * flick;
		c *= 1.0 - smoothstep(0.85, 1.0, across);
	} else if (mode == 2) {
		float side = abs(UV.x - 0.5) - 0.41;
		float rail = exp(-pow(side / 0.025, 2.0));
		float seg = fract(UV.y / 0.9);
		rail *= 0.45 + 0.55 * smoothstep(0.08, 0.18, seg) * smoothstep(0.92, 0.82, seg);
		vec2 q = vec2(side * 3.2, (fract(UV.y / 2.0) - 0.5) * 2.0);
		float bolt = exp(-dot(q, q) * 26.0);
		float brace = exp(-pow((fract(UV.y / 4.0 + UV.x * 0.82) - 0.5) / 0.02, 2.0)) * 0.35
				+ exp(-pow((fract(UV.y / 4.0 - UV.x * 0.82) - 0.5) / 0.02, 2.0)) * 0.35;
		float sweep = exp(-pow((fract(u - TIME * 0.35) - 0.5) / 0.05, 2.0));
		c = color.rgb * (rail * 1.6 + bolt * 2.2 + brace * (1.0 - across) + 0.1) + vec3(1.0) * (bolt * 0.7 + rail * sweep * 0.8);
		c *= spread;
	} else if (mode == 3) {
		float scan = 0.5 + 0.5 * sin(UV.y * 5.0 - TIME * 7.0);
		float edge = exp(-pow((across - 0.9) / 0.05, 2.0));
		float grain = noise2(vec2(UV.x * 30.0, UV.y * 4.0 + TIME * 20.0));
		c = color.rgb * (0.2 + 0.3 * scan + edge * 1.4 + 0.15 * grain) * (0.8 + 0.2 * sin(TIME * 37.0 + seed));
		c *= (1.0 - smoothstep(0.96, 1.0, across)) * spread;
	} else if (mode == 4) {
		vec2 p = vec2(UV.x * tiles.x, UV.y * tiles.y);
		float hx = hex_edge(p);
		float lines = 1.0 - smoothstep(0.02, 0.09, hx);
		float band = exp(-pow((fract(UV.y * 0.8 - TIME * 0.45) - 0.5) / 0.08, 2.0));
		float cell = hash2(floor(p * 0.5) + seed);
		float glint = step(0.93, fract(cell + TIME * 0.35)) * 0.5;
		float fade = pow(clamp(1.0 - UV.y, 0.0, 1.0), 1.3);
		float base = exp(-UV.y * 11.0);
		float on = left >= 0.999 ? 1.0 : 1.0 - smoothstep(left - 0.006, left + 0.006, UV.x);
		c = color.rgb * ((lines * 1.3 + 0.14 + band * 0.45 + glint) * fade + base * 1.4) + vec3(1.0) * lines * band * 0.35 * fade;
		c *= mix(0.12, 1.0, on);
	} else if (mode == 5) {
		vec2 q = UV * 2.0 - 1.0;
		float r = length(q);
		vec2 cell = floor(UV * vec2(22.0, 22.0));
		float t1 = floor(TIME * 14.0);
		float r1 = hash2(cell + t1 + seed);
		float r2 = hash2(cell * 1.7 + floor(TIME * 9.0) + seed);
		float blk = step(0.93 - 0.12 * heat, r1) * (0.6 + 0.4 * r2);
		float lines = step(0.9, hash2(vec2(floor(UV.y * 40.0), t1)));
		float disc = 1.0 - smoothstep(0.75, 1.0, r);
		float ring = exp(-pow((r - 0.86) / 0.04, 2.0)) * (0.4 + 0.6 * step(0.35, hash2(vec2(floor(atan(q.y, q.x) * 6.0), t1))));
		c = mix(color.rgb, color2.rgb, step(0.5, r2)) * (blk * 1.3 + lines * 0.6) * disc + color.rgb * ring * 1.5;
	} else if (mode == 6) {
		vec2 q = UV * 2.0 - 1.0;
		float r = length(q);
		float a = atan(q.y, q.x) / 6.2831853 + 0.5;
		float ring = exp(-pow((r - 0.84) / 0.03, 2.0));
		float k = floor(a * 6.0);
		float ak = (k + 0.5) / 6.0 * 6.2831853 - 3.14159265;
		vec2 bp = 0.84 * vec2(cos(ak), sin(ak));
		float bolt = exp(-dot(q - bp, q - bp) * 520.0);
		float cl = fract(a * 4.0 - TIME * 0.12);
		float clamp_arc = exp(-pow((r - 0.7) / 0.045, 2.0)) * smoothstep(0.05, 0.12, cl) * smoothstep(0.62, 0.55, cl);
		float on = left >= 0.999 ? 1.0 : 1.0 - smoothstep(left - 0.006, left + 0.006, 1.0 - fract(a + 0.25));
		c = color.rgb * (ring * 1.5 + clamp_arc * 1.3) * mix(0.18, 1.0, on) + vec3(1.0) * bolt * 1.6 + color.rgb * bolt;
		c *= 1.0 - smoothstep(0.95, 1.0, r);
	} else {
		float band = smoothstep(0.0, 0.3, UV.y) * smoothstep(1.0, 0.7, UV.y);
		float on = left >= 0.999 ? 1.0 : 1.0 - smoothstep(left - 0.004, left + 0.004, UV.x);
		float tick = step(0.92, fract(UV.x * 30.0));
		c = color.rgb * band * mix(0.1, 1.0, on) * (1.0 - 0.5 * tick);
	}
	ALBEDO = c * intensity;
	ALPHA = 1.0;
}
