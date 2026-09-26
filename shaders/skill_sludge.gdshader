shader_type spatial;
// Mire (SkillFx): sludge poured over a deck - a dark goo in the caster's colour with ragged edges,
// slow bubbles and glowing vines crawling through it. Drawn on SkillFx's deck strip (UV.x 0..1 across,
// UV.y metres along, UV2.x 0..1 along). Alpha-blended (a surface, not a glow), so it darkens the deck.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(0.4, 0.9, 0.3, 1.0);
uniform float fill = 1.0;          // 0..1 spread out from the middle
uniform float intensity = 1.0;     // overall opacity (fades in / out)
uniform float seed = 0.0;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0)), f.x), f.y);
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float n = noise2(vec2(UV.x * 3.0, UV.y * 0.8 + TIME * 0.12) + seed) * 0.65 + noise2(vec2(UV.x * 8.0, UV.y * 2.2 - TIME * 0.2)) * 0.35;
	float edge = 1.0 - smoothstep(0.7 + 0.22 * n, 0.98, across);
	float u = abs(UV2.x - 0.5) * 2.0;
	float spread = 1.0 - smoothstep(fill - 0.08 - 0.06 * n, fill, u);
	// vines: two wavy strands crawling along the deck, with side shoots
	float w1 = abs(UV.x - 0.5 - 0.22 * sin(UV.y * 0.9 + seed) - 0.08 * sin(UV.y * 2.7));
	float w2 = abs(UV.x - 0.5 + 0.25 * sin(UV.y * 0.75 + 1.7 + seed) + 0.06 * sin(UV.y * 3.1));
	float vine = exp(-pow(min(w1, w2) / 0.035, 2.0));
	float shoot = exp(-pow((fract(UV.y * 0.7 + UV.x * 1.5 + seed) - 0.5) / 0.04, 2.0)) * step(0.55, noise2(vec2(UV.y * 0.7, seed))) * (1.0 - across);
	vine = max(vine, shoot * 0.6);
	// bubbles: cells that swell and pop
	vec2 bc = vec2(UV.x * 4.0, UV.y * 1.3);
	vec2 bi = floor(bc);
	vec2 bf = fract(bc) - 0.5;
	float ph = fract(TIME * 0.45 + hash2(bi + seed));
	float br = 0.12 + 0.28 * ph;
	float ring = exp(-pow((length(bf) - br) / 0.035, 2.0)) * step(0.5, hash2(bi * 1.3 + seed)) * (1.0 - ph);
	vec3 murk = vec3(0.07, 0.1, 0.05);
	vec3 goo = mix(murk, mix(murk, color.rgb * 0.45, 0.55), n);
	vec3 vines = mix(color.rgb, vec3(0.45, 1.0, 0.35), 0.5) * 1.8;
	float rim = exp(-pow((across - (0.8 + 0.18 * n)) / 0.05, 2.0));      // a glowing lip where it spills over
	vec3 c = mix(goo, vines, vine) + color.rgb * (ring * 1.3 + rim * 0.9);
	ALBEDO = c;
	ALPHA = clamp(edge * spread * intensity * (0.93 + 0.07 * vine), 0.0, 1.0);
}
