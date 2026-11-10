shader_type canvas_item;
// WORLD COMPLETE LAB: the lab biome's side backdrop (LAB-SIDE A calm / B machinery) on Scenery's sky layer. backdrop.gdshader
// darkens the edges and hazes the middle for the cloud-city sky; here the EDGES are the point (the crust, tanks and pipes
// that frame the board where the floor's district ends), so only a light vignette in the far corners, and the haze toward
// the lab air stays in the middle column behind the board (where the floor covers it anyway at the default camera).
uniform float zoom = 0.94;
uniform float drift = 0.012;
uniform float speed = 0.01;
uniform float brightness = 1.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 abyss : source_color = vec4(0.168, 0.204, 0.263, 1.0);
uniform float abyss_haze = 0.45;     // the middle column's haze toward the lab air
uniform float fog_all = 0.0;         // world-fog: the whole picture incl. the side bands (the pipes) hazed toward the lab air; 0 = off
uniform float side_lift = 1.15;      // the framing machinery a touch brighter than the floor's far haze
void fragment() {
	vec2 wander = vec2(sin(TIME * speed), cos(TIME * speed * 0.7)) * drift;
	vec2 uv = (UV - 0.5) * zoom + 0.5 + wander;
	vec3 c = texture(TEXTURE, uv).rgb * tint.rgb * brightness;
	float side = smoothstep(0.18, 0.40, abs(UV.x - 0.5));       // 0 in the middle column, 1 at the side bands
	c *= mix(1.0, side_lift, side);
	float d = length((UV - 0.5) * vec2(1.1, 1.0));
	c *= mix(1.0, 0.72, smoothstep(0.55, 0.8, d));               // only the far corners darken
	c = mix(c, abyss.rgb, abyss_haze * (1.0 - side));
	c = mix(c, abyss.rgb, fog_all);                              // fog between the play area and the backdrop
	COLOR = vec4(c, 1.0);
}
