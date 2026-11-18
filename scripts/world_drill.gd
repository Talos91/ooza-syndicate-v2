class_name WorldDrill
extends Node3D
## DRILL NODE (Daniele's blueprint 2026-11-16, References/Art direction 2026-11 - backgrounds/drill-node-blueprint-2026-11-16/;
## DECISIONS.md "the drill node blueprint"): under every river-world platform a SKINNY central tube (WorldLayer's goo tube,
## WorldLayer.DRILL_R) runs down to a branch JUNCTION collar just over the bed; a screw DRILL bit hangs under the collar,
## embedded in its crack; BRANCH tubes run from the junction into the bed by the vat's tier: T1 1, T2 2, T3 (and T4) 4
## (the central tube not counted).
## QUOTA launch (Fx._launch drives the platform; WorldLayer._tubes_step lifts the tube with it): the branches RELEASE (they
## kick out and stay in the bed as open stubs) and the collar + drill fly up with the platform, tube and all.
## VIEW ONLY: reads sim.nodes (tier, collapsed) and WorldLayer's tubes; nothing in the Sim or the protocol.
## All geometry is generated here (no kit GLB: nothing to overwrite; pck + a few KB of script).

const COLLAR_R := 0.78         # m: the junction collar (the tube is WorldLayer.DRILL_R = 0.45)
const COLLAR_H := 0.75
const J_UP := 2.1              # m: the junction's centre over the bed under the axis
const BIT_R := 0.62            # m: the drill bit's top radius (under the collar)
const BIT_LEN := 4.6           # m: collar bottom to tip (~2.6 m of it in the crack)
const BIT_TURNS := 3.2         # screw flight turns over the bit
const BR_R := 0.2              # m: a branch tube's radius
const BR_OUT := 3.0            # m: where a branch meets the bed, from the axis
const BR_SINK := 0.35          # m: a branch runs this far into the bed
const RELEASE_T := 0.32        # s: the branches' kick-out at a launch
const RELEASE_KICK := 0.45     # m outward
const RELEASE_TILT := 0.32     # rad outward

# DEMO 2 (Rules.kit2, demo2-kit 2026-11-18): the collar + bit and the legs are the baked kit look (assets/kit/kit2/Drill_Collar,
# Drill_Leg: bake_demo2.py, the MOBILE r1 drill node's collar, bit and goo legs); the legs keep the blueprint's count by tier
# (T1 1 / T2 2 / T3+ 4) and its release. Colours per instance: neon = seat colour (instance colour), goo = faction goo
# (WorldLayer._col, instance custom data); the copper / wine / bronze keep the GLB's own.
const KIT2_COLLAR := "res://assets/kit/kit2/Drill_Collar.glb"
const KIT2_LEG := "res://assets/kit/kit2/Drill_Leg.glb"
# SIZE D (Daniele 11-18, NODE-SIZE-D-SPEC.md; bake_demo2_D.py): the drill below the deck at FULL mobile size (x1.00; the platform
# and vats stay x0.68): collar + bit and legs at 1 / 0.68 of demo 2's, the column = WorldLayer.DRILL_R_KIT2 (1.088 m), and the
# wine bands with copper edges (Drill_Band) repeated down the column at the mobile spacing from under the hub cone.
const KIT2_BAND := "res://assets/kit/kit2/Drill_Band.glb"
const KIT2_LEG_DROP := 2.875   # m: the leg GLB's foot bottom under its origin (the collar centre); bake-report leg_drop
const KIT2_COLLAR_R := 1.686   # m: the collar GLB's radius (a wide tube scales it like the code collar)
const KIT2_COLLAR_TOP := 0.835 # m: the collar GLB's top over its origin
const KIT2_HUB_UNDER_TOP := 0.87   # m: the kit2 hub cone's bottom under the tube's top (the column top sits up inside the cone)
const KIT2_BANDS := [0.91, 4.12, 7.33, 10.54, 13.75]   # m under the hub cone: the mobile band centres (3.21 m apart), as many as fit
const KIT2_BAND_HH := 0.51     # m: a band's half height
const KIT2_BAND_CLEAR := 0.3   # m: a band stays this far over the collar
const TINT_SHADER := """
shader_type spatial;
uniform bool goo = false;
uniform float alb = 0.45;
uniform float glow = 1.4;
uniform float rough = 0.3;
varying vec3 tint;
void vertex() { tint = goo ? INSTANCE_CUSTOM.rgb : COLOR.rgb; }
void fragment() { ALBEDO = tint * alb; EMISSION = tint * glow; ROUGHNESS = rough; }
"""

