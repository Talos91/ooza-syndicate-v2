shader_type spatial;
// WORLD LAYER: the LOCALS (gray native goo, QUEUE KIT on the lab prop sheet): one MultiMesh for all of them, no skeletons.
// INSTANCE_CUSTOM = (phase, walk 0..1, squeeze 0..1 (<0: stretched up), -). The walk is a hop-bob (stretch up, squash on
// landing), the squeeze at the door narrows and flattens it. A pear blob with a flat foot, glossy gray under a fixed sun,
// a small sad face on the front (-Z, the walking direction). Gray only. Unshaded like the floor props (no real light).
render_mode fog_disabled, unshaded, cull_back;

uniform vec3 abyss : source_color = vec3(0.02, 0.02, 0.03);
uniform float haze = 0.12;
uniform vec3 goo : source_color = vec3(0.44, 0.45, 0.50);
uniform float bob_hz = 1.9;      // hops per second while walking

varying vec3 lp;
varying vec3 wn;

void vertex() {
	vec4 cu = INSTANCE_CUSTOM;
	lp = VERTEX;
	vec3 v = VERTEX;
	v.y = max(v.y, -0.32);                                    // a flat foot
	v.xz *= 1.0 - 0.28 * clamp(v.y + 0.1, 0.0, 1.0);          // pear: narrower on top
	float hop = abs(sin((TIME * bob_hz + cu.r) * PI)) * cu.g;
	float sq = 0.12 * hop - 0.08 * (1.0 - hop) * cu.g;
	v.y *= 1.0 + sq;
	v.xz *= 1.0 - sq * 0.6;
	v.y += 0.18 * hop * (1.0 - 0.6 * smoothstep(0.0, 0.3, cu.g - 0.3) * 0.0);
	float s = clamp(cu.b, -1.0, 1.0);
	if (s > 0.0) {                                            // squeezing through the door: narrow + tall, then gone
		v.x *= 1.0 - 0.55 * s;
		v.y *= 1.0 + 0.25 * s;
		v.z *= 1.0 + 0.5 * s;
	} else {                                                  // rising out of the pool: stretched up
		v.y *= 1.0 - s * 0.6;
		v.xz *= 1.0 + s * 0.25;
	}
	VERTEX = v;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wn);
	vec3 L = normalize(vec3(0.35, 1.0, 0.55));
	float lam = 0.55 + 0.45 * clamp(dot(n, L), 0.0, 1.0);
	vec3 Lv = normalize((VIEW_MATRIX * vec4(L, 0.0)).xyz);
	float spec = pow(clamp(dot(normalize(Lv + VIEW), NORMAL), 0.0, 1.0), 28.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 c = goo * lam + vec3(0.9) * spec * 0.5 + vec3(0.6, 0.62, 0.68) * fres * 0.25;
	if (lp.z < -0.25) {                                       // the face, on the front
		vec2 e = vec2(abs(lp.x) - 0.15, lp.y - 0.06);
		float eye = 1.0 - smoothstep(0.045, 0.06, length(e));
		float mouth_y = -0.12 - 1.6 * lp.x * lp.x;            // a frown
		float mouth = (1.0 - smoothstep(0.018, 0.03, abs(lp.y - mouth_y + 0.0) - 0.0)) * step(abs(lp.x), 0.12);
		mouth *= step(lp.y, -0.08);
		c = mix(c, vec3(0.05, 0.05, 0.06), max(eye, mouth * 0.9));
	}
	ALBEDO = mix(c, abyss * 0.6, haze);
}
