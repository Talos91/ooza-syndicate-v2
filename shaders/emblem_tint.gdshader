shader_type canvas_item;
// Faction emblems in the PLAYER's colour (Daniele, Alpha 16: "emblems should take the hue of the colour
// of the player or it's a mess"). The emblem SVGs are drawn in their faction colour with a dark inlay;
// brightness keeps the drawing, the tint replaces the hue.
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float v = max(t.r, max(t.g, t.b));
	COLOR = vec4(tint.rgb * v, t.a * COLOR.a);
}
