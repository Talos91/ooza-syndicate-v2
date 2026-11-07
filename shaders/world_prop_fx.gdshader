shader_type spatial;
// WORLD COMPLETE LAB: the dressing's three translucent passes in one shader (one material per pass, so each is one draw):
//   mode 0 GLASS   the props' glass (specimen tank, pods, bench jars): a cool fresnel sheen, mostly clear
//   mode 1 STEAM   flat steam cards over the vents (no particles): scrolling noise, rising, fading with height
//   mode 2 LIGHT   floor light pools (warm lamp pools, cold panel pools, the drone's soft cone): additive, no real light.
//                  COLOR = tint (rgb) and strength (a); UV.x = 3 for the drone's cone (it follows the drone's orbit,
//                  world_prop.gdshader's kind 3, from the same uniforms)
render_mode fog_disabled, unshaded, depth_draw_never, cull_disabled, blend_mix;

uniform int mode = 0;
uniform vec3 abyss : source_color = vec3(0.02, 0.02, 0.03);
uniform float haze = 0.03;
uniform vec3 drone_c = vec3(0.0);
uniform float drone_r = 6.0;
uniform float drone_w = 0.12;
uniform float strength = 1.0;

varying vec3 wn;
varying vec3 wv;
varying vec2 q;
varying float k3;

void vertex() {
	q = UV2;                    // the card / pool's own 0..1 coordinates
	k3 = 0.0;
	if (mode == 2 && UV.x > 2.5) {
		float a = TIME * drone_w + UV.y;
		VERTEX += vec3(cos(a) * drone_r, 0.0, sin(a) * drone_r);
		k3 = 1.0;
	}
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	wv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	if (mode == 0) {
		vec3 n = normalize(wn);
		vec3 vd = normalize(CAMERA_POSITION_WORLD - wv);
		float fr = pow(1.0 - abs(dot(n, vd)), 2.0);
		float streak = smoothstep(0.75, 0.95, sin(dot(n.xz, vec2(1.0, 0.4)) * 6.0) * 0.5 + 0.5);
		ALBEDO = mix(vec3(0.55, 0.68, 0.8) * 0.9, abyss * 0.6, haze);
		ALPHA = 0.1 + fr * 0.45 + streak * 0.18;
	} else if (mode == 1) {
		float t = TIME * 0.35 + COLOR.r * 7.0;
		vec2 p = vec2(q.x * 2.2 + COLOR.r * 3.0, q.y * 1.6 + t);
		float n = vnoise(p * 2.0) * 0.6 + vnoise(p * 4.3 + 3.1) * 0.4;
		float w = 0.5 - abs(q.x - 0.5);
		float body = smoothstep(0.05, 0.4 - 0.25 * (1.0 - q.y), w * (0.8 + n));
		float h = smoothstep(0.0, 0.12, 1.0 - q.y) * (1.0 - smoothstep(0.35, 1.0, 1.0 - q.y));
		ALBEDO = vec3(0.7, 0.74, 0.8);
		ALPHA = clamp(body * h * (0.35 + 0.65 * n) * 0.55 * strength, 0.0, 1.0);
	} else {
		float r = length(q - 0.5) * 2.0;
		float a = pow(clamp(1.0 - r, 0.0, 1.0), 1.6);
		a *= 0.92 + 0.08 * sin(TIME * (k3 > 0.5 ? 6.0 : 1.3) + COLOR.r * 5.0);
		ALBEDO = COLOR.rgb;
		ALPHA = clamp(a * COLOR.a * strength, 0.0, 1.0);
	}
}
