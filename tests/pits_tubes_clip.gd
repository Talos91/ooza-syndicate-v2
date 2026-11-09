extends Node
## PITS / TUBES clipping probe (no-clipping rule: parts must not intersect or float; spec 05 Handoff/PITS-TUBES-2026-11.md).
## R-01 STRAIT, 4 pits. Every POTENTIAL tube (all T3 slots, the mesh holds them all) is checked as a capsule of radius
## WorldTubes.PIPE_R round its centre line:
##   tube x tube      3D distance between two runs' centre lines >= 2 PIPE_R (points under the goo, r < POOL_R, skipped)
##   tube x Locals    every Locals' lane (pool centre -> rim exit -> path -> door, march columns included): where a tube comes
##                    within LOCAL_HW + PIPE_R of the lane's centre line, its underside clears LOCAL_H over the floor
##   tube x bases     >= BASE_R + PIPE_R from every OTHER column base's axis (own base: past its socket), >= r + PIPE_R from a
##                    pillar sleeve, >= RING_R + PIPE_R from every other pit (or above its rim)
##   floating         on the floor run (not over a lane / tube bridge, not at the socket or the rim) the underside is <= FLOAT_TOL
##   pit_sym (v2)     the 4 pits mirror left/right and top/bottom about the board's centre (0.01 m); prints their coordinates
##   span / post_clip (v2) level runs held by stands <= SPAN_MAX apart; no stand on a Locals' lane or under another tube
##   fan_cross (v2)   no two tubes of one pit cross on the floor plan within HDR_R + HDR_APPR + 2 m of its centre
##   (v2 collectors: runs with col < 0 are a pit's header bar (sock -1) and riser (sock -2), radius HDR_RR; a tube's end on
##   its header and the riser's start on the bar are joints, not clips)
## Prints one PITS_CLIP line per check and PITS_CLIP TOTAL <n>; exit 0 when 0 failures.
##   Godot --headless --path . res://tests/pits_tubes_clip.tscn [-- map=R-05]   (or windowed off-screen + silent)

const MAIN := "res://main.tscn"
const LOCAL_H := 0.64            # a Local's height (world_tubes.gd _hazards)
const LOCAL_HW := 0.39           # half its width (0.78)
const BASE_R := 1.92             # a column base's reach: socket couplings (world_locals.gd TUBE_AVOID note)
const FLOAT_TOL := 0.02          # m of air under a floor run
const STEP := 0.1                # m between samples along a run

var fails := {}
var worst := {}


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _map_file(code: String) -> String:
	for f in DirAccess.get_files_at("res://maps4"):
		if f.begins_with(code) and f.ends_with(".json"):
			return f
	return ""


func _fail(kind: String, what: String) -> void:
	if not fails.has(kind):
		fails[kind] = []
	if (fails[kind] as Array).size() < 6 or OS.has_environment("PITS_CLIP_ALL"):
		print("PITS_CLIP FAIL %s: %s" % [kind, what])
	(fails[kind] as Array).append(what)


func _note(kind: String, v: float) -> void:
	worst[kind] = minf(float(worst.get(kind, INF)), v)


