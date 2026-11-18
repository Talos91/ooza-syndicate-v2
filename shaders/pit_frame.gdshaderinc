// ROUND 44 B4 REAL 3D PIT (bg-44b4 job c, pit_3d.gd): shared by pit_wall / pit_goo3d. The 3D pit lives INSIDE the painted frame:
// where the 2D CRUST is opaque at this screen pixel the pit fragment is discarded (the crust stays the frame: the near wall and
// anything past the painted shoreline never shows), and the painted PIT-RIM (wet bank) is laid over it. Unshaded + inv_post (as
// pit_mirror.gdshader) so the 3D colours leave the screen as computed, matching the 2D canvas.
uniform sampler2D crust : source_color, filter_linear;
uniform sampler2D rim : source_color, filter_linear;
uniform vec2 vp = vec2(812.0, 375.0);        // canvas px
uniform vec2 frame_o = vec2(0.0);            // frame origin (canvas px)
uniform vec2 frame_s = vec2(1.0);            // frame scale (canvas px per pt)
uniform vec2 ref = vec2(812.0, 375.0);
uniform vec4 rim_pt = vec4(0.0, 0.0, 812.0, 375.0);
uniform float exposure = 0.9;
uniform float white = 1.0;
uniform float contrast = 1.0;
uniform float saturation = 1.0;
uniform bool tonemap_on = false;
uniform float srgb_bias = 0.0;
uniform float clip_alpha = 0.5;              // crust alpha over this = outside the painted hole

vec3 pf_to_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }
vec3 pf_to_srgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c)); }

float pf_filmic(float x) {
	return ((x * (0.88 * x + 0.06) + 0.002) / (x * (0.88 * x + 0.6) + 0.06)) - 0.01 / 0.3;
}

float pf_inv_filmic(float y) {
	float k = y * pf_filmic(white) + 0.01 / 0.3;
	float a = 0.88 * (k - 1.0);
	float b = 0.6 * (k - 0.1);
	float c = 0.2 * (k * 0.3 - 0.01);
	return (-b - sqrt(max(b * b - 4.0 * a * c, 0.0))) / (2.0 * a);
}

vec3 pf_inv_post(vec3 lin_target) {
	vec3 s = pf_to_srgb(lin_target) + srgb_bias;
	s = (s - 0.5) / contrast + 0.5;
	float l = dot(s, vec3(0.2126, 0.7152, 0.0722));
	s = l + (s - l) / saturation;
	vec3 lin = pf_to_lin(clamp(s, vec3(0.0), vec3(1.0)));
	if (!tonemap_on) {
		return lin;
	}
	return vec3(pf_inv_filmic(lin.r), pf_inv_filmic(lin.g), pf_inv_filmic(lin.b)) / exposure;
}

// the frame at this screen pixel: rgb = painted rim colour, a = its alpha; crust alpha in the 2nd value
vec4 pf_rim(vec2 screen_uv, out float crust_a) {
	vec2 f = (screen_uv * vp - frame_o) / frame_s;
	crust_a = texture(crust, clamp(f / ref, vec2(0.0), vec2(1.0))).a;
	vec2 ru = (f - rim_pt.xy) / rim_pt.zw;
	if (ru.x >= 0.0 && ru.y >= 0.0 && ru.x <= 1.0 && ru.y <= 1.0) {
		return texture(rim, ru);
	}
	return vec4(0.0);
}
