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
var _tex := {}
var _scale := {}


func setup(m: Node3D, s: Sim, v: Dictionary) -> void:
	main = m
	sim = s
	vis = v
	backdrop = CanvasLayer.new()
	backdrop.layer = -50                              # drawn by the Environment as the background
	var sky := TextureRect.new()
	sky.texture = load("res://assets/art/city-background.png")
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = BACKDROP_SHADER
	sky.material = mat
	backdrop.add_child(sky)
	m.add_child(backdrop)
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
	var rec := {"vat_node": vn, "mi": null, "mat": null, "info": {}, "fill": -1.0, "residents": [], "resident_key": ""}
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
		break
	return rec


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
		mat.set_shader_parameter("level", level)
		mat.set_shader_parameter("liquid_color", col)
		mat.set_shader_parameter("agitation", 1.0 if (n["build_kind"] != "" or not n["siege"].is_empty()) else 0.0)
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
	var key := "%s|%s|%d" % [faction, owner, per_tank]
	if rec["resident_key"] != key:                    # capture or fill step: rebuild the residents
		_clear_residents(rec)
		rec["resident_key"] = key
		if per_tank > 0:
			var m: ShaderMaterial = (Mats.creature(faction, owner, _tex[faction]) as ShaderMaterial).duplicate()
			m.set_shader_parameter("self_glow", 0.35)
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
		mi.global_transform = Transform3D(xf.basis.orthonormalized() * basis, xf * local)


func _clear_residents(rec: Dictionary) -> void:
	for r in rec["residents"]:
		if is_instance_valid(r[0]):
			(r[0] as Node).queue_free()
	(rec["residents"] as Array).clear()
	rec["resident_key"] = ""