const STEEL := Color(0.30, 0.34, 0.38)
const STEEL_DARK := Color(0.17, 0.19, 0.22)
const STEEL_PALE := Color(0.55, 0.58, 0.60)

var wl: WorldLayer
var river: WorldRiver
var sim: Sim
var _collar_mm: MultiMesh
var _bit_mm: MultiMesh
var _br_mm: MultiMesh
var _band_mm: MultiMesh        # SIZE D: the column's bands (KIT2_BANDS.size() per drill)
var _pk: Array = []            # kit2: [collar, legs, bands] Packs - only the pieces over the goo surface are drawn
var _surf := INF               # the goo surface the packs were last flushed against


class Pack:
	## kit2 (size D, bg-44b4): a MultiMesh written packed - the slots' pieces whose top is over the goo surface go first and
	## visible_instance_count stops there, so pieces under the (opaque) goo and unused legs cost nothing (zero-scale hidden
	## instances still ran their vertices: +124k prims at G-06 before packing).
	var mm: MultiMesh
	var xf: Array = []
	var top := PackedFloat32Array()
	var col := PackedColorArray()
	var cus := PackedColorArray()
	var dirty := true

	func _init(m: MultiMesh, n: int) -> void:
		mm = m
		xf.resize(n)
		top.resize(n)
		col.resize(n)
		cus.resize(n)
		col.fill(Color.WHITE)
		cus.fill(Color(0, 0, 0, 0))

	func put(i: int, t: Transform3D, ytop: float) -> void:
		xf[i] = t
		top[i] = ytop
		dirty = true

	func off(i: int) -> void:
		xf[i] = null
		dirty = true

	func tint(i: int, c: Color, g: Color) -> void:
		col[i] = c
		cus[i] = g
		dirty = true

	func flush(surf: float) -> void:
		var k := 0
		for i in range(xf.size()):
			if xf[i] != null and top[i] > surf:
				mm.set_instance_transform(k, xf[i])
				mm.set_instance_color(k, col[i])
				mm.set_instance_custom_data(k, cus[i])
				k += 1
		mm.visible_instance_count = k
		dirty = false
var _d: Array = []             # per WorldLayer tube: {tb, bed, tier, n, ang: Array, rel: float (-1 none), xf_br: Array, spin}
var made := 0                  # probes


static func branches(tier: int) -> int:
	## Branch tubes by vat tier (Daniele's blueprint: T1 1, T2 2, T3 4; T4 as T3).
	return 1 if tier <= 1 else (2 if tier == 2 else 4)


