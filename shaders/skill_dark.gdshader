shader_type spatial;
// POWERS (0.22.2): the dark goo of the new powers (SkillFx, skill_fx.gd). Alpha-blended (it darkens what is under it,
// like skill_sludge.gdshader), unshaded.
//   mode 0 FOG DOME  Fog of War's cloud: a slow churning dark goo on SkillFx's hemisphere (UV.x round, UV.y rim..top),
//                    a glowing seam in the caster's colour at its foot; `alpha` = how opaque (rivals ~0.9, the caster's
//                    side a veil)
//   mode 1 FOG DISC  the cloud's floor on a plane (UV 0..1): darkest in the middle, ragged at the edge
//   mode 2 HOLE      Sinkhole's pit on a plane: a black hole of goo `opening` 0..1 wide, a bubbling rim in `color`
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 color : source_color = vec4(0.4, 0.9, 0.3, 1.0);
uniform int mode = 0;
uniform float alpha = 0.9;
uniform float opening = 1.0;
uniform float seed = 0.0;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	return noise2(p) * 0.55 + noise2(p * 2.1 + 3.7) * 0.3 + noise2(p * 4.3 + 7.1) * 0.15;
}

void fragment() {
	vec3 goo = vec3(0.035, 0.03, 0.05);
	vec3 c = goo;
	float a = 0.0;
	if (mode == 0) {
		vec2 p = vec2(UV.x * 14.0 + TIME * 0.05, UV.y * 3.0 - TIME * 0.12) + seed;
		float n = fbm(p);
		float n2 = fbm(p * 2.3 - vec2(TIME * 0.2, 0.0));
		c = mix(goo, mix(goo, color.rgb, 0.22), smoothstep(0.55, 0.85, n2)) + vec3(0.02) * n;
		float seam = exp(-UV.y * 9.0);
		c = mix(c, color.rgb * 0.8, seam * 0.6);
		a = alpha * (0.82 + 0.18 * n) * (1.0 - 0.25 * smoothstep(0.7, 1.0, UV.y));
	} else if (mode == 1) {
		vec2 q = UV * 2.0 - 1.0;
		float r = length(q);
		float n = fbm(q * 3.0 + vec2(seed, TIME * 0.1));
		a = alpha * (1.0 - smoothstep(0.8 + 0.12 * n, 1.0, r));
		c = goo + color.rgb * 0.06 * n;
	} else {
		vec2 q = UV * 2.0 - 1.0;
		float r = length(q);
		float ang = atan(q.y, q.x);
		float n = noise2(vec2(ang * 3.0 + seed, TIME * 1.5)) * 0.5 + noise2(vec2(ang * 7.0, TIME * 3.0 + seed)) * 0.3;
		float edge = opening * (0.78 + 0.18 * n);
		float pit = 1.0 - smoothstep(edge - 0.08, edge, r);
		float rim = exp(-pow((r - edge) / 0.07, 2.0)) * step(0.02, opening);
		float bub = step(0.8, noise2(q * 14.0 + vec2(0.0, TIME * 2.0) + seed)) * pit * smoothstep(0.2, edge, r);
		c = mix(goo, color.rgb * 1.2, max(rim, bub * 0.6));
		a = alpha * max(pit, rim);
	}
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0);
}
