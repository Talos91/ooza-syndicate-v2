class_name WorldTubes
extends Node3D
## PITS / TUBES / COLUMNS (Daniele 2026-11-07; spec 05 Handoff/PITS-TUBES-2026-11.md, reference sheet
## refs/10-column-sockets "VEX COLUMN / CORNER TUBE SOCKETS + CARDINAL DOORS"). VIEW ONLY: reads sim.nodes (owner, tier,
## build_kind / build_target, structure), sim.homes and the Locals' queues; never writes to the Sim.
##  - the COLUMN BASE (one mesh for every tier, column_base_mesh): an octagonal foot round the central lift (the node's
##    vertical goo tube), 4 corner tube SOCKETS (coupling rings on the diagonal faces) and 4 cardinal walk-in DOORS (arch,
##    frame, dark mouth) each with TWO horizontal laser strands in the owner's light, an owner-light strip round the foot
##    and a collar light round the lift. Vertex-colour regions for shaders/world_entrance.gdshader (magenta key = owner
##    light, the rest steel / recess). 624 tris (v2 four-door entrance: 704).
##  - the TRANSPORT TUBES: per column, tubes from its corner sockets to its NEAREST pit (R1: the sockets closest in
##    direction to that pit first), along the floor then over the pit's rim into the pool (R2 as drawn on the sheet:
##    the network overview's tubes lie on the floor). Where a tube meets a Locals' lane or an earlier tube it rises in a
##    short pipe bridge over it (the Locals walk under; tubes rest on the tube they cross). Count from the sim (rule 4): a seat's home column 1, any other 0;
##    +1 for each tier reached past its start tier to T2, +2 to T3; max 4; never fewer (R4: tubes only grow). While a vat
##    upgrade builds, the tubes it adds show EMPTY glass; when the tier completes they fill from the pit to the column.
##    Goo flows PIT -> COLUMN (rule 5, Daniele 2026-11-07 final) in the column owner's goo colour (R3: WorldLayer._col, the colour the tubes used);
##    a capture recolours every tube of that column at once.
##  - PIT COLOUR (R7): per pit, gray blended toward the tube-weighted mix of the players' colours by T / (T + L / 20).
## Budget: ONE draw for every tube of the map (one ArrayMesh, all potential slots: 4 per column; a slot's state lives in
## a 1-row float texture: rgb colour, a = fill 0..1 from the pit end, < 0 hidden -> the vertex shader collapses it).

const SHADER_PIPE := preload("res://shaders/world_pipe.gdshader")
# the column base (metres; origin = the lift's axis on the floor, doors at +Z, +X, -Z, -X, sockets on the diagonals)
const APOTHEM := 1.6             # centre to a face (doors and sockets sit on the faces)
const WALL_H := 1.05
const ROOF_R := 1.08             # the sloped roof ends round the lift (the lift glass is r 0.95)
const ROOF_H := 1.38
const DOOR_HW := 0.42            # door half width; the arch springs at DOOR_RECT, its top at DOOR_RECT + DOOR_HW
const DOOR_RECT := 0.42
const FRAME := 0.09
const FRAME_D := 0.08            # the frame stands this proud of the face
const LASER_Y := [0.26, 0.5]
const SOCK_Y := 0.48             # socket centre over the floor
const SOCK_R := 0.36
const SOCK_RI := 0.30
const SOCK_D := 0.32             # the coupling stands this proud of its face
const PIPE_R := 0.27
const PIPE_Y := 0.275            # the tube's centre on its run along the floor (it rests on the floor: no clipping rule)
const STEEL := Color(0.20, 0.22, 0.26)
const STEEL_D := Color(0.10, 0.11, 0.13)
const STEEL_L := Color(0.27, 0.29, 0.33)
const RECESS := Color(0.015, 0.015, 0.02)
const FILL_S := 1.6              # s: a finished tube fills from the pit to the column
const TUBE_ADD := {2: 1, 3: 2}   # tubes built by reaching this tier (rule 4)
const MAX_TUBES := 4
const PIT_L_DIV := 20.0          # R7: strength = T / (T + L / 20)
const LANE_SEP := 0.22           # rad round a pit kept clear of a Locals' lane exit (1.3 m at the rim, 0.70 m where a tube enters the goo)
const TUBE_SEP := 0.18           # rad between two tubes over the rim (1.06 m; 0.63 m where they dip into the goo at r 3.5)
const LANE_CLEAR := 1.08         # m: a tube's centre over a Locals' lane (a Local is 0.64 tall: 15 cm under the glass)
const LIFT_RAMP := 1.4           # m: a pipe bridge's ramp each side
const GOO_R := 3.2              # m from the pit's centre: a tube's mouth under the goo (Locals emerge LANE_SEP aside)
const RIB_OFF := 0.92            # m: a column's tubes run beside its Locals' lane, the nearest this far from its centre
const RIB_PITCH := 0.70          # m between two tubes of one column (2 PIPE_R + 16 cm: siblings never touch or cross)

var wl: WorldLayer
var built := false
var cols: Dictionary = {}        # tube index -> {pit, slots: [slot ids, socket order], start, home, n (full), fill_t}
var pit_cols: Array = []         # per pit: its current colour
var _slots := 0
var _state: Image
var _tex: ImageTexture
var _mat: ShaderMaterial
var _mi: MeshInstance3D
var _dirty := true
var tris := 0                    # probes: the tube mesh's triangles
var _laid: Array = []            # the tubes built so far (world points): later tubes bridge over them
var run_pts: Array = []          # probes (tests/pits_tubes_clip.gd): per slot [col index, socket, pit, world points]
static var _base_mesh: ArrayMesh


static func corner_dir(k: int) -> Vector2:
	## the 4 corner sockets: +X+Z, +X-Z, -X-Z, -X+Z (unit, x z)
	var a := PI / 4.0 + PI / 2.0 * k
	return Vector2(sin(a), cos(a))