func build(r: WorldRiver) -> void:
	river = r
	wl = r.wl
	sim = r.sim
	var nt := wl._tubes.size()
	if Rules.kit2:
		_collar_mm = _mm_glb(KIT2_COLLAR, nt)
		_bit_mm = _mm(_bit_mesh(), 1, STEEL_DARK)          # (the bit is in the collar GLB; this one stays empty)
		_br_mm = _mm_glb(KIT2_LEG, nt * 4)
		_band_mm = _mm_glb(KIT2_BAND, nt * KIT2_BANDS.size())
		_pk = [Pack.new(_collar_mm, nt), Pack.new(_br_mm, nt * 4), Pack.new(_band_mm, nt * KIT2_BANDS.size())]
	else:
		_collar_mm = _mm(_collar_mesh(), nt, STEEL)
		_bit_mm = _mm(_bit_mesh(), nt, STEEL_DARK)
		_br_mm = _mm(_branch_mesh(), nt * 4, STEEL_PALE)
	# the camera's screen-right in world xz (blueprint: T1 / T2 branches read left-right, T3 as an X)
	var right := Vector2(r.ax_u.x, r.ax_u.y)
	var base_a := atan2(right.y, right.x)
	for i in range(nt):
		var tb: Dictionary = wl._tubes[i]
		var x: float = tb["x"]
		var z: float = tb["z"]
		var d := {"tb": tb, "bed": r.bed_h(x, z), "tier": -1, "rel": -1.0, "lift": 0.0, "gone": false,
				"spin": fposmod(x * 0.37 + z * 0.61, TAU), "base_a": base_a}
		_d.append(d)
		d["band_top"] = INF
		_place(i)
		if Rules.kit2:
			_tint(i)
	made = nt
	_flush()


func _mm(mesh: Mesh, count: int, col: Color) -> MultiMesh:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.55
	mat.roughness = 0.42
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = maxi(count, 1)
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


func _mm_glb(path: String, count: int) -> MultiMesh:
	## DEMO 2: a kit2 GLB merged into one multi-surface mesh (node transforms applied); OS_Light -> seat neon (instance
	## colour), OS_Ooze* -> faction goo (instance custom data), other surfaces keep their GLB material.
	var mesh := ArrayMesh.new()
	var root := (load(path) as PackedScene).instantiate()
	var neon := ShaderMaterial.new()
	neon.shader = Shader.new()
	neon.shader.code = TINT_SHADER
	var goo := ShaderMaterial.new()
	goo.shader = neon.shader
	goo.set_shader_parameter("goo", true)
	goo.set_shader_parameter("alb", 0.6)
	goo.set_shader_parameter("glow", 0.9)
	goo.set_shader_parameter("rough", 0.12)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var nd: Node = mi
		while nd != root and nd is Node3D:
			xf = (nd as Node3D).transform * xf
			nd = nd.get_parent()
		var src := (mi as MeshInstance3D).mesh
		for s in range(src.get_surface_count()):
			var arr := src.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for k in range(v.size()):
				v[k] = xf * v[k]
			arr[Mesh.ARRAY_VERTEX] = v
			if arr[Mesh.ARRAY_NORMAL] != null:
				var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for k in range(nn.size()):
					nn[k] = (xf.basis * nn[k]).normalized()
				arr[Mesh.ARRAY_NORMAL] = nn
			arr[Mesh.ARRAY_TANGENT] = null
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var m := src.surface_get_material(s)
			var nm := m.resource_name if m else ""
			mesh.surface_set_material(mesh.get_surface_count() - 1,
					neon if nm.begins_with("OS_Light") else (goo if nm.begins_with("OS_Ooze") else m))
	root.free()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = maxi(count, 1)
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


func _tint(i: int) -> void:
	## DEMO 2: drill i's neon in its owner's seat colour, its goo legs in the faction goo (neutral: Rules.NEUTRAL / native gray).
	var d: Dictionary = _d[i]
	var owner: String = str(d["tb"].get("owner", ""))
	d["owner"] = owner
	var neon := Rules.seat_color(owner) if owner != "" else Rules.NEUTRAL
	var goo := WorldLayer._col(owner)
	(_pk[0] as Pack).tint(i, neon, goo)
	for s in range(4):
		(_pk[1] as Pack).tint(i * 4 + s, neon, goo)


func _angles(d: Dictionary, k: int) -> Array:
	var a0: float = d["base_a"]
	if k == 1:
		return [a0]
	if k == 2:
		return [a0, a0 + PI]
	return [a0 + PI * 0.25, a0 + PI * 0.75, a0 + PI * 1.25, a0 + PI * 1.75]


