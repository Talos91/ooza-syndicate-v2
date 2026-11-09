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
##  - v2 (Daniele 2026-11-09, 3 corrections; WorldLocals mirrors the 4 pits on both axes): each pit has ONE COLLECTOR (a header
##    bar outside its rim facing the board + a riser over the rim into the goo); a column's tubes run as one RIBBON (offsets
##    HDR_PITCH from a filleted centre line), the ribbons are uncrossed as blocks and plug into the header side by side after a
##    straight parallel approach. Runs sit level at RACK_Y on steel stands (the Locals walk under; no humps), bridging only
##    over another tube. A tube a vat upgrade adds BUILDS as the vat's blueprint hologram (world_pipe_holo.gdshader, next
##    pass): the ghost first, the real tube revealed from the column end with Sim.build_progress, then the goo fills.
##  - PIT COLOUR (R7): per pit, gray blended toward the tube-weighted mix of the players' colours by T / (T + L / 20).
## Budget: ONE draw for every tube of the map (one ArrayMesh, all potential slots: 4 per column; a slot's state lives in
## a 1-row float texture: rgb colour, a = fill 0..1 from the pit end, < 0 hidden -> the vertex shader collapses it).

const SHADER_PIPE := preload("res://shaders/world_pipe.gdshader")
const SHADER_HOLO := preload("res://shaders/world_pipe_holo.gdshader")   # v2: the build hologram (next pass)
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
const RACK_Y := 1.08             # m: v2 - the tube's centre on its LEVEL run (= LANE_CLEAR: the Locals walk under it, no humps)
const POST_STEP := 3.0           # m between the steel stands under a level run
const POST_HW := 0.07            # a stand's half width
const SPAN_MAX := 12.0           # m: the longest unsupported level stretch (probe; stands every POST_STEP where the floor is free)
const HDR_R := 7.0               # m: v2 - the collector header's axis from its pit's centre (outside the Locals' rim exits at 5.4)
const HDR_APPR := 5.0            # m: each tube's last straight run, parallel to its neighbours, into the header
const HDR_PITCH := 0.90          # m between two tubes' plugs on the header (2 PIPE_R + 36 cm: a stand fits between)
const HDR_END := 0.95            # m: the header runs on past its outer plugs (its end stands stand there)
const RISER_SEP := 0.34         # rad: the riser keeps this far round the pool from a Locals' exit (its mouth at GOO_R)
const RIB_BEND := 3.0            # m: the ribbon centre's bend radius (4 tubes span 1.35 m either side of it)
const RIB_HALF := 1.5            # m: half a 4-tube ribbon's width + a tube: the extra room _steer keeps round obstacles
const RIB_STAGGER := 0.0         # m deeper per m nearer the bundle middle (tried 1.2: the bends crossed farther out; off)
const RIB_START := 3.2           # m: a column's ribbon centre starts this far in front of its base, toward its pit
const HDR_RR := 0.36             # m: the header's / riser's radius

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
var headers: Array = []          # v2: per pit {c, dir (pit -> board), lat, half} ({} = no tubes)
var _centres := {}               # [col, centre offset] -> its ribbon centre line
var hdr_slots: Array = []        # v2: per pit [header slot, riser slot]
var posts: Array = []            # v2: [slot, foot (world), top y] - the stands under the level runs (probes)
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
	# v2 (Daniele 2026-11-09: "each pit should have its tube link to the vertical tube in an orderly fashion, right now feels
	# incredibly messy"): every column takes its nearest pit; each pit gets ONE COLLECTOR - a steel header bar across the
	# board-facing side just outside its rim (HDR_R m from the centre, at the rack height) with one RISER that carries the
	# goo over the rim into the pool. Every tube of that pit runs the last HDR_APPR m PARALLEL to its neighbours and plugs
	# into the header at its own slot, HDR_PITCH apart, in the order of its socket's place across the header - so the
	# tubes fan in as one ordered bundle with one clean entry each, and none crosses another near the pit.
	var fan: Array = []                               # per pit: [col index, socket, side point]
	for k in range(craters.size()):
		fan.append([])
	var socks_of := {}
	for i in cols:
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
		socks_of[i] = order
		for s in order.slice(0, most):
			fan[pi].append([i, s, _side_point(foot, to, s)])
	var arrive := {}                                  # [col, socket] -> [pit, offset across the header]
	headers.clear()
	_centres.clear()
	for k in range(craters.size()):
		var tubes: Array = fan[k]
		var c2 := Vector2(craters[k].x, craters[k].z)
		if tubes.is_empty():
			headers.append({})
			continue
		var m := Vector2.ZERO
		for t in tubes:
			m += ((t[2] as Vector2) - c2).normalized()
		var mean := atan2(m.y, m.x)
		var ang := mean                               # the riser's angle: the mean bearing, nudged off the Locals' exits
		for dd in range(0, 160):
			var cand := mean + float(dd / 2) * 0.02 * (1.0 if dd % 2 == 0 else -1.0)
			var ok := true
			for f in fixed[k]:
				if absf(angle_difference(cand, float(f))) < RISER_SEP:
					ok = false
			if ok:
				ang = cand
				break
		var dir := Vector2(cos(ang), sin(ang))
		var lat := Vector2(-dir.y, dir.x)
		var mouth := c2 + dir * (HDR_R + HDR_APPR)    # the bundle's mouth: its tubes ordered by their bearing from here
		var key := func(t: Array) -> float:
			var v: Vector2 = (t[2] as Vector2) - mouth
			return angle_difference(ang, atan2(v.y, v.x))
		tubes.sort_custom(func(x, y): return key.call(x) < key.call(y))
		# whole columns keep their tubes side by side: groups in bearing order, then uncrossed (2-opt) as blocks
		var groups: Array = []                        # [col index, [its tubes]]
		for t in tubes:
			if groups.is_empty() or int(groups[-1][0]) != int(t[0]):
				var found := -1
				for g in range(groups.size()):
					if int(groups[g][0]) == int(t[0]):
						found = g
				if found < 0:
					groups.append([int(t[0]), [t]])
				else:
					groups[found][1].append(t)
			else:
				groups[-1][1].append(t)
		var n := tubes.size()
		var pre := func(o: float) -> Vector2:
			return c2 + dir * (HDR_R + HDR_APPR + 3.0) + lat * o
		var centres := func(gs: Array) -> Array:
			var out := []
			var j := 0
			for g in gs:
				var m2: int = (g[1] as Array).size()
				out.append((j + (m2 - 1) * 0.5 - (n - 1) * 0.5) * HDR_PITCH)
				j += m2
			return out
		for _it in range(200):
			var cs: Array = centres.call(groups)
			var swapped := false
			for ga in range(groups.size()):
				for gb in range(ga + 1, groups.size()):
					var fa: Vector2 = _col_start(int(groups[ga][0]), pre.call(cs[ga]))
					var fb: Vector2 = _col_start(int(groups[gb][0]), pre.call(cs[gb]))
					if Geometry2D.segment_intersects_segment(fa, pre.call(cs[ga]), fb, pre.call(cs[gb])) != null:
						var t = groups[ga]
						groups[ga] = groups[gb]
						groups[gb] = t
						swapped = true
						cs = centres.call(groups)
			if not swapped:
				break
		var cs2: Array = centres.call(groups)
		var htmp := {"c": c2, "dir": dir, "lat": lat, "w": (n - 1) * 0.5 * HDR_PITCH}
		for g in range(groups.size()):
			var sibs: Array = groups[g][1]
			var m2 := sibs.size()
			# siblings across their OWN ribbon: by their socket's side of the ribbon's first stretch (right side = + offset)
			var cl: Array = _centre(int(groups[g][0]), htmp, float(cs2[g]))
			var t0: Vector2 = ((cl[mini(3, cl.size() - 1)] as Vector2) - (cl[0] as Vector2)).normalized()
			var n0 := Vector2(t0.y, -t0.x)
			var fo := Vector2(wl._tubes[int(groups[g][0])]["x"], wl._tubes[int(groups[g][0])]["z"])
			sibs.sort_custom(func(x, y): return ((x[2] as Vector2) - fo).dot(n0) < ((y[2] as Vector2) - fo).dot(n0))
			for q in range(m2):
				var off: float = float(cs2[g]) + (q - (m2 - 1) * 0.5) * HDR_PITCH
				arrive[[int(sibs[q][0]), int(sibs[q][1])]] = [k, off, float(cs2[g])]
		headers.append({"c": c2, "dir": dir, "lat": lat, "w": (tubes.size() - 1) * 0.5 * HDR_PITCH, "half": (n - 1) * 0.5 * HDR_PITCH + HDR_END})
	var runs: Array = []                              # [col index, socket k, pit, arrival angle, world points]
	_laid.clear()                                     # the floor runs laid so far (later tubes bridge over them)
	var near_first: Array = cols.keys()               # the columns nearest their pit lay their tubes first (inside)
	var pd := func(i: int) -> float:
		var c: Vector3 = craters[int(cols[i]["pit"])]
		return Vector2(wl._tubes[i]["x"], wl._tubes[i]["z"]).distance_to(Vector2(c.x, c.z))
	near_first.sort_custom(func(x, y): return pd.call(x) < pd.call(y))
	for i in near_first:
		var pi := int(cols[i]["pit"])
		var order: Array = socks_of[i]
		for s in order:
			if not arrive.has([i, s]):
				continue
			var off: float = arrive[[i, s]][1]
			var pts := _path(i, s, headers[pi], off, float(arrive[[i, s]][2]))
			_laid.append(pts)
			runs.append([i, s, pi, off, pts])
			cols[i]["slots"].append(runs.size() - 1)
	hdr_slots.clear()
	for k in range(headers.size()):                   # the collectors: header bar + riser, two more slots per pit
		var h: Dictionary = headers[k]
		if h.is_empty():
			hdr_slots.append([])
			continue
		var y := wl.floor_y + RACK_Y
		var hc: Vector2 = h["c"] + h["dir"] * HDR_R
		var e0: Vector2 = hc - h["lat"] * float(h["half"])
		var e1: Vector2 = hc + h["lat"] * float(h["half"])
		var bar := PackedVector3Array([Vector3(e0.x, y, e0.y), Vector3(hc.x, y, hc.y), Vector3(e1.x, y, e1.y)])
		runs.append([-1, -1, k, 0.0, bar])
		runs.append([-1, -2, k, 0.0, _riser(h)])
		hdr_slots.append([runs.size() - 2, runs.size() - 1])
	_slots = runs.size()
	run_pts = runs.map(func(rn): return [rn[0], rn[1], rn[2], rn[4]])
	_place_posts(runs, craters)
	_build_mesh(runs, craters)
	_state = Image.create(maxi(_slots, 1), 2, false, Image.FORMAT_RGBAF)   # row 0 colour + fill, row 1 build progress
	for k in range(maxi(_slots, 1)):
		_state.set_pixel(k, 1, Color(-1, 0, 0, 0))   # not building
	_tex = ImageTexture.create_from_image(_state)
	_mat.set_shader_parameter("state", _tex)
	var holo := ShaderMaterial.new()
	holo.shader = SHADER_HOLO
	holo.set_shader_parameter("state", _tex)
	holo.set_shader_parameter("slots", float(maxi(_slots, 1)))
	_mat.next_pass = holo
	built = true
	_dirty = true


