class_name VatColumn
extends Node3D
## VAT COLUMN (Daniele, 2026-11-07; spec 05 Handoff/VAT-COLUMN-2026-11.md) - VIEW ONLY, the rule is Sim.vat_paused:
## "the vat upgrade involves the entire column. T1 has only the front entrance; T2 attaches a second entrance; T3 opens
## the two sides. When an upgrade starts, the column comes out of the closest pit and attaches to the vat entrance only
## when the new tier is reached. While upgrading, the full column (entrance + column + node + structure on the node)
## becomes a BLUEPRINT hologram of the new-tier structure that fills bottom to top."
## - Doors per tier: WorldLayer's per-tier entrance MultiMeshes (tube_entrance_v3_t1/t2/t3), switched when the tier does.
## - Blueprint (Daniele's correction 2026-11-07: "the node shouldn't have the hologram thing as it's not the part upgraded
##   but just the structure and the tube and door"): while a vat upgrade runs (build_kind "vat"), the solid entrance and
##   vat (the build target's model, main already swaps it in) are hidden and drawn as copies in one shared vat_blueprint
##   material, plus a sleeve over the tube; the PLATFORM stays solid. The fill rises with Sim.build_progress - entrance +
##   tube over the first half, the structure over the second (so the part the camera sees fills for 5 of the 10 s).
## - Entrance modules (one per new door: T1->T2 the back door, T2->T3 both sides) rise out of the nearest crater, glide to
##   their sealed port and hover; when the fill reaches the top they dock (DOCK_S), then the column turns solid.
## - Cancelled (capture, Last Stand drop): the blueprint goes at once, the modules sink back.
## Cost: idle = one dictionary read per tube per frame; per upgrade: the vat + entrance + a sleeve drawn again (blended, unshaded).
## Ours: HUD cyan (UiKit.CYAN) lines + the owner's colour in the filled part; no assets from anywhere else.

const BLUEPRINT := preload("res://shaders/vat_blueprint.gdshader")
const MODULE_GLB := "res://assets/world/tube_entrance_v3_module.glb"
const DOORS := [[], [0.0], [0.0, PI], [0.0, PI / 2.0, PI, -PI / 2.0]]   # door yaws per tier, 0 = the front (crater) door
const MODULE_MAX := 8
const RISE := 0.15               # progress share: out of the pit
const GLIDE_END := 0.8           # progress at which the module hovers by its port
const HOVER_OUT := 1.3           # m out from its port while it waits
const HOVER_UP := 0.45
const DOCK_S := 0.4              # s: the dock after the fill reached the top
const LOWER_SHARE := 0.5         # the fill's progress share for entrance + tube (the rest: the structure)

var wl: WorldLayer
var sim: Sim
var vis: Dictionary
var _ups: Dictionary = {}        # tube index -> upgrade view (see _start)
var _mod_mm: MultiMesh
var _mod_free: Array = []
var _t := 0.0
var started := 0                 # probes / shots read these
var docked := 0
var cancelled := 0
static var _showing := {}        # node id -> true while its blueprint shows (Fx skips its grow-from-the-socket look)


static func shows(node_id: int) -> bool:
	return _showing.has(node_id)


func _exit_tree() -> void:
	_showing.clear()


func setup(w: WorldLayer) -> void:
	wl = w
	_showing.clear()
	sim = w.sim
	vis = w.vis
	var mesh: Mesh = WorldLayer._entrance_mesh(MODULE_GLB)
	_mod_mm = MultiMesh.new()
	_mod_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mod_mm.use_custom_data = true
	_mod_mm.use_colors = true
	_mod_mm.mesh = mesh
	_mod_mm.instance_count = MODULE_MAX
	for i in range(MODULE_MAX):
		_mod_mm.set_instance_transform(i, WorldLayer.HIDDEN)
		_mod_mm.set_instance_color(i, Color.WHITE)
		_mod_free.append(i)
	_mod_mm.visible_instance_count = MODULE_MAX if mesh != null else 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mod_mm
	mmi.material_override = wl._ent_mat           # the entrance's own material: same steel, owner light, floor haze
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


