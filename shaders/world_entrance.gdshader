shader_type spatial;
// WORLD LAYER: the TUBE ENTRANCE at a common tube's foot (Models/2.0/world-1.0/build_tube_entrance.py, GLB v1): collar,
// foot housing, the Locals' door, the laser lens, 4 drains. MultiMesh, one instance per r 0.95 tube; INSTANCE_CUSTOM =
// the owner's goo (alpha 0 = unlit). Regions come from the vertex colours: the magenta key (k, 0, k) is the OWNER
// LIGHT (light channel, door frame, the pump glow behind the door, the drains' goo line) at intensity k; the red is the
// lens; the rest is steel / recess shaded by a fixed sun. Unshaded like the floor: no real-time light, no shadows.
render_mode fog_disabled, unshaded, cull_back;

uniform vec3 abyss : source_color = vec3(0.02, 0.02, 0.03);
uniform float haze = 0.12;       // the floor's haze (world_floor.gdshader), so the entrance sits in the same air
uniform float lift = 1.9;
uniform bool kit = false;        // lab-wire: the lab kit's Node_Base (Look.kit_vc_mesh): vertex colours = its linear albedo        // steel brightness against the floor tiles

varying vec4 tint;
varying vec3 wn;

void vertex() {
	tint = INSTANCE_CUSTOM;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 v = COLOR.rgb;
	float sun = 0.5 + 0.5 * clamp(dot(normalize(wn), normalize(vec3(0.35, 1.0, 0.55))), 0.0, 1.0);
	vec3 c = kit ? v * (0.55 + 0.6 * sun) : v * sun * lift;
	bool key = v.g < 0.02 && v.r > 0.03 && abs(v.r - v.b) < 0.03;
	if (key) {
		vec3 g = tint.a > 0.0 ? tint.rgb : vec3(0.36, 0.37, 0.41) * 0.5;
		c = g * (0.35 + 1.1 * v.r);
	} else if (v.r > 0.6 && v.g < 0.3 && v.b < 0.3) {
		c = (tint.a > 0.0 ? tint.rgb : vec3(0.36, 0.37, 0.41) * 0.5) * 1.4;   // the laser lens: the owner's colour (one colour per player, 2026-11-10; was fixed red)
	}
	ALBEDO = mix(c, abyss * 0.6, haze);
}
