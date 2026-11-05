shader_type spatial;
// WORLD LAYER: a fall's splat on the floor (MultiMesh of flat quads; COLOR = goo colour, INSTANCE_CUSTOM.x = age 0..1,
// .y = seed, .z = how far it has spread 0..1). Lobed blot with a few flung drops, wet centre, fading out.
render_mode fog_disabled, unshaded, blend_mix, depth_draw_never, cull_disabled;

varying vec4 cust;

void vertex() {
	cust = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q);
	float a = atan(q.y, q.x);
	float s = cust.y * 6.2831;
	float lobe = 0.62 + 0.14 * sin(a * 5.0 + s) + 0.08 * sin(a * 9.0 + s * 3.0) + 0.05 * sin(a * 17.0 + s * 7.0);
	float grow = cust.z;
	float blot = smoothstep(lobe * grow, lobe * grow - 0.06, r);
	// flung drops on a ring
	float da = 6.2831 / 9.0;
	float k = floor((a + 3.1416) / da);
	float ca = (k + 0.5) * da - 3.1416;
	float dr = (0.8 + 0.15 * fract(sin(k * 12.9 + s) * 437.5)) * grow;
	vec2 dc = vec2(cos(ca), sin(ca)) * dr;
	float drop = smoothstep(0.075, 0.04, length(q - dc));
	float m = max(blot, drop);
	float wet = smoothstep(0.6, 0.0, r);
	float life = pow(1.0 - clamp(cust.x, 0.0, 1.0), 0.8);
	ALBEDO = COLOR.rgb * (0.5 + 0.55 * wet);
	ALPHA = m * life * 0.9;
}
