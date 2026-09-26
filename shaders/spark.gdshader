shader_type spatial;
// Combat sparks, splats and clash flashes (CombatFx): one MultiMesh of camera-facing quads. Per instance
// COLOR = rgb and brightness (a), INSTANCE_CUSTOM = world velocity (xyz, m/s) and size (w, metres): a moving
// spark is drawn as a streak along its screen-space motion, a still one as a round glow. Additive.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, skip_vertex_transform, fog_disabled;

uniform float stretch = 0.05;       // seconds of motion folded into a streak's length

varying vec4 v_col;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - c);
	vec3 vel = INSTANCE_CUSTOM.xyz;
	vec3 across = vel - dot(vel, to_cam) * to_cam;
	float sp = length(across);
	vec3 ax = sp > 0.05 ? across / sp : INV_VIEW_MATRIX[0].xyz;
	vec3 side = normalize(cross(ax, to_cam));
	float size = INSTANCE_CUSTOM.w;
	float len = size + sp * stretch;
	vec3 w = c + ax * VERTEX.x * len + side * VERTEX.y * size;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	v_col = COLOR;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = dot(q, q);
	float g = max(exp(-r * 3.2) - 0.04, 0.0);
	float core = exp(-r * 16.0);
	ALBEDO = v_col.rgb * g * 1.7 + vec3(1.0) * core * 0.9;
	ALPHA = clamp(v_col.a, 0.0, 1.0);
}
