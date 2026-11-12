shader_type spatial;
// LAB LOOK TEST (--look=lab): the surround picture pinned to the screen ("cover" fit, centred), drawn on a plane under the
// board: the board occludes it, it covers the floor where the picture is opaque.
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float tex_aspect = 2.1546;

void fragment() {
	vec2 vp = VIEWPORT_SIZE;
	float va = vp.x / vp.y;
	vec2 uv = SCREEN_UV;
	if (va < tex_aspect) {            // narrower screen: fill the height, crop the sides
		uv.x = 0.5 + (uv.x - 0.5) * va / tex_aspect;
	} else {                          // wider screen: fill the width, crop top / bottom
		uv.y = 0.5 + (uv.y - 0.5) * tex_aspect / va;
	}
	vec4 c = texture(tex, uv);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
