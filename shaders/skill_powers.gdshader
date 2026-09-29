shader_type spatial;
// POWERS (0.22.2): the new powers' glows (SkillFx, skill_fx.gd). Additive, unshaded, like skill_fx.gdshader.
// Planes: UV 0..1. Deck strips (SkillFx._strip): UV.x 0..1 across, UV.y metres along, UV2.x 0..1 along.
//   mode 0 QUAKE   radial cracks splitting a platform from its centre; heat 0..1 = how close the decks are to going
//   mode 1 SWIRL   a portal's vortex on a platform; dir +1 / -1 = which way it turns (entrance / exit)
//   mode 2 CUT     Sever's glowing cut line across the middle of a deck; heat 0..1 toward the snap
//   mode 3 WAVE    Backwash's goo wave along a deck: its crest at `front` (UV2.x), travelling toward `dir`
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform vec4 color2 : source_color = vec4(1.0, 0.5, 0.12, 1.0);
uniform float intensity = 1.0;
uniform int mode = 0;
uniform float heat = 0.0;
uniform float front = 0.5;
uniform float dir = 1.0;
uniform float seed = 0.0;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0)), f.x), f.y);
}

void fragment() {
	vec3 c = vec3(0.0);
	if (mode == 0) {
		vec2 q = UV * 2.0 - 1.0;
		float r = length(q);
		float a = atan(q.y, q.x);
		float grow = smoothstep(0.0, 1.0, heat);
		// seven jagged cracks from the centre, reaching further out as the heat rises
		float k = a / 6.2831853 * 7.0 + seed;
		float wob = (noise2(vec2(r * 9.0, floor(k) + seed)) - 0.5) * 0.35;
		float d = abs(fract(k + wob) - 0.5);
		float crack = (1.0 - smoothstep(0.0, 0.035 + 0.03 * grow, d)) * step(r, 0.25 + 0.72 * grow);
		float twig = (1.0 - smoothstep(0.0, 0.02, abs(fract(k * 3.0 + r * 4.0 + wob * 2.0) - 0.5))) * step(r, 0.9 * grow) * step(0.35, r);
		float flick = 0.6 + 0.4 * step(0.5, fract(TIME * (4.0 + 10.0 * grow) + seed));
		float rim = exp(-pow((r - 0.9) / 0.05, 2.0)) * (0.3 + 0.7 * grow);
		c = mix(color2.rgb, vec3(1.0, 0.95, 0.8), 0.4 * grow) * (crack * (1.0 + 1.6 * grow) + twig * 0.7 * grow) * flick
				+ color.rgb * rim * flick;
		c *= 1.0 - smoothstep(0.92, 1.0, r);
	} else if (mode == 1) {
		vec2 q = UV * 2.0 - 1.0;
		float r = length(q);
		float a = atan(q.y, q.x);
		float sw = a * 3.0 + dir * (r * 9.0 - TIME * 4.0) + seed;
		float arms = 0.5 + 0.5 * sin(sw);
		arms = pow(arms, 4.0) * smoothstep(1.0, 0.25, r) * smoothstep(0.02, 0.2, r);
		float core = exp(-r * r * 22.0);
		float rim = exp(-pow((r - 0.82) / 0.05, 2.0)) * (0.7 + 0.3 * sin(a * 12.0 - dir * TIME * 6.0));
		float n = noise2(vec2(a * 3.0 + dir * TIME, r * 6.0) + seed);
		c = color.rgb * (arms * (1.2 + 0.8 * n) + rim * 1.4 + core * 0.8) + vec3(1.0) * (core * 1.2 + pow(arms, 3.0) * 0.4);
		c *= 1.0 - smoothstep(0.92, 1.0, r);
	} else if (mode == 2) {
		float u = UV2.x;
		float len = max(UV2.y, 1.0);
		float across = abs(UV.x * 2.0 - 1.0);
		float jag = (noise2(vec2(UV.x * 9.0, seed)) - 0.5) * 0.9 / len;           // a jagged cut, ~1 m wide
		float d = abs(u - 0.5 - jag) * len;                                          // metres from the cut
		float grow = smoothstep(0.0, 1.0, heat);
		float line = exp(-pow(d / (0.12 + 0.18 * grow), 2.0));
		float glow = exp(-d * (1.6 - 0.8 * grow));
		float flick = 0.6 + 0.4 * step(0.5, fract(TIME * (5.0 + 12.0 * grow) + seed));
		c = mix(color.rgb, vec3(1.0, 0.95, 0.85), 0.6 * grow) * line * (1.4 + 2.0 * grow) * flick + color.rgb * glow * 0.4 * (0.4 + grow);
		c *= 1.0 - smoothstep(0.88, 1.0, across);
	} else {
		float u = UV2.x;
		float len = max(UV2.y, 1.0);
		float across = abs(UV.x * 2.0 - 1.0);
		float behind = (front - u) * dir * len;                                      // metres behind the crest
		float n = noise2(vec2(UV.x * 5.0, UV.y * 1.5 - dir * TIME * 6.0) + seed);
		float crest = exp(-pow((behind - 0.3 * n) / 0.6, 2.0));
		float trail = step(0.0, behind) * exp(-behind / 3.5);
		float foam = smoothstep(0.55, 0.85, n) * (crest + trail * 0.5);
		c = color.rgb * (crest * 1.8 + trail * 0.55) + vec3(1.0) * foam * 0.9;
		c *= 1.0 - smoothstep(0.85, 1.0, across);
	}
	ALBEDO = c * intensity;
	ALPHA = 1.0;
}