static func tubes_for(n: Dictionary, start_tier: int, home: bool, tier := -1) -> int:
	## rule 4: home 1, others 0; +1 reaching T2, +2 reaching T3 (counted from the column's start tier); max 4
	var t := int(n.get("tier", 1)) if tier < 0 else tier
	var c := 1 if home else 0
	for k in range(start_tier + 1, mini(t, 3) + 1):
		c += int(TUBE_ADD.get(k, 0))
	return mini(c, MAX_TUBES)


func setup(w: WorldLayer) -> void:
	wl = w
	var homes: Array = wl.sim.homes.values()
	for i in range(wl._tubes.size()):
		var tb: Dictionary = wl._tubes[i]
		if not tb.get("ent", false):
			continue                                  # pillar sleeves have no base, no sockets
		var n: Dictionary = wl.sim.nodes[tb["id"]]
		var st := clampi(int(n.get("tier", 1)), 1, 3)
		var home: bool = int(tb["id"]) in homes
		cols[i] = {"start": st, "home": home, "n": tubes_for(n, st, home), "pit": -1, "slots": [], "fill_t": [0.0, 0.0, 0.0, 0.0],
				"full": [false, false, false, false]}
		for k in range(MAX_TUBES):                    # the tubes there at the start are full already
			cols[i]["full"][k] = k < int(cols[i]["n"])
			cols[i]["fill_t"][k] = -99.0


func build() -> void:
	## once the pits are placed (WorldLocals.place): every potential tube of every column into one mesh
	var craters: Array = wl.locals.craters if wl.locals != null else []
	if craters.is_empty():
		return
	pit_cols.clear()
	for k in range(craters.size()):
		pit_cols.append(WorldLayer.NATIVE_GRAY)
	# the Locals' lane exits round each pit (kept clear) and the tubes' wanted arrival angles
	var fixed: Array = []
	for k in range(craters.size()):
		fixed.append([])
	for fk in wl.locals.feeds:
		var f: Dictionary = wl.locals.feeds[fk]
		var c: Vector3 = craters[int(f["crater"])]
		var ex: Vector2 = (f["path"] as Array)[0]
		fixed[int(f["crater"])].append(atan2(ex.y - c.z, ex.x - c.x))
	var placed: Array = []
	for k in range(craters.size()):
		placed.append([])
	var runs: Array = []                              # [col index, socket k, pit, arrival angle, world points]
	var placed_best := {}
	_laid.clear()                                     # the floor runs laid so far (later tubes bridge over them)
	var near_first: Array = cols.keys()               # the columns nearest their pit lay their tubes first (inside)
	var pd := func(i: int) -> float:
		var best := INF
		for c in craters:
			best = minf(best, Vector2(wl._tubes[i]["x"], wl._tubes[i]["z"]).distance_to(Vector2(c.x, c.z)))
		return best
	near_first.sort_custom(func(x, y): return pd.call(x) < pd.call(y))
	for i in near_first:
		var tb: Dictionary = wl._tubes[i]
		var foot := Vector2(tb["x"], tb["z"])
		var pi := 0
		var bd := INF
		for k in range(craters.size()):
			var d := foot.distance_to(Vector2(craters[k].x, craters[k].z))
			if d < bd:
				bd = d
				pi = k
		cols[i]["pit"] = pi
		var cp := Vector2(craters[pi].x, craters[pi].z)
		var to := (cp - foot).normalized() if cp.distance_to(foot) > 0.01 else Vector2(0, 1)
		var order := [0, 1, 2, 3]                     # R1: the corner closest in direction to the pit first
		order.sort_custom(func(a, b): return corner_dir(a).dot(to) > corner_dir(b).dot(to))
		var n0: Dictionary = wl.sim.nodes[tb["id"]]
		var most := tubes_for(n0, int(cols[i]["start"]), bool(cols[i]["home"]), 3)   # the most it can ever hold
		# its own lane's exit angle: the tubes split round it (left sockets left of the lane, right ones right), each
		# side an ordered bundle TUBE_SEP apart, pushed outward past other lanes and tubes: no tube crosses its column's
		# lane or a sibling
		var lane := atan2(foot.y - cp.y, foot.x - cp.x)
		var spine: Array = []
		if wl.locals.feeds.has(i) and int(wl.locals.feeds[i]["crater"]) == pi:
			var ex: Vector2 = (wl.locals.feeds[i]["path"] as Array)[0]
			lane = atan2(ex.y - cp.y, ex.x - cp.x)
			spine = _spine(wl.locals.feeds[i]["path"])
		if not spine.is_empty():
			# the column's tubes as a ribbon beside its own Locals' lane (the lane is routed round bases and rings already):
			# each side's tubes in order, the inner one nearest the lane, so siblings never cross or touch
			var rib := _ribbon_runs(i, order.slice(0, most), spine, craters[pi], pi, lane, fixed[pi], placed[pi])
			for rn in rib:
				_laid.append((rn[4] as PackedVector3Array).slice(0, (rn[4] as PackedVector3Array).size() - 6))
				runs.append(rn)
				cols[i]["slots"].append(runs.size() - 1)
			var sl0: Array = cols[i]["slots"]
			sl0.sort_custom(func(x, y): return order.find(int(runs[x][1])) < order.find(int(runs[y][1])))
			continue
		# (no lane to this pit: the free layout below)
		var sides := {-1: [], 1: []}
		for s in order.slice(0, most):
			var w := _side_point(foot, to, s)
			var want := angle_difference(lane, atan2(w.y - cp.y, w.x - cp.x))
			sides[-1 if want < 0.0 else 1].append([absf(want), s])
		for sg in [-1, 1]:
			(sides[sg] as Array).sort_custom(func(x, y): return x[0] < y[0])    # nearest the lane first
		# which side of the lane each bundle takes: as split (left sockets left), or all round one side - the layout whose
		# tubes cross the fewest tubes already laid and Locals' lanes (each crossing is a pipe bridge)
		var opts := [sides, {-1: sides[-1] + sides[1], 1: []}, {-1: [], 1: sides[-1] + sides[1]}]
		var best_runs: Array = []
		var best_x := INF
		for o in range(opts.size()):
			if o > 0 and ((opts[o][-1] as Array).is_empty() and (opts[o][1] as Array).size() == (sides[1] as Array).size()
					or (opts[o][1] as Array).is_empty() and (opts[o][-1] as Array).size() == (sides[-1] as Array).size()):
				continue                              # the same as the split
			var pl: Array = placed[pi].duplicate()
			var cand: Array = []
			var x := 0
			for sg in [-1, 1]:
				var bundle: Array = opts[o][sg]
				var angs: Array = _bundle(lane, sg, bundle.size(), fixed[pi], pl)[0]
				for j in range(bundle.size()):
					var pts := _path(i, int(bundle[j][1]), craters[pi], float(angs[j]))
					x += _crossings(pts)
					cand.append([i, int(bundle[j][1]), pi, float(angs[j]), pts])
			if x < best_x:
				best_x = x
				best_runs = cand
				placed_best[pi] = pl
		placed[pi] = placed_best[pi]
		for rn in best_runs:
			_laid.append((rn[4] as PackedVector3Array).slice(0, (rn[4] as PackedVector3Array).size() - 6))
			runs.append(rn)
			cols[i]["slots"].append(runs.size() - 1)
		# the slots in socket order (R1: the first tube built goes to the corner closest in direction to the pit)
		var sl: Array = cols[i]["slots"]
		sl.sort_custom(func(x, y): return order.find(int(runs[x][1])) < order.find(int(runs[y][1])))
	_slots = runs.size()
	run_pts = runs.map(func(rn): return [rn[0], rn[1], rn[2], rn[4]])
	_build_mesh(runs, craters)
	_state = Image.create(maxi(_slots, 1), 1, false, Image.FORMAT_RGBAF)
	_tex = ImageTexture.create_from_image(_state)
	_mat.set_shader_parameter("state", _tex)
	built = true
	_dirty = true


