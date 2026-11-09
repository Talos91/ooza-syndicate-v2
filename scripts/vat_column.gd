class_name VatColumn
extends Node3D
## VAT COLUMN (Daniele, 2026-11-07; spec 05 Handoff/VAT-COLUMN-2026-11.md) - VIEW ONLY, the rule is Sim.vat_paused:
## "the vat upgrade involves the entire column. T1 has only the front entrance; T2 attaches a second entrance; T3 opens
## the two sides. When an upgrade starts, the column comes out of the closest pit and attaches to the vat entrance only
## when the new tier is reached. While upgrading, the full column (entrance + column + node + structure on the node)
## becomes a BLUEPRINT hologram of the new-tier structure that fills bottom to top."
## - PITS / TUBES (2026-11-07) supersede the doors per tier: every column base has 4 doors + 4 corner sockets at all tiers
##   (WorldTubes); the tubes an upgrade adds are drawn empty from the sim state there, the lift by WorldLayer.
## - Blueprint (Daniele's correction 2026-11-07: "the node shouldn't have the hologram thing as it's not the part upgraded
##   but just the structure and the tube and door"): while a vat upgrade runs (build_kind "vat"), the solid entrance and
##   vat (the build target's model, main already swaps it in) are hidden and drawn as copies in one shared vat_blueprint
##   material, plus a sleeve over the tube; the PLATFORM stays solid. The fill rises with Sim.build_progress - entrance +
##   tube over the first half, the structure over the second (so the part the camera sees fills for 5 of the 10 s).
## - When the fill reaches the top the ring widens and goes (DOCK_S), then the column turns solid.
## - Cancelled (capture, Last Stand drop): the blueprint goes at once.
## Cost: idle = one dictionary read per tube per frame; per upgrade: the vat + entrance + a sleeve drawn again (blended, unshaded).
## Ours: HUD cyan (UiKit.CYAN) lines + the owner's colour in the filled part; no assets from anywhere else.
## VAT COLUMN 2 (Daniele, 2026-11-07): "the hologram's TOP (the rising fill ring) must be LARGER than the structure
## outline, in the PLAYER's seat-colour neon (not the faction colour)" and "whatever the top ring has passed takes the
## structure's ACTUAL colour / material, but the tubes stay EMPTY (no goo, no animation) until the structure is complete":
## - a neon RING (TorusMesh, unshaded, Rules.seat_color of the vat's owner) rides the fill height, 1.2 x the widest part
##   of what it is passing (entrance, then tube, then the structure) + 0.3 m;
## - below the ring: a copy of the real entrance / structure in its own materials (vat_reveal.gdshader, clipped at the
##   ring); the blueprint ghost draws only above it; goo surfaces (OS_Ooze, living liquid) are empty glass in the copy;
## - the world tube under the platform shows empty glass while the sim's upgrade builds (WorldLayer._tubes_step reads
##   it from the sim state); then WorldLayer's own goo comes back.

const BLUEPRINT := preload("res://shaders/vat_blueprint.gdshader")
const REVEAL := preload("res://shaders/vat_reveal.gdshader")
const RING_K := 1.15             # the ring's radius over the widest part it passes
const RING_PAD := 0.25           # m added on top
const RING_W := 0.05             # the torus' half-thickness over its radius
const EMPTY_GLASS := Color(0.05, 0.075, 0.1)
const DOCK_S := 0.4              # s: the dock after the fill reached the top
const LOWER_SHARE := 0.5         # the fill's progress share for entrance + tube (the rest: the structure)

var wl: WorldLayer
var sim: Sim
var vis: Dictionary
var _ups: Dictionary = {}        # tube index -> upgrade view (see _start)
var _t := 0.0
var started := 0                 # probes / shots read these
var docked := 0
var cancelled := 0
var _warm_left := 0              # frames the warm-up set still draws (see _warm)
var _warm_node: Node3D
var _pool := {}                  # reveal material key -> free ShaderMaterials (reused by the next upgrade)
static var _reveal_glass: Shader                # vat_reveal with blend_mix (made once from REVEAL's code)
static var _ring_mesh: TorusMesh
static var _clip_cache := {}
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
	_warm()


