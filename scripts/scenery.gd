class_name Scenery
extends Node3D
## Alpha 16 visual pass (Daniele: "a background like Alpha 1 ... the vats were supposed to fill their
## liquids based on how many units were inside them, and the liquids in Alpha 11 contained some small
## creatures with a small animation"):
## - the sky: the cloud city behind the arena on a background canvas layer, drifting slowly, darker at
##   the edges and behind the board (shaders/backdrop.gdshader);
## - vat liquid: each vat's OS_Ooze surface gets its own liquid material cut at a level that follows
##   the garrison against the vat's cap, easing up and down, rippling harder while it builds or fights
##   (shaders/vat_liquid.gdshader) - the tank itself is the unit gauge;
## - residents: small creatures of the owner's faction float in every tank of an owned vat (Alpha 11's
##   tank residents), more of them as it fills, bobbing, turning and drifting under the surface.

const BACKDROP_SHADER := preload("res://shaders/backdrop.gdshader")
const LIQUID_SHADER := preload("res://shaders/vat_liquid.gdshader")
const VOID_SHADER := preload("res://shaders/void_mist.gdshader")
# 0.18.7 look pass: the void under the arena - height fog swallows legs, pillars and pylons as they go
# down, and drifting mist layers with motes sit between the platforms and the sky (make_void)
const FOG_HEIGHT := -1.2             # fog starts just under the platform rims
const FOG_HEIGHT_DENSITY := 0.085    # per metre below FOG_HEIGHT: ~25 % at the legs' feet, ~70 % at -15 m
const FOG_COLOR := Color(0.3, 0.27, 0.5)
const VOID_LAYERS := [[-13.0, 0.3, 0.012], [-34.0, 0.4, 0.007]]   # [height, peak alpha, noise scale]; the
                                                                  # deep layer only at full detail off phones
const RESIDENT_SIZE := 0.62          # metres across a resident (a tank is ~1.7 m wide)
const MAX_PER_TANK := 2
const EASE := 1.8                    # liquid level easing, 1/s

var main: Node3D
var sim: Sim
var vis: Dictionary
var backdrop: CanvasLayer
var _vats := {}                      # node id -> record (see _bind)
static var _tanks := {}              # model key -> {"tanks": [{c, r, y0, y1}], "y0", "y1", "surface"}
var _mesh := {}                      # faction -> creature Mesh
var _res_mat := {}                   # "faction|owner" -> resident ShaderMaterial (seat colours fixed per match)
var _tex := {}
var _scale := {}


static func build_environment(parent: Node, _mobile: bool) -> DirectionalLight3D:
	## The WorldEnvironment and lights (main._build_world; tests/kit_sheet.gd renders the kit under the
	## same light). Returns the sun (main's quality profile turns its shadows off on phones).
	# Alpha 16 visual pass: the cloud-city sky behind the arena (Scenery's canvas layer) and light that
	# belongs to it - violet ambient from the sky, a warm key, a cool violet fill and a back rim that
	# lifts the platform edges off the brighter background.
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -10
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.54, 0.78)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true                             # 0.18.7: height fog only (no distance haze on the board)
	env.fog_light_color = FOG_COLOR
	env.fog_light_energy = 1.0
	env.fog_density = 0.0
	env.fog_height = FOG_HEIGHT
	env.fog_height_density = FOG_HEIGHT_DENSITY
	env.adjustment_enabled = true                      # a touch more punch for the neon and the owner colours
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.94, 0.86)
	sun.shadow_enabled = true
	parent.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-60, -145, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.62, 0.58, 1.0)
	parent.add_child(fill)
	var rim := DirectionalLight3D.new()                # from behind the board, toward the camera
	rim.rotation_degrees = Vector3(-18, 180.0 + rad_to_deg(Rules.view_yaw), 0)
	rim.light_energy = 0.55
	rim.light_color = Color(0.7, 0.62, 1.0)
	parent.add_child(rim)
	return sun


static func make_backdrop(parent: Node) -> CanvasLayer:
	## The cloud-city sky on a background canvas layer (drawn by the Environment as the background).
	var layer := CanvasLayer.new()
	layer.layer = -50
	var sky := TextureRect.new()
	sky.texture = load("res://assets/art/city-background.png")
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = BACKDROP_SHADER
	sky.material = mat
	layer.add_child(sky)
	parent.add_child(layer)
	return layer


static func make_void(parent: Node, centre: Vector3, extent: Vector2, full: bool) -> Array:
	## Mist layers under the arena (shaders/void_mist.gdshader), sized to the map with a wide margin so
	## their soft edges sit off screen. Phones and LOW detail get the near layer only.
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	var out := []
	for i in range(VOID_LAYERS.size() if full else 1):
		var layer: Array = VOID_LAYERS[i]
		var mi := MeshInstance3D.new()
		var quad := PlaneMesh.new()
		quad.size = extent * (2.4 + 0.6 * i) + Vector2(120.0, 120.0)
		mi.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = VOID_SHADER
		mat.set_shader_parameter("noise_tex", tex)
		mat.set_shader_parameter("density", layer[1])
		mat.set_shader_parameter("scale", layer[2])
		mat.set_shader_parameter("motes", 1.0 if i == 0 else 0.6)
		mat.set_shader_parameter("wind", Vector2(0.006, 0.0025) * (1.0 - 0.4 * i))
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = centre + Vector3(0, layer[0], 0)
		parent.add_child(mi)
		out.append(mi)
	return out


