shader_type spatial;
// Fight for a tower (Daniele, 0.18.6: "we need an animation for when 2 teams are fighting for a tower"), a progress
// meter since the match-feel pass (2026-09-28: "doesn't tell me if my troops are close to conquer or not; I don't want
// exact numbers, the ring should give me an idea"): a faint track round the platform's lip in the garrison's colour,
// and the attacker's colour sweeping round it from the far side (the top of the screen), clockwise on screen, over the
// share of the fight they are winning (CombatFx._progress: 0 = the garrison holds, 1 = taken). A white-hot head rides
// the sweep's edge, faint quarter ticks mark the track, soft dashes march forward inside the fill and its glow
// quickens a little with the fight rate. On CombatFx's annulus mesh (UV.x = angle / TAU from +X toward +Z, which is
// clockwise on screen from above; UV.y = 0 inner edge .. 1 outer edge). Mixed, not added (the platform's neon rim runs
// under it: added, the attacker's colour would wash into the owner's), unshaded.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 col_def : source_color = vec4(0.6, 0.7, 0.8, 1.0);
uniform vec4 col_att : source_color = vec4(1.0, 0.3, 0.3, 1.0);
uniform float start_angle = 0.0;    // radians, atan2(z, x) of the sweep's start (the platform's far side)
uniform float progress = 0.0;       // 0..1: the attacker's sweep
uniform float heat = 0.5;           // the fight's rate, 0..1
uniform float life = 1.0;           // fade in / out
uniform float track = 0.28;         // the garrison's track opacity
uniform float ticks = 4.0;          // marks on the track (0: none)

void fragment() {
	float a = UV.x * TAU;
	float rel = mod(a - start_angle, TAU) / TAU;                       // 0..1 clockwise from the start
	float p = clamp(progress, 0.0, 1.0);
	float fill = 1.0 - smoothstep(p - 0.006, p + 0.006, rel);          // 1 inside the attacker's sweep
	float radial = UV.y;
	float band = smoothstep(0.0, 0.3, radial) * (1.0 - smoothstep(0.7, 1.0, radial));
	float tick = 0.0;
	if (ticks > 0.5) {
		float q = fract(rel * ticks);
		tick = (1.0 - smoothstep(0.0, 0.012 * ticks, min(q, 1.0 - q))) * band;
	}
	float march = 0.8 + 0.2 * (sin((rel * 40.0 - TIME * (2.0 + 3.0 * heat)) * PI) * 0.5 + 0.5);
	float glow = 1.1 + 0.25 * heat + 0.1 * sin(TIME * (4.0 + 5.0 * heat));
	float head_d = abs(rel - p) * TAU * 6.0;                           // ~metres along the lip from the head
	float head = (p > 0.004 && p < 0.996) ? exp(-head_d * head_d * 3.0) : 0.0;
	vec3 c = mix(col_def.rgb, col_att.rgb * march * glow, fill);
	c = mix(c, vec3(1.0, 0.96, 0.88) * (1.3 + 0.8 * heat), clamp(head, 0.0, 1.0));
	float a_fill = band * fill;
	float a_track = (band * track + tick * 0.5) * (1.0 - fill);
	ALBEDO = c;
	ALPHA = clamp(max(max(a_fill, a_track), head * band), 0.0, 1.0) * life;
}
