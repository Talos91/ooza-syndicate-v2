shader_type canvas_item;
render_mode unshaded;

uniform sampler2D chamber_sheen : source_color, filter_linear, repeat_disable;
uniform vec4 ends = vec4(0.5, 1.0, 1.0, 1.0);
uniform vec4 goo_1 : source_color = vec4(1.0, 0.098, 0.671, 1.0);
uniform vec4 goo_2 : source_color = vec4(1.0, 0.231, 0.122, 1.0);
uniform vec4 goo_3 : source_color = vec4(1.0, 0.745, 0.098, 1.0);
uniform vec4 goo_4 : source_color = vec4(0.098, 0.898, 1.0, 1.0);

void fragment() {
	vec4 material = texture(TEXTURE, UV);
	vec4 sheen = texture(chamber_sheen, UV);
	vec3 faction_color = goo_4.rgb;
	if (UV.x < ends.x) {
		faction_color = goo_1.rgb;
	} else if (UV.x < ends.y) {
		faction_color = goo_2.rgb;
	} else if (UV.x < ends.z) {
		faction_color = goo_3.rgb;
	}
	float coverage = 1.0 - step(ends.w, UV.x);
	COLOR = vec4(mix(material.rgb * faction_color, sheen.rgb, sheen.a), material.a * coverage);
}
