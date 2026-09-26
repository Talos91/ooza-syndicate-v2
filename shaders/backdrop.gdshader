shader_type canvas_item;
// The sky behind the arena (Daniele, Alpha 16 visual pass: "a background like Alpha 1"): the cloud city
// drifts very slowly so the scene lives, and it darkens toward the edges and behind the board so the
// platforms, decks and badges always read first.
uniform float zoom = 0.9;            // < 1 shows a slightly enlarged crop so the drift never shows an edge
uniform float drift = 0.035;         // how far the crop wanders (UV units)
uniform float speed = 0.012;         // radians per second of the drift loop
uniform float brightness = 0.62;
uniform vec4 tint : source_color = vec4(0.82, 0.8, 1.0, 1.0);
uniform vec4 abyss : source_color = vec4(0.2, 0.17, 0.37, 1.0);   // 0.18.7: the void's colour (Scenery.ABYSS)
uniform float abyss_haze = 0.34;     // how far the sky behind the board is hazed toward it
void fragment() {
	vec2 wander = vec2(sin(TIME * speed), cos(TIME * speed * 0.7)) * drift;
	vec2 uv = (UV - 0.5) * zoom + 0.5 + wander;              // drift stays inside the (1 - zoom) / 2 margin
	vec3 c = texture(TEXTURE, uv).rgb * tint.rgb * brightness;
	float d = length((UV - 0.5) * vec2(1.25, 1.0));
	c *= mix(1.0, 0.45, smoothstep(0.35, 0.85, d));          // vignette
	c *= mix(0.78, 1.0, smoothstep(0.0, 0.45, d));           // a calmer stage behind the board
	// 0.18.7: the abyss - behind the board the sky thins into the void's colour, so what the height fog
	// swallows (pillars, falling bodies) has no edge against it; the city on the horizon stays clear
	c = mix(c, abyss.rgb, abyss_haze * (1.0 - smoothstep(0.25, 0.8, d)) * smoothstep(0.0, 0.35, UV.y));
	COLOR = vec4(c, 1.0);
}
