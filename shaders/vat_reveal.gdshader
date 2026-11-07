shader_type spatial;
// VAT COLUMN 2 (Daniele, 2026-11-07): "whatever the top ring has passed takes the structure's ACTUAL colour / material".
// The upgrading vat's real look, clipped at the fill height (clip_y, world y): vat_column.gd builds one of these per
// source StandardMaterial3D of the new tier's model (albedo / texture / vertex colour, metallic, roughness, emission);
// the part above clip_y is discarded, the blueprint ghost draws there. Opaque (the glass variant is made from this
// code with blend_mix). The goo surfaces (OS_Ooze, living liquid) get empty glass instead - tubes stay empty until done.
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float use_tex = 0.0;
uniform float use_vcol = 0.0;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float metallic = 0.0;
uniform float roughness = 1.0;
uniform vec3 emission : source_color = vec3(0.0);
uniform sampler2D emission_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float use_emi_tex = 0.0;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float use_normal = 0.0;
uniform float normal_scale = 1.0;
uniform float clip_y = 100000.0;

varying float wy;

void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	UV = UV * uv_scale.xy + uv_offset.xy;
}

void fragment() {
	if (wy > clip_y) {
		discard;
	}
	vec4 a = albedo;
	if (use_tex > 0.5) {
		a *= texture(albedo_tex, UV);
	}
	if (use_vcol > 0.5) {
		a *= COLOR;
	}
	ALBEDO = a.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	vec3 e = emission;
	if (use_emi_tex > 0.5) {
		e += texture(emission_tex, UV).rgb;
	}
	EMISSION = e;
	//ALPHA
}