func _crossings(pts: PackedVector3Array) -> int:
	## how many laid tubes' and Locals' lanes' segments this run crosses (on the floor plan)
	var n := 0
	var others: Array = []
	for run in _laid:
		var o := []
		for q in (run as PackedVector3Array):
			o.append(Vector2(q.x, q.z))
		others.append(o)
	if wl.locals != null:
		for fk in wl.locals.feeds:
			others.append(wl.locals.feeds[fk]["path"])
	for k in range(1, pts.size() - 6):
		var a := Vector2(pts[k - 1].x, pts[k - 1].z)
		var b := Vector2(pts[k].x, pts[k].z)
		for o in others:
			for j in range(1, (o as Array).size()):
				if Geometry2D.segment_intersects_segment(a, b, o[j - 1], o[j]) != null:
					n += 1
	return n


static func _bundle(lane: float, sg: int, n: int, fixed: Array, placed: Array) -> Array:
	## n tubes on side sg of the lane exit, each just outside the one before it, past lanes (LANE_SEP) and tubes
	## (TUBE_SEP); placed gets them. Returns [angles, passed another tube]
	var out := []
	var passed := false
	var prev: float = lane + sg * (LANE_SEP - TUBE_SEP)
	for j in range(n):
		var ang: float = prev + sg * TUBE_SEP
		for step in range(300):
			var ok := true
			for f in fixed:
				if absf(angle_difference(ang, float(f))) < LANE_SEP:
					ok = false
			for p in placed:
				if absf(angle_difference(ang, float(p))) < TUBE_SEP - 0.001:
					ok = false
					passed = true
			if ok:
				break
			ang += sg * 0.02
		prev = ang
		placed.append(ang)
		out.append(ang)
	return [out, passed]


func _side_point(foot: Vector2, to: Vector2, s: int) -> Vector2:
	## where a socket's tube heads first: straight out of a front socket, round the base's side for a back one
	var cd := corner_dir(s)
	if cd.dot(to) < 0.0:
		var lat := (cd - to * cd.dot(to)).normalized()
		return foot + lat * 3.4 + to * 0.6
	return foot + cd * (APOTHEM + SOCK_D + 1.2)


func _path(i: int, s: int, cp: Vector3, ang: float) -> PackedVector3Array:
	## socket -> along the floor -> over the rim -> into the pool (world points)
	var tb: Dictionary = wl._tubes[i]
	var foot := Vector2(tb["x"], tb["z"])
	var cd := corner_dir(s)
	var p0 := foot + cd * (APOTHEM + 0.05)
	var p1 := foot + cd * (APOTHEM + SOCK_D + 1.2)    # straight out of its socket first
	var dir := Vector2(cos(ang), sin(ang))
	var c2 := Vector2(cp.x, cp.z)
	var rim_out := c2 + dir * (WorldLocals.RING_R + 0.9)
	var p2 := c2 + dir * (WorldLocals.RING_R + 3.0)
	var way := [p0, p1]
	var to := (c2 - foot).normalized()
	if cd.dot(to) < 0.0:                              # a back socket: round the base's side, outside the front tubes
		var lat := (cd - to * cd.dot(to)).normalized()
		way.append(foot + lat * 3.4 + to * 0.6)
	way += _steer(way[-1], p2, i, int(tb["id"]), cp, 0)   # round other columns' bases and other pits
	way.append(p2)
	way.append(rim_out)
	return _shape(way, c2, dir)