func _warm() -> void:
	## VAT FRAME SPIKE (2026-11-09): the first upgrade hitched ~75-80 ms on its first frame (desktop; the second upgrade
	## didn't): the new tier's model and every shader the hologram adds (blueprint, vat_reveal + its glass variant, the
	## clip-injected entrance / kit glass, the unshaded ring) compiled on first draw. Like WorldLayer._warm: draw each
	## once, tiny, under the floor, for a few frames at load; the reveal materials made here go to the pool.
	_warm_node = Node3D.new()
	add_child(_warm_node)
	var seats := {}
	for nd in sim.nodes:
		if str(nd.get("owner", "")) != "":
			seats[str(nd["owner"])] = true
	var keys := {}
	for seat in seats:
		for t in [2, 3]:
			keys[Cosmetics.key_for("vat", seat, t)] = seat
	var m := ShaderMaterial.new()
	m.shader = BLUEPRINT
	var made := []
	var reals := []
	for key in keys:
		var src := MapBuilder.piece(key)
		reals.append(src)
		_warm_node.add_child(src)
		MapBuilder.apply_owner([src], keys[key])
		_copy_into(_warm_node, src, m)
		var tmp := {"reveal": [], "pooled": []}
		_real_copy(src, tmp, _warm_node)
		made.append(tmp)
	for t in [1, 2, 3]:
		var mm = wl._ent_mms[t]
		if mm is MultiMesh and (mm as MultiMesh).mesh != null:
			var e := MeshInstance3D.new()
			e.mesh = (mm as MultiMesh).mesh
			var etmp := {"reveal": [], "pooled": []}
			e.material_override = _pooled(etmp, "ent", func(): return _entrance_reveal())
			made.append(etmp)
			_warm_node.add_child(e)
			break
	var ring := MeshInstance3D.new()
	ring.mesh = _ring()
	ring.material_override = _ring_mat()
	_warm_node.add_child(ring)
	var glass := MeshInstance3D.new()                 # the glass variant (a copy may not have a transparent surface)
	glass.mesh = BoxMesh.new()
	glass.material_override = _reveal_mat(null, true)
	_warm_node.add_child(glass)
	for c in _warm_node.find_children("*", "GeometryInstance3D", true, false):   # (owned = false: duplicates)
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for src in reals:                                 # the real model as the game draws it (its shadow pass too)
		for c in (src as Node).find_children("*", "GeometryInstance3D", true, false):
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var fl = wl.get("_floor")
	var at := Vector3(fl.position.x, wl.floor_y - 2.0, fl.position.z) if fl is Node3D else Vector3(0, wl.floor_y - 2.0, 0)
	for c in _warm_node.get_children():
		if c is Node3D:
			(c as Node3D).global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.01), at)
	for tmp in made:                                  # the warm copies' materials serve the first real upgrade
		for pk in tmp["pooled"]:
			_release(pk)
	_warm_left = 3


static func upgrading(n: Dictionary) -> bool:
	return n["build_kind"] == "vat" and n["structure"] == "vat"


func step(dt: float) -> void:
	_t += dt
	if _warm_left > 0:
		_warm_left -= 1
		if _warm_left == 0 and is_instance_valid(_warm_node):
			_warm_node.queue_free()
			_warm_node = null
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
			var rg: MeshInstance3D = up["ring"]
			rg.transform.basis = Basis.from_scale(Vector3.ONE * float(up.get("ring_r", 2.0)) * (1.0 + 0.25 * k))   # widens, then goes
			(up["ring_mat"] as StandardMaterial3D).albedo_color = (up["seat"] as Color).lerp(Color.WHITE, 0.3 + 0.5 * (1.0 - k))
			rg.visible = k < 0.95
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
	var seat := Color(oc.r, oc.g, oc.b, 1.0)
	var up := {"phase": "fill", "y_base": 0.0, "from": from, "to": to, "owner": n["owner"], "mat": m, "copies": [],
			"plat": entry.get("platform"), "vat_src": null, "vat_copy": null, "y_mid": 0.0, "y_top": 0.0,
			"t_dock": 0.0, "reveal": [], "vat_real": null, "pooled": []}
	# the new tier's entrance, in blueprint (above the ring) and in its real material (below it)
	var ent_mesh: Mesh = (wl._ent_mms[to] as MultiMesh).mesh
	var ent := MeshInstance3D.new()
	ent.mesh = ent_mesh
	ent.material_override = m
	ent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ent)
	ent.transform = tb["ent_xf"]
	up["copies"].append(ent)
	var er := MeshInstance3D.new()
	er.mesh = ent_mesh
	er.material_override = _pooled(up, "ent", func(): return _entrance_reveal())
	er.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(er)
	er.transform = tb["ent_xf"]
	up["copies"].append(er)
	up["reveal"].append(er.material_override)
	up["r_ent"] = 1.0
	up["ent_top"] = wl.floor_y + 1.0
	if ent_mesh != null:
		var ebb: AABB = (tb["ent_xf"] as Transform3D) * ent_mesh.get_aabb()
		up["r_ent"] = _xz_radius(ebb, Vector2(tb["x"], tb["z"]))
		up["ent_top"] = ebb.end.y
	# the rising ring, the player's seat colour in neon
	var ring := MeshInstance3D.new()
	ring.mesh = _ring()
	var rm := _ring_mat()
	rm.albedo_color = seat.lerp(Color.WHITE, 0.3)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	up["ring"] = ring
	up["ring_mat"] = rm
	up["seat"] = seat
	up["copies"].append(ring)
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
	_fill_step(up, tb, n)
	return up


