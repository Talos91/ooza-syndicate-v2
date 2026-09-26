shader_type spatial;
// Fight for a tower (Daniele, 0.18.6: "we need an animation for when 2 teams are fighting for a tower"):
// a ring round the platform's lip in both owners' colours - the attacker's arc centred where they came in,
// the garrison's colour round the rest - with a white-hot seam where they meet, dashes marching toward
// each other and a pulse that quickens with the fight rate. On CombatFx's annulus mesh (UV.x = angle / TAU
// from +X toward +Z, UV.y = 0 inner edge .. 1 outer edge). Additive, unshaded.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 col_def : source_color = vec4(0.6, 0.7, 0.8, 1.0);
uniform vec4 col_att : source_color = vec4(1.0, 0.3, 0.3, 1.0);
uniform float att_angle = 0.0;      // radians, atan2(z, x) of the attack's side
uniform float share = 0.25;         // the attacker's arc, as a fraction of the ring
uniform float heat = 0.5;           // the fight's rate, 0..1
uniform float life = 1.0;           // fade in / out

void fragment() {
	float a = UV.x * TAU;
	float d = abs(mod(a - att_angle + PI, TAU) - PI);                  // 0..PI from the attack's centre
	float edge = clamp(share, 0.06, 0.94) * PI + 0.10 * sin(TIME * 7.0 + a * 5.0) * (0.4 + heat);
	float side = smoothstep(edge - 0.16, edge + 0.16, d);             // 0 attacker .. 1 garrison
	vec3 c = mix(col_att.rgb, col_def.rgb, side);
	float seam = exp(-pow((d - edge) / 0.08, 2.0));
	float radial = UV.y;
	float band = smoothstep(0.0, 0.4, radial) * (1.0 - smoothstep(0.62, 1.0, radial));
	float pulse = 0.6 + 0.4 * sin(TIME * (5.0 + 10.0 * heat) - d * 2.5);
	float dir = side * 2.0 - 1.0;                                     // the two sides march at each other
	float dash = 0.7 + 0.3 * smoothstep(0.2, 0.8, sin(a * 22.0 + TIME * 7.0 * dir) * 0.5 + 0.5);
	vec3 outc = c * band * pulse * dash * (1.0 + 1.0 * heat)
			+ vec3(1.0, 0.96, 0.88) * seam * band * (1.1 + 1.6 * heat);
	ALBEDO = outc * life;
	ALPHA = 1.0;
}
