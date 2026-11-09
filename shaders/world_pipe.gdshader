shader_type spatial;
// WORLD LAYER: the TRANSPORT TUBES from the column bases' corner sockets to the pits (scripts/world_tubes.gd). One mesh
// for every tube of the map. UV = (round the tube 0..1, metres from the socket); UV2 = (slot + 0.5, share of the run
// from the column 0..1). The slot's state is one texel of `state`: rgb = the goo colour, a = how far the goo has
// filled the run from the PIT end (0 = empty glass, 1 = full and flowing), a < 0 = no tube (collapsed in vertex()).
// Goo flows PIT -> COLUMN (rule 5, Daniele 2026-11-07 final): the bands and bubbles scroll toward the column. Unshaded like the floor props, with
// the floor's haze, steel couplings every 3 m.
render_mode fog_disabled, unshaded, cull_back;

uniform sampler2D state : filter_nearest, repeat_disable;
uniform float slots = 1.0;
uniform vec3 abyss : source_color = vec3(0.02, 0.02, 0.03);
uniform float haze = 0.12;
uniform float flow_v = 2.2;      // m/s toward the column

varying vec4 st;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	st = texture(state, vec2(UV2.x / slots, 0.5));
	if (st.a < 0.0) {
		VERTEX = vec3(0.0);                           // no tube in this slot: degenerate
	}
}

void fragment() {
	float s = UV.y;                                   // metres from the socket
	float k = 1.0 - UV2.y;                            // share of the run from the pit
	float fill = st.a;
	float in_goo = step(k, fill) * step(0.0005, fill);
	float flow = s + TIME * flow_v;                   // toward the socket (s falls)
	float band = 0.5 + 0.5 * sin(flow * 2.4);
	vec2 bc = vec2(floor(UV.x * 8.0), floor(flow * 1.4));
	float bub = step(0.8, hash(bc)) * smoothstep(0.42, 0.1, length(fract(vec2(UV.x * 8.0, flow * 1.4)) - 0.5));
	vec3 goo = st.rgb * (0.75 + 0.3 * band + 0.6 * bub);
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	vec3 glass = vec3(0.07, 0.1, 0.13) + vec3(0.25, 0.35, 0.42) * fres * 0.6;
	vec3 c = mix(glass, goo + vec3(0.6, 0.7, 0.75) * fres * 0.25, in_goo);
	float front = smoothstep(0.02, 0.0, abs(k - fill)) * step(0.0005, fill) * step(fill, 0.999);
	c += vec3(0.9, 1.0, 1.0) * front * 0.7;           // the filling goo's front
	float ring = step(fract(s / 3.0 + 0.5), 0.05);    // steel couplings every 3 m
	c = mix(c, vec3(0.2, 0.22, 0.26) * 1.6, ring);
	ALBEDO = mix(c, abyss * 0.6, haze);
}
