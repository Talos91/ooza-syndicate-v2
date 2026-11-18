class_name Pit3D
extends Node3D
## ROUND 44 B4 REAL 3D PIT (bg-44b4 job c; Daniele 11-18 via designer 11: "sorry i meant real 3d"; role note NEXT 3).
## The painted lake's shoreline (the CRUST's alpha hole, after the lower-lake placement: PitBackdrop._o / _s) is marched from the
## stadium centre in RAYS directions, mapped to screen px and unprojected through the match camera onto the goo's 0:00 level =
## the RIM polygon, lined up with the painted bank by construction (PIT3D prints the reprojection error). From it:
##  - WALLS (RINGS rings down to the bed, steep and irregular, inset toward the centre) + the FLOOR (the river bed the drills are
##    planted in, flat at WorldRiver.top_y - CHANNEL_DEPTH): ONE mesh, one draw (pit_wall.gdshader: crust greys, one small noise
##    texture triplanar, darker with depth, wet just over the goo);
##  - the GOO SURFACE at the river's draining level (pit_goo3d.gdshader: drift + swirl to the drain point, darker toward the
##    centre, wet sheen, a meniscus round every column it touches): one mesh, one draw.
## Both are clipped in screen space by the painted crust and laid under the painted PIT-RIM (pit_frame.gdshaderinc), so the 2D
## frame stays on top while every 3D platform / unit still draws over the crust. Replaces the flat goo tile + pit_mirror plane.
## Rebuilt when the pit is placed again (a resize). Not re-placed when the Last Stand camera zooms (known: role note gotcha).
## Unreliable unprojection (a ray at or over the horizon, a point farther than MAX_DIST): no pit, the mirror plane stays, and
## PIT3D FAIL is printed. VIEW ONLY. Off with --no-pit3d.

const RAYS := 120
const RINGS := 6                 # wall rings rim .. bed
const WALL_INSET := 3.4          # m: how far the wall foot steps in from the rim (steep: ~11 m down)
const WALL_JITTER := 0.7         # m: irregular ledges on the middle rings
const GOO_GROW := 1.08           # the goo polygon past the rim (clipped by the crust anyway; covers the bank)
const MAX_DIST := 2500.0
const RUN_PT := 3.0              # pt of opaque crust in a row = the shore (skips specks)

static var crust_img: Image

var river: WorldRiver
var pb: PitBackdrop
var ok := false
var stamp := -1
var rim_y := 0.0
var floor_y := 0.0
var centre := Vector2.ZERO
var rim_xz := PackedVector2Array()
var foot_xz := PackedVector2Array()
var err_px := 0.0
var _wall: MeshInstance3D
var _goo: MeshInstance3D
var _wall_mat: ShaderMaterial
var _goo_mat: ShaderMaterial
var _grain: NoiseTexture2D
var _fwd := Vector2(0, -1)       # the camera's forward in world xz: walls on the near side lean OUT (under the painted crust)


static func enabled() -> bool:
	return PitBackdrop.on and not "--no-pit3d" in OS.get_cmdline_user_args()


func setup(r: WorldRiver, p: PitBackdrop) -> void:
	river = r
	pb = p
	name = "Pit3D"
	rim_y = r.top_y
	floor_y = r.top_y - WorldRiver.CHANNEL_DEPTH


