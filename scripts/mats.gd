class_name Mats
extends RefCounted
## Shared, cached materials: seat lights and vat ooze for the kit, goo and creatures for hordes.

static var _cache := {}
const CREATURE_SHADER := preload("res://shaders/creature.gdshader")


static func light(seat: String) -> StandardMaterial3D:
	var key := "light_" + seat
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		var c: Color = Rules.SEATS[seat]
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 3.0
		_cache[key] = m
	return _cache[key]


static func ooze(seat: String) -> StandardMaterial3D:
	var key := "ooze_" + seat
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		var c: Color = Rules.SEATS[seat]
		m.albedo_color = c * 0.6
		m.roughness = 0.2
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.2
		_cache[key] = m
	return _cache[key]


static func goo(seat: String) -> StandardMaterial3D:
	var key := "goo_" + seat
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		var c: Color = Rules.SEATS[seat]
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
	var key := "cr_%s_%s" % [faction, seat]
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = CREATURE_SHADER
		m.set_shader_parameter("albedo_tex", tex)
		var seat_hue: float = (Rules.SEATS[seat] as Color).h
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
	var key := "line_" + seat
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Rules.SEATS[seat]
		m.no_depth_test = true
		_cache[key] = m
	return _cache[key]
