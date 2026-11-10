shader_type canvas_item;
// ui-r19-import (round 19, DELIVERY.md "White-core rendering matters"; designer Q2 = adopt): the two-tone emissive ramp for the
// greyscale W tube layers. The tint C is the draw call's modulate colour (vertex COLOR: the player's goo, a slot colour, a banner
// tint), so one material serves every tube. v = W intensity (red channel):
//   white = clamp((v - 0.70) / 0.30, 0, 1)^2 * 0.92
//   rgb   = mix(C, white_rgb, white) * min(v / 0.70, 1)
// The W layer's alpha is kept (x the tint's alpha). Halos do NOT use this: they keep the plain multiply tint.

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 w = texture(TEXTURE, UV);
	float v = w.r;
	float white = pow(clamp((v - 0.70) / 0.30, 0.0, 1.0), 2.0) * 0.92;
	vec3 rgb = mix(tint.rgb, vec3(1.0), white) * min(v / 0.70, 1.0);
	COLOR = vec4(rgb, w.a * tint.a);
}