func setup(m: Node3D, s: Sim, v: Dictionary) -> void:
	main = m
	sim = s
	vis = v
	backdrop = make_backdrop(m)
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for n in s.nodes:
		lo = lo.min(n["pos"])
		hi = hi.max(n["pos"])
	make_void(self, (lo + hi) / 2.0, Vector2(hi.x - lo.x, hi.z - lo.z), not (Rules.low_detail or main.mobile))
	for f in Rules.FACTIONS.keys():
		var root: Node = load("res://assets/units/%s.glb" % f).instantiate()
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			_mesh[f] = (mi as MeshInstance3D).mesh
			break
		root.free()
		if _mesh.has(f):
			var aabb: AABB = (_mesh[f] as Mesh).get_aabb()
			_scale[f] = RESIDENT_SIZE / maxf(maxf(aabb.size.x, aabb.size.z), 0.001)
			var src := (_mesh[f] as Mesh).surface_get_material(0) as BaseMaterial3D
			_tex[f] = src.albedo_texture if src else null


static func tank_info(vat_mesh: Mesh, key: String) -> Dictionary:
	## The tanks of a vat model, from its OS_Ooze surface: vertices grouped into columns across x,
	## each column one tank. Cached per model.
	if _tanks.has(key):
		return _tanks[key]
	var info := {"tanks": [], "y0": 0.0, "y1": 1.0, "surface": -1}
	for s in range(vat_mesh.get_surface_count()):
		var m := vat_mesh.surface_get_material(s)
		if m and m.resource_name.begins_with("OS_Ooze"):
			info["surface"] = s
			var v: PackedVector3Array = vat_mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var pts := Array(v)
			pts.sort_custom(func(a, b): return a.x < b.x)
			var cols := [[pts[0]]]
			for i in range(1, pts.size()):
				if pts[i].x - pts[i - 1].x > 0.35:
					cols.append([])
				cols[-1].append(pts[i])
			var y0 := INF
			var y1 := -INF
			for st in cols:                               # a cylinder has vertices only at its ends: one tank per column
				var lo := Vector3(INF, INF, INF)
				var hi := -lo
				for p in st:
					lo = lo.min(p)
					hi = hi.max(p)
				if (hi - lo).x < 0.4 or (hi - lo).y < 0.3:
					continue                          # a sliver, not a tank
				info["tanks"].append({"c": Vector3((lo.x + hi.x) / 2.0, 0.0, (lo.z + hi.z) / 2.0),
						"r": minf(hi.x - lo.x, hi.z - lo.z) / 2.0, "y0": lo.y, "y1": hi.y})
				y0 = minf(y0, lo.y)
				y1 = maxf(y1, hi.y)
			info["y0"] = y0
			info["y1"] = y1
			break
	_tanks[key] = info
	return info


func _bind(id: int, entry: Dictionary) -> Dictionary:
	## A vat model appeared (map build, upgrade, restore): give its liquid its own material.
	var vn: Node3D = entry["vat_node"]
	var rec := {"vat_node": vn, "mi": null, "mat": null, "info": {}, "fill": -1.0, "residents": [], "glass": -1,
			"res_faction": "", "res_owner": "", "res_n": -1,
			"last_level": INF, "last_col": null, "last_agit": -1.0}   # last values sent to the shader
	for mi in vn.find_children("*", "MeshInstance3D", true, false):
		var info := tank_info((mi as MeshInstance3D).mesh, entry["model_key"])
		if info["surface"] < 0 or (info["tanks"] as Array).is_empty():
			continue
		var mat := ShaderMaterial.new()
		mat.shader = LIQUID_SHADER
		mat.set_shader_parameter("y_min", info["y0"])
		mat.set_shader_parameter("y_max", info["y1"])
		(mi as MeshInstance3D).set_surface_override_material(info["surface"], mat)
		mi.set_meta("vat_liquid", mat)                 # MapBuilder.apply_owner leaves it alone
		rec["mi"] = mi
		rec["mat"] = mat
		rec["info"] = info
		rec["glass"] = glass_surface((mi as MeshInstance3D).mesh)
		break
	return rec


static func glass_surface(mesh: Mesh) -> int:
	for s in range(mesh.get_surface_count()):
		var m := mesh.surface_get_material(s)
		if m and m.resource_name.begins_with("OS_Glass"):
			return s
	return -1


static func glass_tint(owner: String) -> Color:
	## 0.18.7: a vat's tank glass carries its owner's colour at the rim, so an empty tank still says whose it is.
	return Rules.seat_color(owner) if owner != "" else Rules.NEUTRAL


