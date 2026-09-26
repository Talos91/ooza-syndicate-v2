class_name Mats
extends RefCounted
## Shared, cached materials: seat lights and vat ooze for the kit, goo and creatures for hordes,
## state colours for relays, the effect materials (rings, beams, construction, relay ghosts) and the
## kit surface detail (detail/apply_detail).

static var _cache := {}
const CREATURE_SHADER := preload("res://shaders/creature.gdshader")
const GLASS_SHADER := preload("res://shaders/kit_glass.gdshader")


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


static func glass(c: Color) -> ShaderMaterial:
	## 0.18.7 kit glass (shaders/kit_glass.gdshader): clear body, lit rim, tinted - the vats' tanks take
	## their owner's colour (Scenery), every other glass the neutral light (apply_detail).
	var key := "glass_" + c.to_html()
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = GLASS_SHADER
		m.set_shader_parameter("tint", c)
		_cache[key] = m
	return _cache[key]


# ------------------------------------------------------------------ Alpha 16 surface detail
# OS_Shell: the 0.18.7 structure housings (vats, cannons, forge, relay housings) - brushed like steel
const DETAILED := {"OS_Plate": "plate", "OS_Dark": "grain", "OS_Steel": "grain", "OS_Recess": "grain", "OS_Shell": "grain"}


static func detail(orig: Material) -> Material:
	## The kit's flat colours get world-space surface detail (Alpha 16 visual pass: "better textures"):
	## deck and platform plates get cell seams and wear, dark metal and steel a brushed grain. Same
	## base colours, metal and roughness; the texture only varies them. Phones and LOW detail skip the
	## normal map (the cache is keyed by that choice, so a Detail toggle applies at the next map build).
	var base := orig as StandardMaterial3D
	if base == null or not DETAILED.has(base.resource_name):
		return orig
	var phone := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	var normals := not phone and not Rules.low_detail
	var key := "detail_%s_%d" % [base.resource_name, int(normals)]
	if _cache.has(key):
		return _cache[key]
	var kind: String = DETAILED[base.resource_name]
	var m := base.duplicate() as StandardMaterial3D
	var tx := _detail_textures(kind, normals)
	m.albedo_texture = tx[0]
	m.roughness_texture = tx[0]
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	if tx[1] != null:
		m.normal_enabled = true
		m.normal_texture = tx[1]
		m.normal_scale = 0.35 if kind == "plate" else 0.25
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * (0.2 if kind == "plate" else 0.45)
	_cache[key] = m
	return m


static func _detail_textures(kind: String, normals: bool) -> Array:
	## [albedo/roughness noise, normal map or null] per detail kind: the three grain materials share
	## one set (same seed and settings, so the pixels are identical).
	var key := "dtex_%s_%d" % [kind, int(normals)]
	if not _cache.has(key):
		var noise := FastNoiseLite.new()
		noise.seed = 7
		if kind == "plate":
			noise.noise_type = FastNoiseLite.TYPE_CELLULAR
			noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
			noise.frequency = 0.012
		else:
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			noise.frequency = 0.02
			noise.fractal_octaves = 4
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.84, 0.84, 0.87) if kind == "plate" else Color(0.8, 0.8, 0.83))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.noise = noise
		tex.color_ramp = ramp
		var ntex: NoiseTexture2D = null
		if normals:
			ntex = NoiseTexture2D.new()
			ntex.width = 256
			ntex.height = 256
			ntex.seamless = true
			ntex.as_normal_map = true
			ntex.bump_strength = 2.5 if kind == "plate" else 1.5
			ntex.noise = noise
		_cache[key] = [tex, ntex]
	return _cache[key]


static func apply_detail(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for s in range(mesh.get_surface_count()):
			var src := mesh.surface_get_material(s)
			if src == null or (mi as MeshInstance3D).get_surface_override_material(s) != null:
				continue
			if DETAILED.has(src.resource_name):
				(mi as MeshInstance3D).set_surface_override_material(s, detail(src))
			elif src.resource_name == "OS_Glass":           # 0.18.7: lit-rim glass instead of a grey film
				(mi as MeshInstance3D).set_surface_override_material(s, glass(Rules.NEUTRAL))
