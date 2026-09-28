shader_type spatial;
// Under attack (match-feel pass, 2026-09-28: "we need an animation that shows when a building is under attack"): a red
// arc on the rim of YOUR node (an ally's, dimmer) on the side an enemy line is pouring in from, flickering while it
// pours. CombatFx._alarms drives `power` (the flicker, the fade and the ally dimming); the arc's ends fade softly.
// On CombatFx's thin annulus (UV.x = angle / TAU from +X toward +Z, UV.y = 0 inner .. 1 outer edge), just outside
// the lip; additive and drawn over the bodies and the platform's bumpers (no depth test), so it always reads.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.23, 0.19, 1.0);
uniform float att_angle = 0.0;      // radians, atan2(z, x) of the attack's side
uniform float arc = 0.3;            // fraction of the rim lit
uniform float power = 1.0;          // 0..1 (the flicker and fade)

void fragment() {
	float a = UV.x * TAU;
	float d = abs(mod(a - att_angle + PI, TAU) - PI) / PI;           // 0 at the attack's centre .. 1 opposite
	float lit = 1.0 - smoothstep(arc * 0.55, arc, d);
	float radial = UV.y;
	float band = smoothstep(0.0, 0.45, radial) * (1.0 - smoothstep(0.55, 1.0, radial));
	float core = exp(-pow((radial - 0.5) / 0.16, 2.0));
	ALBEDO = (color.rgb * band * 1.6 + vec3(1.0, 0.85, 0.8) * core * 0.35) * lit * power;
	ALPHA = 1.0;
}
