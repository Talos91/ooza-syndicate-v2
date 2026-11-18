shader_type canvas_item;
// ROUND 44 B4 (pit_backdrop.gd): the pit's goo floor = the seam-fixed goo tile repeated at its painted period, anchored on
// the lake centre (layout.json pit.floor_tile_period 395 x 258 pt). Only the lake opening of the crust shows it.
uniform sampler2D tile : source_color, repeat_enable, filter_linear_mipmap;
uniform vec2 rect_px = vec2(812.0, 375.0);
uniform vec2 anchor_px = vec2(406.0, 187.5);
uniform vec2 period_px = vec2(395.0, 258.0);

void fragment() {
	vec2 p = UV * rect_px - anchor_px;
	COLOR = vec4(texture(tile, p / period_px + 0.5).rgb, 1.0);
}
