shader_type spatial;
// WORLD LAYER: the socket a node's tube stands in on the floor (MultiMesh of flat quads, one per tube; COLOR = the
// owner's goo, alpha 0 = neutral; INSTANCE_CUSTOM.x = the tube's radius as a share of the quad's half size). A steel
// collar, a lit goo ring and four drain channels leading in - it shows where a tube meets the floor even when the
// platform hides the tube itself (steep phone pitches).
render_mode fog_disabled, unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec3 steel : source_color = vec3(0.10, 0.11, 0.14);

varying vec4 cust;

void vertex() {
	cust = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q);
	float rt = cust.x;
	float collar = smoothstep(rt - 0.02, rt, r) * smoothstep(rt + 0.30, rt + 0.27, r);
	float lit = smoothstep(0.035, 0.0, abs(r - (rt + 0.13)));
	float a = atan(q.y, q.x);
	float ch = smoothstep(0.12, 0.06, abs(sin(a * 2.0))) * step(rt + 0.28, r) * smoothstep(0.98, 0.85, r);
	float chl = ch * smoothstep(0.05, 0.0, abs(sin(a * 2.0)));
	vec3 goo = COLOR.a > 0.0 ? COLOR.rgb : vec3(0.32, 0.3, 0.4);
	float g = COLOR.a > 0.0 ? 1.0 : 0.35;
	vec3 c = steel;
	c = mix(c, goo * 0.9 * g, lit);
	c = mix(c, goo * 0.45 * g, chl * 0.8);
	ALBEDO = c;
	ALPHA = max(collar, max(lit, ch * 0.85)) * 0.95 + smoothstep(1.0, rt, r) * 0.25;
}