func _shape(way: Array, c2: Vector2, dir: Vector2) -> PackedVector3Array:
	## waypoints (x z) -> world points: smooth along the floor, bridges over lanes / laid tubes, over the rim, into the pool
	var fy := wl.floor_y
	var rim_out: Vector2 = way[way.size() - 1]
	var flat := []
	for k in range(way.size() - 1):                   # Catmull-Rom through the waypoints, 0.5 m samples
		var a: Vector2 = way[maxi(k - 1, 0)]
		var b: Vector2 = way[k]
		var c: Vector2 = way[k + 1]
		var d: Vector2 = way[mini(k + 2, way.size() - 1)]
		var m := clampi(int(b.distance_to(c) / 0.5), 1, 80)
		for j in range(m):
			var t := float(j) / m
			flat.append(0.5 * ((2.0 * b) + (c - a) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (3.0 * b - a - 3.0 * c + d) * t * t * t))
	flat.append(rim_out)
	var tot := 0.0
	for k in range(1, flat.size()):
		tot += (flat[k] as Vector2).distance_to(flat[k - 1])
	var top := WorldLocals.RIM_H + PIPE_R + 0.18
	var haz := _hazards(flat)
	var ys := PackedFloat32Array()
	var base_y := PackedFloat32Array()
	var lifts := PackedFloat32Array()
	var cum := 0.0
	for k in range(flat.size()):
		if k > 0:
			cum += (flat[k] as Vector2).distance_to(flat[k - 1])
		var y := lerpf(SOCK_Y, PIPE_Y, smoothstep(0.0, 1.2, cum))
		y = lerpf(y, top, smoothstep(tot - 3.2, tot, cum))    # climbs to clear the rim
		base_y.append(y)
		var lf := _lift(flat[k], haz)                 # over a Locals' lane / an earlier tube: a pipe bridge
		lifts.append(lf if lf > PIPE_Y + 0.05 else 0.0)   # a ramp's last few cm sit on the floor (no hovering foot)
	for k in range(flat.size()):                      # bridges less than 6 m apart join into one (no zigzag)
		var lm := 0.0
		var rm := 0.0
		for j in range(maxi(k - 12, 0), k + 1):
			lm = maxf(lm, lifts[j])
		for j in range(k, mini(k + 13, flat.size())):
			rm = maxf(rm, lifts[j])
		var join := minf(lm, rm)
		if join - PIPE_R < 0.5:
			join = 0.0                                # never a low level span hovering over the floor (no clipping rule)
		ys.append(maxf(base_y[k], maxf(lifts[k], join)))
	# keep the 0.5 m samples where the tube bends up or down, ~2.5 m steps elsewhere (the triangle budget)
	var pts := PackedVector3Array()
	var since := 0.0
	for k in range(flat.size()):
		if k > 0:
			since += (flat[k] as Vector2).distance_to(flat[k - 1])
		var keep := k == 0 or k == flat.size() - 1 or since >= 2.4
		if not keep and absf(ys[k - 1] - 2.0 * ys[k] + ys[k + 1]) > 0.012:
			keep = true
		if keep:
			pts.append(Vector3(flat[k].x, fy + ys[k], flat[k].y))
			since = 0.0
	# over the rim (r RING_R + 0.9 -> 3.0) and down into the pool
	for k in range(1, 7):
		var t := float(k) / 6.0
		var r := lerpf(WorldLocals.RING_R + 0.9, GOO_R, t)
		var y := top + 0.12 * sin(t * PI) if r > WorldLocals.POOL_R else lerpf(top, WorldLocals.POOL_H - 0.25, smoothstep(WorldLocals.POOL_R, GOO_R, r))
		var q := c2 + dir * r
		pts.append(Vector3(q.x, fy + y, q.y))
	return pts


func _spine(path: Array) -> Array:
	## the Locals' lane (rim exit ... 5.3 m in front of the door, the door slot) from the column end to the pit end, 0.5 m samples
	var way: Array = path.slice(0, path.size() - 1)
	way.reverse()
	var out: Array = []
	for k in range(way.size() - 1):
		var a: Vector2 = way[maxi(k - 1, 0)]
		var b: Vector2 = way[k]
		var c: Vector2 = way[k + 1]
		var d: Vector2 = way[mini(k + 2, way.size() - 1)]
		var m := clampi(int(b.distance_to(c) / 0.5), 1, 200)
		for j in range(m):
			var t := float(j) / m
			out.append(0.5 * ((2.0 * b) + (c - a) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (3.0 * b - a - 3.0 * c + d) * t * t * t))
	if not way.is_empty():
		out.append(way[way.size() - 1])
	return out if out.size() >= 4 else []


static func _nrm_at(spine: Array, k: int) -> Vector2:
	var t: Vector2 = (spine[mini(k + 1, spine.size() - 1)] - spine[maxi(k - 1, 0)])
	t = t.normalized() if t.length() > 0.001 else Vector2(1, 0)
	return Vector2(-t.y, t.x)


func _ribbon_runs(i: int, socks: Array, spine: Array, cp: Vector3, pi: int, lane: float, fixed: Array, placed: Array) -> Array:
	## [col, socket, pit, arrival angle, points] per tube: sockets split by the side of the lane they sit on, inner first
	var tb: Dictionary = wl._tubes[i]
	var foot := Vector2(tb["x"], tb["z"])
	var c2 := Vector2(cp.x, cp.z)
	var to := (c2 - foot).normalized() if c2.distance_to(foot) > 0.01 else Vector2(0, 1)
	var a0: Vector2 = spine[0]
	var td := (a0 - foot).normalized() if a0.distance_to(foot) > 0.01 else to   # the door's axis: left / right of it
	var n0 := Vector2(-td.y, td.x)
	var sides := {-1: [], 1: []}
	for s in socks:
		var lat := (_side_point(foot, to, s) - foot).dot(n0)
		sides[1 if lat > 0.0 else -1].append([absf(lat), s])
	var e: Vector2 = spine[spine.size() - 1]
	var ne := _nrm_at(spine, spine.size() - 2)
	var out: Array = []
	for g in [-1, 1]:
		var bundle: Array = sides[g]
		if bundle.is_empty():
			continue
		bundle.sort_custom(func(x, y): return x[0] < y[0])
		var tp: Vector2 = e + ne * float(g)
		var sg := 1 if angle_difference(lane, atan2(tp.y - c2.y, tp.x - c2.x)) > 0.0 else -1
		var k0 := placed.size()                      # this pit's tubes so far: each swings round the pit on its own arc
		var angs: Array = _bundle(lane, sg, bundle.size(), fixed, placed)[0]
		var best: Array = []
		var best_d := -INF
		for perm in ([[0, 1], [1, 0]] if bundle.size() == 2 else [range(bundle.size())]):
			# two tubes on a side: the rim angles go the way round whose swing into the pit keeps them farther apart
			var cand: Array = []
			var n_laid := _laid.size()
			for j in range(bundle.size()):
				var s := int(bundle[j][1])
				var a := float(angs[perm[j]])
				cand.append([i, s, pi, a, _rib_path(i, s, cp, a, spine, g * (RIB_OFF + j * RIB_PITCH), j, k0 + j, sg)])
				var pts: PackedVector3Array = cand[-1][4]
				_laid.append(pts.slice(0, pts.size() - 6))   # the next sibling bridges over it wherever they meet
			_laid.resize(n_laid)
			var d := INF if cand.size() < 2 else _min_gap(cand[0][4], cand[1][4])
			if d > best_d:
				best_d = d
				best = cand
		out += best
	return out