func _place(i: int) -> void:
	## The collar, bit and branches of drill i at its current lift (0 = in the bed).
	var d: Dictionary = _d[i]
	var tb: Dictionary = d["tb"]
	var x: float = tb["x"]
	var z: float = tb["z"]
	var bed: float = d["bed"]
	var lift: float = d["lift"]
	var jy := bed + J_UP + lift
	var hide := Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(x, bed - 40.0, z))
	if d["gone"]:
		if Rules.kit2:
			(_pk[0] as Pack).off(i)
		else:
			_collar_mm.set_instance_transform(i, hide)
		_bit_mm.set_instance_transform(i, hide)
	else:
		if Rules.kit2:                                     # DEMO kit2 (size D): the collar GLB carries its bit (origin = collar centre)
			var k2 := maxf(1.0, (float(tb["r"]) + 0.2) / KIT2_COLLAR_R)
			(_pk[0] as Pack).put(i, Transform3D(Basis(Vector3.UP, float(d["spin"])).scaled(Vector3(k2, 1.0, k2)), Vector3(x, jy, z)), jy + KIT2_COLLAR_TOP)
		else:
			_collar_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, jy, z)))
			_bit_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(d["spin"])), Vector3(x, jy - COLLAR_H * 0.5, z)))
	if not Rules.kit2:
		_collar_mm.visible_instance_count = _d.size()
	_bit_mm.visible_instance_count = 0 if Rules.kit2 else _d.size()


func _place_branches(i: int) -> void:
	var d: Dictionary = _d[i]
	var tb: Dictionary = d["tb"]
	var n: Dictionary = sim.nodes[tb["id"]]
	var k := branches(int(n["tier"]))
	d["tier"] = int(n["tier"])
	var x: float = tb["x"]
	var z: float = tb["z"]
	var bed: float = d["bed"]
	var jy := bed + J_UP
	var angs := _angles(d, k)
	var rel: float = d["rel"]
	var kick := 0.0 if rel < 0.0 else smoothstep(0.0, 1.0, clampf(rel / RELEASE_T, 0.0, 1.0))
	for s in range(4):
		var idx := i * 4 + s
		if s >= k:
			if Rules.kit2:
				(_pk[1] as Pack).off(idx)
			else:
				_br_mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(x, bed - 40.0, z)))
			continue
		var a: float = angs[s]
		var dir := Vector2(cos(a), sin(a))
		var end := Vector2(x, z) + dir * BR_OUT
		var gy := river.bed_h(end.x, end.y)
		var drop := maxf(jy - (gy - BR_SINK), 0.8)          # the bent tube's height, junction to its end in the bed
		var sy := drop / (J_UP + BR_SINK)
		if Rules.kit2:                                     # DEMO 2 leg: foot bottom KIT2_LEG_DROP under the collar centre
			sy = maxf(jy - (gy - 0.12), 0.8) / KIT2_LEG_DROP
		# local frame: +X outward along dir, +Y up; the mesh starts at the collar (x = COLLAR_R) and ends at (BR_OUT, -1)
		var bx := Vector3(dir.x, 0, dir.y)
		var bz := bx.cross(Vector3.UP)
		var basis := Basis(bx, Vector3.UP * sy, bz)
		var at := Vector3(x, jy, z)
		if Rules.kit2:
			at += Vector3(dir.x, 0, dir.y) * KIT2_COLLAR_R * (maxf(1.0, (float(tb["r"]) + 0.2) / KIT2_COLLAR_R) - 1.0)
		if kick > 0.0:                                     # released: the stub kicks out and tips away, its foot in the bed
			basis = Basis(bz.normalized(), -RELEASE_TILT * kick) * basis
			at += bx * RELEASE_KICK * kick
		if Rules.kit2:
			(_pk[1] as Pack).put(idx, Transform3D(basis, at), at.y + 0.26 * sy)
		else:
			_br_mm.set_instance_transform(idx, Transform3D(basis, at))
	if not Rules.kit2:
		_br_mm.visible_instance_count = _d.size() * 4


