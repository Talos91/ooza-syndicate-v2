shader_type spatial;
// ROUND 44 B4 (pit_backdrop.gd, bg-44b4): the river world's goo plane at the goo level, painted with exactly what the 2D background
// shows at that screen pixel (goo tile under CRUST under PIT-RIM, the same frame transform). It is invisible against the backdrop
// but opaque in depth, so a drill / tube ends where it meets the goo surface (Daniele 11-18: the node's base = where its drill meets
// the goo) instead of running on down over the painted ash.
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D goo_tile : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D crust : source_color, filter_linear;
uniform sampler2D rim : source_color, filter_linear;
uniform vec2 vp = vec2(812.0, 375.0);        // canvas px
uniform vec2 frame_o = vec2(0.0);            // frame origin (canvas px)
uniform vec2 frame_s = vec2(1.0);            // frame scale (canvas px per pt)
uniform vec2 ref = vec2(812.0, 375.0);
uniform vec4 rim_pt = vec4(0.0, 0.0, 812.0, 375.0);
uniform vec2 anchor_px = vec2(406.0, 187.5);
uniform vec2 period_px = vec2(395.0, 258.0);
// the Environment's post chain the 2D background never goes through (scenery.gd build_environment): filmic tonemap at `exposure`
// (white `white`), then contrast / saturation on the sRGB result. inv_post() undoes it, so the plane leaves the screen as painted.
uniform float exposure = 0.9;
uniform float white = 1.0;
uniform float contrast = 1.0;
uniform float saturation = 1.0;
uniform bool tonemap_on = true;
uniform float srgb_bias = 0.0;   // measured residual of the 3D path vs the 2D canvas (bg-44b4 shots: ~ -4.5 / 255 flat in sRGB)

vec3 to_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }
vec3 to_srgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c)); }

float filmic_f(float x) {
	const float FA = 0.22 * 4.0;
	const float FB = 0.30 * 2.0;
	const float FC = 0.10;
	const float FD = 0.20;
	const float FE = 0.01;
	const float FF = 0.30;
	return ((x * (FA * x + FC * FB) + FD * FE) / (x * (FA * x + FB) + FD * FF)) - FE / FF;
}

float inv_filmic(float y) {
	const float FA = 0.22 * 4.0;
	const float FB = 0.30 * 2.0;
	const float FC = 0.10;
	const float FD = 0.20;
	const float FE = 0.01;
	const float FF = 0.30;
	float k = y * filmic_f(white) + FE / FF;
	float a = FA * (k - 1.0);
	float b = FB * (k - FC);
	float c = FD * (k * FF - FE);
	float disc = max(b * b - 4.0 * a * c, 0.0);
	return (-b - sqrt(disc)) / (2.0 * a);        // a < 0 for y < 1: the positive root
}

vec3 inv_post(vec3 lin_target) {
	vec3 s = to_srgb(lin_target) + srgb_bias;
	s = (s - 0.5) / contrast + 0.5;
	float l = dot(s, vec3(0.2126, 0.7152, 0.0722));
	s = l + (s - l) / saturation;
	vec3 lin = to_lin(clamp(s, vec3(0.0), vec3(1.0)));
	if (!tonemap_on) {
		return lin;
	}
	return vec3(inv_filmic(lin.r), inv_filmic(lin.g), inv_filmic(lin.b)) / exposure;
}

void fragment() {
	vec2 px = SCREEN_UV * vp;
	vec3 col = texture(goo_tile, (px - anchor_px) / period_px + 0.5).rgb;
	vec2 f = (px - frame_o) / frame_s;
	vec4 c = texture(crust, clamp(f / ref, vec2(0.0), vec2(1.0)));
	col = mix(col, c.rgb, c.a);
	vec2 ru = (f - rim_pt.xy) / rim_pt.zw;
	if (ru.x >= 0.0 && ru.y >= 0.0 && ru.x <= 1.0 && ru.y <= 1.0) {
		vec4 r = texture(rim, ru);
		col = mix(col, r.rgb, r.a);
	}
	ALBEDO = inv_post(col);
}
