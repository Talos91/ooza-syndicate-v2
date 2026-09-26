shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// The void under the arena (0.18.7 look pass, Daniele: "push the graphic further"): a slow drifting mist
// layer between the platforms and the cloud-city sky, with sparse motes twinkling in it, so the arena
// floats over depth instead of over a flat picture. One quad per layer, two taps of a small tiling
// noise texture and a cell hash for the motes: cheap enough for the phone profile.
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 mist_color : source_color = vec4(0.2, 0.17, 0.4, 1.0);
uniform vec4 glow_color : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform float density = 0.34;        // peak mist alpha
uniform float scale = 0.012;         // noise tiles per metre
uniform vec2 wind = vec2(0.006, 0.0025);
uniform float motes = 1.0;           // 0 = no motes
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wpos.xz;
	float a = texture(noise_tex, p * scale + wind * TIME).r;
	float b = texture(noise_tex, p * scale * 2.3 - wind.yx * TIME * 1.7 + vec2(0.37, 0.61)).r;
	float m = smoothstep(0.3, 1.05, a * 0.62 + b * 0.48);
	vec2 e = abs(UV - 0.5) * 2.0;                                   // soft edges: never a visible quad border
	float edge = (1.0 - smoothstep(0.55, 1.0, e.x)) * (1.0 - smoothstep(0.55, 1.0, e.y));
	vec3 col = mix(mist_color.rgb, glow_color.rgb, smoothstep(0.75, 1.0, m) * 0.18);
	float alpha = m * density * edge;
	// motes: one candidate per 3 m cell, a few percent lit, each blinking on its own phase
	vec2 g = p / 3.0 + vec2(TIME * 0.05, TIME * 0.02);
	vec2 cell = floor(g);
	float h = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	vec2 off = vec2(fract(h * 17.0), fract(h * 29.0)) * 0.6 + 0.2;
	float d = length(fract(g) - off);
	float lit = step(0.93, h) * (0.5 + 0.5 * sin(TIME * (1.0 + h * 2.0) + h * 40.0));
	float mote = smoothstep(0.09, 0.0, d) * lit * motes * edge;
	ALBEDO = col + glow_color.rgb * mote * 2.0;
	ALPHA = clamp(alpha + mote * 0.8, 0.0, 1.0);
}
