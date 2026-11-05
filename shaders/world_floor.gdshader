shader_type spatial;
// WORLD LAYER (Daniele, 2026-11-06): the floor under the decks - dark graphite plates with seams, a faint goo sheen
// in the drains, hazed toward the void colour with distance and faded out at the edges so the sky still shows.
// Its own depth tint (fog_disabled): the scene's height fog would swallow it whole at this depth.
render_mode fog_disabled, unshaded, blend_mix, depth_draw_opaque, cull_disabled;

uniform vec3 base : source_color = vec3(0.035, 0.042, 0.06);
uniform vec3 seam : source_color = vec3(0.012, 0.014, 0.022);
uniform vec3 drain : source_color = vec3(0.09, 0.08, 0.17);
uniform vec3 abyss : source_color = vec3(0.2, 0.17, 0.37);
uniform vec2 centre = vec2(0.0);
uniform float r0 = 40.0;        // full floor out to here
uniform float r1 = 90.0;        // gone (sky) from here
uniform float tile = 4.0;       // metres per plate
uniform float haze = 0.22;      // how much of the void colour the floor carries at the centre

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 cell = floor(p / tile);
	vec2 g = abs(fract(p / tile) - 0.5);
	float seam_l = smoothstep(0.455, 0.5, max(g.x, g.y));
	vec2 big = abs(fract(p / (tile * 4.0)) - 0.5);
	float drain_l = smoothstep(0.485, 0.5, max(big.x, big.y));       // a drain channel every 4 plates
	float shade = 0.85 + 0.3 * hash(cell);                             // plates a little uneven
	vec3 c = base * shade;
	c = mix(c, seam, seam_l * 0.8);
	c = mix(c, drain, drain_l);
	float d = length(p - centre);
	c = mix(c, abyss * 0.6, haze + (1.0 - haze) * 0.7 * smoothstep(r0 * 0.4, r1, d));
	ALBEDO = c;
	ALPHA = 1.0 - smoothstep(r0, r1, d);
}