static func _min_gap(p: PackedVector3Array, q: PackedVector3Array) -> float:
	## the least distance between two tubes' centre lines
	var d := INF
	for i in range(1, p.size()):
		for j in range(1, q.size()):
			var cp := Geometry3D.get_closest_points_between_segments(p[i - 1], p[i], q[j - 1], q[j])
			d = minf(d, (cp[0] as Vector3).distance_to(cp[1]))
	return d


func _rib_path(i: int, s: int, cp: Vector3, ang: float, spine: Array, off: float, j: int, kp: int, sg: int) -> PackedVector3Array:
	## socket -> out of it (a back one round the base's side) -> its lane beside the Locals' lane -> the pit's rim at ang
	var tb: Dictionary = wl._tubes[i]
	var foot := Vector2(tb["x"], tb["z"])
	var cd := corner_dir(s)
	var c2 := Vector2(cp.x, cp.z)
	var to := (c2 - foot).normalized() if c2.distance_to(foot) > 0.01 else Vector2(0, 1)
	var way := [foot + cd * (APOTHEM + 0.05), foot + cd * (APOTHEM + SOCK_D + 1.2)]
	if cd.dot(to) < 0.0:
		var lat := (cd - to * cd.dot(to)).normalized()
		way.append(foot + lat * 3.4 + to * 0.6)
	var dir := Vector2(cos(ang), sin(ang))
	var arc_r := WorldLocals.RING_R + 3.0 + kp * RIB_PITCH   # its arc round the pit (outer for later tubes: no two coincide)
	var stop_r := maxf(WorldLocals.RING_R + 4.5, arc_r + 1.5)
	var k := int((1.5 + 1.5 * j) / 0.5)              # outer tubes join their lane a little later (no crossing at the base)
	while k < spine.size() - 1:
		var q: Vector2 = spine[k]
		if q.distance_to(c2) < stop_r:
			break
		way.append(q + _nrm_at(spine, k) * _rib_off(q, spine, k, off, j, i, c2))
		k += 2                                        # 1 m steps (the shape smooths them)
	# round the pit on its arc (the way its side goes, never across its own lane) to its rim angle, then straight in
	var last: Vector2 = way[way.size() - 1]
	var a0 := atan2(last.y - c2.y, last.x - c2.x)
	var swing := fposmod(sg * (ang - a0), TAU)
	if swing > PI * 1.6:
		swing = 0.0                                   # (already a little past it)
	if swing > 0.12:
		var steps := int(ceil(swing / 0.2))
		for m in range(1, steps + 1):
			var a := a0 + sg * swing * float(m) / steps
			way.append(c2 + Vector2(cos(a), sin(a)) * arc_r)
	way.append(c2 + dir * (WorldLocals.RING_R + 3.0))
	way.append(c2 + dir * (WorldLocals.RING_R + 0.9))
	return _shape(way, c2, dir)


func _rib_off(q: Vector2, spine: Array, k: int, off: float, j: int, skip: int, own_pit: Vector2) -> float:
	## the tube's offset from its lane at spine sample k: an obstacle on its side (another column's base, a pillar sleeve,
	## another pit's ring) is passed on its FAR side by the whole side bundle in order (j-th tube j pitches out), blended
	## in over 4 m before / after it - the siblings keep their order and spacing, nothing collapses onto one circle
	var sg := signf(off)
	var o_max := RIB_OFF + 3.0 * RIB_PITCH                # the widest a side bundle can be (the same call for all siblings)
	var t := (spine[mini(k + 1, spine.size() - 1)] - spine[maxi(k - 1, 0)]) as Vector2
	t = t.normalized() if t.length() > 0.001 else Vector2(1, 0)
	var n := Vector2(-t.y, t.x)
	var obs: Array = []
	for jj in range(wl._tubes.size()):
		if jj == skip:
			continue
		var t2: Dictionary = wl._tubes[jj]
		obs.append([Vector2(t2["x"], t2["z"]), 2.6 if t2.get("ent", false) else float(t2["r"]) + 1.0])
	for cc in wl.locals.craters:
		var c := Vector2((cc as Vector3).x, (cc as Vector3).z)
		if c.distance_to(own_pit) > 0.1:
			obs.append([c, WorldLocals.RING_R + 1.0])
	var best := absf(off)
	for ob in obs:
		var rel: Vector2 = (ob[0] as Vector2) - q
		var r: float = ob[1]
		var along := rel.dot(t)
		var lat := rel.dot(n)
		if signf(lat) != sg or absf(along) > r + 4.0 or absf(lat) - r >= o_max + 0.1:
			continue
		var far := absf(lat) + sqrt(maxf(r * r - along * along, 0.0)) + RIB_OFF * 0.5 + j * RIB_PITCH
		var w := 1.0 - smoothstep(r, r + 4.0, absf(along))
		best = maxf(best, lerpf(absf(off), far, w))
	return sg * best


func _hazards(flat: Array) -> Array:
	## what this tube must go over: [segment a, b (x z), clearance height of the tube's centre, half width]. The Locals'
	## lanes (a Local is 0.64 m tall, 0.78 wide) and the tubes already laid (go over them, resting on them)
	var out := []
	var bb := Rect2(flat[0], Vector2.ZERO)
	for q in flat:
		bb = bb.expand(q)
	bb = bb.grow(2.0)
	if wl.locals != null:
		for fk in wl.locals.feeds:
			var path: Array = wl.locals.feeds[fk]["path"]
			for k in range(1, path.size()):
				var a: Vector2 = path[k - 1]
				var b: Vector2 = path[k]
				if _meets(flat, a, b, 0.45 + PIPE_R + 0.1, bb):
					out.append([a, b, LANE_CLEAR, 0.45])
	for run in _laid:
		var pts: PackedVector3Array = run
		for k in range(1, pts.size()):
			var a := Vector2(pts[k - 1].x, pts[k - 1].z)
			var b := Vector2(pts[k].x, pts[k].z)
			if _meets(flat, a, b, 2.0 * PIPE_R + 0.1, bb):
				out.append([a, b, maxf(pts[k - 1].y, pts[k].y) - wl.floor_y + 2.0 * PIPE_R + 0.03, PIPE_R])
	return out