func _side_point(foot: Vector2, to: Vector2, s: int) -> Vector2:
	## where a socket's tube heads first: straight out of a front socket, round the base's side for a back one
	var cd := corner_dir(s)
	if cd.dot(to) < 0.0:
		var lat := (cd - to * cd.dot(to)).normalized()
		return foot + lat * 3.4 + to * 0.6
	return foot + cd * (APOTHEM + SOCK_D + 1.2)


func _col_start(i: int, c2: Vector2) -> Vector2:
	## where a column's tube ribbon leaves its base: RIB_START m in front of it, toward where it heads (its approach)
	var foot := Vector2(wl._tubes[i]["x"], wl._tubes[i]["z"])
	var to := (c2 - foot).normalized() if c2.distance_to(foot) > 0.01 else Vector2(0, 1)
	return foot + to * RIB_START


func _centre(i: int, h: Dictionary, coff: float) -> Array:
	## the column's ribbon centre line (1 m samples): from in front of its base round other bases / pits to the start of
	## its approach; every tube of the column runs parallel to it at its own offset (cached per column)
	var key := [i, coff]
	if _centres.has(key):
		return _centres[key]
	var tb: Dictionary = wl._tubes[i]
	var c2: Vector2 = h["c"]
	var e: Vector2 = c2 + (h["dir"] as Vector2) * (HDR_R + HDR_APPR + 3.0) + (h["lat"] as Vector2) * coff
	# its last stretch runs straight toward the header (offsets = across it); inner ribbons turn onto it farther out, so the
	# bends nest (the reference sheet's network overview) instead of overlapping
	var e2: Vector2 = e + (h["dir"] as Vector2) * (6.0 + RIB_STAGGER * (float(h.get("w", 0.0)) - absf(coff)))
	var a := _col_start(i, e2)
	var way: Array = _fillet([a] + _steer(a, e2, i, int(tb["id"]), Vector3(c2.x, 0, c2.y), 0) + [e2, e], RIB_BEND)
	var out: Array = []
	for k in range(way.size() - 1):
		var p: Vector2 = way[k]
		var q: Vector2 = way[k + 1]
		var m := maxi(int(p.distance_to(q)), 1)
		for j in range(m):
			out.append(p.lerp(q, float(j) / m))
	out.append(e)
	_centres[key] = out
	return out