static func upgrading(n: Dictionary) -> bool:
	return n["build_kind"] == "vat" and n["structure"] == "vat"


func step(dt: float) -> void:
	_t += dt
	for i in range(wl._tubes.size()):
		var tb: Dictionary = wl._tubes[i]
		if not tb.get("ent", false):
			continue
		var n: Dictionary = sim.nodes[tb["id"]]
		var up = _ups.get(i)
		if up == null:
			if upgrading(n) and tb.get("shown", false) and not sim.collapsed.get(n["id"], false):
				_ups[i] = _start(i, tb, n)
			continue
		if up["phase"] == "fill":
			if upgrading(n) and not sim.collapsed.get(n["id"], false):
				_fill_step(up, tb, n)
			elif int(n["tier"]) == int(up["to"]) and n["owner"] == up["owner"] and not sim.collapsed.get(n["id"], false):
				up["phase"] = "dock"                  # the fill reached the top: the new tier stands
				up["t_dock"] = _t
				_fill_step(up, tb, n)
			else:
				_end(i, up, tb, false)               # cancelled
				continue
		if up["phase"] == "dock":
			var k := clampf((_t - float(up["t_dock"])) / DOCK_S, 0.0, 1.0)
			_modules_step(up, tb, 1.0, k)
			(up["mat"] as ShaderMaterial).set_shader_parameter("strength", 1.0 + 0.8 * sin(k * PI))
			(up["mat"] as ShaderMaterial).set_shader_parameter("t", _t)
			_hide_solid(up)
			if k >= 1.0:
				_end(i, up, tb, true)


func _start(i: int, tb: Dictionary, n: Dictionary) -> Dictionary:
	started += 1
	_showing[n["id"]] = true
	var entry: Dictionary = vis[n["id"]]
	var from := clampi(int(n["tier"]), 1, 3)
	var to := clampi(int(n["build_target"].get("tier", from + 1)), 1, 3)
	var m := ShaderMaterial.new()
	m.shader = BLUEPRINT
	m.set_shader_parameter("line_col", UiKit.CYAN)
	var oc := Rules.seat_color(n["owner"])
	m.set_shader_parameter("fill_col", Color(oc.r, oc.g, oc.b, 1.0))
	m.set_shader_parameter("y_bot", wl.floor_y)
	m.render_priority = 2
	var up := {"phase": "fill", "y_base": 0.0, "from": from, "to": to, "owner": n["owner"], "mat": m, "copies": [],
			"plat": entry.get("platform"), "vat_src": null, "vat_copy": null, "mods": [], "y_mid": 0.0, "y_top": 0.0,
			"t_dock": 0.0}
	# the new tier's entrance, in blueprint
	var ent := MeshInstance3D.new()
	ent.mesh = (wl._ent_mms[to] as MultiMesh).mesh
	ent.material_override = m
	ent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ent)
	ent.transform = tb["ent_xf"]
	up["copies"].append(ent)
	# a sleeve over the tube
	var sl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = float(tb["r"]) + 0.12
	cm.bottom_radius = float(tb["r"]) + 0.12
	cm.height = 1.0
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	sl.mesh = cm
	sl.material_override = m
	sl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sl)
	up["sleeve"] = sl
	up["copies"].append(sl)
	# the tube's top under the platform (the platform itself stays solid)
	var plat = up["plat"]
	if plat is Node3D and is_instance_valid(plat):
		up["y_mid"] = (plat as Node3D).global_position.y + float(tb["top_off"])
	else:
		up["y_mid"] = wl.floor_y + 10.0
	tb["holo"] = true
	wl._sock_lit(tb, tb["base"])
	_vat_copy(up, entry)
	# the entrance modules: one per door the new tier adds, out of the nearest crater
	var have: Array = DOORS[from]
	for yaw in DOORS[to]:
		if yaw in have or _mod_free.is_empty():
			continue
		var slot: int = _mod_free.pop_back()
		_mod_mm.set_instance_custom_data(slot, tb["base"])
		up["mods"].append({"slot": slot, "yaw": float(tb.get("ent_yaw", 0.0)) + float(yaw)})
	up["pit"] = _pit(tb)
	_fill_step(up, tb, n)
	return up