static func _meets(flat: Array, a: Vector2, b: Vector2, w: float, bb: Rect2) -> bool:
	## does the segment a-b come within w of the tube's centre line (crossing it, or running into it; a neighbour running
	## alongside farther off is not a hazard: no bridge)
	var r := Rect2(a, Vector2.ZERO).expand(b).grow(w)
	if not bb.intersects(r):
		return false
	for q in flat:
		if r.has_point(q) and (q as Vector2).distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)) < w:
			return true
	return false


static func _lift(q: Vector2, haz: Array) -> float:
	## the height the tube's centre needs at q: full over a hazard (its half width + the tube + 10 cm), ramping down in 1.4 m
	var h := 0.0
	for hz in haz:
		var d := q.distance_to(Geometry2D.get_closest_point_to_segment(q, hz[0], hz[1]))
		var w0: float = float(hz[3]) + PIPE_R + 0.1
		if d < w0 + LIFT_RAMP:
			h = maxf(h, float(hz[2]) * (1.0 - smoothstep(w0, w0 + LIFT_RAMP, d)))
	return h


func _steer(a: Vector2, b: Vector2, skip: int, _id: int, pit: Vector3, depth: int) -> Array:
	## straight a -> b unless another column's base / lift or another pit is in the way: one detour point beside it,
	## then recurse (R2 routes round nothing else: the tubes cross under the bridges)
	if depth > 4:
		return []
	var worst = null
	var worst_t := INF
	var obs := []
	for j in range(wl._tubes.size()):
		if j == skip:
			continue
		var t2: Dictionary = wl._tubes[j]
		obs.append([Vector2(t2["x"], t2["z"]), 2.6 if t2.get("ent", false) else float(t2["r"]) + 1.0])
	for c in wl.locals.craters:                       # its own pit too: it arrives radially at r RING_R + 3
		obs.append([Vector2((c as Vector3).x, (c as Vector3).z), WorldLocals.RING_R + 1.5])
	for ob in obs:
		var c: Vector2 = ob[0]
		var r: float = ob[1]
		if c.distance_to(a) < r or c.distance_to(b) < r:
			continue
		var q := Geometry2D.get_closest_point_to_segment(c, a, b)
		if q.distance_to(c) < r and a.distance_to(q) < worst_t:
			worst_t = a.distance_to(q)
			worst = ob
	if worst == null:
		return []
	var c2: Vector2 = worst[0]
	var q2 := Geometry2D.get_closest_point_to_segment(c2, a, b)
	var nrm := q2 - c2
	if nrm.length() < 0.01:
		nrm = (b - a).orthogonal()
	var w := c2 + nrm.normalized() * (float(worst[1]) + 0.6)
	return _steer(a, w, skip, _id, pit, depth + 1) + [w] + _steer(w, b, skip, _id, pit, depth + 1)


func _build_mesh(runs: Array, craters: Array) -> void:
	var sides := 6
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for r in range(runs.size()):
		var run: Array = runs[r]
		var pts: PackedVector3Array = run[4]
		var total := 0.0
		for k in range(1, pts.size()):
			total += pts[k].distance_to(pts[k - 1])
		var cum := 0.0
		var base := vs.size()
		for k in range(pts.size()):
			if k > 0:
				cum += pts[k].distance_to(pts[k - 1])
			var tg: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
			var ref := Vector3.UP if absf(tg.y) < 0.95 else Vector3.RIGHT
			var bx := tg.cross(ref).normalized()
			var by := bx.cross(tg).normalized()
			for j in range(sides + 1):
				var a := TAU * j / sides
				var nrm := bx * cos(a) + by * sin(a)
				vs.append(pts[k] + nrm * PIPE_R)
				ns.append(nrm)
				uv.append(Vector2(float(j) / sides, cum))
				uv2.append(Vector2(float(r) + 0.5, cum / maxf(total, 0.01)))
		for k in range(pts.size() - 1):
			for j in range(sides):
				var a0 := base + k * (sides + 1) + j
				var b0 := a0 + sides + 1
				# front face: (c - a) x (b - a) points out
				_tri_out(vs, idx, a0, a0 + 1, b0 + 1, ns[a0] + ns[b0 + 1])
				_tri_out(vs, idx, a0, b0 + 1, b0, ns[a0] + ns[b0])
	tris = idx.size() / 3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vs
	arrays[Mesh.ARRAY_NORMAL] = ns
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	if not vs.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER_PIPE
	_mat.set_shader_parameter("abyss", wl.haze_abyss())
	if wl.floor_haze >= 0.0:
		_mat.set_shader_parameter("haze", wl.floor_haze)
	_mat.set_shader_parameter("slots", float(maxi(runs.size(), 1)))
	_mi = MeshInstance3D.new()
	_mi.mesh = m
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)


static func _tri_out(vs: PackedVector3Array, idx: PackedInt32Array, a: int, b: int, c: int, out: Vector3) -> void:
	if (vs[c] - vs[a]).cross(vs[b] - vs[a]).dot(out) < 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