static func _fillet(way: Array, rb: float) -> Array:
	## every corner of the polyline replaced by a circular arc of radius rb (less where the legs are short), so a ribbon's
	## inner tube never pinches against its sibling at a bend (its offset stays well under the bend's radius)
	if way.size() < 3:
		return way
	var out: Array = [way[0]]
	for k in range(1, way.size() - 1):
		var p0: Vector2 = out[out.size() - 1]
		var p: Vector2 = way[k]
		var p1: Vector2 = way[k + 1]
		var u := (p - p0)
		var v := (p1 - p)
		if u.length() < 0.01 or v.length() < 0.01:
			continue
		var phi := angle_difference(atan2(u.y, u.x), atan2(v.y, v.x))
		if absf(phi) < 0.05:
			out.append(p)
			continue
		var th := tan(minf(absf(phi), 2.6) * 0.5)
		var t := minf(rb * th, minf(u.length() * 0.48, v.length() * 0.48))
		var r := t / th
		var un := u.normalized()
		var vn := v.normalized()
		var st := p - un * t
		var nl := Vector2(-un.y, un.x) * signf(phi)    # toward the centre (left for a left turn)
		var cc := st + nl * r
		var a0 := atan2(st.y - cc.y, st.x - cc.x)
		var steps := maxi(int(ceil(absf(phi) / 0.2)), 2)
		for j in range(steps + 1):
			var a := a0 + phi * float(j) / steps
			out.append(cc + Vector2(cos(a), sin(a)) * r)
		out[out.size() - 1] = p + vn * t
	out.append(way[way.size() - 1])
	return out


