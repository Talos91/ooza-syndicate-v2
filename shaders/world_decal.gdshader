shader_type spatial;
// WORLD LAYER: the LAB FLOOR DECALS (director round 5, LAB-FLOOR-DECALS atlas, 32 px/m): one MultiMesh of flat quads
// over the floor, one draw. INSTANCE_CUSTOM = the atlas cell (u0, v0, du, dv) in 0..1; dv < 0 = a lane that repeats
// along its length (the quad's Z scale in metres / lane_m). COLOR = tint (rgb) and opacity (a): the tube-foot pools are
// white in the atlas and take the owner's colour. TRACE (2026-11-11): a lane's Y scale (unused by the flat quad) is its
// reveal 0..1 from the crater end (+Z, UV.y = 1): the part toward the door shows only once the Locals walked it. Hazed and faded exactly as the floor under them (world_floor.gdshader).
render_mode fog_disabled, unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D atlas : source_color, hint_default_transparent, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float lane_m = 16.0;
uniform float gain = 1.0;
uniform float contrast = 1.0;    // marks pushed away from the floor's mean (mid) so they read through the mist
uniform vec3 mid = vec3(0.0296, 0.0409, 0.0656);   // #343C4A (the lab5 floor's mean), linear
uniform vec3 abyss : source_color = vec3(0.2, 0.17, 0.37);
uniform vec2 centre = vec2(0.0);
uniform float r0 = 40.0;
uniform float r1 = 90.0;
uniform float haze = 0.12;

varying vec4 cell;
varying float reps;
varying vec3 wpos;
varying float reveal;

void vertex() {
	cell = INSTANCE_CUSTOM;
	reps = length(MODEL_MATRIX[2].xyz) / lane_m;
	reveal = length(MODEL_MATRIX[1].xyz);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	vec2 g = uv;
	if (cell.w < 0.0) {
		g = vec2(uv.x, uv.y * reps);
		uv.y = fract(g.y);
	}
	vec2 du = abs(cell.zw);
	vec2 a_uv = cell.xy + uv * du;
	vec4 t = textureGrad(atlas, a_uv, dFdx(g) * du, dFdy(g) * du);
	vec3 c = max(mid + (t.rgb - mid) * contrast, vec3(0.0)) * COLOR.rgb * gain;
	float d = length(wpos.xz - centre);
	c = mix(c, abyss * 0.6, haze + (haze > 0.0 ? (1.0 - haze) * 0.7 * smoothstep(r0 * 0.4, r1, d) : 0.0));
	ALBEDO = c;
	float shown = 1.0;
	if (cell.w < 0.0) {                               // a lane: hidden ahead of its walkers, a soft 0.6 m front
		float ahead = (1.0 - reveal - UV.y) * reps * lane_m;   // metres past the revealed end
		shown = (reveal < 0.001) ? 0.0 : 1.0 - smoothstep(-0.6, 0.0, ahead);
	}
	ALPHA = clamp(t.a * COLOR.a, 0.0, 1.0) * (1.0 - smoothstep(r0, r1, d)) * shown;
}
