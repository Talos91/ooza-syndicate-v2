shader_type canvas_item;
// The sky behind the arena (Daniele, Alpha 16 visual pass: "a background like Alpha 1"): the cloud city
// drifts very slowly so the scene lives, and it darkens toward the edges and behind the board so the
// platforms, decks and badges always read first.
uniform float zoom = 0.9;            // < 1 shows a slightly enlarged crop so the drift never shows an edge
uniform float drift = 0.035;         // how far the crop wanders (UV units)
uniform float speed = 0.012;         // radians per second of the drift loop
uniform float brightness = 0.62;
uniform vec4 tint : source_color = vec4(0.82, 0.8, 1.0, 1.0);
void fragment() {
	vec2 wander = vec2(sin(TIME * speed), cos(TIME * speed * 0.7)) * drift;
	vec2 uv = (UV - 0.5) * zoom + 0.5 + wander;              // drift stays inside the (1 - zoom) / 2 margin
	vec3 c = texture(TEXTURE, uv).rgb * tint.rgb * brightness;
	float d = length((UV - 0.5) * vec2(1.25, 1.0));
	c *= mix(1.0, 0.45, smoothstep(0.35, 0.85, d));          // vignette
	c *= mix(0.78, 1.0, smoothstep(0.0, 0.45, d));           // a calmer stage behind the board
	COLOR = vec4(c, 1.0);
}