func _ring_mat() -> StandardMaterial3D:
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.render_priority = 3
	return rm


func _pooled(up: Dictionary, key: String, make: Callable) -> ShaderMaterial:
	## a reveal material for `key` (source material + empty flag): a free one from the pool, else a new one; _end
	## gives it back. Each upgrade owns its materials while it runs (clip_y differs per column).
	var free: Array = _pool.get(key, [])
	var m: ShaderMaterial = free.pop_back() if not free.is_empty() else make.call()
	(up["pooled"] as Array).append([key, m])
	return m


func _release(pk: Array) -> void:
	if not _pool.has(pk[0]):
		_pool[pk[0]] = []
	(pk[1] as ShaderMaterial).set_shader_parameter("clip_y", 100000.0)
	(_pool[pk[0]] as Array).append(pk[1])


func _copy(src: Node3D, m: Material) -> Node3D:
	return _copy_into(self, src, m)


func _copy_into(parent: Node, src: Node3D, m: Material) -> Node3D:
	var c := src.duplicate() as Node3D
	MapBatch.show_copy(c)                          # a copy of a batched piece draws itself
	for mi in [c] + c.find_children("*", "MeshInstance3D", true, false):
		if mi is MeshInstance3D:
			(mi as MeshInstance3D).material_override = m
			(mi as MeshInstance3D).layers = 1          # (a duplicate may keep the batch's layers = 0 without its meta)
			(mi as MeshInstance3D).material_overlay = null
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(c)
	c.global_transform = Transform3D(src.global_transform.basis.orthonormalized(), src.global_transform.origin)   # full size
	c.visible = true
	return c


func _vat_copy(up: Dictionary, entry: Dictionary) -> void:
	## the build target's model (main swapped it in when the upgrade started; a skin load may swap it again)
	var src = entry.get("vat_node")
	if src == up["vat_src"]:
		return
	for k in ["vat_copy", "vat_real"]:
		if up[k] != null and is_instance_valid(up[k]):
			(up["copies"] as Array).erase(up[k])
			(up[k] as Node).queue_free()
		up[k] = null
	up["vat_src"] = src
	if src is Node3D and is_instance_valid(src):
		var c := _copy(src, up["mat"])
		up["vat_copy"] = c
		up["copies"].append(c)
		var real := _real_copy(src as Node3D, up)
		up["vat_real"] = real
		up["copies"].append(real)
		var top: float = (src as Node3D).global_position.y + 2.0
		up["y_base"] = (src as Node3D).global_position.y
		var rv := 1.0
		var foot := Vector2((src as Node3D).global_position.x, (src as Node3D).global_position.z)
		for mi in c.find_children("*", "MeshInstance3D", true, false):
			var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			top = maxf(top, bb.end.y)
			rv = maxf(rv, _xz_radius(bb, foot))
		up["y_top"] = top
		up["r_vat"] = rv
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
	_reveal_step(up, tb, fy, p)
	var m: ShaderMaterial = up["mat"]
	m.set_shader_parameter("y_top", y_top)
	m.set_shader_parameter("fill_y", fy + (0.3 if p >= 1.0 else 0.0))
	m.set_shader_parameter("done", 1.0 if p >= 1.0 else 0.0)
	m.set_shader_parameter("t", _t)
	m.set_shader_parameter("strength", clampf(p * 12.0, 0.35, 1.0))   # fades in over the first second
	var sl: MeshInstance3D = up["sleeve"]
	var h := maxf(y_mid - wl.floor_y, 0.1)
	sl.transform = Transform3D(Basis.from_scale(Vector3(1.0, h, 1.0)), Vector3(tb["x"], wl.floor_y + h / 2.0, tb["z"]))


