shader_type canvas_item;
// Alpha 24 Neon Noir (art director revision 4-6): a glass vessel holding lit ooze up to `level` - the skill vessels (hex) and
// the SEND vats. One quad, the director's layers composited here (they share one canvas): the dark glass (TEXTURE), the white
// liquid tinted `liquid_col` and clipped bottom-up under a wavy surface, its untinted shine, the meniscus strip riding the
// waterline (scrolling), a few rising bubbles, then the white rim tinted `rim_col`. Cheap: 5 texture reads, no loops over
// pixels, ~110 px quads.
uniform sampler2D liquid_tex : filter_linear_mipmap;
uniform sampler2D shine_tex : filter_linear_mipmap;
uniform sampler2D rim_tex : filter_linear_mipmap;
uniform sampler2D surface_tex : filter_linear_mipmap;
uniform vec4 liquid_col : source_color = vec4(1.0);
uniform vec4 rim_col : source_color = vec4(1.0);
uniform sampler2D rim_lit_tex : filter_linear_mipmap;       // GMN-1: the burning tube ring, revealed bottom-up with the level
uniform vec4 rim_lit_col : source_color = vec4(0.0);    // a = 0: no lit ring (SEND, old parts)
uniform float level : hint_range(0.0, 1.0) = 1.0;     // 0 empty .. 1 full, of the body's height
uniform float liquid_a = 1.0;                          // idle SEND vats are dimmer than the picked one
uniform float slosh = 0.0;                             // 1 right after the level jumped, eased to 0 by the script
uniform float glow = 0.0;                              // full and ready: the ooze breathes brighter
uniform vec4 body = vec4(0.13, 0.13, 0.74, 0.74);      // body x, y, w, h in canvas UV
uniform vec4 strip = vec4(0.13, 0.35, 0.74, 0.29);     // the meniscus strip's body in ITS texture's UV (x, y, w, h)
uniform float strip_h = 0.11;                          // the strip's body height in canvas UV (drawn centred on the waterline)
uniform float seed = 0.0;
varying vec4 vcol;                                     // the node's own modulate (COLOR in fragment() is it x TEXTURE)

void vertex() {
	vcol = COLOR;
}

vec4 over(vec4 dst, vec3 c, float a) {                 // premultiplied: c over dst
	return vec4(c * a + dst.rgb * (1.0 - a), a + dst.a * (1.0 - a));
}

float ring(vec2 p, vec2 c, float r, float w) {
	float d = abs(length(p - c) - r);
	return 1.0 - smoothstep(w * 0.5, w, d);
}

void fragment() {
	vec2 uv = UV;
	vec4 f = texture(TEXTURE, uv);
	vec4 o = vec4(f.rgb * f.a, f.a);
	float bx = (uv.x - body.x) / body.z;                  // 0..1 across the body
	float lv = clamp(level, 0.0, 1.0);
	if (lv > 0.002) {
		float amp = (0.012 + 0.05 * slosh) * body.w * step(lv, 0.985);
		float wave = amp * (0.6 * sin(bx * 9.0 + TIME * 2.3 + seed) + 0.4 * sin(bx * 17.0 - TIME * 3.4 + seed * 2.0))
				+ slosh * 0.04 * body.w * sin(TIME * 9.0) * (bx - 0.5);
		float wl = body.y + body.w * (1.0 - lv) + wave;   // the waterline (canvas UV, y down)
		float under = smoothstep(wl - 0.004, wl + 0.004, uv.y);
		float la = texture(liquid_tex, uv).a;
		vec3 lc = liquid_col.rgb * (1.0 + 0.35 * glow);
		o = over(o, lc, la * under * liquid_a);
		// bubbles: four small rings rising through the liquid, clipped by it
		float b = 0.0;
		for (int i = 0; i < 4; i++) {
			float fi = float(i);
			float sp = 0.06 + 0.035 * fract(fi * 0.37 + seed);
			float t = fract(TIME * sp + fi * 0.29 + seed * 0.13);
			vec2 c = vec2(body.x + body.z * (0.25 + 0.5 * fract(fi * 0.61 + seed * 0.7) + 0.04 * sin(TIME * 2.0 + fi)),
					body.y + body.w * (1.0 - t * lv));
			b = max(b, ring(uv, c, body.z * (0.018 + 0.01 * fract(fi * 0.53)), body.z * 0.008) * step(wl + 0.01, c.y));
		}
		o = over(o, mix(lc, vec3(1.0), 0.6), b * la * under * 0.7 * liquid_a);
		o = over(o, vec3(1.0), texture(shine_tex, uv).a * under * liquid_a);
		// the meniscus strip, centred on the waterline, scrolling sideways (its body tiles left-right). 0.23.23 (Daniele: "the
		// wave texture has a small artifact"): fract() made a seam where it wrapped - a mip jump plus the strip's transparent
		// border bled in (a dark notch / a bright streak). Two samples half a tile apart, cross-faded so neither is read near
		// its wrap, inset from the strip's border, sampled with the unwrapped gradients.
		float sv = (uv.y - wl) / strip_h + 0.5;
		if (sv > 0.0 && sv < 1.0 && lv < 0.985) {
			float u = bx + TIME * 0.035 + seed;
			float u1 = fract(u);
			float u2 = fract(u + 0.5);
			float w1 = 1.0 - abs(2.0 * u1 - 1.0);           // 0 at u1's wrap, 1 half a tile away (where u2 wraps)
			vec2 ts = vec2(textureSize(surface_tex, 0));
			float inset = 2.0 / ts.x;
			float sx = strip.x + inset;
			float sw = strip.z - 2.0 * inset;
			float sy = strip.y + strip.w * sv;
			vec2 gx = vec2(dFdx(bx) * sw, dFdx(uv.y) / strip_h * strip.w);
			vec2 gy = vec2(dFdy(bx) * sw, dFdy(uv.y) / strip_h * strip.w);
			float sa1 = textureGrad(surface_tex, vec2(sx + sw * u1, sy), gx, gy).a;
			float sa2 = textureGrad(surface_tex, vec2(sx + sw * u2, sy), gx, gy).a;
			float sa = mix(sa2, sa1, w1) * smoothstep(0.02, 0.2, la);
			o = over(o, mix(lc, vec3(1.0), 0.45), sa * min(1.0, liquid_a + 0.2));
		}
	}
	vec4 r = texture(rim_tex, uv);
	o = over(o, rim_col.rgb, r.a * rim_col.a);
	if (rim_lit_col.a > 0.0) {                          // the ring lights with the goo: from the bottom up to the waterline
		float lit = step(body.y + body.w * (1.0 - clamp(level, 0.0, 1.0)) - 0.002, uv.y);
		o = over(o, rim_lit_col.rgb * (1.0 + 0.3 * glow), texture(rim_lit_tex, uv).a * rim_lit_col.a * lit);
	}
	// GMN-2: COLOR.a here already carries the glass's alpha, which clipped every ring outside the glass (r 127): the skill
	// window's neon at r 130 never showed. Fade by the node's modulate only.
	COLOR = vec4(o.rgb / max(o.a, 0.0001), o.a * vcol.a);
}
