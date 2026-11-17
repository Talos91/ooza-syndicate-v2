shader_type spatial;
// DRILL NODE launch: the goo splat a booster jet leaves where a platform stood (Daniele 11-16: the circle a launch leaves
// stays, as a goo splat in the owner's FACTION goo colour). A small grid laid on the goo / bed (Fx._ground_splat); UV 0..1.
// Lobed blot + flung drops (like world_splat), a wet glossy centre and a darker scorched ring where the jet hit; `grow` 0..1
// spreads it, then it stays for the match.
render_mode fog_disabled, unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 col : source_color = vec4(0.36, 0.37, 0.41, 1.0);
uniform float seed = 0.0;
uniform float grow = 1.0;

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q);
	float a = atan(q.y, q.x);
	float s = seed * 6.2831;
	float lobe = 0.66 + 0.11 * sin(a * 5.0 + s) + 0.07 * sin(a * 9.0 + s * 3.0) + 0.04 * sin(a * 17.0 + s * 7.0);
	float g = clamp(grow, 0.0, 1.0);
	float blot = smoothstep(lobe * g, lobe * g - 0.05, r);
	float da = 6.2831 / 11.0;
	float k = floor((a + 3.1416) / da);
	float ca = (k + 0.5) * da - 3.1416;
	float dr = (0.84 + 0.12 * fract(sin(k * 12.9 + s) * 437.5)) * g;
	float drop = smoothstep(0.065, 0.035, length(q - vec2(cos(ca), sin(ca)) * dr));
	float m = max(blot, drop);
	float wet = smoothstep(0.55, 0.0, r);
	float scorch = smoothstep(0.12, 0.0, abs(r - 0.3 * g)) * 0.35;
	float gloss = smoothstep(0.08, 0.0, abs(r - 0.18 - 0.05 * sin(a * 3.0 + s))) * 0.25;
	vec3 c = col.rgb * (0.62 + 0.5 * wet) * (1.0 - scorch) + vec3(gloss);
	ALBEDO = c;
	ALPHA = m * 0.94;
}