func _xz_radius(bb: AABB, c: Vector2) -> float:
	var r := 0.0
	for x in [bb.position.x, bb.end.x]:
		for z in [bb.position.z, bb.end.z]:
			r = maxf(r, Vector2(x - c.x, z - c.y).length())
	return r


func _ring() -> TorusMesh:
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 1.0 - 2.0 * RING_W
		_ring_mesh.outer_radius = 1.0
		_ring_mesh.rings = 32 if wl._low else 48
		_ring_mesh.ring_segments = 6
	return _ring_mesh


func _reveal_step(up: Dictionary, tb: Dictionary, fy: float, p: float) -> void:
	for rm in up["reveal"]:
		(rm as ShaderMaterial).set_shader_parameter("clip_y", fy)
	# the ring: 1.2 x the widest part at the fill height (entrance, tube, structure) + 0.3 m
	var r: float
	var c := Vector2(tb["x"], tb["z"])
	if p >= LOWER_SHARE:
		r = float(up.get("r_vat", 2.0))
		c = up.get("ring_c", c)
	elif fy < float(up["ent_top"]):
		r = float(up["r_ent"])
	else:
		r = float(tb["r"]) + 0.12
	r = r * RING_K + RING_PAD
	up["ring_r"] = r
	var rg: MeshInstance3D = up["ring"]
	rg.transform = Transform3D(Basis.from_scale(Vector3.ONE * r), Vector3(c.x, fy, c.y))
	rg.visible = p < 1.0 or up["phase"] == "dock"


func _entrance_reveal() -> ShaderMaterial:
	## the entrance's own shader, clipped at the ring (owner light left unlit: no goo until the column is complete)
	var m := ShaderMaterial.new()
	m.shader = _clip_shader(WorldLayer.SHADER_ENTRANCE)
	m.set_shader_parameter("abyss", wl._ent_mat.get_shader_parameter("abyss"))
	var hz = wl._ent_mat.get_shader_parameter("haze")
	if hz != null:
		m.set_shader_parameter("haze", hz)
	return m


static func _clip_shader(src: Shader) -> Shader:
	## a copy of a shader that discards above clip_y (world y)
	if not _clip_cache.has(src):
		var code := src.code
		code = code.replace("void vertex() {", "varying float vc_wy;\nuniform float clip_y = 100000.0;\nvoid vertex() {\n\tvc_wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;")
		code = code.replace("void fragment() {", "void fragment() {\n\tif (vc_wy > clip_y) {\n\t\tdiscard;\n\t}")
		var sh := Shader.new()
		sh.code = code
		_clip_cache[src] = sh
	return _clip_cache[src]