# ------------------------------------------------------------------ per frame
func step(_dt: float) -> void:
	if not built:
		return
	var now := wl._t
	var changed := false
	var weights: Array = []                           # per pit: {seat: full tubes}
	for k in range(pit_cols.size()):
		weights.append({})
	for i in cols:
		var c: Dictionary = cols[i]
		var tb: Dictionary = wl._tubes[i]
		var n: Dictionary = wl.sim.nodes[tb["id"]]
		var live: bool = tb.get("shown", false) and tb["alive"] and (tb["mi"] as MeshInstance3D).visible
		var full_n := maxi(int(c["n"]), tubes_for(n, int(c["start"]), bool(c["home"])))   # R4: never fewer
		var want_n := full_n
		if VatColumn.upgrading(n):                    # the tubes the upgrade adds: empty glass until the tier completes
			var to := int((n["build_target"] as Dictionary).get("tier", int(n["tier"]) + 1))
			want_n = maxi(full_n, tubes_for(n, int(c["start"]), bool(c["home"]), to))
		c["n"] = full_n
		var col: Color = WorldLayer._col(str(n["owner"]))
		var slots: Array = c["slots"]
		for k in range(slots.size()):
			var fill := -1.0                           # hidden
			if live and k < want_n:
				fill = 0.0
				if k < full_n:
					if not c["full"][k]:
						c["full"][k] = true
						c["fill_t"][k] = now
					fill = clampf((now - float(c["fill_t"][k])) / FILL_S, 0.0, 1.0)
					if fill >= 1.0 and str(n["owner"]) != "":
						var w: Dictionary = weights[int(c["pit"])]
						w[n["owner"]] = int(w.get(n["owner"], 0)) + 1
			var px := Color(col.r, col.g, col.b, fill)
			if _state.get_pixel(int(slots[k]), 0) != px:
				_state.set_pixel(int(slots[k]), 0, px)
				changed = true
	if changed or _dirty:
		_tex.update(_state)
		_dirty = false
	_pits_step(weights)


func _pits_step(weights: Array) -> void:
	## R7: gray -> the tube-weighted mix of the players' goo colours, by T / (T + L / 20)
	var queued: Array = []
	for k in range(pit_cols.size()):
		queued.append(0)
	if wl.locals != null:
		for fk in wl.locals.feeds:
			var f: Dictionary = wl.locals.feeds[fk]
			queued[int(f["crater"])] += (f["line"] as Array).size()
	for k in range(pit_cols.size()):
		var w: Dictionary = weights[k]
		var t := 0
		var mix := Color(0, 0, 0)
		for s in w:
			t += int(w[s])
			var sc := WorldLayer._col(s)
			mix += Color(sc.r, sc.g, sc.b) * float(w[s])
		var target := WorldLayer.NATIVE_GRAY
		if t > 0:
			mix /= float(t)
			var strength := float(t) / (float(t) + float(queued[k]) / PIT_L_DIV)
			target = WorldLayer.NATIVE_GRAY.lerp(Color(mix.r, mix.g, mix.b, 1.0), strength)
		pit_cols[k] = (pit_cols[k] as Color).lerp(target, 0.05)
		if wl.locals != null:
			wl.locals.tint_pit(k, pit_cols[k])


func near(q: Vector2, r: float) -> bool:
	## WorldDressing: is q within r of a transport tube's floor run (props, lane pipes and rails keep off the tubes)
	for run in _laid:
		var pts: PackedVector3Array = run
		for k in range(1, pts.size()):
			var a := Vector2(pts[k - 1].x, pts[k - 1].z)
			var b := Vector2(pts[k].x, pts[k].z)
			if absf(q.x - a.x) > r + 3.0 and absf(q.x - b.x) > r + 3.0:
				continue
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)) < r + PIPE_R:
				return true
	return false


func pit_of(tb: Dictionary) -> Vector3:
	## the nearest pit's centre on the floor (no pits: 10 m in front of the base)
	var foot := Vector3(tb["x"], wl.floor_y, tb["z"])
	var best := foot + Vector3(0, 0, 10.0)
	var bd := INF
	if wl.locals != null:
		for c in wl.locals.craters:
			var d: float = Vector2((c as Vector3).x - foot.x, (c as Vector3).z - foot.z).length()
			if d < bd:
				bd = d
				best = c
	return Vector3(best.x, wl.floor_y, best.z)


func pit_strength(k: int) -> Dictionary:
	## probes: the pit's tube weights now
	var out := {}
	for i in cols:
		var c: Dictionary = cols[i]
		if int(c["pit"]) == k:
			var o := str(wl.sim.nodes[wl._tubes[i]["id"]]["owner"])
			out[o] = int(out.get(o, 0)) + int(c["n"])
	return out


# ------------------------------------------------------------------ the column base mesh
static func column_base_mesh() -> ArrayMesh:
	if _base_mesh != null:
		return _base_mesh
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var cs := PackedColorArray()
	var rc := APOTHEM / cos(PI / 8.0)                 # the octagon's corner radius
	var ro := ROOF_R / cos(PI / 8.0)
	for f in range(8):                                # faces: f even = a door (0 +Z, 2 +X, 4 -Z, 6 -X), odd = a socket
		var a0 := PI / 4.0 * f - PI / 8.0
		var a1 := a0 + PI / 4.0
		var d0 := Vector3(sin(a0), 0, cos(a0))
		var d1 := Vector3(sin(a1), 0, cos(a1))
		var out := Vector3(sin(PI / 4.0 * f), 0, cos(PI / 4.0 * f))
		for row in [[0.0, 0.07, STEEL_D], [0.07, 0.15, _key(0.75)], [0.15, WALL_H, STEEL]]:
			_quad(vs, ns, cs, d0 * rc + Vector3.UP * float(row[0]), d1 * rc + Vector3.UP * float(row[0]),
					d1 * rc + Vector3.UP * float(row[1]), d0 * rc + Vector3.UP * float(row[1]), row[2], out)
		_quad(vs, ns, cs, d0 * rc + Vector3.UP * WALL_H, d1 * rc + Vector3.UP * WALL_H, d1 * ro + Vector3.UP * ROOF_H,
				d0 * ro + Vector3.UP * ROOF_H, STEEL_L if f % 2 == 0 else STEEL, out + Vector3.UP * 1.5)
		_quad(vs, ns, cs, d0 * ro + Vector3.UP * ROOF_H, d1 * ro + Vector3.UP * ROOF_H, d1 * 0.97 + Vector3.UP * ROOF_H,
				d0 * 0.97 + Vector3.UP * ROOF_H, _key(0.9), Vector3.UP)
		var side := Vector3(out.z, 0, -out.x)         # along the face (right when looking at it)
		var c := out * APOTHEM
		if f % 2 == 0:
			_door(vs, ns, cs, c, out, side)
		else:
			_socket(vs, ns, cs, c + Vector3.UP * SOCK_Y, out, side)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vs
	arrays[Mesh.ARRAY_NORMAL] = ns
	arrays[Mesh.ARRAY_COLOR] = cs
	_base_mesh = ArrayMesh.new()
	_base_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _base_mesh


