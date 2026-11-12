shader_type spatial;
// WORLD LAYER: the CONTAINMENT RING crater (Models/2.0/world-1.0/build_containment_ring.py, GLB v1): segmented steel ring,
// 4 pipe elbows, vent grilles, lamps, and the POOL of gray native goo (the Locals' source). MultiMesh, one instance per
// crater; INSTANCE_CUSTOM.r = a phase so craters do not swirl in step. Regions from the vertex colours: the green key
// (0, k, 0) is the goo pool (a slow swirl, glossy highlights; gray, tinted by R7 pit colour from INSTANCE_CUSTOM.gba), amber / white-blue
// tops are the lamps, the rest steel / recess under a fixed sun. Unshaded like the floor: no real-time light, no shadows.
render_mode fog_disabled, unshaded, cull_disabled;

uniform vec3 abyss : source_color = vec3(0.02, 0.02, 0.03);
uniform float haze = 0.12;       // the floor's haze, so the ring sits in the same air
uniform float lift = 1.9;        // steel brightness against the floor (as the tube entrance)
uniform float swirl_speed = 0.12;
uniform bool lab = false;
uniform bool kit = false;        // lab-wire: the lab kit's Pit (Look.kit_vc_mesh): vertex colours = its linear albedo, lit softly        // LAB LOOK TEST (--look=lab): steel -> ivory shell, dark -> detail recess (26S Pit sheet)

varying vec3 lp;
varying vec3 wn;
varying float ph;
varying vec3 pool;               // PITS / TUBES R7: the pool's colour (INSTANCE_CUSTOM.gba; zero = the native gray)

void vertex() {
	lp = VERTEX;
	ph = INSTANCE_CUSTOM.r;
	pool = INSTANCE_CUSTOM.gba;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 v = COLOR.rgb;
	vec3 n = normalize(wn) * (FRONT_FACING ? 1.0 : -1.0);
	float sun = 0.5 + 0.5 * clamp(dot(n, normalize(vec3(0.35, 1.0, 0.55))), 0.0, 1.0);
	vec3 c = v * sun * lift;
	if (lab) {
		float l = dot(v, vec3(0.333));
		c = mix(vec3(0.239, 0.341, 0.345), vec3(0.918, 0.886, 0.82), smoothstep(0.05, 0.3, l)) * sun * 1.1;
	}
	if (kit) {
		c = v * (0.55 + 0.6 * sun);
	}
	if (v.g > 0.5 && v.r < 0.05 && v.b < 0.05) {                       // GOO POOL
		vec2 p = lp.xz;
		float r = length(p);
		float t = TIME * swirl_speed + ph;
		float a = atan(p.y, p.x) + t + (3.5 - r) * 0.55;               // a slow spiral, faster at the middle
		float w = sin(a * 3.0 + r * 1.7 + sin(r * 2.3 - t * 2.0) * 1.4);
		float w2 = sin(a * 5.0 - r * 2.9 + t * 1.3);
		float g = 0.30 + 0.035 * w + 0.025 * w2;
		float hl = smoothstep(0.82, 0.98, 0.5 + 0.5 * sin(a * 2.0 + r * 3.1 - t * 0.7)) * smoothstep(3.4, 2.0, r);
		float rim = smoothstep(2.6, 3.5, r);                            // darker against the wall
		float bub = smoothstep(0.88, 1.0, sin(p.x * 3.1 + t * 4.0) * sin(p.y * 2.7 - t * 3.0));
		vec3 base = dot(pool, vec3(1.0)) > 0.001 ? pool * 1.03 : vec3(0.37, 0.38, 0.42);
		c = base * (g * 2.1) * (1.0 - 0.35 * rim) + vec3(0.55, 0.56, 0.6) * (hl * 0.3 + bub * 0.2);
	} else if (v.r > 0.9 && v.g > 0.4 && v.g < 0.7 && v.b < 0.2) {     // WARM lamp
		c = vec3(1.0, 0.62, 0.22) * (1.15 + 0.15 * sin(TIME * 1.7 + ph * 3.0));
	} else if (v.b > 0.9 && v.r > 0.4) {                               // COOL lamp
		c = vec3(0.7, 0.85, 1.0) * 1.1;
	}
	ALBEDO = mix(c, abyss * 0.6, haze);
}
