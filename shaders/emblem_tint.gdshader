shader_type canvas_item;
// Faction emblems in the PLAYER's colour (Daniele, Alpha 16: "emblems should take the hue of the colour
// of the player or it's a mess"). The emblem SVGs are drawn in their faction colour with a dark inlay;
// brightness keeps the drawing, the tint replaces the hue.
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	// the race emblems v2 (Alpha 21) are neon over dark metal: the metal would tint to a muddy dark blob at badge size, so
	// the value is lifted - the neon ring and glyph read at full strength, the dark body falls away
	float raw = max(t.r, max(t.g, t.b));
	float v = smoothstep(0.12, 0.62, raw);
	COLOR = vec4(tint.rgb * v, t.a * COLOR.a * smoothstep(0.04, 0.3, raw));
}