func step(dt: float) -> void:
	for i in range(_d.size()):
		var d: Dictionary = _d[i]
		var tb: Dictionary = d["tb"]
		var n: Dictionary = sim.nodes[tb["id"]]
		var launched: bool = Rules.quota and sim.collapsed.get(tb["id"], false)
		if launched:
			if float(d["rel"]) < 0.0:
				d["rel"] = 0.0
			if float(d["rel"]) <= RELEASE_T:
				d["rel"] = float(d["rel"]) + dt
				_place_branches(i)
			var lift: float = tb.get("lift", 0.0)
			var gone: bool = tb.get("gone", false)
			if absf(lift - float(d["lift"])) > 0.005 or gone != bool(d["gone"]):
				d["lift"] = lift
				d["gone"] = gone
				_place(i)
		elif int(n["tier"]) != int(d["tier"]):
			_place_branches(i)
		if Rules.kit2 and str(tb.get("owner", "")) != str(d.get("owner", "")):
			_tint(i)
		if _band_mm != null and absf(float(tb.get("top_y", 999.0)) - float(d["band_top"])) > 0.005:
			_place_bands(i)
	_flush()


func _flush() -> void:
	## kit2: write the packs when a piece moved or the goo surface moved (pieces under it are not drawn)
	if _pk.is_empty():
		return
	var sf := river.surface_y()
	var moved := absf(sf - _surf) > 0.05
	for p in _pk:
		if moved or (p as Pack).dirty:
			(p as Pack).flush(sf)
	if moved:
		_surf = sf


func _place_bands(i: int) -> void:
	## SIZE D: drill i's bands down its column from under the hub cone, the ones that fit over the collar (they ride a launch
	## with the tube: top_y follows the platform); none while the tube is not placed yet or gone.
	var d: Dictionary = _d[i]
	var tb: Dictionary = d["tb"]
	var top: float = tb.get("top_y", 999.0)
	d["band_top"] = top
	var nb := KIT2_BANDS.size()
	var low := float(d["bed"]) + J_UP + float(d["lift"]) + KIT2_COLLAR_TOP + KIT2_BAND_HH + KIT2_BAND_CLEAR
	var hidden := top > 900.0 or bool(d["gone"]) or not bool(tb.get("alive", true))
	for b in range(nb):
		var y := top - KIT2_HUB_UNDER_TOP - float(KIT2_BANDS[b])
		if hidden or y < low:
			(_pk[2] as Pack).off(i * nb + b)
		else:
			(_pk[2] as Pack).put(i * nb + b, Transform3D(Basis(Vector3.UP, float(d["spin"])), Vector3(float(tb["x"]), y, float(tb["z"]))),
					y + KIT2_BAND_HH)


# ------------------------------------------------------------------ meshes (generated once)
static func _ring(_st: SurfaceTool, c: Vector3, r: float, seg: int, ax_a := Vector3.RIGHT, ax_b := Vector3.BACK) -> Array:
	var out := []
	for s in range(seg + 1):
		var a := TAU * float(s) / float(seg)
		out.append(c + (ax_a * cos(a) + ax_b * sin(a)) * r)
	return out


static func _band(st: SurfaceTool, a: Array, b: Array) -> void:
	## Quads between two rings of equal length (outward normals by winding; normals generated after).
	for s in range(a.size() - 1):
		st.add_vertex(a[s]); st.add_vertex(b[s]); st.add_vertex(a[s + 1])
		st.add_vertex(a[s + 1]); st.add_vertex(b[s]); st.add_vertex(b[s + 1])


