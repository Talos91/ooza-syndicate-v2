shader_type canvas_item;
// An ultimate's cast moment (SkillFx): the screen's edges tint in the caster's colour for a moment.
// Drawn on a full-screen ColorRect that ignores the mouse, under the HUD: it never blocks input.

uniform vec4 color : source_color = vec4(1.0);
uniform float amount = 0.0;

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float e = max(abs(q.x) * 0.92, abs(q.y));
	float edge = smoothstep(0.5, 1.0, e);
	float pulse = 0.85 + 0.15 * sin(TIME * 18.0);
	COLOR = vec4(color.rgb, clamp(amount * edge * edge * 0.5 * pulse, 0.0, 1.0));
}
