shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never;
// Vat liquid (Alpha 16 visual pass: "the vats were supposed to fill their liquids based on how many
// units were inside"). The tank's OS_Ooze surface is cut at `level` (model-space height), with a
// wobbling, glowing surface band, slow rising bubbles and a deeper colour at the bottom. Back faces
// show through the open top so the liquid reads as a volume.
uniform vec4 liquid_color : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform float level = 2.0;
uniform float y_min = 0.9;
uniform float y_max = 4.0;
uniform float agitation = 0.0;       // 0 calm .. 1 (construction / fighting)
varying vec3 lpos;
void vertex() {
	lpos = VERTEX;
}
void fragment() {
	float wob = sin(TIME * 2.3 + lpos.x * 3.1 + lpos.z * 2.3) * (0.035 + 0.06 * agitation)
			+ sin(TIME * 3.7 - lpos.z * 4.0) * 0.015;
	float top = level + wob;
	if (lpos.y > top) {
		discard;
	}
	float h = clamp((lpos.y - y_min) / max(y_max - y_min, 0.01), 0.0, 1.0);
	vec3 c = liquid_color.rgb;
	ALBEDO = c * mix(0.35, 0.6, h);
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	float surface = smoothstep(0.14, 0.0, top - lpos.y);                       // glowing meniscus
	vec2 g = vec2((lpos.x + lpos.z) * 5.0, lpos.y * 5.0 - TIME * (1.4 + 2.0 * agitation));   // sparse rising bubbles
	vec2 cell = floor(g);
	float rnd = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	float bubbles = rnd > 0.8 - 0.15 * agitation ? smoothstep(0.24, 0.0, length(fract(g) - 0.5)) : 0.0;
	float e = mix(0.55, 1.05, h) + surface * 1.4 + bubbles * 1.6;
	EMISSION = c * e * (FRONT_FACING ? 1.0 : 0.65);
	ALPHA = clamp((FRONT_FACING ? 0.5 : 0.32) + surface * 0.35, 0.0, 0.92);   // see the residents inside (Alpha 11)
}