static func _collar_mesh() -> ArrayMesh:
	## The junction: a banded steel collar with a lip at each end (centred on y = 0).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 16
	var h := COLLAR_H * 0.5
	var prof := [[0.45, h + 0.12], [COLLAR_R * 0.92, h + 0.05], [COLLAR_R, h], [COLLAR_R, h - 0.12], [COLLAR_R * 0.94, h - 0.16],
			[COLLAR_R * 0.94, -h + 0.16], [COLLAR_R, -h + 0.12], [COLLAR_R, -h], [COLLAR_R * 0.8, -h - 0.05], [0.4, -h - 0.08]]
	var rings := []
	for p in prof:
		rings.append(_ring(st, Vector3(0, p[1], 0), p[0], seg))
	for k in range(rings.size() - 1):
		_band(st, rings[k], rings[k + 1])
	st.generate_normals()
	return st.commit()


static func _bit_mesh() -> ArrayMesh:
	## The drill bit: a tapering core from y = 0 (under the collar) to the tip at -BIT_LEN, with a screw flight round it.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 12
	var steps := 14
	var core := []
	for k in range(steps + 1):
		var t := float(k) / steps
		core.append(_ring(st, Vector3(0, -t * BIT_LEN, 0), lerpf(BIT_R * 0.62, 0.02, pow(t, 0.9)), seg))
	for k in range(steps):
		_band(st, core[k], core[k + 1])
	# the flight: a helical blade, inner edge on the core, outer edge BIT_R tapering to the tip
	var n := int(BIT_TURNS * 18.0)
	var prev_in := Vector3.ZERO
	var prev_out := Vector3.ZERO
	var prev_top := Vector3.ZERO
	for k in range(n + 1):
		var t := float(k) / n
		var a := t * BIT_TURNS * TAU
		var y := -t * BIT_LEN * 0.94
		var rc := lerpf(BIT_R * 0.62, 0.02, pow(t, 0.9))
		var ro := lerpf(BIT_R, 0.05, pow(t, 1.1))
		var dv := Vector3(cos(a), 0, sin(a))
		var p_in := Vector3(0, y, 0) + dv * rc * 0.95
		var p_out := Vector3(0, y - 0.08, 0) + dv * ro
		var p_top := Vector3(0, y + 0.1, 0) + dv * rc * 0.95
		if k > 0:                                           # two faces: a thin wedge so it reads from above and below
			st.add_vertex(prev_top); st.add_vertex(p_top); st.add_vertex(prev_out)
			st.add_vertex(prev_out); st.add_vertex(p_top); st.add_vertex(p_out)
			st.add_vertex(prev_in); st.add_vertex(prev_out); st.add_vertex(p_in)
			st.add_vertex(p_in); st.add_vertex(prev_out); st.add_vertex(p_out)
		prev_in = p_in
		prev_out = p_out
		prev_top = p_top
	st.generate_normals()
	return st.commit()


static func _branch_mesh() -> ArrayMesh:
	## One branch tube in its local frame: from the collar's side (x = COLLAR_R, y = 0) out and down a quarter bend into the bed at
	## (BR_OUT, -(J_UP + BR_SINK)); the instance's Y scale stretches it to the real bed. A flange where it leaves the collar.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 8
	var n := 12
	var p0 := Vector3(COLLAR_R - 0.05, 0.0, 0.0)
	var p1 := Vector3(BR_OUT, 0.15, 0.0)                     # control point: out first, then down (the blueprint's arch)
	var p2 := Vector3(BR_OUT, -(J_UP + BR_SINK), 0.0)
	var rings := []
	for k in range(n + 1):
		var t := float(k) / n
		var p := p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		var tan := (2.0 * (1.0 - t) * (p1 - p0) + 2.0 * t * (p2 - p1)).normalized()
		var side := Vector3.BACK
		var up := side.cross(tan).normalized()
		var r := BR_R * (1.35 if k == 0 else 1.0)
		rings.append(_ring(st, p, r, seg, up, side))
	for k in range(n):
		_band(st, rings[k], rings[k + 1])
	st.generate_normals()
	return st.commit()