func _reveal_mat(src: Material, empty: bool) -> ShaderMaterial:
	## the real look of one surface, clipped at the ring; goo surfaces become empty glass
	var m := ShaderMaterial.new()
	if not empty and src is ShaderMaterial and (src as ShaderMaterial).shader != null:   # e.g. the kit glass: its own shader, clipped
		var ss := src as ShaderMaterial
		m.shader = _clip_shader(ss.shader)
		for u in ss.shader.get_shader_uniform_list():
			var v = ss.get_shader_parameter(u["name"])
			if v != null:
				m.set_shader_parameter(u["name"], v)
		m.render_priority = ss.render_priority
		return m
	var sm := src as BaseMaterial3D
	var glass := empty or (sm != null and sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
	if glass:
		if _reveal_glass == null:
			_reveal_glass = Shader.new()
			_reveal_glass.code = REVEAL.code.replace("render_mode cull_back;", "render_mode cull_back, blend_mix, depth_draw_opaque;").replace("//ALPHA", "ALPHA = a.a;")
		m.shader = _reveal_glass
	else:
		m.shader = REVEAL
	if empty or sm == null:
		m.set_shader_parameter("albedo", Color(EMPTY_GLASS.r, EMPTY_GLASS.g, EMPTY_GLASS.b, 0.55) if empty else Color(0.45, 0.47, 0.5))
		m.set_shader_parameter("metallic", 0.3)
		m.set_shader_parameter("roughness", 0.15 if empty else 0.6)
		return m
	m.set_shader_parameter("albedo", sm.albedo_color)
	if sm.albedo_texture != null:
		m.set_shader_parameter("albedo_tex", sm.albedo_texture)
		m.set_shader_parameter("use_tex", 1.0)
	m.set_shader_parameter("use_vcol", 1.0 if sm.vertex_color_use_as_albedo else 0.0)
	m.set_shader_parameter("uv_scale", sm.uv1_scale)
	m.set_shader_parameter("uv_offset", sm.uv1_offset)
	m.set_shader_parameter("metallic", sm.metallic)
	m.set_shader_parameter("roughness", sm.roughness)
	if sm.normal_enabled and sm.normal_texture != null:
		m.set_shader_parameter("normal_tex", sm.normal_texture)
		m.set_shader_parameter("use_normal", 1.0)
		m.set_shader_parameter("normal_scale", sm.normal_scale)
	if sm.emission_enabled:
		var e := sm.emission * sm.emission_energy_multiplier
		m.set_shader_parameter("emission", Color(e.r, e.g, e.b))
		if sm.emission_texture != null:
			m.set_shader_parameter("emission_tex", sm.emission_texture)
			m.set_shader_parameter("use_emi_tex", 1.0)
	return m


func _real_copy(src: Node3D, up: Dictionary, parent: Node = null) -> Node3D:
	## the new tier's model in its own materials, clipped at the ring (the goo surfaces empty)
	var c := src.duplicate() as Node3D
	MapBatch.show_copy(c)
	var made := {}
	var src_mis: Array = [src] + src.find_children("*", "MeshInstance3D", true, false)
	var dst_mis: Array = [c] + c.find_children("*", "MeshInstance3D", true, false)
	for j in range(mini(src_mis.size(), dst_mis.size())):
		var smi = src_mis[j]
		var dmi = dst_mis[j]
		if not (smi is MeshInstance3D and dmi is MeshInstance3D) or (dmi as MeshInstance3D).mesh == null:
			continue
		var d := dmi as MeshInstance3D
		var liquid: bool = (smi as MeshInstance3D).has_meta("vat_liquid")
		for s in range(d.mesh.get_surface_count()):
			var sm: Material = (smi as MeshInstance3D).get_active_material(s)
			var base_m: Material = d.mesh.surface_get_material(s)
			var nm := base_m.resource_name if base_m != null else ""
			var empty := nm.begins_with("OS_Ooze") or (liquid and sm is ShaderMaterial and str((sm as ShaderMaterial).shader.resource_path).ends_with("vat_liquid.gdshader"))
			var key := "%d:%s" % [sm.get_instance_id() if sm != null else 0, empty]
			if not made.has(key):
				made[key] = _pooled(up, key, func(): return _reveal_mat(sm, empty))
				up["reveal"].append(made[key])
			d.set_surface_override_material(s, made[key])
		d.material_override = null
		d.material_overlay = null
		d.layers = 1
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else self).add_child(c)
	c.global_transform = Transform3D(src.global_transform.basis.orthonormalized(), src.global_transform.origin)
	c.visible = true
	up["ring_c"] = Vector2(src.global_position.x, src.global_position.z)
	return c


func _end(i: int, up: Dictionary, tb: Dictionary, done: bool) -> void:
	if done:
		docked += 1
		for k in range(4):                            # a spark burst at the base's corner sockets as the column turns solid
			var c := WorldTubes.corner_dir(k) * (WorldTubes.APOTHEM + WorldTubes.SOCK_D)
			var at := Vector3(float(tb["x"]) + c.x, wl.floor_y + WorldTubes.SOCK_Y, float(tb["z"]) + c.y)
			for j in range(3 if not wl._low else 2):
				var a := randf() * TAU
				wl._add_drop(at, Vector3(cos(a) * 2.0, randf_range(1.5, 3.0), sin(a) * 2.0), UiKit.CYAN)
	else:
		cancelled += 1
	for c in up["copies"]:
		if c != null and is_instance_valid(c):
			(c as Node).queue_free()
	for pk in up["pooled"]:
		_release(pk)
	var v = vis[tb["id"]].get("vat_node")
	if v is Node3D and is_instance_valid(v):
		(v as Node3D).visible = true
	tb["holo"] = false
	_showing.erase(int(tb["id"]))
	wl._sock_lit(tb, tb["base"] if (tb["mi"] as MeshInstance3D).visible else Color(0, 0, 0, 0))
	_ups.erase(i)