func try_build(cam: Camera3D) -> bool:
	## (Re)build from the current placement; false (and the mirror plane stays) when the shoreline cannot be unprojected.
	stamp = pb.placed_n
	if crust_img == null:
		var t := pb._tex(str(pb._el("crust").get("file", "crust.png")))
		crust_img = t.get_image() if t != null else null
		if crust_img != null and crust_img.is_compressed():
			crust_img.decompress()
	if crust_img == null or cam == null:
		print("PIT3D FAIL no crust image / camera")
		return false
	var ppt := float(crust_img.get_width()) / PitBackdrop.REF.x
	var st := pb._stadium()
	var c_pt: Vector2 = st[0]
	var radii := PackedFloat32Array()
	for k in range(RAYS):
		var a := TAU * float(k) / float(RAYS)
		var dir := Vector2(cos(a), sin(a))
		var r := 10.0
		var run := 0.0
		while r < 700.0:
			var p := (c_pt + dir * r) * ppt
			if p.x < 0.0 or p.y < 0.0 or p.x >= crust_img.get_width() or p.y >= crust_img.get_height():
				break
			if crust_img.get_pixel(int(p.x), int(p.y)).a > 0.5:
				run += 0.5
				if run >= RUN_PT:
					r -= run
					break
			else:
				run = 0.0
			r += 0.5
		radii.append(r)
	var sm := PackedFloat32Array()                    # a light 3-tap smoothing (the marched edge is pixel-stepped)
	for k in range(RAYS):
		sm.append((radii[(k + RAYS - 1) % RAYS] + 2.0 * radii[k] + radii[(k + 1) % RAYS]) / 4.0)
	var rim := PackedVector2Array()
	var scr := PackedVector2Array()
	err_px = 0.0
	for k in range(RAYS):
		var a := TAU * float(k) / float(RAYS)
		var pt := c_pt + Vector2(cos(a), sin(a)) * sm[k]
		var s: Vector2 = pb._o + pt * pb._s
		var o := cam.project_ray_origin(s)
		var d := cam.project_ray_normal(s)
		if d.y > -0.02:
			print("PIT3D FAIL ray %d at %s over the horizon (d.y %.3f)" % [k, s, d.y])
			return false
		var t := (rim_y - o.y) / d.y
		if t < 0.0 or t > MAX_DIST:
			print("PIT3D FAIL ray %d at %s: distance %.0f" % [k, s, t])
			return false
		var w := o + d * t
		rim.append(Vector2(w.x, w.z))
		scr.append(s)
		err_px = maxf(err_px, cam.unproject_position(w).distance_to(s))
	rim_xz = rim
	var cs := Vector2.ZERO
	for q in rim:
		cs += q
	centre = cs / float(RAYS)
	var fw := -cam.global_transform.basis.z
	_fwd = Vector2(fw.x, fw.z).normalized() if Vector2(fw.x, fw.z).length() > 0.01 else Vector2(0, -1)
	_build_meshes()
	var inside := 0
	var out_ids := []
	for n in river.sim.nodes:
		var p3: Vector3 = n["pos"]
		if Geometry2D.is_point_in_polygon(Vector2(p3.x, p3.z), foot_xz):
			inside += 1
		else:
			out_ids.append("%d%s" % [n["id"], "r" if str(n.get("relay", "")) != "" else ""])
	var m_px := _m_per_px(cam)
	print("PIT3D ok: %d rays, rim y %.1f, bed y %.1f, reprojection max %.2f px, %d of %d nodes over the bed, %d tris, %.3f m/px"
			% [RAYS, rim_y, floor_y, err_px, inside, river.sim.nodes.size(), RAYS * (RINGS * 2 + 1) + RAYS, m_px])
	print("PIT3D frame o %.2f,%.2f s %.4f,%.4f vp %s; outside the bed: %s" % [pb._o.x, pb._o.y, pb._s.x, pb._s.y, pb._vp, out_ids])
	_frame_uniforms(cam, m_px)
	ok = true
	return true


func _m_per_px(cam: Camera3D) -> float:
	var vp := cam.get_viewport().get_visible_rect().size
	var a := _hit(cam, vp * 0.5)
	var b := _hit(cam, vp * 0.5 + Vector2(10, 0))
	return a.distance_to(b) / 10.0


func _hit(cam: Camera3D, s: Vector2) -> Vector3:
	var o := cam.project_ray_origin(s)
	var d := cam.project_ray_normal(s)
	return o + d * ((rim_y - o.y) / minf(d.y, -0.001))


func _noise(k: int, ring: int) -> float:
	return fposmod(sin(float(k) * 12.9898 + float(ring) * 78.233) * 43758.5453, 1.0)


func _build_meshes() -> void:
	## the walls (RINGS rings) + floor fan in one mesh; the goo fan in another
	var rings: Array = []
	for g in range(RINGS + 1):
		var t := float(g) / float(RINGS)
		var ring := PackedVector3Array()
		for k in range(RAYS):
			var q := rim_xz[k]
			var to_c := (centre - q)
			var dist := to_c.length()
			var dir := to_c / maxf(dist, 0.001)
			var n0 := _noise(k / 3, g) * 0.6 + _noise(k, g) * 0.4      # irregular, a little coherent along the shore
			# far / side walls step in (seen, steep); near walls (facing the camera) lean out under the crust, so the bed reaches
			# every front node's drill and no wall face shows in front of the pit
			var side := smoothstep(-0.45, 0.15, (-dir).dot(_fwd))
			var inset := WALL_INSET * pow(t, 0.7) * (0.55 + 0.9 * n0) * lerpf(-0.8, 1.0, side)
			if g > 0 and g < RINGS:
				inset += (n0 - 0.5) * WALL_JITTER
			inset = clampf(inset, -WALL_INSET, dist * 0.5)
			var y := lerpf(rim_y, floor_y, t)
			if g > 0 and g < RINGS:
				y += (_noise(k, g + 7) - 0.5) * 0.6
			var p := q + dir * inset
			ring.append(Vector3(p.x, y, p.y))
		rings.append(ring)
	foot_xz = PackedVector2Array()
	for v in (rings[RINGS] as PackedVector3Array):
		foot_xz.append(Vector2(v.x, v.z))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for g in range(RINGS):
		var r0: PackedVector3Array = rings[g]
		var r1: PackedVector3Array = rings[g + 1]
		var c0 := Color(float(g) / RINGS, 0, 0)
		var c1 := Color(float(g + 1) / RINGS, 0, 0)
		for k in range(RAYS):
			var k2 := (k + 1) % RAYS
			for v in [[r0[k], c0], [r1[k], c1], [r1[k2], c1], [r0[k], c0], [r1[k2], c1], [r0[k2], c0]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
	var bot: PackedVector3Array = rings[RINGS]
	var fc := Vector3(centre.x, floor_y, centre.y)
	for k in range(RAYS):
		var k2 := (k + 1) % RAYS
		for v in [fc, bot[k2], bot[k]]:
			st.set_color(Color(1, 1, 0))
			st.add_vertex(v)
	st.generate_normals()
	if _wall == null:
		_wall = MeshInstance3D.new()
		_wall.name = "PitWalls"
		_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_wall)
		_goo = MeshInstance3D.new()
		_goo.name = "PitGoo"
		_goo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_goo)
	_wall.mesh = st.commit()
	var gs := SurfaceTool.new()                      # the goo: the rim polygon (grown) at y 0, moved to the level
	gs.begin(Mesh.PRIMITIVE_TRIANGLES)
	gs.set_normal(Vector3.UP)
	for k in range(RAYS):
		var k2 := (k + 1) % RAYS
		var a := centre + (rim_xz[k] - centre) * GOO_GROW
		var b := centre + (rim_xz[k2] - centre) * GOO_GROW
		for v in [Vector3(centre.x, 0, centre.y), Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y)]:
			gs.add_vertex(v)
	_goo.mesh = gs.commit()
	_goo.position.y = rim_y