func sync(dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for n in sim.nodes:
		var id: int = n["id"]
		var entry: Dictionary = vis[id]
		var rec: Dictionary = _vats.get(id, {})
		var is_vat: bool = str(entry.get("model_key", "")).begins_with("Vat_") and is_instance_valid(entry.get("vat_node"))
		if sim.collapsed.get(id, false) or not is_vat:
			if not rec.is_empty():
				_clear_residents(rec)
				_vats.erase(id)
			continue
		if rec.is_empty() or rec["vat_node"] != entry["vat_node"]:
			if not rec.is_empty():
				_clear_residents(rec)
			rec = _bind(id, entry)
			_vats[id] = rec
		if rec["mat"] == null:
			continue
		var cap: float = float(Rules.CAPS[n["tier"]])
		var target := clampf(float(n["units"]) / maxf(cap, 1.0), 0.06, 1.0)
		rec["fill"] = target if rec["fill"] < 0.0 else lerpf(rec["fill"], target, minf(1.0, EASE * dt))
		var info: Dictionary = rec["info"]
		var level: float = lerpf(info["y0"], info["y1"], rec["fill"])
		var owner: String = n["owner"]
		var col: Color = Rules.seat_color(owner) if owner != "" else Rules.NEUTRAL * 0.55
		var mat: ShaderMaterial = rec["mat"]
		if absf(level - float(rec["last_level"])) > 0.0005:   # uniforms only when they change
			mat.set_shader_parameter("level", level)
			rec["last_level"] = level
		if rec["last_col"] != col:
			mat.set_shader_parameter("liquid_color", col)
			rec["last_col"] = col
			if rec["glass"] >= 0:
				(rec["mi"] as MeshInstance3D).set_surface_override_material(rec["glass"], Mats.glass(glass_tint(owner)))
		var ag := 1.0 if (n["build_kind"] != "" or not n["siege"].is_empty()) else 0.0
		if ag != float(rec["last_agit"]):
			mat.set_shader_parameter("agitation", ag)
			rec["last_agit"] = ag
		_residents(rec, n, level, t)


func _residents(rec: Dictionary, n: Dictionary, level: float, t: float) -> void:
	var owner: String = n["owner"]
	var faction: String = sim.factions.get(owner, "")
	var per_tank := 0
	if owner != "" and _mesh.has(faction):
		per_tank = clampi(int(ceil(rec["fill"] * MAX_PER_TANK)), 1, MAX_PER_TANK)
		if Rules.low_detail or main.mobile:
			per_tank = 1
	var tanks: Array = rec["info"]["tanks"]
	if rec["res_faction"] != faction or rec["res_owner"] != owner or rec["res_n"] != per_tank:
		_clear_residents(rec)                         # capture or fill step: rebuild the residents
		rec["res_faction"] = faction
		rec["res_owner"] = owner
		rec["res_n"] = per_tank
		if per_tank > 0:
			var mk := faction + "|" + owner
			if not _res_mat.has(mk):
				var dm: ShaderMaterial = (Mats.creature(faction, owner, _tex[faction]) as ShaderMaterial).duplicate()
				dm.set_shader_parameter("self_glow", 0.35)
				_res_mat[mk] = dm
			var m: ShaderMaterial = _res_mat[mk]
			for ti in range(tanks.size()):
				for k in range(per_tank):
					var mi := MeshInstance3D.new()
					mi.mesh = _mesh[faction]
					mi.material_override = m
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(mi)
					(rec["residents"] as Array).append([mi, ti, k])
	var vn: Node3D = rec["vat_node"]
	var xf := vn.global_transform
	var s: float = _scale.get(faction, 1.0)
	var rb := xf.basis.orthonormalized()
	for r in rec["residents"]:
		var mi: MeshInstance3D = r[0]
		var tank: Dictionary = tanks[r[1]]
		var ph: float = r[2] * 2.4 + r[1] * 1.3 + n["id"] * 0.7
		var top := minf(level, tank["y1"]) - RESIDENT_SIZE * 0.45
		var bottom: float = tank["y0"] + RESIDENT_SIZE * 0.45
		mi.visible = top > bottom                      # the liquid is below this tank: nobody home
		if not mi.visible:
			continue
		var y := lerpf(bottom, top, 0.5 + 0.35 * sin(t * 0.9 + ph))
		var swirl: float = tank["r"] * 0.32
		var local: Vector3 = tank["c"] + Vector3(cos(t * 0.55 + ph) * swirl, y, sin(t * 0.55 + ph) * swirl)
		var squash := sin(t * 3.0 + ph) * 0.06        # Alpha 11: a slow breathing squash in the tank
		var basis := Basis(Vector3.UP, t * 0.7 + ph) * Basis.from_scale(Vector3(1.0 + squash * 0.6, 1.0 - squash, 1.0 + squash * 0.45) * s)
		mi.global_transform = Transform3D(rb * basis, xf * local)


func _clear_residents(rec: Dictionary) -> void:
	for r in rec["residents"]:
		if is_instance_valid(r[0]):
			(r[0] as Node).queue_free()
	(rec["residents"] as Array).clear()
	rec["res_faction"] = ""
	rec["res_owner"] = ""
	rec["res_n"] = -1
