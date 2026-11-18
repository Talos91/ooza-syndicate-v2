shader_type canvas_item;
// hud-40b6 (2026-11-15): the 40B5 / 40B6 pipes are painted with NULL goo (faction rgb 255, 25, 171). This swaps that goo for
// `goo` with the delivery's own material model (40B5 cut.json goo_material): t = (r - g) / (255 - 25); reflection = pixel - NULL * t;
// owner = goo * t + reflection. Only goo-coloured pixels (magenta: r > g and b > g) change; cream / sage housings, collars and
// charcoal stay as painted.
uniform vec4 goo : source_color = vec4(1.0, 0.098, 0.671, 1.0);
const vec3 NULLC = vec3(1.0, 0.098, 0.671);

void fragment() {
	vec4 c = COLOR;                                   // = the texture x modulate already (Godot 4 canvas)
	float t = clamp((c.r - c.g) / 0.902, 0.0, 1.0);
	float w = smoothstep(0.04, 0.16, c.b - c.g) * smoothstep(0.12, 0.30, c.r - c.g);
	// the pipe core (t = 0.578, measured 179 / 46 / 117) takes exactly the vat's rendered goo (goo = the vat tint x 1.24, as
	// hud_goo's lit surface), darker / lighter with the painted shading; the glass reflection kept at a third
	vec3 o = clamp(goo.rgb * min(t / 0.578, 1.35) + (c.rgb - NULLC * t) * 0.35, 0.0, 1.0);
	COLOR = vec4(mix(c.rgb, o, w), c.a);
}
