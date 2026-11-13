shader_type spatial;
// WORLD LAYER: the TRANSPORT TUBES from the column bases' corner sockets to the pits (scripts/world_tubes.gd). One mesh
// for every tube of the map. UV = (round the tube 0..1, metres from the socket); UV2 = (slot + 0.5, share of the run
// from the column 0..1). The slot's state is one texel of `state`: rgb = the goo colour, a = how far the goo has
// filled the run from the PIT end (0 = empty glass, 1 = full and flowing), a < 0 = no tube (collapsed in vertex()).
// Goo flows PIT -> COLUMN (rule 5, Daniele 2026-11-07 final): the bands and bubbles scroll toward the column. Unshaded like the floor props, with
// the floor's haze, steel couplings every 3 m.
// v2 BUILD (Daniele 2026-11-09: "tube shouldn't just appear all of a sudden ... the same building hologram animation"): row 1
// of `state` holds the slot's build progress (r, 0..1; < 0 = not building). While a vat upgrade builds the tube, this pass
// draws only the part already built - revealed from the COLUMN end along the run - and world_pipe_holo.gdshader (next pass)
// draws the rest as the blueprint hologram, with the seat-coloured front band between them (vat_blueprint's look).
render_mode fog_disabled, unshaded, cull_back;

uniform sampler2D state : filter_nearest, repeat_disable;
uniform float slots = 1.0;
uniform vec3 abyss : source_color = vec3(0.02, 0.02, 0.03);
uniform float haze = 0.12;
uniform float goo_dim = 1.0;      // 1 = the goo colour as is, 0 = black (dev switch / WorldLayer.TUBE_GOO_DIM)
uniform float flow_v = 2.2;      // m/s along the run
// TUBE FLOW (Daniele 2026-11-11 on demo15: "when a tube is completed, its flow animation starts from the NODE end, not from
// the pit"): true = the fill front and the bands start at the column (node) and run toward the pit (WorldTubes.FLOW_FROM_NODE).
uniform bool from_node = true;
uniform bool lab = false;        // LAB LOOK TEST (--look=lab): 26S zones - mint glass, ivory sleeves, detail-grey stand
uniform vec3 lab_sleeve = vec3(0.92, 0.886, 0.82);     // THEMES (LookTheme): the lab's values by default
uniform vec3 lab_stand = vec3(0.443, 0.541, 0.514);
uniform vec3 lab_glass = vec3(0.42, 0.55, 0.54);

varying vec4 st;
varying float bp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	st = texture(state, vec2(UV2.x / slots, 0.25));
	bp = texture(state, vec2(UV2.x / slots, 0.75)).r;
	if (st.a < 0.0) {
		VERTEX = vec3(0.0);                           // no tube in this slot: degenerate
	}
}

void fragment() {
	if (bp >= 0.0 && UV2.y > bp) {
		discard;                                      // not built yet: the hologram pass draws it
	}
	float s = UV.y;                                   // metres from the socket
	float k = from_node ? UV2.y : 1.0 - UV2.y;        // share of the run from where the goo starts (column or pit)
	float fill = st.a;
	float in_goo = step(k, fill) * step(0.0005, fill);
	float flow = from_node ? s - TIME * flow_v : s + TIME * flow_v;   // from_node: toward the pit (s rises)
	float band = 0.5 + 0.5 * sin(flow * 2.4);
	vec2 bc = vec2(floor(UV.x * 8.0), floor(flow * 1.4));
	float bub = step(0.8, hash(bc)) * smoothstep(0.42, 0.1, length(fract(vec2(UV.x * 8.0, flow * 1.4)) - 0.5));
	vec3 goo = st.rgb * (0.75 + 0.3 * band + 0.6 * bub) * goo_dim;
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	vec3 glass = lab ? lab_glass * 0.55 + vec3(0.68, 0.79, 0.78) * fres * 0.5 : vec3(0.07, 0.1, 0.13) + vec3(0.25, 0.35, 0.42) * fres * 0.6;
	vec3 c = mix(glass, goo + vec3(0.6, 0.7, 0.75) * fres * 0.25, in_goo);
	float front = smoothstep(0.02, 0.0, abs(k - fill)) * step(0.0005, fill) * step(fill, 0.999);
	c += vec3(0.9, 1.0, 1.0) * front * 0.7;           // the filling goo's front
	float ring = step(fract(s / 3.0 + 0.5), 0.05);    // steel couplings every 3 m
	if (lab) {
		ring = step(fract(s / 3.0 + 0.5), 0.0933);        // 0.28 m ivory sleeve every 3 m
		c = mix(c, lab_sleeve, ring);
	} else {
		c = mix(c, vec3(0.2, 0.22, 0.26) * 1.6, ring);
	}
	if (bp >= 0.0) {                                  // the build front (the vat ring's band) in the seat colour
		float bf = 1.0 - smoothstep(0.0, 0.025, abs(UV2.y - bp));
		c = mix(c, mix(st.rgb, vec3(1.0), 0.35), bf * step(bp, 0.999));
	}
	if (UV.x < -0.5) {                                // v2: a steel stand under the level run
		float lit = 0.75 + 0.25 * abs(NORMAL.x) + 0.35 * max(NORMAL.y, 0.0);
		c = (lab ? lab_stand : vec3(0.2, 0.22, 0.26)) * lit;
	}
	ALBEDO = mix(c, abyss * 0.6, haze);
}
