class_name Mats
extends RefCounted
## Shared, cached materials: seat lights and vat ooze for the kit, goo and creatures for hordes,
## state colours for relays, and the Alpha 12 effect materials (shield, rings, beams, construction).

static var _cache := {}
const CREATURE_SHADER := preload("res://shaders/creature.gdshader")


static func light(seat: String) -> StandardMaterial3D:
	return light_color(Rules.seat_color(seat), "light_" + Rules.seat_color(seat).to_html())


static func light_color(c: Color, key := "") -> StandardMaterial3D:
	## An emissive light strip in any colour (relay state colours on decks and towers).
	if key == "":
		key = "lc_" + c.to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 3.0
		_cache[key] = m
	return _cache[key]


static func ooze(seat: String) -> StandardMaterial3D:
	var key := "ooze_" + Rules.seat_color(seat).to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		var c: Color = Rules.seat_color(seat)
		m.albedo_color = c * 0.6
		m.roughness = 0.2
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.2
		_cache[key] = m
	return _cache[key]


static func goo(seat: String) -> StandardMaterial3D:
	var key := "goo_" + Rules.seat_color(seat).to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		var c: Color = Rules.seat_color(seat)
		m.albedo_color = Color(c.r * 0.55, c.g * 0.55, c.b * 0.55)
		m.roughness = 0.1
		m.clearcoat_enabled = true
		m.clearcoat = 0.6
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.9
		_cache[key] = m
	return _cache[key]


static func creature(faction: String, seat: String, tex: Texture2D) -> ShaderMaterial:
	## Body hue = seat colour (hue-shifted texture), race colour as a rim accent (rules §5).
	var key := "cr_%s_%s" % [faction, Rules.seat_color(seat).to_html()]
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = CREATURE_SHADER
		m.set_shader_parameter("albedo_tex", tex)
		var seat_hue: float = Rules.seat_color(seat).h
		m.set_shader_parameter("hue_shift", fposmod(seat_hue - Rules.FACTIONS[faction][0], 1.0))
		m.set_shader_parameter("accent", Rules.FACTIONS[faction][1])
		_cache[key] = m
	return _cache[key]


static func seam() -> StandardMaterial3D:
	## The hot line where two hordes' goo meets at a frontline.
	if not _cache.has("seam"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 1.0, 1.0)
		m.roughness = 0.05
		m.emission_enabled = true
		m.emission = Color(1.0, 0.98, 0.9)
		m.emission_energy_multiplier = 2.4
		_cache["seam"] = m
	return _cache["seam"]


static func line(seat: String) -> StandardMaterial3D:
	var key := "line_" + Rules.seat_color(seat).to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Rules.seat_color(seat)
		m.no_depth_test = true
		_cache[key] = m
	return _cache[key]


static func glow(c: Color, alpha := 1.0, unshaded := true, key := "") -> StandardMaterial3D:
	## Unshaded emissive colour, optionally translucent - rings, beams, warnings, overlays.
	if key == "":
		key = "glow_%s_%.2f_%s" % [c.to_html(), alpha, str(unshaded)]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(c.r, c.g, c.b, alpha)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.6
		if alpha < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache[key] = m
	return _cache[key]


static func shield(seat: String) -> StandardMaterial3D:
	## The regenerating shield: a translucent dome of the owner's goo colour over the river.
	var key := "shield_" + Rules.seat_color(seat).to_html()
	if not _cache.has(key):
		var c: Color = Rules.seat_color(seat)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(c.r, c.g, c.b, 0.16)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.7
		m.roughness = 0.05
		m.cull_mode = BaseMaterial3D.CULL_FRONT           # the far wall only: reads as a dome, not a blob
		m.no_depth_test = false
		_cache[key] = m
	return _cache[key]


static func construction() -> StandardMaterial3D:
	## The build state: the kit's construction yellow, pulsing (see Fx).
	return glow(Rules.state_color("build"), 0.85, true, "construction")


static func ghost(c: Color) -> StandardMaterial3D:
	## A tinted, translucent version of a piece: the NEXT relay state's preview during a warning.
	var key := "ghost_" + c.to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(c.r, c.g, c.b, 0.28)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.9
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_cache[key] = m
	return _cache[key]