func _pit(tb: Dictionary) -> Vector3:
	## the nearest crater's centre (no Locals / craters: 10 m out in front of the entrance)
	var foot := Vector3(tb["x"], wl.floor_y, tb["z"])
	var best := foot + Basis(Vector3.UP, float(tb.get("ent_yaw", 0.0))) * Vector3(0, 0, 10.0)
	if wl.locals != null and not wl.locals.craters.is_empty():
		var bd := INF
		for c in wl.locals.craters:
			var d: float = Vector2((c as Vector3).x - foot.x, (c as Vector3).z - foot.z).length()
			if d < bd:
				bd = d
				best = c
	return Vector3(best.x, wl.floor_y, best.z)


func _copy(src: Node3D, m: Material) -> Node3D:
	var c := src.duplicate() as Node3D
	MapBatch.show_copy(c)                          # a copy of a batched piece draws itself
	for mi in [c] + c.find_children("*", "MeshInstance3D", true, false):
		if mi is MeshInstance3D:
			(mi as MeshInstance3D).material_override = m
			(mi as MeshInstance3D).layers = 1          # (a duplicate may keep the batch's layers = 0 without its meta)
			(mi as MeshInstance3D).material_overlay = null
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(c)
	c.global_transform = Transform3D(src.global_transform.basis.orthonormalized(), src.global_transform.origin)   # full size
	c.visible = true
	return c


func _vat_copy(up: Dictionary, entry: Dictionary) -> void:
	## the build target's model (main swapped it in when the upgrade started; a skin load may swap it again)
	var src = entry.get("vat_node")
	if src == up["vat_src"]:
		return
	if up["vat_copy"] != null and is_instance_valid(up["vat_copy"]):
		(up["copies"] as Array).erase(up["vat_copy"])
		(up["vat_copy"] as Node).queue_free()
	up["vat_src"] = src
	up["vat_copy"] = null
	if src is Node3D and is_instance_valid(src):
		var c := _copy(src, up["mat"])
		up["vat_copy"] = c
		up["copies"].append(c)
		var top: float = (src as Node3D).global_position.y + 2.0
		up["y_base"] = (src as Node3D).global_position.y
		for mi in c.find_children("*", "MeshInstance3D", true, false):
			var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			top = maxf(top, bb.end.y)
		up["y_top"] = top
		if OS.is_debug_build() and "--vat-column-log" in OS.get_cmdline_user_args():
			print("VAT_COLUMN copy %s: %d meshes, base %.2f top %.2f" % [(src as Node).name, c.find_children("*", "MeshInstance3D", true, false).size(), float(up["y_base"]), top])
	elif float(up["y_top"]) <= 0.0:
		up["y_top"] = float(up["y_mid"]) + 6.0
		up["y_base"] = float(up["y_mid"]) + 3.5


func _hide_solid(up: Dictionary) -> void:
	var v = up["vat_src"]
	if v is Node3D and is_instance_valid(v) and (v as Node3D).visible:
		(v as Node3D).visible = false