func _path(i: int, s: int, h: Dictionary, off: float, coff: float) -> PackedVector3Array:
	## socket -> up to the rack height -> its column's ribbon (parallel to its siblings, `off - coff` from the centre line)
	## -> its approach lane (parallel to every tube of the pit, `off` across the header) -> into the pit's header
	var tb: Dictionary = wl._tubes[i]
	var foot := Vector2(tb["x"], tb["z"])
	var cd := corner_dir(s)
	var c2: Vector2 = h["c"]
	var dir: Vector2 = h["dir"]
	var lat: Vector2 = h["lat"]
	var p0 := foot + cd * (APOTHEM + 0.05)
	var p1 := foot + cd * (APOTHEM + SOCK_D + 1.2)    # straight out of its socket first
	var hj := c2 + dir * HDR_R + lat * off            # its plug on the header
	var aj := hj + dir * HDR_APPR                     # the start of its parallel approach
	var way := [p0, p1]
	var to := (c2 - foot).normalized()
	if cd.dot(to) < 0.0:                              # a back socket: round the base's side, outside the front tubes
		var side := (cd - to * cd.dot(to)).normalized()
		way.append(foot + side * 3.4 + to * 0.6)
	var cl: Array = _centre(i, h, coff)
	var d := off - coff
	for k in range(2, cl.size() - 2):                 # the ribbon: the centre line shifted by d (left of travel = +lat side)
		var t: Vector2 = (cl[k + 1] as Vector2) - (cl[k - 1] as Vector2)
		t = t.normalized() if t.length() > 0.001 else -dir
		var nrm := Vector2(t.y, -t.x)                 # (travel toward the pit: -dir; its right-hand normal is +lat)
		way.append((cl[k] as Vector2) + nrm * d)
	way.append(aj + dir * 3.0)                        # onto its approach line, so the approach itself is dead straight
	way.append(aj + dir * 1.5)
	way.append(aj)
	way.append(aj.lerp(hj, 0.34))
	way.append(aj.lerp(hj, 0.67))
	way.append(hj)
	return _shape(way, c2, dir, false)