static func _samples(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in range(1, pts.size()):
		var m := maxi(int(pts[k].distance_to(pts[k - 1]) / STEP), 1)
		for j in range(m):
			out.append(pts[k - 1].lerp(pts[k], float(j) / m))
	out.append(pts[pts.size() - 1])
	return out


static func _rad(run: Array) -> float:
	return WorldTubes.HDR_RR if int(run[0]) < 0 else WorldTubes.PIPE_R


static func _joint(a: Array, b: Array, at: Vector3) -> bool:
	## v2: where a run meets b at a designed joint - a tube's last point on its pit's header, or the riser's first on the bar
	if int(a[2]) != int(b[2]) or int(b[0]) >= 0:
		return false
	var pa: PackedVector3Array = a[3]
	if int(a[0]) >= 0:                                # its plug on the header (the middle plug meets the riser there too)
		return at.distance_to(pa[pa.size() - 1]) < WorldTubes.HDR_RR + WorldTubes.PIPE_R + 0.3
	if int(a[1]) == -2 and int(b[1]) == -1:
		return at.distance_to(pa[0]) < 2.0 * WorldTubes.HDR_RR + 0.6
	return false


func _run() -> void:
	var code := "R-01"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("map="):
			code = a.substr(4)                        # another map: -- map=R-05
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": "res://maps4/" + _map_file(code)}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.demo = false
	get_tree().root.add_child(inst)
	var wl: WorldLayer = inst.world_layer
	var tries := 0
	while (wl.pipes == null or not wl.pipes.built) and tries < 600:
		await get_tree().process_frame
		tries += 1
	if wl.pipes == null or not wl.pipes.built:
		print("PITS_CLIP tubes never built")
		get_tree().quit(1)
		return
	var tp: WorldTubes = wl.pipes
	var lc: WorldLocals = wl.locals
	var fy := wl.floor_y
	var R := WorldTubes.PIPE_R
	var runs: Array = tp.run_pts
	var crat: Array = lc.craters
	print("PITS_CLIP %s: %d pits, %d tube slots, %d feeds (marches %d), floor y %.2f" % [code, crat.size(), runs.size(), lc.feeds.size(),
			lc.feeds.keys().filter(func(k): return int(k) >= WorldLocals.MARCH_KEY).size(), fy])
	# ---- v2 pit symmetry (Daniele 2026-11-09): the 4 pits mirror left/right and top/bottom about the board's centre
	var bc := lc.board_bounds().get_center()
	print("PITS_CLIP pits %s centre (%.2f, %.2f): %s" % [code, bc.x, bc.y, str(crat.map(func(v): return "(%.2f, %.2f)" % [v.x, v.z]))])
	if crat.size() != 4:
		_fail("pit_sym", "%d pits (want 4)" % crat.size())
	else:
		var o: Vector2 = Vector2(absf(crat[0].x - bc.x), absf(crat[0].z - bc.y))
		var sg := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
		for k in range(4):
			var want: Vector2 = bc + o * (sg[k] as Vector2)
			var d := Vector2(crat[k].x, crat[k].z).distance_to(want)
			_note("pit_sym_err", -d)
			if d > 0.01:
				_fail("pit_sym", "pit %d at (%.2f, %.2f), mirror wants (%.2f, %.2f)" % [k, crat[k].x, crat[k].z, want.x, want.y])
	# ---- v2 fan: no two tubes cross (on the floor plan) within the fan's reach of a pit
	var fan_r := WorldTubes.HDR_R + WorldTubes.HDR_APPR + 2.0
	for a in range(runs.size()):
		var pa: PackedVector3Array = runs[a][3]
		if int(runs[a][0]) < 0:
			continue                                      # the collector itself (the tubes end on it)
		for b in range(a + 1, runs.size()):
			if int(runs[a][2]) != int(runs[b][2]) or int(runs[b][0]) < 0:
				continue
			var pc: Vector3 = crat[int(runs[a][2])]
			var c2 := Vector2(pc.x, pc.z)
			var pb: PackedVector3Array = runs[b][3]
			var hit := false
			for i in range(1, pa.size()):
				var a0 := Vector2(pa[i - 1].x, pa[i - 1].z)
				var a1 := Vector2(pa[i].x, pa[i].z)
				if a0.distance_to(c2) > fan_r and a1.distance_to(c2) > fan_r:
					continue
				for j in range(1, pb.size()):
					var b0 := Vector2(pb[j - 1].x, pb[j - 1].z)
					var b1 := Vector2(pb[j].x, pb[j].z)
					var x = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
					if x != null and (x as Vector2).distance_to(c2) <= fan_r:
						hit = true
			if hit:
				_fail("fan_cross", "slot %d (col %d) x slot %d (col %d) cross within %.1f m of pit %d" % [a, runs[a][0], b, runs[b][0], fan_r, runs[a][2]])
	# ---- tube x tube (segment pairs, submerged points skipped)
	var pairs := 0
	for a in range(runs.size()):
		var pa: PackedVector3Array = runs[a][3]
		var ca: Vector3 = crat[int(runs[a][2])]
		for b in range(a + 1, runs.size()):
			var pb: PackedVector3Array = runs[b][3]
			var cb: Vector3 = crat[int(runs[b][2])]
			for i in range(1, pa.size()):
				var a0 := pa[i - 1]
				var a1 := pa[i]
				if Vector2(a1.x - ca.x, a1.z - ca.z).length() < WorldLocals.POOL_R and Vector2(a0.x - ca.x, a0.z - ca.z).length() < WorldLocals.POOL_R:
					continue
				for j in range(1, pb.size()):
					var b0 := pb[j - 1]
					var b1 := pb[j]
					if Vector2(b1.x - cb.x, b1.z - cb.z).length() < WorldLocals.POOL_R and Vector2(b0.x - cb.x, b0.z - cb.z).length() < WorldLocals.POOL_R:
						continue
					var cp := Geometry3D.get_closest_points_between_segments(a0, a1, b0, b1)
					var d := (cp[0] as Vector3).distance_to(cp[1])
					var rr := _rad(runs[a]) + _rad(runs[b])
					if _joint(runs[a], runs[b], cp[0]) or _joint(runs[b], runs[a], cp[1]):
						continue
					pairs += 1
					_note("tube_tube_gap", d - rr)
					if d < rr - 0.005:
						_fail("tube_tube", "slot %d (col %d sock %d) x slot %d (col %d sock %d) at (%.1f, %.1f, %.1f): centres %.3f m apart" % [
								a, runs[a][0], runs[a][1], b, runs[b][0], runs[b][1], cp[0].x, cp[0].y - fy, cp[0].z, d])
	# ---- the Locals' lanes (2D polylines) with the pool -> rim hop in front
	var lanes: Array = []
	for fk in lc.feeds:
		var f: Dictionary = lc.feeds[fk]
		var c: Vector3 = crat[int(f["crater"])]
		var pl: Array = [Vector2(c.x, c.z)] + (f["path"] as Array)
		lanes.append([fk, pl])
	# ---- per tube sample: Locals, bases, pits, floating
	var samples := 0
	for r in range(runs.size()):
		var col: int = runs[r][0]
		var own: Dictionary = wl._tubes[col] if col >= 0 else {"x": 99999.0, "z": 99999.0}
		var own_foot := Vector2(own["x"], own["z"])
		R = _rad(runs[r])
		var pit: Vector3 = crat[int(runs[r][2])]
		var pit2 := Vector2(pit.x, pit.z)
		var sp := _samples(runs[r][3])
		for k in range(sp.size()):
			var q := sp[k]
			var q2 := Vector2(q.x, q.z)
			var under := q.y - R - fy
			samples += 1
			for ln in lanes:
				var pl: Array = ln[1]
				for j in range(1, pl.size()):
					var d := q2.distance_to(Geometry2D.get_closest_point_to_segment(q2, pl[j - 1], pl[j]))
					if d < LOCAL_HW + R:
						var hop := 0.0
						if j == 1:                        # the hop out of the pool over the rim: a Local tops RIM_H there
							hop = WorldLocals.RIM_H
						_note("lane_clear", under - (LOCAL_H + hop))
						if under < LOCAL_H + hop - 0.005:
							_fail("tube_locals", "slot %d (col %d) over lane %s seg %d at (%.1f, %.1f): underside %.2f m, needs %.2f" % [
									r, col, str(ln[0]), j, q.x, q.z, under, LOCAL_H + hop])
			for j in range(wl._tubes.size()):
				var t2: Dictionary = wl._tubes[j]
				var c2 := Vector2(t2["x"], t2["z"])
				var d2 := q2.distance_to(c2)
				if t2.get("ent", false):
					if j == col:
						continue                          # its own socket
					_note("base_gap", d2 - BASE_R - R)
					if d2 < BASE_R + R and under < WorldTubes.ROOF_H + WorldTubes.WALL_H:
						_fail("tube_base", "slot %d (col %d) into column %d's base at (%.1f, %.1f): %.2f m from its axis" % [r, col, j, q.x, q.z, d2])
				else:
					_note("pillar_gap", d2 - float(t2["r"]) - R)
					if d2 < float(t2["r"]) + R:
						_fail("tube_pillar", "slot %d (col %d) into pillar %d at (%.1f, %.1f)" % [r, col, j, q.x, q.z])
			for c in crat:
				var cc := Vector2((c as Vector3).x, (c as Vector3).z)
				if cc.distance_to(pit2) < 0.1:
					continue
				_note("other_pit_gap", q2.distance_to(cc) - WorldLocals.RING_R - R)
				if q2.distance_to(cc) < WorldLocals.RING_R + R and under < WorldLocals.RIM_H:
					_fail("tube_pit", "slot %d (col %d) into another pit's ring at (%.1f, %.1f)" % [r, col, q.x, q.z])
			# floating: a LEVEL stretch hovering FLOAT_TOL..0.5 m over the floor (a pipe bridge over a lane stands >= 0.8 m,
			# one resting on another tube 0.57 m; ramps are not level), away from the socket and the rim
			var from_sock := q2.distance_to(own_foot) - WorldTubes.APOTHEM
			var to_rim := q2.distance_to(pit2) - WorldLocals.RING_R
			if from_sock > WorldTubes.SOCK_D + 1.4 and to_rim > 4.0 and k > 0 and k < sp.size() - 1:
				var level := absf(sp[k + 1].y - q.y) < 0.004 and absf(sp[k - 1].y - q.y) < 0.004
				if level and under < 0.5:
					worst["float_gap_max"] = maxf(float(worst.get("float_gap_max", -INF)), under)
					if under > FLOAT_TOL:
						_fail("floating", "slot %d (col %d) at (%.1f, %.1f): %.3f m of air under a level run" % [r, col, q.x, q.z, under])
	# ---- v2 stands: every level run is held up at most SPAN_MAX apart (socket, stands, pool end, floor contact); a stand
	# never stands on a Locals' lane or under another tube
	var by_slot := {}
	for pp in tp.posts:
		var ft: Vector3 = pp[1]
		for ln in lanes:
			var pl: Array = ln[1]
			for j in range(1, pl.size()):
				var q2 := Vector2(ft.x, ft.z)
				if q2.distance_to(Geometry2D.get_closest_point_to_segment(q2, pl[j - 1], pl[j])) < LOCAL_HW + WorldTubes.POST_HW:
					_fail("post_clip", "stand of slot %d at (%.1f, %.1f) on lane %s" % [pp[0], ft.x, ft.z, str(ln[0])])
		for o in range(runs.size()):
			if o == int(pp[0]):
				continue
			var po: PackedVector3Array = runs[o][3]
			for j in range(1, po.size()):
				var q2 := Vector2(ft.x, ft.z)
				var cq := Geometry2D.get_closest_point_to_segment(q2, Vector2(po[j - 1].x, po[j - 1].z), Vector2(po[j].x, po[j].z))
				if q2.distance_to(cq) < _rad(runs[o]) + WorldTubes.POST_HW:
					_fail("post_clip", "stand of slot %d at (%.1f, %.1f) under slot %d" % [pp[0], ft.x, ft.z, o])
		if not by_slot.has(int(pp[0])):
			by_slot[int(pp[0])] = []
		by_slot[int(pp[0])].append(Vector2(ft.x, ft.z))
	for r in range(runs.size()):
		var sp := _samples(runs[r][3])
		var pit: Vector3 = crat[int(runs[r][2])]
		var last := 0.0
		var cum := 0.0
		var held: Array = by_slot.get(r, [])
		for k in range(sp.size()):
			if k > 0:
				cum += Vector2(sp[k].x - sp[k - 1].x, sp[k].z - sp[k - 1].z).length()
			var q2 := Vector2(sp[k].x, sp[k].z)
			var sup := sp[k].y - _rad(runs[r]) - fy <= FLOAT_TOL or q2.distance_to(Vector2(pit.x, pit.z)) < WorldLocals.RING_R + 0.9
			if int(runs[r][0]) < 0:
				for o in runs:                        # the header is held by the tubes plugged into it too
					var po: PackedVector3Array = o[3]
					if int(o[0]) >= 0 and int(o[2]) == int(runs[r][2]) and q2.distance_to(Vector2(po[po.size() - 1].x, po[po.size() - 1].z)) < STEP:
						sup = true
			for h in held:
				if q2.distance_to(h) < STEP * 0.6:
					sup = true
			if sup or k == sp.size() - 1:
				_note("span_room", WorldTubes.SPAN_MAX - (cum - last))
				if cum - last > WorldTubes.SPAN_MAX:
					_fail("span", "slot %d (col %d): %.1f m unsupported ending at (%.1f, %.1f)" % [r, runs[r][0], cum - last, q2.x, q2.y])
				last = cum
	print("PITS_CLIP stands %d" % tp.posts.size())
	if OS.has_environment("PITS_CLIP_DUMP"):              # debug: every run + lane as JSON
		var dump := {"runs": [], "lanes": [], "cols": {}}
		for rn in runs:
			dump["runs"].append({"col": rn[0], "sock": rn[1], "pts": Array(rn[3]).map(func(v): return [snappedf(v.x, 0.01), snappedf(v.y - fy, 0.01), snappedf(v.z, 0.01)])})
		for ln in lanes:
			dump["lanes"].append({"key": ln[0], "pts": (ln[1] as Array).map(func(v): return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)])})
		for i in tp.cols:
			dump["cols"][str(i)] = [wl._tubes[i]["x"], wl._tubes[i]["z"]]
		var fd := FileAccess.open(OS.get_environment("PITS_CLIP_DUMP"), FileAccess.WRITE)
		fd.store_string(JSON.stringify(dump))
		fd.close()
	var total := 0
	for kind in ["pit_sym", "fan_cross", "span", "post_clip", "tube_tube", "tube_locals", "tube_base", "tube_pillar", "tube_pit", "floating"]:
		var n := (fails.get(kind, []) as Array).size()
		total += n
		print("PITS_CLIP %-12s %d" % [kind, n])
	var w := {}
	for k in worst:
		w[k] = snappedf(float(worst[k]), 0.001)
	print("PITS_CLIP margins (m, min; float_gap_max = most air under a floor run) %s" % str(w))
	print("PITS_CLIP %d segment pairs, %d samples" % [pairs, samples])
	print("PITS_CLIP TOTAL %d" % total)
	get_tree().quit(0 if total == 0 else 1)
