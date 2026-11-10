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
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float cloud_amt = 0.0;       // world-fog: the CLOUD layer, opacity where it is present (0 = none, 1 = fully covers); roams
uniform float fog_amt = 0.0;         // world-fog: the FOG layer underneath, drifting the other way; cloud 0.9 x fog 0.6 overlap = 96 % cover
uniform float cloud_density = 0.55;   // 0 = sparse wisps .. 1 = a solid sheet (how much of the layer is present)
uniform float fog_density = 0.55;
uniform vec4 cloud_col : source_color = vec4(0.27, 0.31, 0.38, 1.0);
uniform vec4 fog_col : source_color = vec4(0.2, 0.24, 0.31, 1.0);
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
	// two roaming layers over the picture (the picture is behind the 3D board, so the play area is never touched):
	// the fog first (under), then the cloud on top; coverage is the noise thresholded so both leave moving gaps
	vec2 q = UV * vec2(2.2, 1.0);
	float nf = texture(noise_tex, q * 0.9 + vec2(TIME * 0.006, TIME * -0.003)).r;
	float nc = texture(noise_tex, q * 0.6 + vec2(TIME * -0.009, TIME * 0.004) + 0.37).r;
	c = mix(c, fog_col.rgb, fog_amt * smoothstep(mix(0.62, -0.1, fog_density), mix(0.62, -0.1, fog_density) + 0.28, nf));
	c = mix(c, cloud_col.rgb, cloud_amt * smoothstep(mix(0.62, -0.1, cloud_density), mix(0.62, -0.1, cloud_density) + 0.3, nc));
	COLOR = vec4(c, 1.0);
}