static func _key(k: float) -> Color:
	return Color(k, 0.0, k)                           # the entrance shader's OWNER LIGHT key


static func _tri(vs: PackedVector3Array, ns: PackedVector3Array, cs: PackedColorArray, a: Vector3, b: Vector3, c: Vector3,
		col: Color, out: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.dot(out) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	vs.append_array([a, b, c])
	ns.append_array([n, n, n])
	cs.append_array([col, col, col])


static func _quad(vs: PackedVector3Array, ns: PackedVector3Array, cs: PackedColorArray, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, col: Color, out: Vector3) -> void:
	_tri(vs, ns, cs, a, b, c, col, out)
	_tri(vs, ns, cs, a, c, d, col, out)


static func _arch(w: float) -> Array:
	## the door outline (face coords: x along, y up), bottom-left round the arch to bottom-right
	var pts := [Vector2(-w, 0.0), Vector2(-w, DOOR_RECT)]
	for k in range(1, 5):
		var a := PI - PI * k / 5.0
		pts.append(Vector2(cos(a) * w, DOOR_RECT + sin(a) * w))
	pts.append(Vector2(w, DOOR_RECT))
	pts.append(Vector2(w, 0.0))
	return pts


static func _door(vs: PackedVector3Array, ns: PackedVector3Array, cs: PackedColorArray, c: Vector3, out: Vector3, side: Vector3) -> void:
	var inner := _arch(DOOR_HW)
	var outer := _arch(DOOR_HW + FRAME)
	var P := func(q: Vector2, d: float) -> Vector3: return c + side * q.x + Vector3.UP * q.y + out * d
	# the dark mouth
	var mid := Vector2(0.0, DOOR_RECT * 0.7)
	for k in range(inner.size()):
		var q0: Vector2 = inner[k]
		var q1: Vector2 = inner[(k + 1) % inner.size()]
		_tri(vs, ns, cs, P.call(mid, 0.012), P.call(q0, 0.012), P.call(q1, 0.012), RECESS, out)
	# the frame: front, inner reveal, outer side
	for k in range(inner.size() - 1):
		var i0: Vector2 = inner[k]
		var i1: Vector2 = inner[k + 1]
		var o0: Vector2 = outer[k]
		var o1: Vector2 = outer[k + 1]
		_quad(vs, ns, cs, P.call(i0, FRAME_D), P.call(i1, FRAME_D), P.call(o1, FRAME_D), P.call(o0, FRAME_D), STEEL_L, out)
		var mi := (i0 + i1) / 2.0
		var mo := (o0 + o1) / 2.0
		var ti := Vector2(0.0, minf(mi.y, DOOR_RECT)) - mi    # the reveal faces the opening's centre line
		var to := mo - Vector2(0.0, minf(mo.y, DOOR_RECT))    # the frame's outer side faces away from it
		_quad(vs, ns, cs, P.call(i0, 0.0), P.call(i1, 0.0), P.call(i1, FRAME_D), P.call(i0, FRAME_D), STEEL_D,
				side * ti.x + Vector3.UP * ti.y)
		_quad(vs, ns, cs, P.call(o0, 0.0), P.call(o1, 0.0), P.call(o1, FRAME_D), P.call(o0, FRAME_D), STEEL,
				side * to.x + Vector3.UP * to.y)
	# the double laser: two strands across the mouth
	for ly in LASER_Y:
		var h := 0.022
		var a := c + side * -DOOR_HW + Vector3.UP * float(ly) + out * 0.05
		var b := c + side * DOOR_HW + Vector3.UP * float(ly) + out * 0.05
		for fdir in [[Vector3.UP, out], [out, -Vector3.UP], [-Vector3.UP, -out], [-out, Vector3.UP]]:
			var u: Vector3 = fdir[0]
			var v: Vector3 = fdir[1]
			_quad(vs, ns, cs, a + (u + v) * h, b + (u + v) * h, b + (u - v) * h, a + (u - v) * h, _key(1.0), u)


static func _socket(vs: PackedVector3Array, ns: PackedVector3Array, cs: PackedColorArray, c: Vector3, out: Vector3, side: Vector3) -> void:
	var n := 10
	var ring := func(r: float, d: float, k: int) -> Vector3:
		var a := TAU * k / n
		return c + (side * cos(a) + Vector3.UP * sin(a)) * r + out * d
	for k in range(n):
		var a := TAU * (k + 0.5) / n
		var rad := side * cos(a) + Vector3.UP * sin(a)
		_quad(vs, ns, cs, ring.call(SOCK_R, 0.0, k), ring.call(SOCK_R, 0.0, k + 1), ring.call(SOCK_R, SOCK_D, k + 1),
				ring.call(SOCK_R, SOCK_D, k), STEEL, rad)
		_quad(vs, ns, cs, ring.call(SOCK_RI, 0.0, k), ring.call(SOCK_RI, 0.0, k + 1), ring.call(SOCK_RI, SOCK_D, k + 1),
				ring.call(SOCK_RI, SOCK_D, k), STEEL_D, -rad)
		_quad(vs, ns, cs, ring.call(SOCK_RI, SOCK_D, k), ring.call(SOCK_RI, SOCK_D, k + 1), ring.call(SOCK_R, SOCK_D, k + 1),
				ring.call(SOCK_R, SOCK_D, k), STEEL_L, out)
		_tri(vs, ns, cs, c + out * 0.012, ring.call(SOCK_RI, 0.012, k), ring.call(SOCK_RI, 0.012, k + 1), RECESS, out)