func _riser(h: Dictionary) -> PackedVector3Array:
	## the collector's riser: from the header's middle up over the rim and down into the goo (the pit end last)
	var c2: Vector2 = h["c"]
	var hd: Vector2 = h["dir"]
	var fy := wl.floor_y
	var top := WorldLocals.RIM_H + HDR_RR + 0.18
	var pts := PackedVector3Array()
	for k in range(0, 5):
		var t := float(k) / 4.0
		var q := c2 + hd * lerpf(HDR_R, WorldLocals.RING_R + 0.9, t)
		pts.append(Vector3(q.x, fy + lerpf(RACK_Y, top, smoothstep(0.0, 1.0, t)), q.y))
	for k in range(1, 7):
		var t := float(k) / 6.0
		var r := lerpf(WorldLocals.RING_R + 0.9, GOO_R, t)
		var y := top + 0.12 * sin(t * PI) if r > WorldLocals.POOL_R else lerpf(top, WorldLocals.POOL_H - 0.25, smoothstep(WorldLocals.POOL_R, GOO_R, r))
		var q := c2 + hd * r
		pts.append(Vector3(q.x, fy + y, q.y))
	return pts


func _shape(way: Array, c2: Vector2, dir: Vector2, tail := true) -> PackedVector3Array:
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
		var y := lerpf(SOCK_Y, RACK_Y, smoothstep(0.0, LIFT_RAMP + 0.4, cum))   # v2: up to the rack height out of the socket
		if tail:
			y = lerpf(y, top, smoothstep(tot - 3.2, tot, cum))    # climbs to clear the rim
		base_y.append(y)
		var lf := _lift(flat[k], haz)                 # over a Locals' lane / an earlier tube: a pipe bridge
		lifts.append(lf)                              # (a lane near the socket ramp lifts it to the rack early)
	for k in range(flat.size()):                      # bridges less than 6 m apart join into one (no zigzag)
		var lm := 0.0
		var rm := 0.0
		for j in range(maxi(k - 12, 0), k + 1):
			lm = maxf(lm, lifts[j])
		for j in range(k, mini(k + 13, flat.size())):
			rm = maxf(rm, lifts[j])
		var join := minf(lm, rm)
		if join < RACK_Y + 0.05:
			join = 0.0
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
	if not tail:
		return pts
	# over the rim (r RING_R + 0.9 -> 3.0) and down into the pool
	for k in range(1, 7):
		var t := float(k) / 6.0
		var r := lerpf(WorldLocals.RING_R + 0.9, GOO_R, t)
		var y := top + 0.12 * sin(t * PI) if r > WorldLocals.POOL_R else lerpf(top, WorldLocals.POOL_H - 0.25, smoothstep(WorldLocals.POOL_R, GOO_R, r))
		var q := c2 + dir * r
		pts.append(Vector3(q.x, fy + y, q.y))
	return pts


