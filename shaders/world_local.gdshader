shader_type spatial;
// WORLD LAYER: the LOCALS (gray native goo loading the vats) - WORLD PASS 2, GPU-driven (scripts/world_locals.gd).
// One MultiMesh for all of them. The CPU writes a Local's path data ONCE per event (spawn, queue advance, door entry,
// melt) into its instance transform (float32; colour / custom data are half floats in the Compatibility renderer):
//   MODEL_MATRIX[0].xyz = (t_spawn, t_walk0, d0)     the walk: d(t) = min(d0 + walk_v * (now - t_walk0), d1)
//   MODEL_MATRIX[1].xyz = (d1, t_door, feed)          t_door > 0: squeezing in through the door from then;
//                                                     < 0: melting from -t_door (its tube is gone); feed = path row
//   MODEL_MATRIX[2].xyz = (pool x, pool z, seed)      where it wells up in the containment pool
//   MODEL_MATRIX[3].x   = size (x LOCAL_SIZE)
// and the shader does the rest from `now`: rise + stretch out of the pool with two droplets, the hop over the rim and
// the plop on landing, the walk along the feed's path (paths texture: row = feed, texel k = (x, z, distance), texel 16
// = (mouth x, mouth z, points, length)), the hop-bob, the idle breathing in the queue, the squash through the door.
// The look: glossy gray goo, a soft cool rim light so it reads on the dark floor, a small face. Gray only.
// Mesh (world_locals.gd local_mesh): a 10-sided goo drop, 1.0 m long (+Z forward), 30 tris + 2 droplet quads (UV.x 1 / 2).
render_mode fog_disabled, unshaded, cull_back, skip_vertex_transform;

uniform float now = 0.0;
uniform float floor_y = -16.0;
uniform float pool_y = -15.45;
uniform float walk_v = 1.3;
uniform float emerge_t = 1.0;
uniform float hop_t = 1.0;
uniform float squeeze_t = 0.6;
uniform float rim_h = 0.8;
uniform float bob_hz = 1.9;
uniform sampler2D paths : filter_nearest, repeat_disable;
uniform vec3 abyss : source_color = vec3(0.02, 0.02, 0.03);
uniform float haze = 0.12;
uniform vec3 goo : source_color = vec3(0.47, 0.48, 0.53);
uniform vec3 rim_col : source_color = vec3(0.72, 0.80, 0.95);
uniform float rim_k = 0.55;

varying vec3 lp;
varying float droplet;

vec2 along(int f, float d, out vec2 dir) {
	vec4 info = texelFetch(paths, ivec2(16, f), 0);
	int n = int(info.z + 0.5);
	vec4 a = texelFetch(paths, ivec2(0, f), 0);
	dir = vec2(0.0, 1.0);
	for (int k = 1; k < 16; k++) {
		if (k >= n) {
			break;
		}
		vec4 b = texelFetch(paths, ivec2(k, f), 0);
		if (d <= b.z || k == n - 1) {
			float seg = max(b.z - a.z, 0.001);
			dir = (b.xy - a.xy) / seg;
			return mix(a.xy, b.xy, clamp((d - a.z) / seg, 0.0, 1.0));
		}
		a = b;
	}
	return a.xy;
}

