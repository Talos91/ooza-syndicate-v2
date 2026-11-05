shader_type spatial;
// WORLD LAYER: a node's goo tube - glass held by steel bands, goo flowing UP in the owner's colour. The top `split`
// of the tube holds col_top (an invader's goo pushing in, or the capturer's pushing the old colour down: push = 1
// scrolls the bottom colour downward); alpha 0 = empty glass (neutral). Riders: up to 4 blobs of returning goo
// sliding up inside the glass (world y, colour). Own depth tint toward the void (fog_disabled), capped so the
// tube still reads down to the floor.
render_mode fog_disabled, cull_back;

uniform vec4 col_top : source_color = vec4(0.0);
uniform vec4 col_bot : source_color = vec4(0.0);
uniform float split = 0.0;
uniform float push = 0.0;
uniform float y_top = 0.0;
uniform float y_bot = -16.0;
uniform float fade_top = -4.0;
uniform float fade_max = 0.55;
uniform float glow = 0.42;
uniform vec3 abyss : source_color = vec3(0.2, 0.17, 0.37);
uniform vec4 rider_y = vec4(-999.0);
uniform vec4 rider_c0 : source_color = vec4(1.0);
uniform vec4 rider_c1 : source_color = vec4(1.0);
uniform vec4 rider_c2 : source_color = vec4(1.0);
uniform vec4 rider_c3 : source_color = vec4(1.0);

varying vec3 wpos;
varying vec3 lpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lpos = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float rider(float ry, float y) {
	return smoothstep(0.75, 0.15, abs(y - ry));
}

void fragment() {
	float h = max(y_top - y_bot, 0.01);
	float t = clamp((y_top - wpos.y) / h, 0.0, 1.0);                  // 0 at the top, 1 at the floor
	bool in_top = t < split;
	vec4 gc = in_top ? col_top : col_bot;
	float dir = (!in_top && push > 0.5) ? -1.0 : 1.0;                 // pushed goo runs down, pumped goo up
	float ang = atan(lpos.x, lpos.z);
	float flow = wpos.y - dir * TIME * 2.4;
	float band = 0.5 + 0.5 * sin(flow * 2.1);
	vec2 bc = vec2(floor(ang * 1.6), floor(flow * 1.3));
	float bub = step(0.82, hash(bc)) * smoothstep(0.42, 0.1, length(fract(vec2(ang * 1.6, flow * 1.3)) - 0.5));
	float fill = gc.a;
	vec3 goo = gc.rgb * (0.55 + 0.25 * band + 0.6 * bub);
	float men = in_top ? 0.0 : smoothstep(0.03, 0.0, abs(t - split)) * step(0.001, split) * step(split, 0.999);
	// riders: returning goo blobs climbing the glass
	vec4 rc = vec4(0.0);
	float r;
	r = rider(rider_y.x, wpos.y); rc = mix(rc, vec4(rider_c0.rgb, 1.0), r);
	r = rider(rider_y.y, wpos.y); rc = mix(rc, vec4(rider_c1.rgb, 1.0), r);
	r = rider(rider_y.z, wpos.y); rc = mix(rc, vec4(rider_c2.rgb, 1.0), r);
	r = rider(rider_y.w, wpos.y); rc = mix(rc, vec4(rider_c3.rgb, 1.0), r);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec3 glass = vec3(0.05, 0.075, 0.1);
	vec3 c = mix(glass, goo * 0.5, fill);
	vec3 e = goo * glow * fill;
	c = mix(c, rc.rgb * 0.6, rc.a);
	e = mix(e, rc.rgb * 1.1, rc.a);
	e += vec3(0.9, 1.0, 1.0) * men * 0.8 * max(col_top.a, 0.4);
	e += vec3(0.35, 0.5, 0.6) * fres * 0.35;                          // the glass rim
	float ring = step(fract((y_top - wpos.y) / 3.0), 0.07);            // steel bands every 3 m
	c = mix(c, vec3(0.09, 0.1, 0.12), ring);
	e *= 1.0 - ring;
	float f = clamp((fade_top - wpos.y) / max(fade_top - y_bot, 0.01), 0.0, 1.0) * fade_max;
	ALBEDO = mix(c, abyss * 0.5, f);
	EMISSION = e * (1.0 - f);
	ROUGHNESS = mix(0.15, 0.6, ring);
	METALLIC = ring * 0.6;
}