func _place_posts(runs: Array, craters: Array) -> void:
	## v2: a steel stand every POST_STEP m under each level run - never on a Locals' lane, under another tube, on a column
	## base or inside a pit's ring (shifted along the run up to 1.4 m to find clear floor)
	posts.clear()
	var lanes: Array = []
	if wl.locals != null:
		for fk in wl.locals.feeds:
			var f: Dictionary = wl.locals.feeds[fk]
			var c: Vector3 = craters[int(f["crater"])]
			lanes.append([Vector2(c.x, c.z)] + (f["path"] as Array))
	var flat: Array = []
	for rn in runs:
		var o := []
		for q in (rn[4] as PackedVector3Array):
			o.append(Vector2(q.x, q.z))
		flat.append(o)
	for r in range(runs.size()):
		var pts: PackedVector3Array = runs[r][4]
		if int(runs[r][1]) == -1:                     # a header bar: a stand under each end
			for e in [0, pts.size() - 1]:
				var q: Vector3 = pts[e].lerp(pts[1], 0.3 / maxf(pts[e].distance_to(pts[1]), 0.01))
				if _post_clear(Vector2(q.x, q.z), r, lanes, flat, craters):
					posts.append([r, Vector3(q.x, wl.floor_y, q.z), q.y - HDR_RR + 0.06])
			continue
		if int(runs[r][0]) < 0:
			continue                                  # the riser rests on the rim and the pool
		var cum := PackedFloat32Array([0.0])
		for k in range(1, pts.size()):
			cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
		var tot := cum[cum.size() - 1]
		var at := LIFT_RAMP + 0.6
		while at < tot - 0.9:                         # (the header holds the end)
			var placed := false
			for dd in [0.0, 0.35, -0.35, 0.7, -0.7, 1.05, -1.05, 1.4, -1.4, 1.75, -1.75, 2.1, -2.1, 2.45, -2.45, 2.8, -2.8]:
				var q := _at(pts, cum, at + dd)
				if q.y - wl.floor_y - PIPE_R < 0.3:
					break                                 # resting low here (the socket ramp): no stand needed
				if _post_clear(Vector2(q.x, q.z), r, lanes, flat, craters):
					posts.append([r, Vector3(q.x, wl.floor_y, q.z), q.y - PIPE_R + 0.06])
					placed = true
					at += dd
					break
			at += POST_STEP if placed else 0.7


static func _at(pts: PackedVector3Array, cum: PackedFloat32Array, d: float) -> Vector3:
	for k in range(1, pts.size()):
		if cum[k] >= d:
			return pts[k - 1].lerp(pts[k], clampf((d - cum[k - 1]) / maxf(cum[k] - cum[k - 1], 0.001), 0.0, 1.0))
	return pts[pts.size() - 1]


