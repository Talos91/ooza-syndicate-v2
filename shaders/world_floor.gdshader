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
// R3A-2 GEOMETRY v2 (director, 2026-11-07): flat gray-code tiles (0/64/128/191), 1792 px = 16 m, one tile per 16 m cell;
// each cell picks the base (~60 %) or a variant B-E by a hash of the cell (all share an identical 1 m border); beyond the
// district (r_district) the crust tile, hard boundary on the cell grid. Codes go through a TEMPORARY dark palette.
uniform bool tiles = true;      // false: the old procedural placeholder above (--floor-v1)
uniform sampler2D t_base : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D t_b : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D t_c : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D t_d : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D t_e : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D t_crust : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float tile_m = 16.0;
uniform float r_district = 60.0;
uniform vec3 pal0 : source_color = vec3(0.035, 0.043, 0.059);   // code 0   #090B0F
uniform vec3 pal1 : source_color = vec3(0.071, 0.094, 0.133);   // code 64  #121822
uniform vec3 pal2 : source_color = vec3(0.102, 0.133, 0.188);   // code 128 #1A2230
uniform vec3 pal3 : source_color = vec3(0.180, 0.212, 0.267);   // code 191 #2E3644

// LAB CLEAN FLOOR (--floor=labpic, Daniele 2026-11-07): his painted lab floor, rectified to top-down from its own 2 m grid
// (Models/2.0/world-1.0/floor/rectify_lab_clean_floor.py), laid on the floor plane at 1:1 (its 2 m grid = 2 m), world-
// locked (pans / zooms with the board). Past the picture: its mean colour plus the same faint 2 m grid, the picture's edge
// fading into it over pic_fade metres (a noisy edge) - or, the default, mirror-repeated over the whole floor (the board's
// visible floor is ~2x the picture: R-01's footprint is ~110 x 70 m, the picture 54 x 41 m).
uniform bool pic = false;
uniform sampler2D t_pic : source_color, hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec2 pic_origin = vec2(0.0);     // world xz of the picture's top-left (far-left) corner
uniform vec2 pic_size = vec2(53.8, 40.7);
uniform float pic_fade = 7.0;
uniform bool pic_mirror = true;
uniform float pic_gain = 1.0;            // brightness on the picture (the arena's fog layers above swallow its darks)          // mirror-repeat the picture over the whole floor (false: fade into pic_bg)
uniform vec3 pic_bg : source_color = vec3(0.127, 0.150, 0.187);
uniform vec3 pic_line : source_color = vec3(0.150, 0.175, 0.215);

// LAB FLOOR R5 (--floor=lab5, the lab default since world pass 2, director round 5): one seamless 32 x 32 m tile (2048 px,
// 64 px/m, sixteen 2 m tiles), world-locked, plain repeat (no mirroring), mipmapped. Its mean is #343C4A.
uniform bool lab5 = false;
uniform sampler2D t_lab5 : source_color, hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float lab5_m = 32.0;
uniform float lab5_gain = 1.0;

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

vec3 palette(float v) {          // piecewise between the four codes (filtered texels fall in between)
	float k = v * 255.0;
	if (k < 64.0) return mix(pal0, pal1, k / 64.0);
	if (k < 128.0) return mix(pal1, pal2, (k - 64.0) / 64.0);
	return mix(pal2, pal3, clamp((k - 128.0) / 63.0, 0.0, 1.0));
}

vec3 tiled(vec2 p) {
	vec2 cell = floor(p / tile_m);
	vec2 uv = p / tile_m;                         // whole tile per cell; gradients stay continuous across cells
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	float v;
	if (length((cell + 0.5) * tile_m - centre) > r_district) {
		v = textureGrad(t_crust, uv, dx, dy).r;
	} else {
		float h = hash(cell + vec2(17.0, 3.0));
		if (h < 0.6) v = textureGrad(t_base, uv, dx, dy).r;
		else if (h < 0.7) v = textureGrad(t_b, uv, dx, dy).r;
		else if (h < 0.8) v = textureGrad(t_c, uv, dx, dy).r;
		else if (h < 0.9) v = textureGrad(t_d, uv, dx, dy).r;
		else v = textureGrad(t_e, uv, dx, dy).r;
	}
	return palette(v);
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 c;
	if (lab5) {
		c = texture(t_lab5, p / lab5_m).rgb * lab5_gain;
	} else if (pic) {
		vec2 uv = (p - pic_origin) / pic_size;
		if (pic_mirror) {
			uv = 1.0 - abs(mod(uv, 2.0) - 1.0);                         // mirror-repeat: no seams, mirrored copies
		}
		vec2 m = pic_mirror ? vec2(1e4) : min(p - pic_origin, pic_origin + pic_size - p);   // metres inside the edge
		float n = hash(floor(p * 0.7)) * 0.5 + 0.5 * sin(p.x * 0.31 + p.y * 0.17);
		float k = smoothstep(0.0, pic_fade, min(m.x, m.y) - 1.0 + n * 2.0);
		vec3 bg = pic_bg * (0.94 + 0.08 * hash(floor(p / 2.0)));
		bg = mix(bg, pic_line, grid(p, vec2(2.0), 0.012) * 0.8);
		vec3 tex = texture(t_pic, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
		c = mix(bg, tex, k) * pic_gain;
	} else if (tiles) {
		c = tiled(p);
	} else if (kind == 0) {                                      // STREET
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
	c = mix(c, abyss * 0.6, haze + (haze > 0.0 ? (1.0 - haze) * 0.7 * smoothstep(r0 * 0.4, r1, d) : 0.0));
	ALBEDO = c;
	ALPHA = 1.0 - smoothstep(r0, r1, d);
}