func _frame_uniforms(cam: Camera3D, m_px: float) -> void:
	if _wall_mat == null:
		_grain = NoiseTexture2D.new()
		_grain.width = 128
		_grain.height = 128
		_grain.seamless = true
		_grain.generate_mipmaps = true
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_CELLULAR
		fn.frequency = 0.045
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM
		fn.fractal_octaves = 3
		_grain.noise = fn
		_wall_mat = ShaderMaterial.new()
		_wall_mat.shader = preload("res://shaders/pit_wall.gdshader")
		_wall_mat.set_shader_parameter("grain", _grain)
		_wall_mat.set_shader_parameter("crust_col", _crust_grey())
		_goo_mat = ShaderMaterial.new()
		_goo_mat.shader = preload("res://shaders/pit_goo3d.gdshader")
		_goo_mat.set_shader_parameter("goo_tile", pb._tex(str(pb._el("goo_tile").get("file", "goo_tile.png"))))
		_wall.material_override = _wall_mat
		_goo.material_override = _goo_mat
	for m in [_wall_mat, _goo_mat]:
		pb.frame_uniforms(m)
	var per: Array = pb._el("goo_tile").get("period_pt", [395, 258])
	_goo_mat.set_shader_parameter("tile_m", maxf(float(per[0]) * pb._s.x * m_px, 4.0))
	_goo_mat.set_shader_parameter("drain", centre)
	var reach := 0.0
	for q in rim_xz:
		reach = maxf(reach, q.distance_to(centre))
	_goo_mat.set_shader_parameter("reach", reach)


func _crust_grey() -> Color:
	## the painted crust's mean colour in a band just outside the shoreline
	var ppt := float(crust_img.get_width()) / PitBackdrop.REF.x
	var st := pb._stadium()
	var c_pt: Vector2 = st[0]
	var acc := Vector3.ZERO
	var n := 0
	for k in range(0, RAYS, 2):
		var a := TAU * float(k) / float(RAYS)
		for r in range(0, 400, 2):
			var p := (c_pt + Vector2(cos(a), sin(a)) * float(r)) * ppt
			if p.x < 0.0 or p.y < 0.0 or p.x >= crust_img.get_width() or p.y >= crust_img.get_height():
				break
			var px := crust_img.get_pixel(int(p.x), int(p.y))
			if px.a > 0.9:
				for e in range(0, 24, 3):              # 24 pt of crust past the shore
					var p2 := (c_pt + Vector2(cos(a), sin(a)) * float(r + e)) * ppt
					if p2.x >= 0.0 and p2.y >= 0.0 and p2.x < crust_img.get_width() and p2.y < crust_img.get_height():
						var q := crust_img.get_pixel(int(p2.x), int(p2.y))
						acc += Vector3(q.r, q.g, q.b)
						n += 1
				break
	if n == 0:
		return Color(0.42, 0.42, 0.42)
	acc /= float(n)
	return Color(acc.x, acc.y, acc.z)


func step(level: float, progress: float, cam: Camera3D) -> void:
	if pb == null:
		return
	if pb._placed and stamp != pb.placed_n and cam != null:
		ok = try_build(cam)
		visible = ok
	if not ok:
		return
	_goo.position.y = level
	_goo.visible = progress < 0.999
	_wall_mat.set_shader_parameter("level_y", level)
	_goo_mat.set_shader_parameter("t0", progress)
	var cols := PackedVector3Array()
	for tb in river.wl._tubes:
		if cols.size() >= 16:
			break
		if not bool(tb.get("alive", true)) or bool(tb.get("gone", false)) or float(tb.get("lift", 0.0)) > 0.05:
			continue
		cols.append(Vector3(float(tb["x"]), float(tb["z"]), float(tb["r"])))
	_goo_mat.set_shader_parameter("n_cols", cols.size())
	if cols.size() > 0:
		while cols.size() < 16:
			cols.append(Vector3(0, 0, -100))
		_goo_mat.set_shader_parameter("cols", cols)


func floor_h() -> float:
	return floor_y