void vertex() {
	vec3 c0 = MODEL_MATRIX[0].xyz;
	vec3 c1 = MODEL_MATRIX[1].xyz;
	vec3 c2 = MODEL_MATRIX[2].xyz;
	float sz = MODEL_MATRIX[3].x;
	float t_spawn = c0.x;
	float t_walk0 = c0.y;
	float d0 = c0.z;
	float d1 = c1.x;
	float t_door = c1.y;
	int f = int(c1.z + 0.5);
	vec2 pool = c2.xy;
	float seed = c2.z;
	float age = now - t_spawn;
	lp = VERTEX;
	droplet = UV.x;
	vec3 pos = vec3(pool.x, pool_y, pool.y);
	vec2 dir = vec2(0.0, 1.0);
	vec3 sc = vec3(1.0);                      // x width, y height, z length
	float alive = 1.0;
	float lift = 0.0;
	vec4 info = texelFetch(paths, ivec2(16, f), 0);
	vec2 exit_p = texelFetch(paths, ivec2(0, f), 0).xy;
	if (age < 0.0) {
		alive = 0.0;
	} else if (age < emerge_t) {              // rising out of the pool: up from under the surface, stretched tall
		float k = age / emerge_t;
		float e = 1.0 - pow(1.0 - k, 3.0);
		lift = -0.55 * (1.0 - e);
		float wob = sin(k * 9.0 + seed * 6.0) * 0.08 * (1.0 - k);
		sc = vec3(0.55 + 0.45 * e - wob, 0.5 + 0.9 * e - 0.25 * smoothstep(0.75, 1.0, k), 0.55 + 0.45 * e + wob);
		dir = normalize(exit_p - pool + vec2(0.001));
	} else if (age < emerge_t + hop_t) {      // the hop over the rim: stretched in the air, down onto the floor
		float k = (age - emerge_t) / hop_t;
		pos.xz = mix(pool, exit_p, k);
		pos.y = mix(pool_y, floor_y, k) + sin(k * 3.14159) * (rim_h + 0.7);
		float st = sin(k * 3.14159);
		sc = vec3(1.0 - 0.18 * st, 1.0 + 0.3 * st, 1.0 + 0.1 * st);
		dir = normalize(exit_p - pool + vec2(0.001));
	} else {                                  // on the floor: walk the path to the queue slot (d1), wait there
		float d = min(d0 + walk_v * max(now - t_walk0, 0.0), d1);
		pos.xz = along(f, d, dir);
		pos.y = floor_y;
		bool moving = d < d1 - 0.01;
		float landed = age - emerge_t - hop_t;
		float plop = landed < 0.35 ? sin(landed / 0.35 * 3.14159) * (1.0 - landed / 0.35) : 0.0;
		if (moving) {
			float hop = abs(sin((now * bob_hz + seed * 3.0) * 3.14159));
			lift = 0.14 * hop;
			sc = vec3(1.0 - 0.07 * hop, 1.0 + 0.14 * hop - 0.12 * (1.0 - hop), 1.0 + 0.05 * hop);
		} else {                              // waiting in line: slow breathing
			float br = sin(now * 1.6 + seed * 6.0);
			sc = vec3(1.0 + 0.03 * br, 1.0 - 0.05 * br, 1.0 + 0.03 * br);
		}
		sc *= vec3(1.0 + 0.4 * plop, 1.0 - 0.45 * plop, 1.0 + 0.4 * plop);
		if (t_door > 0.0 && now >= t_door) {  // squeezing in through the door: narrow, long, shrinking into the mouth
			float k = clamp((now - t_door) / squeeze_t, 0.0, 1.0);
			pos.xz = mix(pos.xz, info.xy, k * k);
			dir = normalize(info.xy - pos.xz + dir * 0.001);
			float s = 1.0 - k;
			sc = vec3(1.0 - 0.55 * k, 1.0 - 0.3 * k, 1.0 + 0.6 * k) * max(s, 0.0);
			if (k >= 1.0) {
				alive = 0.0;
			}
		} else if (t_door < 0.0) {            // its tube is gone: it melts where it stands
			float k = clamp((now + t_door) / 0.6, 0.0, 1.0);
			sc *= vec3(1.0 + 0.6 * k, 1.0 - k, 1.0 + 0.6 * k) * (1.0 - k * k);
			if (k >= 1.0) {
				alive = 0.0;
			}
		}
	}
	vec3 fw = normalize(vec3(dir.x, 0.0, dir.y) + vec3(0.0, 0.0, 0.0001));
	vec3 rt = vec3(fw.z, 0.0, -fw.x);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 world;
	vec3 nrm;
	if (UV.x > 0.5) {                         // a droplet: flung out of the pool while it rises, camera-facing
		float j = UV.x - 1.0;
		float tl = age - emerge_t * 0.45 - j * 0.12;
		float a = seed * 6.2831 + j * 2.4;
		vec3 v0 = vec3(cos(a) * 1.4, 3.0 + j * 0.6, sin(a) * 1.4);
		vec3 dp = vec3(pool.x, pool_y + 0.3, pool.y) + v0 * tl + vec3(0.0, -4.9 * tl * tl, 0.0);
		float on = step(0.0, tl) * step(tl, 0.75) * step(pool_y - 0.05, dp.y);
		vec3 cr = INV_VIEW_MATRIX[0].xyz;
		vec3 cu = INV_VIEW_MATRIX[1].xyz;
		world = dp + (cr * VERTEX.x + cu * VERTEX.y) * 0.16 * sz * on;
		nrm = INV_VIEW_MATRIX[2].xyz;
	} else {
		vec3 v = VERTEX * sc * sz;
		world = pos + rt * v.x + up * (v.y + lift * sz) + fw * v.z;
		vec3 nl = NORMAL / max(sc, vec3(0.05));
		nrm = normalize(rt * nl.x + up * nl.y + fw * nl.z);
	}
	world = mix(vec3(pool.x, floor_y - 3.0, pool.y), world, alive);   // gone / not born: collapsed under the floor
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
}

void fragment() {
	if (droplet > 0.5 && length(lp.xy) > 0.5) {
		discard;                                              // round droplets
	}
	vec3 n = normalize(NORMAL);
	vec3 L = normalize((VIEW_MATRIX * vec4(0.35, 1.0, 0.55, 0.0)).xyz);
	float lam = 0.5 + 0.5 * clamp(dot(n, L) * 0.8 + 0.2, 0.0, 1.0);
	float spec = pow(clamp(dot(normalize(L + VIEW), n), 0.0, 1.0), 36.0);
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 2.5);
	vec3 c = goo * lam + vec3(1.0) * spec * 0.55 + rim_col * fres * rim_k;
	c *= mix(0.65, 1.0, smoothstep(0.0, 0.25, lp.y));         // darker where it sits on the floor
	if (droplet < 0.5 && lp.z > 0.28) {                        // the face, on the front (+Z)
		vec2 e = vec2(abs(lp.x) - 0.12, lp.y - 0.34);
		float eye = 1.0 - smoothstep(0.04, 0.055, length(e));
		float mouth_y = 0.2 - 1.4 * lp.x * lp.x;
		float mouth = (1.0 - smoothstep(0.015, 0.028, abs(lp.y - mouth_y))) * step(abs(lp.x), 0.1);
		c = mix(c, vec3(0.05, 0.05, 0.06), max(eye, mouth * 0.85));
	}
	ALBEDO = mix(c, abyss * 0.6, haze);
}