func _fill_step(up: Dictionary, tb: Dictionary, n: Dictionary) -> void:
	_vat_copy(up, vis[n["id"]])
	_hide_solid(up)
	var p := Sim.build_progress(n) if up["phase"] == "fill" else 1.0
	var y_mid: float = up["y_mid"]
	var y_top: float = up["y_top"]
	var fy: float
	if p < LOWER_SHARE:
		fy = lerpf(wl.floor_y, y_mid, p / LOWER_SHARE)
	else:
		fy = lerpf(float(up.get("y_base", y_mid)), y_top, (p - LOWER_SHARE) / (1.0 - LOWER_SHARE))
	var m: ShaderMaterial = up["mat"]
	m.set_shader_parameter("y_top", y_top)
	m.set_shader_parameter("fill_y", fy + (0.3 if p >= 1.0 else 0.0))
	m.set_shader_parameter("done", 1.0 if p >= 1.0 else 0.0)
	m.set_shader_parameter("t", _t)
	m.set_shader_parameter("strength", clampf(p * 12.0, 0.35, 1.0))   # fades in over the first second
	var sl: MeshInstance3D = up["sleeve"]
	var h := maxf(y_mid - wl.floor_y, 0.1)
	sl.transform = Transform3D(Basis.from_scale(Vector3(1.0, h, 1.0)), Vector3(tb["x"], wl.floor_y + h / 2.0, tb["z"]))
	_modules_step(up, tb, p, 0.0)


func _modules_step(up: Dictionary, tb: Dictionary, p: float, dock: float) -> void:
	var foot := Vector3(tb["x"], wl.floor_y, tb["z"])
	var pit: Vector3 = up["pit"]
	for md in up["mods"]:
		var b := Basis(Vector3.UP, float(md["yaw"]))
		var out := b * Vector3(0, 0, 1)
		var hover := foot + out * HOVER_OUT + Vector3(0, HOVER_UP + 0.08 * sin(_t * 3.0 + float(md["slot"])), 0)
		var at: Vector3
		if dock > 0.0:                                # slide in, settle on the floor
			var k := dock * dock * (3.0 - 2.0 * dock)
			at = hover.lerp(foot, k)
		elif p < RISE:                                # out of the pit's pool, module turned toward its port already
			var k := p / RISE
			at = pit + Vector3(0, lerpf(-1.6, HOVER_UP, k * k * (3.0 - 2.0 * k)), 0) - out * 1.3
		elif p < GLIDE_END:
			var k := (p - RISE) / (GLIDE_END - RISE)
			k = k * k * (3.0 - 2.0 * k)
			var from := pit + Vector3(0, HOVER_UP, 0) - out * 1.3
			at = from.lerp(hover, k) + Vector3(0, 0.5 * sin(k * PI), 0)
		else:
			at = hover
		_mod_mm.set_instance_transform(int(md["slot"]), Transform3D(b, at))


func _end(i: int, up: Dictionary, tb: Dictionary, done: bool) -> void:
	if done:
		docked += 1
		for md in up["mods"]:                         # a spark burst where each module locks on
			var b := Basis(Vector3.UP, float(md["yaw"]))
			var at := Vector3(tb["x"], wl.floor_y + 0.7, tb["z"]) + b * Vector3(0, 0, 1.4)
			for j in range(6 if not wl._low else 3):
				var a := randf() * TAU
				wl._add_drop(at, Vector3(cos(a) * 2.0, randf_range(1.5, 3.0), sin(a) * 2.0), UiKit.CYAN)
	else:
		cancelled += 1
	for md in up["mods"]:
		_mod_mm.set_instance_transform(int(md["slot"]), WorldLayer.HIDDEN)
		_mod_free.append(int(md["slot"]))
	for c in up["copies"]:
		if c != null and is_instance_valid(c):
			(c as Node).queue_free()
	var v = vis[tb["id"]].get("vat_node")
	if v is Node3D and is_instance_valid(v):
		(v as Node3D).visible = true
	tb["holo"] = false
	_showing.erase(int(tb["id"]))
	wl._sock_lit(tb, tb["base"] if (tb["mi"] as MeshInstance3D).visible else Color(0, 0, 0, 0))
	_ups.erase(i)
