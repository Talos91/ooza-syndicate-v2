shader_type spatial;
// WORLD COMPLETE LAB: the LAB PROP KIT on the floor (Models/2.0/world-1.0/build_lab_props.py -> lab_props_v1.glb), every
// placed prop merged into ONE mesh (one draw). Same look as the containment ring (world_ring.gdshader): unshaded, a fixed
// sun, vertex-colour regions (steel / copper / green key = a gray Local / warm + cool lamps), hazed like the floor.
// Animation, all in this shader (the CPU never touches the mesh after the build): UV.x = kind, UV.y = phase,
// CUSTOM0.xyz = the anchor, UV2 = a vector:
//   1 conveyor rider: anchor = the belt's start (the rider's centre), UV2 = the belt's travel (x, z); it rides and shrinks
//     away at the belt's end, reappearing at its start
//   2 robot arm's upper part: anchor = its turntable axis; it swings about it (yaw), slowly
//   3 the maintenance drone: modelled at the origin; it orbits drone_c at drone_r (rad / s drone_w), bobbing, yawing
render_mode fog_disabled, unshaded, cull_disabled;

uniform vec3 abyss : source_color = vec3(0.02, 0.02, 0.03);
uniform float haze = 0.03;
uniform float lift = 2.5;
uniform float rim_k = 0.35;       // a cool rim so the props read against the floor through the mist
uniform float rider_v = 0.55;     // m/s along the belt
uniform vec3 drone_c = vec3(0.0);
uniform float drone_r = 6.0;
uniform float drone_w = 0.12;

varying vec3 wn;
varying vec3 lp;

vec3 yaw(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

void vertex() {
	int kind = int(UV.x + 0.5);
	float ph = UV.y;
	vec3 n = NORMAL;
	lp = VERTEX - CUSTOM0.xyz;
	if (kind == 1) {
		float len = max(length(UV2), 0.1);
		float f = fract(TIME * rider_v / len + ph);
		float s = smoothstep(0.0, 0.06, f) * (1.0 - smoothstep(0.92, 1.0, f));
		float hop = abs(sin(f * len * 2.2)) * 0.06;
		vec3 local = VERTEX - CUSTOM0.xyz;
		local.y *= 1.0 + 0.08 * sin(TIME * 5.0 + ph * 9.0);
		VERTEX = CUSTOM0.xyz + vec3(UV2.x, 0.0, UV2.y) * f + local * s + vec3(0.0, hop, 0.0);
	} else if (kind == 2) {
		float a = sin(TIME * 0.45 + ph) * 0.75 + sin(TIME * 0.17 + ph * 2.0) * 0.35;
		VERTEX = CUSTOM0.xyz + yaw(VERTEX - CUSTOM0.xyz, a);
		n = yaw(n, a);
	} else if (kind == 3) {
		float a = TIME * drone_w + ph;
		vec3 at = drone_c + vec3(cos(a) * drone_r, 0.18 * sin(TIME * 1.3), sin(a) * drone_r);
		float y = -a - 1.5708;
		VERTEX = at + yaw(VERTEX, y + 0.1 * sin(TIME * 0.7));
		n = yaw(n, y);
	}
	wn = n;
}

void fragment() {
	vec3 v = COLOR.rgb;
	vec3 n = normalize(wn) * (FRONT_FACING ? 1.0 : -1.0);
	float sun = 0.4 + 0.75 * clamp(dot(n, normalize(vec3(0.35, 1.0, 0.55))), 0.0, 1.0);
	vec3 c = v * sun * lift;
	vec3 nv = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	c += vec3(0.5, 0.65, 0.85) * pow(1.0 - clamp(abs(dot(nv, VIEW)), 0.0, 1.0), 3.0) * rim_k;
	if (v.g > 0.5 && v.r < 0.05 && v.b < 0.05) {                       // a gray LOCAL (in a tank, on the belt)
		float rim = pow(1.0 - clamp(abs(n.y), 0.0, 1.0), 2.0);
		float hl = smoothstep(0.75, 0.95, dot(n, normalize(vec3(-0.3, 1.0, 0.4))));
		c = vec3(0.36, 0.37, 0.41) * (0.75 + 0.45 * sun) + vec3(0.55, 0.6, 0.7) * (rim * 0.25 + hl * 0.45);
	} else if (v.r > 0.9 && v.g > 0.4 && v.g < 0.7 && v.b < 0.2) {     // WARM lamp
		c = vec3(1.0, 0.62, 0.22) * 1.25;
	} else if (v.b > 0.9 && v.r > 0.4) {                               // COOL panel / lamp
		c = vec3(0.6, 0.85, 1.0) * 1.15;
	}
	ALBEDO = mix(c, abyss * 0.6, haze);
}
