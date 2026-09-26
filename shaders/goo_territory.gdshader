shader_type spatial;
render_mode shadows_disabled;             // no shadow acne on the near-flat slab; cheaper on phones
// GOO territory (GooTerritory, scripts/goo_territory.gd): the goo slab over an owned platform or deck
// half in the owner's player colour. Round 3 of Models/2.0/goo_readability (goo_round2.py goo_material,
// core 0.22 / edge glow 2.2 / power 2.5): a dark glossy core facing the camera (the floor under the
// units stays calm), the colour glowing at grazing angles (fresnel) so the meniscus, the drips and the
// bubbles carry it; clearcoat for the wet highlight. No subsurface (web / phones).
// The value variation through the slab is baked per vertex (COLOR.r, 3-octave noise at 0.35 / m).
// Takeover: inside `front` metres of `origin` (world, plan distance) the goo is col_in, outside col_out;
// has_in / has_out 0 drop that part (a spread over bare deck, a recede). A shared steady material per
// colour keeps front huge; a piece gets its own material only while it animates.

uniform vec3 col_in : source_color = vec3(0.29, 0.47, 1.0);
uniform vec3 col_out : source_color = vec3(0.29, 0.47, 1.0);
uniform float has_in = 1.0;
uniform float has_out = 0.0;
uniform vec3 origin = vec3(0.0);
uniform float front = 100000.0;
uniform float core = 0.22;
uniform float edge_glow = 2.2;
uniform float glow_power = 2.5;
uniform float roughness = 0.3;         // the experiment: 0.12 / clearcoat 1.0 - too much sheen under the game's rim light
uniform float specular = 0.15;
uniform float clearcoat = 0.8;
uniform float wave_glow = 2.4;          // the bright rim of goo as it spreads
uniform float wave_width = 0.7;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = distance(wpos.xz, origin.xz);
	float inside = step(d, front);
	if (inside * has_in + (1.0 - inside) * has_out < 0.5) {
		discard;
	}
	vec3 c = mix(col_out, col_in, inside);
	ALBEDO = c * mix(core * 0.55, core * 1.3, smoothstep(0.35, 0.7, COLOR.r));
	ROUGHNESS = roughness;
	SPECULAR = specular;
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = 0.03;
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), glow_power);
	float wave = (1.0 - smoothstep(0.0, wave_width, abs(d - front))) * step(front, 9999.0);
	EMISSION = c * (f * edge_glow + wave * wave_glow);
}
