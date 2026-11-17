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

const STEEL := Color(0.30, 0.34, 0.38)
const STEEL_DARK := Color(0.17, 0.19, 0.22)
const STEEL_PALE := Color(0.55, 0.58, 0.60)

var wl: WorldLayer
var river: WorldRiver
var sim: Sim
var _collar_mm: MultiMesh
var _bit_mm: MultiMesh
var _br_mm: MultiMesh
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
		_place(i)
	made = nt


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
		_collar_mm.set_instance_transform(i, hide)
		_bit_mm.set_instance_transform(i, hide)
	else:
		_collar_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, jy, z)))
		_bit_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(d["spin"])), Vector3(x, jy - COLLAR_H * 0.5, z)))
	_collar_mm.visible_instance_count = _d.size()
	_bit_mm.visible_instance_count = _d.size()


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
			_br_mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(x, bed - 40.0, z)))
			continue
		var a: float = angs[s]
		var dir := Vector2(cos(a), sin(a))
		var end := Vector2(x, z) + dir * BR_OUT
		var gy := river.bed_h(end.x, end.y)
		var drop := maxf(jy - (gy - BR_SINK), 0.8)          # the bent tube's height, junction to its end in the bed
		var sy := drop / (J_UP + BR_SINK)
		# local frame: +X outward along dir, +Y up; the mesh starts at the collar (x = COLLAR_R) and ends at (BR_OUT, -1)
		var bx := Vector3(dir.x, 0, dir.y)
		var bz := bx.cross(Vector3.UP)
		var basis := Basis(bx, Vector3.UP * sy, bz)
		var at := Vector3(x, jy, z)
		if kick > 0.0:                                     # released: the stub kicks out and tips away, its foot in the bed
			basis = Basis(bz.normalized(), -RELEASE_TILT * kick) * basis
			at += bx * RELEASE_KICK * kick
		_br_mm.set_instance_transform(idx, Transform3D(basis, at))
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
