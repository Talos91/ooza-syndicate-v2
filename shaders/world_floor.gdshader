shader_type spatial;
// WORLD LAYER (Daniele, 2026-11-06): the floor under the decks. It varies per map (his answer: "street/factory/sewer/lab"):
// kind 0 street (asphalt, dim lane dashes, kerbs, manholes), 1 factory (graphite plates, seams, drain channels),
// 2 sewer (brick courses, a murky channel), 3 lab (big tiles, faint cyan guide lines). Hazed toward the void colour with
// distance and faded out at the edges so the sky still shows at the horizon. Its own depth tint (fog_disabled): the scene's
// height fog would swallow it whole at this depth. Always darker than a deck's shadow side.
render_mode fog_disabled, unshaded, blend_mix, depth_draw_opaque, cull_disabled;

uniform int kind = 1;
uniform vec3 abyss : source_color = vec3(0.2, 0.17, 0.37);
uniform vec2 centre = vec2(0.0);
uniform float r0 = 40.0;        // full floor out to here
uniform float r1 = 90.0;        // gone (sky) from here
uniform float haze = 0.12;      // how much of the void colour the floor carries at the centre

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float grid(vec2 p, vec2 size, float w) {
	vec2 g = abs(fract(p / size) - 0.5);
	return smoothstep(0.5 - w, 0.5, max(g.x, g.y));
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 c;
	if (kind == 0) {                                      // STREET
		float speck = hash(floor(p * 3.0)) * 0.25;
		c = vec3(0.045, 0.048, 0.058) * (0.9 + speck);
		float lane = abs(fract(p.y / 12.0) - 0.5);
		float dash = step(0.5, fract(p.x / 6.0));
		c = mix(c, vec3(0.42, 0.3, 0.1), smoothstep(0.02, 0.0, lane) * dash * 0.8);
		float kerb = smoothstep(0.03, 0.0, abs(abs(fract(p.y / 12.0) - 0.5) - 0.42));
		c = mix(c, vec3(0.14, 0.14, 0.17), kerb);
		vec2 mh = fract(p / 18.0) - 0.5;
		float man = smoothstep(0.06, 0.05, length(mh)) - smoothstep(0.045, 0.04, length(mh)) * 0.5;
		c = mix(c, vec3(0.1, 0.1, 0.12), clamp(man, 0.0, 1.0));
	} else if (kind == 2) {                               // SEWER
		vec2 b = p / vec2(1.2, 0.6);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		float mortar = grid(b, vec2(1.0), 0.06);
		c = vec3(0.09, 0.06, 0.065) * (0.75 + 0.5 * hash(floor(b)));
		c = mix(c, vec3(0.02, 0.02, 0.025), mortar);
		float ch = abs(fract(p.y / 20.0) - 0.5) * 20.0;      // a 2.4 m channel every 20 m
		float water = smoothstep(1.2, 1.0, ch);
		float ripple = 0.5 + 0.5 * sin(p.x * 1.4 - TIME * 1.5 + sin(p.y * 3.0));
		c = mix(c, vec3(0.04, 0.14, 0.12) * (0.7 + 0.6 * ripple), water);
		c = mix(c, vec3(0.1, 0.1, 0.11), smoothstep(0.12, 0.0, abs(ch - 1.25)));
	} else if (kind == 3) {                               // LAB
		c = vec3(0.1, 0.11, 0.13) * (0.9 + 0.15 * hash(floor(p / 2.0)));
		c = mix(c, vec3(0.025, 0.03, 0.04), grid(p, vec2(2.0), 0.03));
		float guide = smoothstep(0.05, 0.0, abs(fract(p.x / 8.0) - 0.5) - 0.0) + smoothstep(0.05, 0.0, abs(fract(p.y / 8.0) - 0.5));
		c = mix(c, vec3(0.08, 0.3, 0.36), clamp(guide, 0.0, 1.0) * 0.45);
	} else {                                              // FACTORY
		vec2 cell = floor(p / 4.0);
		c = vec3(0.035, 0.042, 0.06) * (0.85 + 0.3 * hash(cell));
		c = mix(c, vec3(0.012, 0.014, 0.022), grid(p, vec2(4.0), 0.045) * 0.8);
		c = mix(c, vec3(0.14, 0.12, 0.26), grid(p, vec2(16.0), 0.02));
	}
	float d = length(p - centre);
	c = mix(c, abyss * 0.6, haze + (1.0 - haze) * 0.7 * smoothstep(r0 * 0.4, r1, d));
	ALBEDO = c;
	ALPHA = 1.0 - smoothstep(r0, r1, d);
}
