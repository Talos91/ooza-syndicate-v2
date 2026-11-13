shader_type canvas_item;
// hud-lab (2026-11-13, round-29/30 lab HUD): the goo inside the HUD's glass - the vat, the score tube and the feed pipes.
// TEXTURE = the pack's WHITE goo master: its alpha is the glass's inside (so the goo never leaves the glass), its grey is the
// painted shading. The game tints it per player, fills it to a level from the match, sloshes the surface, raises bubbles and
// lays a soft glass highlight over it. Nothing is baked: every number comes from the uniforms each frame.
uniform int mode = 0;                 // 0 vat: vertical fill / 1 tube: shares left to right / 2 pipe: full, pulses travel / 3 pipe: fills along
uniform vec4 tint : source_color = vec4(0.18, 0.52, 0.68, 1.0);
uniform float level = 0.5;            // mode 0 / 3: 0..1
uniform float v_top = 0.0;            // mode 0: UV y of 100 % / mode 2-3: UV of the path's start (axis)
uniform float v_bot = 1.0;            // mode 0: UV y of 0 % / mode 2-3: UV of the path's end
uniform float slosh = 0.0;            // 0..1, a fresh change sloshes harder
uniform float wave = 0.006;           // the idle wave's height in UV
uniform float u_left = 0.0;           // mode 1: the goo's span across the texture (UV x)
uniform float u_right = 1.0;
uniform int seats = 2;
uniform vec4 seat_tint[6] : source_color;
uniform float seat_end[6];            // mode 1: cumulative share ends 0..1 across the span
uniform float collar = 0.004;         // mode 1: the white collar at each share's start (UV x)
uniform float pulse_rate = 0.5;       // mode 2: pulses per second along the pipe
uniform float axis = 0.0;             // mode 2 / 3: 0 = the path runs along x, 1 = along y
uniform float aspect = 1.0;           // texture width / height (round bubbles)
uniform float highlight_u = 0.24;     // the glass highlight's place across the goo (0..1 of its width)

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

vec3 goo(vec3 base, float lum, float depth) {
	// the master's shading carries the light; deeper goo is darker
	vec3 c = base * (0.62 + 0.62 * lum);
	return mix(c, c * 0.62, clamp(depth, 0.0, 1.0));
}

void fragment() {
	vec4 m = texture(TEXTURE, UV);
	float a = m.a;
	float lum = dot(m.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = goo(tint.rgb, lum, 0.0);
	float t = TIME;
	if (mode == 0) {
		float surf = mix(v_bot, v_top, clamp(level, 0.0, 1.0));
		float gw = (u_right - u_left);
		float ux = (UV.x - u_left) / max(gw, 0.0001);
		float amp = wave * (1.0 + 4.0 * slosh) * (level >= 0.999 ? 0.35 : 1.0);
		surf += amp * (0.58 * sin(ux * 7.0 + t * 2.1) + 0.42 * sin(ux * 13.0 - t * 3.1));
		surf += slosh * wave * 3.0 * sin(t * 9.0) * (ux - 0.5) * 2.0;
		float d = UV.y - surf;                                 // > 0: under the surface
		a *= smoothstep(-0.0015, 0.0015, d) * step(0.001, level);
		float depth = d / max(v_bot - v_top, 0.0001);
		col = goo(tint.rgb, lum, depth * 0.9);
		col = mix(col, mix(tint.rgb, vec3(1.0), 0.55), (1.0 - smoothstep(0.0, 0.010, d)) * 0.85);   // the meniscus, lit
		for (int i = 0; i < 7; i++) {                          // bubbles rising from the bottom to the surface
			float fi = float(i);
			float sp = 0.06 + 0.05 * hash(fi + 3.0);
			float k = fract(t * sp + hash(fi + 11.0));
			float bx = u_left + gw * (0.18 + 0.64 * hash(fi + 5.0)) + 0.01 * sin(t * 2.0 + fi);
			float by = mix(v_bot, surf, k);
			float r = gw * (0.025 + 0.025 * hash(fi + 17.0));
			float dd = length(vec2((UV.x - bx) * aspect, UV.y - by)) / max(r * aspect, 0.0001);
			float ring = smoothstep(1.0, 0.75, dd) - smoothstep(0.75, 0.45, dd);
			col += vec3(0.55) * ring * step(by, v_bot) * step(surf + 0.01, by);
		}
	} else if (mode == 1) {
		float span = max(u_right - u_left, 0.0001);
		float x = (UV.x - u_left) / span;
		vec3 c = seat_tint[0].rgb;
		float start = 0.0;
		for (int i = 0; i < 6; i++) {
			if (i >= seats) { break; }
			if (x <= seat_end[i] || i == seats - 1) { c = seat_tint[i].rgb; break; }
			start = seat_end[i];
		}
		col = goo(c, lum, 0.0);
		float wob = 0.004 * sin(UV.y * 20.0 + t * 3.0);
		for (int i = 0; i < 5; i++) {                          // the white collar where each share meets the next
			if (i >= seats - 1) { break; }
			float e = u_left + span * seat_end[i] + wob;
			col = mix(col, vec3(1.0), (1.0 - smoothstep(collar * 0.5, collar, abs(UV.x - e))) * 0.9);
		}
		col += vec3(0.10) * sin(UV.x * 40.0 - t * 1.6) * 0.5;     // a slow drift in the goo
	} else {
		float p = mix(UV.x, UV.y, axis);
		float along = (p - v_top) / max(v_bot - v_top, 0.0001);
		if (mode == 3) {
			a *= smoothstep(level + 0.01, level - 0.01, along);
		}
		float pulse = smoothstep(0.82, 1.0, fract(along * 2.0 - t * pulse_rate));
		col = mix(col, mix(tint.rgb, vec3(1.0), 0.6), pulse * 0.75);
	}
	// the glass highlight: a soft streak down the goo (vat) / along its top (tube and pipes)
	if (mode == 0) {
		float hu = u_left + (u_right - u_left) * highlight_u;
		col += vec3(0.22) * exp(-pow((UV.x - hu) / max((u_right - u_left) * 0.05, 0.0001), 2.0));
	} else {
		col += vec3(0.12) * lum;
	}
	COLOR = vec4(col, a * tint.a);
}