func _post_clear(q: Vector2, r: int, lanes: Array, flat: Array, craters: Array) -> bool:
	for pl in lanes:
		for j in range(1, (pl as Array).size()):
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, pl[j - 1], pl[j])) < 0.39 + POST_HW + 0.03:
				return false
	for o in range(flat.size()):
		if o == r:
			continue
		var f: Array = flat[o]
		for j in range(1, f.size()):
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, f[j - 1], f[j])) < PIPE_R + POST_HW + 0.03:
				return false
	for t2 in wl._tubes:
		if q.distance_to(Vector2(t2["x"], t2["z"])) < (2.0 if t2.get("ent", false) else float(t2["r"]) + 0.2):
			return false
	for c in craters:
		if q.distance_to(Vector2((c as Vector3).x, (c as Vector3).z)) < WorldLocals.RING_R + 0.3:
			return false
	return true


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
			if _meets(flat, a, b, 2.0 * PIPE_R + 0.3, bb):   # (0.5 m samples: a near miss between two still lifts)
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
		obs.append([Vector2(t2["x"], t2["z"]), (2.6 if t2.get("ent", false) else float(t2["r"]) + 1.0) + RIB_HALF])
	for c in wl.locals.craters:                       # its own pit too (and room for a whole ribbon past each)
		obs.append([Vector2((c as Vector3).x, (c as Vector3).z), WorldLocals.RING_R + 1.5 + RIB_HALF])
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
		var rad := HDR_RR if int(run[0]) < 0 else PIPE_R  # v2: the collector's header / riser are a size up
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
				vs.append(pts[k] + nrm * rad)
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
		if int(run[1]) == -1:                         # the header bar: closed ends (steel caps)
			for e in [0, pts.size() - 1]:
				var out: Vector3 = (pts[int(e)] - pts[1]).normalized()
				var cb := vs.size()
				vs.append(pts[e])
				ns.append(out)
				uv.append(Vector2(-1.0, 0.0))
				uv2.append(Vector2(float(r) + 0.5, 0.5))
				var ring0: int = base + int(e) * (sides + 1)
				for j in range(sides + 1):
					vs.append(vs[ring0 + j])
					ns.append(out)
					uv.append(Vector2(-1.0, 0.0))
					uv2.append(Vector2(float(r) + 0.5, 0.5))
				for j in range(sides):
					_tri_out(vs, idx, cb, cb + 1 + j, cb + 2 + j, out)
	for pp in posts:                                  # v2: the stands (UV.x < 0 = steel; UV2 = the slot, its share of the run)
		var r: int = pp[0]
		var foot: Vector3 = pp[1]
		var top: float = pp[2]
		var pr: PackedVector3Array = runs[r][4]
		var share := 0.5
		var best := INF
		var tot := 0.0
		var acc := PackedFloat32Array([0.0])
		for k in range(1, pr.size()):
			tot += pr[k].distance_to(pr[k - 1])
			acc.append(tot)
		for k in range(pr.size()):
			var d := Vector2(pr[k].x - foot.x, pr[k].z - foot.z).length()
			if d < best:
				best = d
				share = acc[k] / maxf(tot, 0.01)
		for box in [[POST_HW, foot.y, top], [0.2, foot.y, foot.y + 0.04]]:
			var hw: float = box[0]
			var y0: float = box[1]
			var y1: float = box[2]
			var c := [Vector3(-hw, 0, -hw), Vector3(hw, 0, -hw), Vector3(hw, 0, hw), Vector3(-hw, 0, hw)]
			for f in range(5):                        # 4 sides + top
				var q: Array
				var nrm: Vector3
				if f < 4:
					var a: Vector3 = c[f]
					var b: Vector3 = c[(f + 1) % 4]
					q = [foot + a + Vector3(0, y0 - foot.y, 0), foot + b + Vector3(0, y0 - foot.y, 0), foot + b + Vector3(0, y1 - foot.y, 0), foot + a + Vector3(0, y1 - foot.y, 0)]
					nrm = ((a + b) * 0.5).normalized()
				else:
					q = [foot + c[0] + Vector3(0, y1 - foot.y, 0), foot + c[1] + Vector3(0, y1 - foot.y, 0), foot + c[2] + Vector3(0, y1 - foot.y, 0), foot + c[3] + Vector3(0, y1 - foot.y, 0)]
					nrm = Vector3.UP
				var b0 := vs.size()
				for v in q:
					vs.append(v)
					ns.append(nrm)
					uv.append(Vector2(-1.0, 0.0))
					uv2.append(Vector2(float(r) + 0.5, share))
				_tri_out(vs, idx, b0, b0 + 1, b0 + 2, nrm)
				_tri_out(vs, idx, b0, b0 + 2, b0 + 3, nrm)
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
		var bp := -1.0
		if VatColumn.upgrading(n):                    # the tubes the upgrade adds: built as a hologram, empty until the tier completes
			var to := int((n["build_target"] as Dictionary).get("tier", int(n["tier"]) + 1))
			want_n = maxi(full_n, tubes_for(n, int(c["start"]), bool(c["home"]), to))
			bp = Sim.build_progress(n)
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
			var b := Color(bp if live and k >= full_n and k < want_n else -1.0, 0, 0, 0)   # v2: building -> hologram
			if _state.get_pixel(int(slots[k]), 1) != b:
				_state.set_pixel(int(slots[k]), 1, b)
				changed = true
	for k in range(hdr_slots.size()):                 # v2: a collector shows once its pit has a tube; it builds with the first
		var hs: Array = hdr_slots[k]
		if hs.is_empty():
			continue
		var shown := false
		var full := false
		var bmax := -1.0
		for i in cols:
			if int(cols[i]["pit"]) != k:
				continue
			for sl in cols[i]["slots"]:
				var st := _state.get_pixel(int(sl), 0)
				var bb := _state.get_pixel(int(sl), 1).r
				if st.a < 0.0:
					continue
				if bb >= 0.0:
					bmax = maxf(bmax, bb)
				else:
					shown = true
				if st.a >= 1.0:
					full = true
		var pc: Color = pit_cols[k] if k < pit_cols.size() else WorldLayer.NATIVE_GRAY
		var px := Color(pc.r, pc.g, pc.b, (1.0 if full else 0.0) if shown or bmax >= 0.0 else -1.0)
		var bx := Color(-1.0 if shown or bmax < 0.0 else bmax, 0, 0, 0)
		for sl in hs:
			if _state.get_pixel(int(sl), 0) != px or _state.get_pixel(int(sl), 1) != bx:
				_state.set_pixel(int(sl), 0, px)
				_state.set_pixel(int(sl), 1, bx)
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
