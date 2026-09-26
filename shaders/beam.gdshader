shader_type spatial;
// Cannon laser (Daniele, 0.18.6: "laser needs to be made looking good, right now it's still default
// mode"). A camera-facing ribbon from the muzzle (p0) to the target (p1), built on a unit strip mesh
// (VERTEX.x = -1 / +1 across, UV.y = 0..1 along): hot white core, the owner's colour as the outer glow,
// energy noise and pulses scrolling toward the target, soft tapered ends. Additive, no lighting.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, skip_vertex_transform, fog_disabled;

uniform vec3 p0 = vec3(0.0);
uniform vec3 p1 = vec3(0.0, 0.0, 1.0);
uniform vec4 color : source_color = vec4(1.0, 0.3, 0.3, 1.0);
uniform float width = 1.0;          // metres, the glow's full width
uniform float power = 1.0;          // 0..1: charge-in, burst, fade-out
uniform float seed = 0.0;

varying float v_len;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

void vertex() {
	float t = UV.y;
	vec3 axis = p1 - p0;
	float len = max(length(axis), 0.001);
	vec3 ax = axis / len;
	vec3 pos = p0 + axis * t;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 side = normalize(cross(ax, cam - pos));
	float d = min(t * len, (1.0 - t) * len);
	float taper = 0.3 + 0.7 * smoothstep(0.0, 1.6, d);             // narrow at the muzzle and the hit
	float w = width * (0.35 + 0.65 * power) * taper;
	pos += side * sin(t * len * 1.7 - TIME * 31.0 + seed) * 0.05 * width * power;   // a live, humming line
	VERTEX = (VIEW_MATRIX * vec4(pos + side * VERTEX.x * w * 0.5, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	v_len = len;
}

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);                                // 0 on the axis, 1 at the edge
	float along = UV.y * v_len;
	float n1 = noise(along * 0.9 - TIME * 24.0 + seed);
	float n2 = noise(along * 3.3 - TIME * 47.0 + seed * 3.1);
	float energy = 0.6 + 0.5 * n1 * n1 + 0.3 * n2;
	float pulse = smoothstep(0.78, 1.0, fract(along * 0.22 - TIME * 3.4 + seed));   // packets racing out
	float core = exp(-x * x * 60.0);
	float inner = exp(-x * x * 11.0);
	float glow = exp(-x * x * 3.0) * (1.0 - x);
	float ends = smoothstep(0.0, 0.5, along) * smoothstep(0.0, 0.35, v_len - along);
	vec3 c = color.rgb * (glow * 1.1 + inner * 0.9) * (energy + pulse * 0.9)
			+ vec3(1.0) * core * (1.5 + 0.6 * n2 + pulse);
	ALBEDO = c * ends;
	ALPHA = clamp(power, 0.0, 1.0);
}
