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
##  - v3 (Daniele 2026-11-09/10 on the v2 sheet): NO COLLECTOR - a column's k-th tube runs to its k-th nearest pit (one
##    tube per pit per column: the 4 sockets reach the 4 pits), each over the rim into the goo at its own bearing (the pit's
##    tubes keep their columns' circular order, TUBE_SEP apart, LANE_SEP off the Locals' exits). Out of the socket the tube
##    climbs straight at SOCK_ANG (the coupling is tilted up) to the RACK_Y = 2 m level run on steel stands <= SPAN_MAX
##    apart; the Locals pass under, tubes bridge only over another tube. A tube a vat upgrade adds BUILDS as the vat's
##    blueprint hologram (world_pipe_holo.gdshader, next pass), revealed from the column end with Sim.build_progress.
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
const SOCK_Y := 0.62             # socket centre over the floor (v3: raised for the coupling tilted up)
const SOCK_ANG := 0.70           # rad (40 deg): v3 - the socket coupling and the tube leaving it point up toward the rack
#   (Daniele 2026-11-09 pt2-rack: "have their connection to the base be angled towards the top")
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
const TUBES_BY_TIER := {1: 1, 2: 2, 3: 4}   # tubes a column has at each tier (Daniele 2026-11-11; the tubes only grow, R4)
const MAX_TUBES := 4
const PIT_L_DIV := 20.0          # R7: strength = T / (T + L / 20)
const LANE_SEP := 0.22           # rad round a pit kept clear of a Locals' lane exit (1.3 m at the rim, 0.70 m where a tube enters the goo)
const TUBE_SEP := 0.18           # rad between two tubes over the rim (1.06 m; 0.63 m where they dip into the goo at r 3.5)
const LANE_CLEAR := 2.0          # m: a tube's centre over a Locals' lane (v3 = RACK_Y: the Locals pass well under)
const LIFT_RAMP := 1.4           # m: a pipe bridge's ramp each side
const GOO_R := 3.2              # m from the pit's centre: a tube's mouth under the goo (Locals emerge LANE_SEP aside)
const RACK_Y := 2.0              # m: the tube's centre on its LEVEL run (v3, Daniele pt2-rack: "raise even more so the locals
#   can pass perfectly under, to 2 m"; a Local is 0.64 m tall: 1.09 m of air under the glass)
const RAMP_RUN := (RACK_Y - SOCK_Y) / 0.8391   # m of floor the angled climb socket -> rack takes (tan SOCK_ANG)
const PAR_GAP := 0.95            # m: v3 - two tubes running along each other keep their centres this far apart (side by side)
const ENTRY_RUN := 4.0           # m: v3 - each tube's straight radial approach before it climbs over its pit's rim
const POST_STEP := 3.0           # m between the steel stands under a level run
const POST_HW := 0.07            # a stand's half width
const SPAN_MAX := 12.0           # m: the longest unsupported level stretch (probe; stands every POST_STEP where the floor is free)
const RIB_BEND := 3.0            # m: the ribbon centre's bend radius (4 tubes span 1.35 m either side of it)
const RIB_HALF := 0.6            # m: v3 one tube (no ribbons): the extra room _steer keeps round obstacles

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
var posts: Array = []            # v2: [slot, foot (world), top y] - the stands under the level runs (probes)
var run_pts: Array = []          # probes (tests/pits_tubes_clip.gd): per slot [col index, socket, pit, world points]
static var _base_mesh: ArrayMesh
# ORTHO ROUTING (Daniele 2026-11-11, "try tubes aligned, moving only on cardinal axes, minimal corners, as much parallel
# overlap as possible so the background is more orderly"): a switch. Off = the v3 free routing. On = socket stub, then ONE
# corner, every straight leg on a global lane grid (ORTHO_GAP) so neighbours run exactly side by side, and each tube enters its
# pit along an axis. A tube the grid cannot place (an obstacle, a Locals' exit) falls back to the v3 route. Dev: --tubes=ortho.
# CONNECTORS (Daniele 2026-11-11, "build the connector version"): ortho tubes all on ONE level; where an x run crosses a z run
# they meet inside a small steel CONNECTOR block (the tubes enter its left / right faces and its up / down faces through
# doors), so the overlap is hidden in a node, not bridged. Dev: --tubes=connectors. (--tubes=ortho = the two-level version.)
const CONN_PAD := 0.8            # m the connector block extends past the crossing tubes
const CONN_MAX := 7.5             # m: the biggest trunk block
const CONN_MERGE := 3.0           # m: blocks closer than this merge into one trunk block
const CONN_H := 1.5              # m: block height (centred on the tube level)
var connectors := false
const GRID_CROSS := 14.0         # m-equivalent cost of crossing another tube (fewer crossings = fewer connectors)
const GRID_BUNDLE := 0.35        # m-equivalent saving per step that runs right beside another tube (stripes form)
const GRID_MIN_RUN := 5          # cells (3.3 m) a tube runs straight before it may turn again: no zigzags, no tight kinks
const GRID_TURN := 30.0           # m-equivalent cost of a corner in the grid router (fewer corners)
const GRID_CAP := 60000          # expansions per tube before the router gives up (the v3 route is the fallback)
var grid_routed := 0             # probes: tubes the grid router placed
var build_ms := [0.0, 0.0]       # probes: [routing ms, routing + mesh + connectors ms] of the last build()
var _gobs: Array = []            # grid router obstacles [centre, radius]
var _gbox := Rect2i()
var _from_ortho := false
var conn_count := 0
var _conn_nodes: Array = []
var _ortho_runs: Array = []      # indices into _laid of the runs that came from the ortho routes
const ORTHO_GAP := 1.1           # m between two parallel lanes (tube diameter 0.54)
const ORTHO_LEVEL_STEP := 0.9     # m: ortho mode - legs along x run at the rack level, legs along z this much higher, so crossings never touch
const FLOOR_RUN_Y := 0.35          # m: connectors mode - the tubes run ON the floor (the connector blocks hide the crossings, no rack)
const ORTHO_BEND := 2.2          # m: corner radius in ortho mode
const ORTHO_DEFAULT := false
var ortho := ORTHO_DEFAULT
var ortho_stats := [0, 0, 0]     # probes: tubes routed on the grid (1 corner) / fallen back to v3 / of those fallen back, routed with 2 corners
var _lanes := {}                 # "X<idx>" / "Z<idx>" -> [[lo, hi], ...] the stretches already taken
var _fixed: Array = []           # per pit: the bearings of the Locals' exits


static func base45() -> bool:
	## Daniele 2026-11-11: turn every node base 45 degrees - tube sockets on the CARDINALS, walk-in doors on the CORNERS (the
	## base mesh is unchanged: its yaw comes from WorldLocals.door_dirs(), which become the diagonals). Dev: --base45.
	for a in OS.get_cmdline_user_args():
		if a == "--base45" or a == "--tubes=ortho" or a == "--tubes=connectors":
			return true                                   # the ortho routings only make 90-degree turns on cardinal sockets
	return false


static func corner_dir(k: int) -> Vector2:
	## the 4 tube sockets: +X+Z, +X-Z, -X-Z, -X+Z (unit, x z); with --base45 the cardinals +Z, +X, -Z, -X
	var a := (0.0 if base45() else PI / 4.0) + PI / 2.0 * k
	return Vector2(sin(a), cos(a))


static func tubes_for(n: Dictionary, _start_tier: int, _home: bool, tier := -1) -> int:
	## Daniele 2026-11-11: every column plugs into the pits with T1 = 1 tube, T2 = 2, T3 = 4 (was: home 1, +1 at T2, +2 at T3)
	var t := clampi(int(n.get("tier", 1)) if tier < 0 else tier, 1, 3)
	return int(TUBES_BY_TIER[t])


func setup(w: WorldLayer) -> void:
	wl = w
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tubes="):
			ortho = a.substr(8) in ["ortho", "connectors"]
			connectors = a.substr(8) == "connectors"
	var homes: Array = wl.sim.homes.values()
	for i in range(wl._tubes.size()):
		var tb: Dictionary = wl._tubes[i]
		if not tb.get("ent", false):
			continue                                  # pillar sleeves have no base, no sockets
		var n: Dictionary = wl.sim.nodes[tb["id"]]
		var st := clampi(int(n.get("tier", 1)), 1, 3)
		var home: bool = int(tb["id"]) in homes
		cols[i] = {"start": st, "home": home, "n": tubes_for(n, st, home), "pit": -1, "pits": [], "slots": [], "fill_t": [0.0, 0.0, 0.0, 0.0],
				"full": [false, false, false, false]}
		for k in range(MAX_TUBES):                    # the tubes there at the start are full already
			cols[i]["full"][k] = k < int(cols[i]["n"])
			cols[i]["fill_t"][k] = -99.0


func build() -> void:
	## once the pits are placed (WorldLocals.place): every potential tube of every column into one mesh
	## v3 (Daniele 2026-11-09/10: "I don't like the collector bar, it defeats the purpose of showing nodes go to take goo from
	## inside the pits; the vertical tube is the tube underneath a node" + "each door has 4 tube connections and we have 4
	## pits: 1 pit connected to 1 tube, no pit fed by more than one tube"): no collector. A column's k-th tube goes to its k-th
	## nearest pit (so its tubes reach DIFFERENT pits), out of the socket that faces that pit best, angled up to the 2 m rack,
	## and each tube climbs over the rim and dips into the goo on its own.
	var craters: Array = wl.locals.craters if wl.locals != null else []
	if craters.is_empty():
		return
	var t_build := Time.get_ticks_usec()
	pit_cols.clear()
	for k in range(craters.size()):
		pit_cols.append(WorldLayer.NATIVE_GRAY)
	_lanes.clear()
	_ortho_runs.clear()
	ortho_stats = [0, 0, 0]
	grid_routed = 0
	_grid_prepare()
	var fixed: Array = []                             # the Locals' lane exits round each pit (kept clear)
	for k in range(craters.size()):
		fixed.append([])
	for fk in wl.locals.feeds:
		var f: Dictionary = wl.locals.feeds[fk]
		var c: Vector3 = craters[int(f["crater"])]
		var ex: Vector2 = (f["path"] as Array)[0]
		fixed[int(f["crater"])].append(atan2(ex.y - c.z, ex.x - c.x))
	_fixed = fixed
	var into: Array = []                              # per pit: [col index, slot k, socket, wanted bearing]
	for k in range(craters.size()):
		into.append([])
	var plan := {}                                    # [col, slot k] -> [pit, socket]
	for i in cols:
		var tb: Dictionary = wl._tubes[i]
		var foot := Vector2(tb["x"], tb["z"])
		var porder: Array = range(craters.size())
		porder.sort_custom(func(a, b): return foot.distance_to(Vector2(craters[a].x, craters[a].z)) < foot.distance_to(Vector2(craters[b].x, craters[b].z)))
		var n0: Dictionary = wl.sim.nodes[tb["id"]]
		var most := mini(tubes_for(n0, int(cols[i]["start"]), bool(cols[i]["home"]), 3), mini(craters.size(), MAX_TUBES))
		var pits: Array = porder.slice(0, most)
		var socks := _assign_sockets(foot, pits, craters)
		cols[i]["pits"] = pits
		cols[i]["pit"] = int(pits[0]) if not pits.is_empty() else -1
		for k in range(pits.size()):
			var c2 := Vector2(craters[pits[k]].x, craters[pits[k]].z)
			plan[[i, k]] = [int(pits[k]), int(socks[k])]
			into[int(pits[k])].append([i, k, int(socks[k]), _approach(i, int(socks[k]), craters[pits[k]])])
	var angle_of := {}                                # [col, slot k] -> the bearing it enters its pit at
	for p in range(craters.size()):
		var got := _entry_angles(into[p], fixed[p])
		for key in got:
			angle_of[key] = got[key]
	var order: Array = plan.keys()                    # the shortest tubes are laid first (the long ones bridge over them)
	var tlen := func(key: Array) -> float:
		var c: Vector3 = craters[int(plan[key][0])]
		return Vector2(wl._tubes[int(key[0])]["x"], wl._tubes[int(key[0])]["z"]).distance_to(Vector2(c.x, c.z))
	order.sort_custom(func(a, b): return tlen.call(a) < tlen.call(b))
	var runs: Array = []                              # [col index, socket, pit, entry angle, world points]
	var slot_of := {}
	_laid.clear()
	var done := {}
	for key in order:
		if done.has(key):
			continue
		var i := int(key[0])
		var p := int(plan[key][0])
		var s := int(plan[key][1])
		var ang: float = angle_of[key]
		var pts := PackedVector3Array()
		_from_ortho = false
		_lane_log.clear()
		_lane_logging = true
		if ortho:
			pts = _path_grid(i, s, craters[p], p)
			if not pts.is_empty():
				grid_routed += 1
			else:
				pts = _path_ortho(i, s, craters[p], p)
			ortho_stats[0 if not pts.is_empty() else 1] += 1
			if pts.is_empty():
				pts = _path_ortho3(i, s, craters[p], p)
				ortho_stats[2] += 1 if not pts.is_empty() else 0
				if pts.is_empty():
					pts = _path_grid(i, s, craters[p], p)
					if not pts.is_empty():
						grid_routed += 1
		_lane_logging = false
		_from_ortho = not pts.is_empty()
		if pts.is_empty():
			pts = _path(i, s, craters[p], ang)
		_register(runs, slot_of, key, i, s, p, ang, pts, _from_ortho)
		done[key] = true
		# the map is symmetric (x and z mirrors): the mirrored tubes are THIS route mirrored, so the layout is symmetric too
		for t in [Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var pk = _mirror_key(key, t, plan, craters)
			if pk == null or done.has(pk):
				continue
			_register(runs, slot_of, pk, int(pk[0]), int(plan[pk][1]), int(plan[pk][0]), angle_of[pk], _mirror_pts(pts, t), _from_ortho)
			_mirror_lanes(t)
			done[pk] = true
	for i in cols:                                    # slots in tube order (k-th tube = k-th nearest pit)
		var sl: Array = []
		for k in range((cols[i]["pits"] as Array).size()):
			sl.append(slot_of[[i, k]])
		cols[i]["slots"] = sl
	var t_route := Time.get_ticks_usec() - t_build
	_slots = runs.size()
	run_pts = runs.map(func(rn): return [rn[0], rn[1], rn[2], rn[4]])
	_place_posts(runs, craters)
	_build_mesh(runs, craters)
	if connectors:
		_build_connectors()
	build_ms = [t_route / 1000.0, (Time.get_ticks_usec() - t_build) / 1000.0]
	print("TUBES build ms: routing %.0f, total %.0f (tubes %d)" % [build_ms[0], build_ms[1], _slots])
	_state = Image.create(maxi(_slots, 1), 2, false, Image.FORMAT_RGBAF)   # row 0 colour + fill, row 1 build progress
	for k in range(maxi(_slots, 1)):
		_state.set_pixel(k, 0, Color(0, 0, 0, -1))   # hidden until step()
		_state.set_pixel(k, 1, Color(-1, 0, 0, 0))   # not building
	_tex = ImageTexture.create_from_image(_state)
	_mat.set_shader_parameter("state", _tex)
	_mat.set_shader_parameter("goo_dim", WorldLayer.TUBE_GOO_DIM)
	var holo := ShaderMaterial.new()
	holo.shader = SHADER_HOLO
	holo.set_shader_parameter("state", _tex)
	holo.set_shader_parameter("slots", float(maxi(_slots, 1)))
	_mat.next_pass = holo
	built = true
	_dirty = true


func _side_by_side(way: Array) -> Array:
	## v3: where this tube would run ALONG a tube laid before it (near-parallel, closer than PAR_GAP), it moves beside it
	## instead of stacking on top (crossings still bridge over); the socket climb and the radial entry stay put
	var laid2: Array = []
	for run in _laid:
		var o: Array = []
		for q in (run as PackedVector3Array):
			o.append(Vector2(q.x, q.z))
		laid2.append(o)
	var out := way.duplicate()
	var n := out.size()
	var lo := mini(4, n)
	var hi := maxi(n - ceili((ENTRY_RUN + 0.9) / 1.5) - 1, lo)
	for _pass in range(4):
		var side := 0.0
		for k in range(lo, hi):
			var p: Vector2 = out[k]
			var t: Vector2 = ((out[mini(k + 1, n - 1)] as Vector2) - (out[maxi(k - 1, 0)] as Vector2)).normalized()
			var push := Vector2.ZERO
			for o in laid2:
				for j in range(1, (o as Array).size()):
					var a: Vector2 = o[j - 1]
					var b: Vector2 = o[j]
					if absf(p.x - a.x) > 4.0 and absf(p.x - b.x) > 4.0:
						continue
					var cq := Geometry2D.get_closest_point_to_segment(p, a, b)
					var d := p.distance_to(cq)
					var ts := (b - a).normalized()
					if d >= PAR_GAP or absf(ts.dot(t)) < 0.75:
						continue
					var sgn := signf(ts.cross(p - cq)) if d > 0.02 else (side if side != 0.0 else 1.0)
					side = sgn
					var nrm := Vector2(-ts.y, ts.x) * sgn
					push += nrm * (PAR_GAP - d + 0.03)
			out[k] = p + push
		for _sm in range(3):                          # smoothing: no kinks or wobble where it steps aside
			for k in range(lo + 1, hi - 1):
				out[k] = ((out[k - 1] as Vector2) + (out[k] as Vector2) * 2.0 + (out[k + 1] as Vector2)) / 4.0
	return out


func rebuild(on: bool, with_connectors := false) -> void:
	## the switch (playground / probes): re-lay every tube with the ortho routing on or off
	ortho = on
	connectors = on and with_connectors
	for n in _conn_nodes:
		(n as Node).queue_free()
	_conn_nodes.clear()
	if _mi != null:
		_mi.queue_free()
		_mi = null
	_laid.clear()
	built = false
	if wl.locals != null:
		wl.locals.reroute()                           # the walkway layer follows the tube mode
	build()
	if wl.locals != null:
		wl.locals.sync_walkways()


static func _lk(ax: String, coord: float) -> int:
	return (100000 if ax == "X" else 200000) + roundi(coord / ORTHO_GAP) + 50000


func _lane_free(ax: String, coord: float, lo: float, hi: float) -> bool:
	var key := _lk(ax, coord)
	for iv in _lanes.get(key, []):
		if lo < float(iv[1]) + 0.9 and hi > float(iv[0]) - 0.9:
			return false
	return true


func _lane_covers(ax: String, coord: float, pos: float) -> bool:
	for iv in _lanes.get(_lk(ax, coord), []):
		if pos >= float(iv[0]) - 0.05 and pos <= float(iv[1]) + 0.05:
			return true
	return false


var _lane_log: Array = []
var _lane_logging := false


func _register(runs: Array, slot_of: Dictionary, key: Array, i: int, s: int, p: int, ang: float, pts: PackedVector3Array, from_ortho: bool) -> void:
	_laid.append(pts)
	if from_ortho:
		_ortho_runs.append(_laid.size() - 1)
	runs.append([i, s, p, ang, pts])
	slot_of[key] = runs.size() - 1


func _mirror_key(key: Array, t: Vector2, plan: Dictionary, craters: Array):
	## the tube that is this one seen in the x / z mirror (the maps are symmetric), or null
	var tb: Dictionary = wl._tubes[int(key[0])]
	var foot := Vector2(float(tb["x"]) * t.x, float(tb["z"]) * t.y)
	var cd := corner_dir(int(plan[key][1]))
	var want_cd := Vector2(cd.x * t.x, cd.y * t.y)
	var c: Vector3 = craters[int(plan[key][0])]
	var want_c := Vector2(c.x * t.x, c.z * t.y)
	for k2 in plan.keys():
		var t2: Dictionary = wl._tubes[int(k2[0])]
		if Vector2(float(t2["x"]), float(t2["z"])).distance_to(foot) > 0.1:
			continue
		var c2: Vector3 = craters[int(plan[k2][0])]
		if Vector2(c2.x, c2.z).distance_to(want_c) > 0.1:
			continue
		if corner_dir(int(plan[k2][1])).distance_to(want_cd) > 0.05:
			continue
		return k2
	return null


static func _mirror_pts(pts: PackedVector3Array, t: Vector2) -> PackedVector3Array:
	var out := PackedVector3Array()
	for q in pts:
		out.append(Vector3(q.x * t.x, q.y, q.z * t.y))
	return out


func _mirror_lanes(t: Vector2) -> void:
	for e in _lane_log:
		var ax: String = e[0]
		var coord: float = e[1]
		var lo: float = e[2]
		var hi: float = e[3]
		if ax == "X":                                 # an x run: z is its lane, x its interval
			var a := lo * t.x
			var b := hi * t.x
			_lane_take_raw("X", coord * t.y, minf(a, b), maxf(a, b))
		else:
			var a2 := lo * t.y
			var b2 := hi * t.y
			_lane_take_raw("Z", coord * t.x, minf(a2, b2), maxf(a2, b2))


func _lane_take_raw(ax: String, coord: float, lo: float, hi: float) -> void:
	var key := _lk(ax, coord)
	if not _lanes.has(key):
		_lanes[key] = []
	_lanes[key].append([lo, hi])


func _lane_take(ax: String, coord: float, lo: float, hi: float) -> void:
	if _lane_logging:
		_lane_log.append([ax, coord, minf(lo, hi), maxf(lo, hi)])
	var key := _lk(ax, coord)
	if not _lanes.has(key):
		_lanes[key] = []
	_lanes[key].append([minf(lo, hi), maxf(lo, hi)])


func _ortho_clear(a: Vector2, b: Vector2, i: int, pit_c: Vector2) -> bool:
	## a straight leg keeps clear of every other column's base and of every pit but its own
	for j in range(wl._tubes.size()):
		if j == i:
			continue
		var t2: Dictionary = wl._tubes[j]
		var r := (2.0 if t2.get("ent", false) else float(t2["r"]) + 1.0) + 0.35
		var cc := Vector2(t2["x"], t2["z"])
		if Geometry2D.get_closest_point_to_segment(cc, a, b).distance_to(cc) < r:
			return false
	for c in wl.locals.craters:
		var cc := Vector2((c as Vector3).x, (c as Vector3).z)
		if cc.distance_to(pit_c) < 0.1:
			continue
		if Geometry2D.get_closest_point_to_segment(cc, a, b).distance_to(cc) < WorldLocals.RING_R + 1.3:
			return false
	return true


func _path_ortho(i: int, s: int, pit: Vector3, pi: int) -> PackedVector3Array:
	## socket stub (diagonal, climbing) -> one leg along an axis on a grid lane -> ONE corner -> the final leg along the other
	## axis on a grid lane into the pit. Empty = no grid route (the caller uses the v3 path).
	var tb: Dictionary = wl._tubes[i]
	var foot := Vector2(tb["x"], tb["z"])
	var cd := corner_dir(s)
	var c2 := Vector2(pit.x, pit.z)
	var G := ORTHO_GAP
	var R0 := WorldLocals.RING_R + 0.9
	var L0 := APOTHEM + 0.05 + RAMP_RUN + 0.9
	var p0 := foot + cd * (APOTHEM + 0.05)
	var d0 := (foot + cd * L0) - c2
	var axes: Array = ["X", "Z"] if absf(d0.x) >= absf(d0.y) else ["Z", "X"]   # the final leg's axis: the longer one first
	for fa in axes:
		var fx: bool = fa == "X"                         # the final leg runs along x (so the first leg runs along z)
		var sgn := signf(d0.x if fx else d0.y)
		if sgn == 0.0:
			continue
		var cdc: float = cd.x if fx else cd.y
		if absf(cdc) < 0.01:
			continue
		var f0: float = foot.x if fx else foot.y
		for dstub in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 8, -8, 10, -10]:                  # the first leg's lane: the grid line nearest the stub's end, then its neighbours
			var lane: float = (roundf((f0 + cdc * L0) / G) + dstub) * G
			var L := (lane - f0) / cdc
			if L < APOTHEM + 0.05 + RAMP_RUN + 0.2:
				continue
			var p1 := foot + cd * L
			for o in [0.0, G, -G, 2.0 * G, -2.0 * G, 3.0 * G, -3.0 * G, 4.0 * G, -4.0 * G]:
				var latc: float = c2.y if fx else c2.x
				var lat: float = roundf((latc + o) / G) * G
				if absf(lat - latc) > 4.6:
					continue
				var corner := Vector2(lane, lat) if fx else Vector2(lat, lane)
				var rim := Vector2(c2.x + sgn * R0, lat) if fx else Vector2(lat, c2.y + sgn * R0)
				var a := Vector2(c2.x + sgn * (R0 + ENTRY_RUN), lat) if fx else Vector2(lat, c2.y + sgn * (R0 + ENTRY_RUN))
				var along_c: float = corner.x if fx else corner.y
				var along_a: float = a.x if fx else a.y
				if (along_c - along_a) * sgn < 0.5:     # the corner must lie outside the approach run
					continue
				var bear := atan2(rim.y - c2.y, rim.x - c2.x)
				var blocked := false
				for fb in _fixed[pi]:
					if absf(angle_difference(bear, float(fb))) < LANE_SEP:
						blocked = true
				if blocked:
					continue
				if not (_ortho_clear(p1, corner, i, c2) and _ortho_clear(corner, a, i, c2)):
					continue
				var d1 := (corner - p1).length()
				var ax1 := "Z" if fx else "X"            # the first leg runs along the other axis
				var lo1: float = minf(p1.y, corner.y) if fx else minf(p1.x, corner.x)
				var hi1: float = maxf(p1.y, corner.y) if fx else maxf(p1.x, corner.x)
				var lo2: float = minf(corner.x, rim.x) if fx else minf(corner.y, rim.y)
				var hi2: float = maxf(corner.x, rim.x) if fx else maxf(corner.y, rim.y)
				if d1 > 0.05 and not _lane_free(ax1, lane, lo1, hi1):
					continue
				if not _lane_free(fa, lat, lo2, hi2):
					continue
				if d1 > 0.05:
					_lane_take(ax1, lane, lo1, hi1)
				_lane_take(fa, lat, lo2, hi2)
				var way: Array = [p0, p1]
				if d1 > 0.05:
					way.append(corner)
				way.append(a)
				way.append(rim)
				way = _fillet(way, ORTHO_BEND)
				var even: Array = [way[0]]
				for k in range(1, way.size()):
					var q0: Vector2 = way[k - 1]
					var q1: Vector2 = way[k]
					var m := maxi(ceili(q0.distance_to(q1) / 1.5), 1)
					for j in range(1, m + 1):
						even.append(q0.lerp(q1, float(j) / m))
				var axis := Vector2(sgn, 0.0) if fx else Vector2(0.0, sgn)
				return _shape(even, c2, axis, true, axis, true)
	return PackedVector3Array()


func _grid_prepare() -> void:
	_gobs.clear()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for j in range(wl._tubes.size()):
		var t2: Dictionary = wl._tubes[j]
		var c := Vector2(t2["x"], t2["z"])
		_gobs.append([c, (2.0 if t2.get("ent", false) else float(t2["r"]) + 1.0) + 1.4])
		lo = lo.min(c)
		hi = hi.max(c)
	if wl.locals != null:
		for cr in wl.locals.craters:
			var c := Vector2((cr as Vector3).x, (cr as Vector3).z)
			_gobs.append([c, WorldLocals.RING_R + 1.5])
			lo = lo.min(c)
			hi = hi.max(c)
	var G := ORTHO_GAP
	lo -= Vector2(14, 14)
	hi += Vector2(14, 14)
	_gbox = Rect2i(Vector2i(floori(lo.x / G), floori(lo.y / G)), Vector2i(ceili((hi.x - lo.x) / G), ceili((hi.y - lo.y) / G)))


func _grid_blocked(v: Vector2i, cache: Dictionary) -> bool:
	if cache.has(v):
		return cache[v]
	var q := Vector2(v.x, v.y) * ORTHO_GAP
	var b := false
	for ob in _gobs:
		if q.distance_to(ob[0]) < float(ob[1]):
			b = true
			break
	cache[v] = b
	return b


func _path_grid(i: int, s: int, pit: Vector3, pi: int) -> PackedVector3Array:
	## the real ortho router for what the lane tries could not place: a shortest-path search on the global lane grid (a vertex every
	## ORTHO_GAP), edges free of other tubes' lanes, a cost per corner (fewer corners), ending at one of the pit's entry lanes
	var G := ORTHO_GAP
	var tb: Dictionary = wl._tubes[i]
	var foot := Vector2(tb["x"], tb["z"])
	var cd := corner_dir(s)
	var c2 := Vector2(pit.x, pit.z)
	var R0 := WorldLocals.RING_R + 0.9
	var L0 := APOTHEM + 0.05 + RAMP_RUN + 0.9
	var p0 := foot + cd * (APOTHEM + 0.05)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	# the end vertices: every face and lane the pit still offers
	var ends := {}                                      # vertex -> [required direction index, rim, a]
	for fx in [true, false]:
		for sg in [1.0, -1.0]:
			for o in [0.0, G, -G, 2.0 * G, -2.0 * G, 3.0 * G, -3.0 * G, 4.0 * G, -4.0 * G]:
				var latc: float = c2.y if fx else c2.x
				var lat: float = roundf((latc + o) / G) * G
				if absf(lat - latc) > 4.6:
					continue
				var a_al: float = roundf(((c2.x if fx else c2.y) + sg * (R0 + ENTRY_RUN)) / G) * G
				var a := Vector2(a_al, lat) if fx else Vector2(lat, a_al)
				var rim := Vector2(c2.x + sg * R0, lat) if fx else Vector2(lat, c2.y + sg * R0)
				var bear := atan2(rim.y - c2.y, rim.x - c2.x)
				var blocked := false
				for fb in _fixed[pi]:
					if absf(angle_difference(bear, float(fb))) < LANE_SEP:
						blocked = true
				if blocked:
					continue
				var ax := "X" if fx else "Z"
				var lo2: float = minf(a_al, (c2.x if fx else c2.y) + sg * R0)
				var hi2: float = maxf(a_al, (c2.x if fx else c2.y) + sg * R0)
				if not _lane_free(ax, lat, lo2, hi2):
					continue
				var di := (1 if sg > 0.0 else 0) if fx else (3 if sg > 0.0 else 2)   # arrives moving toward the pit
				var vk := Vector2i(roundi(a.x / G), roundi(a.y / G))
				if not ends.has(vk):
					ends[vk] = [di, rim, a, sg, fx]
	if ends.is_empty():
		return PackedVector3Array()
	var cache := {}
	var starts: Array = []                              # every first-leg lane the stub can reach: [vertex, direction, p1]
	for variant in [0, 1]:                              # the first leg runs along x (z lane fixed) or along z
		var cdc: float = cd.y if variant == 0 else cd.x
		if absf(cdc) < 0.01:
			continue
		var f0: float = foot.y if variant == 0 else foot.x
		for dstub in [0, 1, -1, 2, -2]:
			var lane: float = (roundf((f0 + cdc * L0) / G) + dstub) * G
			var L := (lane - f0) / cdc
			if L < APOTHEM + 0.05 + RAMP_RUN + 0.2:
				continue
			var p1 := foot + cd * L
			if variant == 0:
				var ix := p1.x / G
				starts.append([Vector2i(floori(ix), roundi(lane / G)), 1, p1])
				starts.append([Vector2i(ceili(ix), roundi(lane / G)), 0, p1])
			else:
				var iz := p1.y / G
				starts.append([Vector2i(roundi(lane / G), floori(iz)), 3, p1])
				starts.append([Vector2i(roundi(lane / G), ceili(iz)), 2, p1])
	var res := _grid_search(starts, ends, cache, dirs)
	if res.is_empty():
		return PackedVector3Array()
	return _grid_finish(res, ends, p0, res[2], c2)


func _grid_search(starts: Array, ends: Dictionary, cache: Dictionary, dirs: Array) -> Array:
	## A* over (vertex, direction, run) states with integer keys and a bucketed queue (cost in half metres); returns [vertex path, end record]
	var G := ORTHO_GAP
	var W := _gbox.size.y + 2
	var best := {}
	var prev := {}
	var hmemo := {}
	var root_p1 := {}
	var end_v: Array = ends.keys()
	var hstep := (G - GRID_BUNDLE) * 0.98
	var buckets: Array = []
	for _b in range(2400):
		buckets.append([])
	for st in starts:
		var v: Vector2i = st[0]
		if not _gbox.has_point(v) or _grid_blocked(v, cache):
			continue
		var key := (((v.x - _gbox.position.x) * W + (v.y - _gbox.position.y)) * 4 + int(st[1])) * 8
		var c0 := Vector2(v.x, v.y) * G
		var p1: Vector2 = st[2]
		var cost := p1.distance_to(c0)
		root_p1[key] = p1
		best[key] = cost
		prev[key] = -1
		buckets[mini(int(cost * 2.0), 2399)].append([cost, key])
	var expansions := 0
	for bi in range(buckets.size()):
		var bucket: Array = buckets[bi]
		var qi := 0
		while qi < bucket.size():
			var item: Array = bucket[qi]
			qi += 1
			var cost: float = item[0]
			var key: int = item[1]
			if cost > float(best.get(key, INF)) + 0.001 + 0.0:
				continue
			expansions += 1
			if expansions > GRID_CAP:
				return []
			var run: int = key % 8
			var rest := key / 8
			var d: int = rest % 4
			rest = rest / 4
			var v := Vector2i(rest / W + _gbox.position.x, rest % W + _gbox.position.y)
			if ends.has(v) and int(ends[v][0]) == d:
				var path: Array = []
				var cur := key
				var cur0 := key
				while cur != -1:
					cur0 = cur
					var r2 := cur / 8
					var d2: int = r2 % 4
					r2 = r2 / 4
					path.append([r2 / W + _gbox.position.x, r2 % W + _gbox.position.y, d2])
					cur = int(prev[cur])
				path.reverse()
				return [path, ends[v], root_p1[cur0]]
			for nd in range(4):
				if (nd == 0 and d == 1) or (nd == 1 and d == 0) or (nd == 2 and d == 3) or (nd == 3 and d == 2):
					continue
				if nd != d and run < GRID_MIN_RUN:
					continue                                # a corner needs a straight run before it
				var nv: Vector2i = v + dirs[nd]
				if not _gbox.has_point(nv) or _grid_blocked(nv, cache):
					continue
				var a := Vector2(v.x, v.y) * G
				var b := Vector2(nv.x, nv.y) * G
				var ax := "X" if nd < 2 else "Z"
				var coord: float = a.y if nd < 2 else a.x
				var lo: float = minf(a.x if nd < 2 else a.y, b.x if nd < 2 else b.y)
				var hi: float = maxf(a.x if nd < 2 else a.y, b.x if nd < 2 else b.y)
				if not _lane_free(ax, coord, lo, hi):
					continue
				var ncost := cost + G + (GRID_TURN if nd != d else 0.0)
				var perp := "Z" if nd < 2 else "X"
				if _lane_covers(perp, b.x if nd < 2 else b.y, coord):
					ncost += GRID_CROSS                    # it would cross another tube here
				if not _lane_free(ax, coord + G, lo, hi) or not _lane_free(ax, coord - G, lo, hi):
					ncost -= GRID_BUNDLE                   # it runs right beside another tube: stripes, not strands
				var nrun := mini(run + 1, GRID_MIN_RUN) if nd == d else 1
				var nkey := (((nv.x - _gbox.position.x) * W + (nv.y - _gbox.position.y)) * 4 + nd) * 8 + nrun
				if ncost < float(best.get(nkey, INF)) - 0.001:
					best[nkey] = ncost
					prev[nkey] = key
					var hv := 0.0
					var hk := nkey / 32
					if hmemo.has(hk):
						hv = hmemo[hk]
					else:
						hv = INF
						for ev in end_v:
							hv = minf(hv, float(absi(nv.x - (ev as Vector2i).x) + absi(nv.y - (ev as Vector2i).y)))
						hv *= hstep
						hmemo[hk] = hv
					buckets[mini(int((ncost + hv) * 2.0), 2399)].append([ncost, nkey])
	return []


func _grid_finish(res: Array, ends: Dictionary, p0: Vector2, p1: Vector2, c2: Vector2) -> PackedVector3Array:
	var G := ORTHO_GAP
	var path: Array = res[0]
	var rec: Array = res[1]
	var rim: Vector2 = rec[1]
	var a_end: Vector2 = rec[2]
	var sg: float = rec[3]
	var fx: bool = rec[4]
	var way: Array = [p0, p1]
	var seg_start := Vector2(path[0][0], path[0][1]) * G
	way.append(seg_start)
	var cur_dir: int = path[0][2]
	var run_a := seg_start
	var last := seg_start
	for k in range(1, path.size()):
		var v := Vector2(path[k][0], path[k][1]) * G
		if int(path[k][2]) != cur_dir:
			_grid_take(run_a, last, cur_dir)
			way.append(last)
			run_a = last
			cur_dir = int(path[k][2])
		last = v
	_grid_take(run_a, last, cur_dir)
	way.append(last)
	way.append(a_end)
	way.append(rim)
	var ax := "X" if fx else "Z"
	var lat: float = rim.y if fx else rim.x
	_lane_take(ax, lat, minf(a_end.x if fx else a_end.y, rim.x if fx else rim.y), maxf(a_end.x if fx else a_end.y, rim.x if fx else rim.y))
	# drop duplicate / collinear points
	var clean: Array = [way[0]]
	for k in range(1, way.size()):
		if (way[k] as Vector2).distance_to(clean[clean.size() - 1]) > 0.05:
			clean.append(way[k])
	var f: Array = _fillet(clean, ORTHO_BEND)
	var even: Array = [f[0]]
	for k in range(1, f.size()):
		var q0: Vector2 = f[k - 1]
		var q1: Vector2 = f[k]
		var m := maxi(ceili(q0.distance_to(q1) / 1.5), 1)
		for j in range(1, m + 1):
			even.append(q0.lerp(q1, float(j) / m))
	var axis := Vector2(sg, 0.0) if fx else Vector2(0.0, sg)
	return _shape(even, c2, axis, true, axis, true)


func _grid_take(a: Vector2, b: Vector2, d: int) -> void:
	if d < 2:
		_lane_take("X", a.y, minf(a.x, b.x), maxf(a.x, b.x))
	else:
		_lane_take("Z", a.x, minf(a.y, b.y), maxf(a.y, b.y))


func _mk(fx: bool, along: float, lat: float) -> Vector2:
	return Vector2(along, lat) if fx else Vector2(lat, along)


func _path_ortho3(i: int, s: int, pit: Vector3, pi: int) -> PackedVector3Array:
	## two corners: stub -> a leg along the final axis on a grid lane -> across to the pit's lane -> final leg along the axis
	var tb: Dictionary = wl._tubes[i]
	var foot := Vector2(tb["x"], tb["z"])
	var cd := corner_dir(s)
	var c2 := Vector2(pit.x, pit.z)
	var G := ORTHO_GAP
	var R0 := WorldLocals.RING_R + 0.9
	var L0 := APOTHEM + 0.05 + RAMP_RUN + 0.9
	var p0 := foot + cd * (APOTHEM + 0.05)
	var d0 := (foot + cd * L0) - c2
	var axes: Array = ["X", "Z"] if absf(d0.x) >= absf(d0.y) else ["Z", "X"]
	for fa in axes:
		var fx: bool = fa == "X"
		var sgn := signf(d0.x if fx else d0.y)
		if sgn == 0.0:
			continue
		var cdl: float = cd.y if fx else cd.x           # the stub's lateral component: it sets the first leg's lane
		if absf(cdl) < 0.01:
			continue
		var fl: float = foot.y if fx else foot.x
		var latc: float = c2.y if fx else c2.x
		var other := "Z" if fx else "X"
		for dstub in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6]:
			var lane_l: float = (roundf((fl + cdl * L0) / G) + dstub) * G
			var L := (lane_l - fl) / cdl
			if L < APOTHEM + 0.05 + RAMP_RUN + 0.2:
				continue
			var p1 := foot + cd * L
			var along1: float = p1.x if fx else p1.y
			for o in [0.0, G, -G, 2.0 * G, -2.0 * G, 3.0 * G, -3.0 * G, 4.0 * G, -4.0 * G]:
				var lat: float = roundf((latc + o) / G) * G
				if absf(lat - latc) > 4.6:
					continue
				var rim := _mk(fx, (c2.x if fx else c2.y) + sgn * R0, lat)
				var a_al: float = (c2.x if fx else c2.y) + sgn * (R0 + ENTRY_RUN)
				var a := _mk(fx, a_al, lat)
				var bear := atan2(rim.y - c2.y, rim.x - c2.x)
				var blocked := false
				for fb in _fixed[pi]:
					if absf(angle_difference(bear, float(fb))) < LANE_SEP:
						blocked = true
				if blocked:
					continue
				var dirm := signf(a_al - along1)
				if dirm == 0.0:
					continue
				for step in range(1, 60):
					var m: float = roundf((along1 + dirm * float(step) * G * 2.0) / G) * G
					if (m - a_al) * dirm > 0.0:          # past the approach point: no
						break
					if (m - a_al) * sgn < 0.5:           # the cross leg must lie outside the approach run
						continue
					var c1 := _mk(fx, m, lane_l)
					var c2p := _mk(fx, m, lat)
					if not (_ortho_clear(p1, c1, i, c2) and _ortho_clear(c1, c2p, i, c2) and _ortho_clear(c2p, a, i, c2)):
						continue
					var lo1 := minf(along1, m)
					var hi1 := maxf(along1, m)
					var lo2 := minf(lane_l, lat)
					var hi2 := maxf(lane_l, lat)
					var rim_al: float = rim.x if fx else rim.y
					var lo3 := minf(m, rim_al)
					var hi3 := maxf(m, rim_al)
					if not (_lane_free(fa, lane_l, lo1, hi1) and _lane_free(other, m, lo2, hi2) and _lane_free(fa, lat, lo3, hi3)):
						continue
					_lane_take(fa, lane_l, lo1, hi1)
					_lane_take(other, m, lo2, hi2)
					_lane_take(fa, lat, lo3, hi3)
					var way: Array = _fillet([p0, p1, c1, c2p, a, rim], ORTHO_BEND)
					var even: Array = [way[0]]
					for k in range(1, way.size()):
						var q0: Vector2 = way[k - 1]
						var q1: Vector2 = way[k]
						var mm := maxi(ceili(q0.distance_to(q1) / 1.5), 1)
						for j in range(1, mm + 1):
							even.append(q0.lerp(q1, float(j) / mm))
					var axis := Vector2(sgn, 0.0) if fx else Vector2(0.0, sgn)
					return _shape(even, c2, axis, true, axis, true)
	return PackedVector3Array()


func _build_connectors() -> void:
	## every crossing of two ortho runs (an x run over a z run, one level) gets a connector block that swallows the overlap.
	## The block is cut to the LANES that cross there: k x-lanes enter its left / right faces, m z-lanes its up / down faces, one
	## coupling ring per lane (2, 3 or 4 slots as the overlap needs), faces snapped to the lane grid like the stripes themselves.
	## Crossings closer than 2.6 m merge into one block.
	conn_count = 0
	var pts2: Array = []
	for ri in _ortho_runs:
		var a: Array = []
		for q in (_laid[ri] as PackedVector3Array):
			a.append(Vector2(q.x, q.z))
		pts2.append(a)
	var hits: Array = []                               # [point, tube level y, the first run runs along x]
	for i1 in range(pts2.size()):
		var A: Array = pts2[i1]
		var bbA := Rect2(A[0], Vector2.ZERO)
		for q in A:
			bbA = bbA.expand(q)
		for i2 in range(i1 + 1, pts2.size()):
			var B: Array = pts2[i2]
			var bbB := Rect2(B[0], Vector2.ZERO)
			for q in B:
				bbB = bbB.expand(q)
			if not bbA.grow(0.5).intersects(bbB):
				continue
			for k in range(1, A.size()):
				var a0: Vector2 = A[k - 1]
				var a1: Vector2 = A[k]
				var ra := Rect2(a0, Vector2.ZERO).expand(a1).grow(0.3)
				if not ra.intersects(bbB):
					continue
				for j in range(1, B.size()):
					var b0: Vector2 = B[j - 1]
					var b1: Vector2 = B[j]
					if not ra.intersects(Rect2(b0, Vector2.ZERO).expand(b1)):
						continue
					if absf((a1 - a0).normalized().dot((b1 - b0).normalized())) > 0.6:
						continue
					var hit = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
					if hit != null:
						var da := a1 - a0
						hits.append([hit, (laid_y(i1, k) + laid_y(i2, j)) * 0.5, absf(da.x) >= absf(da.y)])
	var group: Array = []                              # union by proximity
	for h in hits:
		var placed := -1
		for gi in range(group.size()):
			for m in group[gi]:
				if (m[0] as Vector2).distance_to(h[0]) < 4.5:
					placed = gi
					break
			if placed >= 0:
				break
		if placed >= 0:
			group[placed].append(h)
		else:
			group.append([h])
	var cyl := CylinderMesh.new()
	cyl.top_radius = SOCK_R
	cyl.bottom_radius = SOCK_R
	cyl.height = 0.3
	cyl.radial_segments = 10
	cyl.rings = 1
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = STEEL_D
	ring_mat.metallic = 0.6
	ring_mat.roughness = 0.4
	var rects: Array = []                              # one [x0, x1, z0, z1, y, xl, zl] per group, then merged
	for g in group:
		var xl: Array = []                             # z coordinates of the x runs (one lane each, snapped to the grid)
		var zl: Array = []                             # x coordinates of the z runs
		var y := 0.0
		for h in g:
			y += float(h[1])
			var pt: Vector2 = h[0]
			var lx := roundf((pt.y if h[2] else pt.x) / ORTHO_GAP) * ORTHO_GAP
			var lz := roundf((pt.x if h[2] else pt.y) / ORTHO_GAP) * ORTHO_GAP
			if h[2]:
				if not xl.has(lx): xl.append(lx)
				if not zl.has(lz): zl.append(lz)
			else:
				if not zl.has(lx): zl.append(lx)
				if not xl.has(lz): xl.append(lz)
		y /= float(g.size())
		if xl.is_empty() or zl.is_empty():
			continue
		rects.append({"xl": xl, "zl": zl, "y": y})
	var merged := true
	while merged:                                      # trunk blocks: neighbouring crossings become one bigger block
		merged = false
		for i1 in range(rects.size()):
			for i2 in range(i1 + 1, rects.size()):
				var ra := _conn_rect(rects[i1])
				var rb := _conn_rect(rects[i2])
				if not ra.grow(CONN_MERGE).intersects(rb):
					continue
				var u := {"xl": (rects[i1]["xl"] as Array) + (rects[i2]["xl"] as Array), "zl": (rects[i1]["zl"] as Array) + (rects[i2]["zl"] as Array),
						"y": (float(rects[i1]["y"]) + float(rects[i2]["y"])) * 0.5}
				var ur := _conn_rect(u)
				if ur.size.x > CONN_MAX or ur.size.y > CONN_MAX or _conn_hits_obstacle(ur):
					continue                           # never swallow a column base or a pit, never grow into a slab
				rects[i1] = u
				rects.remove_at(i2)
				merged = true
				break
			if merged:
				break
	for rc in rects:
		var xl: Array = rc["xl"]
		var zl: Array = rc["zl"]
		var y: float = rc["y"]
		xl.sort()
		zl.sort()
		var rr := _conn_rect(rc)
		var x0 := rr.position.x
		var x1 := rr.end.x
		var z0 := rr.position.y
		var z1 := rr.end.y
		var cy := maxf(y, CONN_H * 0.5)
		var ring_dy := y - cy
		var cen := Vector3((x0 + x1) * 0.5, wl.floor_y + cy, (z0 + z1) * 0.5)
		var mi := MeshInstance3D.new()
		var bx := BoxMesh.new()
		bx.size = Vector3(x1 - x0, CONN_H, z1 - z0)
		mi.mesh = bx
		var m := StandardMaterial3D.new()
		m.albedo_color = STEEL_L
		m.metallic = 0.5
		m.roughness = 0.5
		mi.material_override = m
		mi.position = cen
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_conn_nodes.append(mi)
		var mm := MultiMesh.new()                       # one coupling ring per lane on the faces it enters
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cyl
		mm.instance_count = (xl.size() + zl.size()) * 2
		var n := 0
		for lz2 in xl:                                  # x runs: left and right faces
			for sg in [-1.0, 1.0]:
				var pos := Vector3(sg * ((x1 - x0) * 0.5 + 0.04), ring_dy, float(lz2) - cen.z)
				mm.set_instance_transform(n, Transform3D(Basis(Quaternion(Vector3.UP, Vector3(sg, 0, 0))), pos))
				n += 1
		for lx2 in zl:                                  # z runs: up and down faces
			for sg in [-1.0, 1.0]:
				var pos := Vector3(float(lx2) - cen.x, ring_dy, sg * ((z1 - z0) * 0.5 + 0.04))
				mm.set_instance_transform(n, Transform3D(Basis(Quaternion(Vector3.UP, Vector3(0, 0, sg))), pos))
				n += 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = ring_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(mmi)
		conn_count += 1


func _conn_rect(rc: Dictionary) -> Rect2:
	var xl: Array = rc["xl"]
	var zl: Array = rc["zl"]
	var half := ORTHO_GAP * 0.5 + 0.25 + CONN_PAD * 0.5
	var xs: Array = zl.duplicate()
	var zs: Array = xl.duplicate()
	xs.sort()
	zs.sort()
	return Rect2(Vector2(float(xs[0]) - half, float(zs[0]) - half), Vector2(float(xs[xs.size() - 1]) - float(xs[0]) + 2.0 * half, float(zs[zs.size() - 1]) - float(zs[0]) + 2.0 * half))


func _conn_hits_obstacle(r: Rect2) -> bool:
	for ob in _gobs:
		var c: Vector2 = ob[0]
		var q := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
		if q.distance_to(c) < float(ob[1]) - 0.6:
			return true
	return false


func laid_y(ri: int, k: int) -> float:
	var q: PackedVector3Array = _laid[_ortho_runs[ri]]
	return q[mini(k, q.size() - 1)].y - wl.floor_y


func _approach(i: int, s: int, pit: Vector3) -> float:
	## v3: the bearing (from the pit) the tube really comes in from: its route steered round bases / pits toward the pit,
	## its last waypoint before the pit (the column's foot when the way is clear)
	var foot := Vector2(wl._tubes[i]["x"], wl._tubes[i]["z"])
	var c2 := Vector2(pit.x, pit.z)
	var p1 := foot + corner_dir(s) * (APOTHEM + 0.05 + RAMP_RUN + 0.9)
	var d0 := (p1 - c2).normalized() if p1.distance_to(c2) > 0.01 else Vector2(1, 0)
	var a0 := c2 + d0 * (WorldLocals.RING_R + 0.9 + ENTRY_RUN)
	var mid: Array = _steer(p1, a0, i, int(wl._tubes[i]["id"]), pit, 0)
	var last: Vector2 = mid[mid.size() - 1] if not mid.is_empty() else p1
	return atan2(last.y - c2.y, last.x - c2.x)


static func _assign_sockets(foot: Vector2, pits: Array, craters: Array) -> Array:
	## v3: one socket per pit, the 4! assignments tried: the most total "faces its pit" (no tube leaves backwards if avoidable)
	var dirs: Array = []
	for p in pits:
		var c2 := Vector2(craters[p].x, craters[p].z)
		dirs.append((c2 - foot).normalized() if c2.distance_to(foot) > 0.01 else Vector2(0, 1))
	var best: Array = [0, 1, 2, 3]
	var bs := -INF
	for a in range(4):
		for b in range(4):
			for c in range(4):
				for d in range(4):
					var perm := [a, b, c, d]
					if a == b or a == c or a == d or b == c or b == d or c == d:
						continue
					var sc := 0.0
					for k in range(dirs.size()):
						sc += corner_dir(perm[k]).dot(dirs[k]) * (1.0 + 0.01 * (dirs.size() - k))   # nearer pits break ties
					if sc > bs:
						bs = sc
						best = perm
	return best.slice(0, pits.size())


static func _entry_angles(tubes: Array, fixed: Array) -> Dictionary:
	## v3: each tube's own bearing into its pit: free angles (TUBE_SEP apart, LANE_SEP off the Locals' exits) picked nearest
	## the column's bearing, then handed back in the columns' circular order (so no two tubes cross round the pit)
	var out := {}
	if tubes.is_empty():
		return out
	var taken: Array = []
	var by_near := tubes.duplicate()
	for t in by_near:
		var w: float = t[3]
		var pick := w
		for dd in range(0, 320):
			var cand := w + float(dd / 2) * 0.02 * (1.0 if dd % 2 == 0 else -1.0)
			var ok := true
			for f in fixed:
				if absf(angle_difference(cand, float(f))) < LANE_SEP:
					ok = false
			for a in taken:
				if absf(angle_difference(cand, float(a))) < TUBE_SEP:
					ok = false
			if ok:
				pick = cand
				break
		taken.append(pick)
	var ws := tubes.duplicate()
	ws.sort_custom(func(a, b): return fposmod(float(a[3]), TAU) < fposmod(float(b[3]), TAU))
	taken.sort_custom(func(a, b): return fposmod(float(a), TAU) < fposmod(float(b), TAU))
	var m := ws.size()
	var best_r := 0
	var best_e := INF
	for r in range(m):                                # the rotation that moves the tubes least
		var e := 0.0
		for j in range(m):
			e += absf(angle_difference(float(ws[j][3]), float(taken[(j + r) % m])))
		if e < best_e:
			best_e = e
			best_r = r
	for j in range(m):
		out[[int(ws[j][0]), int(ws[j][1])]] = float(taken[(j + best_r) % m])
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


func _path(i: int, s: int, pit: Vector3, ang: float) -> PackedVector3Array:
	## v3: socket -> straight out along its diagonal, climbing at SOCK_ANG to the rack (RACK_Y) -> round other bases and
	## pits (filleted) -> its own radial approach -> over the rim into the goo at its own bearing
	var tb: Dictionary = wl._tubes[i]
	var foot := Vector2(tb["x"], tb["z"])
	var cd := corner_dir(s)
	var c2 := Vector2(pit.x, pit.z)
	var dir := Vector2(cos(ang), sin(ang))
	var p0 := foot + cd * (APOTHEM + 0.05)
	var p1 := foot + cd * (APOTHEM + 0.05 + RAMP_RUN + 0.9)   # the angled climb runs straight out of its socket
	var rim := c2 + dir * (WorldLocals.RING_R + 0.9)
	var a := c2 + dir * (WorldLocals.RING_R + 0.9 + ENTRY_RUN)   # its own straight radial approach
	var mid: Array = _steer(p1, a, i, int(tb["id"]), pit, 0)
	var way: Array = _fillet([p0, p1] + mid + [a, rim], RIB_BEND)
	var even: Array = [way[0]]                        # even <= 1.5 m steps: the spline then follows the filleted polyline
	for k in range(1, way.size()):                    # (a short socket leg before a 90 m leg made it loop)
		var q0: Vector2 = way[k - 1]
		var q1: Vector2 = way[k]
		var m := maxi(ceili(q0.distance_to(q1) / 1.5), 1)
		for j in range(1, m + 1):
			even.append(q0.lerp(q1, float(j) / m))
	return _shape(_side_by_side(even), c2, dir, true)


func _shape(way: Array, c2: Vector2, dir: Vector2, tail := true, axis := Vector2.ZERO, levels := false) -> PackedVector3Array:
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
	var haz := _hazards(flat, levels)
	var lvl := PackedFloat32Array()                   # ortho: the level each sample runs on (x legs low, z legs high), eased at corners
	if levels:
		for k in range(flat.size()):
			var tg: Vector2 = (flat[mini(k + 1, flat.size() - 1)] as Vector2) - (flat[maxi(k - 1, 0)] as Vector2)
			lvl.append(FLOOR_RUN_Y if connectors else (RACK_Y if absf(tg.x) >= absf(tg.y) else RACK_Y + ORTHO_LEVEL_STEP))
		var sm := lvl.duplicate()
		for k in range(flat.size()):
			var acc := 0.0
			var cnt := 0
			for j in range(maxi(k - 6, 0), mini(k + 7, flat.size())):
				acc += lvl[j]
				cnt += 1
			sm[k] = acc / float(cnt)
		lvl = sm
	var ys := PackedFloat32Array()
	var base_y := PackedFloat32Array()
	var lifts := PackedFloat32Array()
	var cum := 0.0
	for k in range(flat.size()):
		if k > 0:
			cum += (flat[k] as Vector2).distance_to(flat[k - 1])
		var y := lerpf(SOCK_Y, lvl[k] if levels else RACK_Y, _knee(cum / RAMP_RUN))   # v3: a straight climb at SOCK_ANG out of the socket, eased onto the rack
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
		if axis != Vector2.ZERO:                      # ortho: it dips in along its own axis (axis points away from the pit)
			q = rim_out + axis * (r - (WorldLocals.RING_R + 0.9))
		pts.append(Vector3(q.x, fy + y, q.y))
	return pts


func _place_posts(runs: Array, craters: Array) -> void:
	if connectors:
		posts.clear()
		return                                          # floor-level tubes need no stands
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
		var cum := PackedFloat32Array([0.0])
		for k in range(1, pts.size()):
			cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
		var tot := cum[cum.size() - 1]
		var at := RAMP_RUN + 0.6
		var last_at := at
		while at < tot - 0.9:                         # (the header holds the end)
			var placed := false
			for dd in [0.0, 0.35, -0.35, 0.7, -0.7, 1.05, -1.05, 1.4, -1.4, 1.75, -1.75, 2.1, -2.1, 2.45, -2.45, 2.8, -2.8, -3.15, -3.5, -3.85, -4.2]:   # (v3: back up to 4.2 m on a crowded floor)
				var q := _at(pts, cum, at + dd)
				if q.y - wl.floor_y - PIPE_R < 0.3:
					break                                 # resting low here (the socket ramp): no stand needed
				if _post_clear(Vector2(q.x, q.z), r, lanes, flat, craters):
					posts.append([r, Vector3(q.x, wl.floor_y, q.z), q.y - PIPE_R + 0.06])
					placed = true
					at = maxf(at + dd + POST_STEP, last_at + 0.7)   # (a stand backed up never stalls the walk)
					break
			if not placed:
				at += 0.7
			last_at = at


static func _knee(t: float) -> float:
	## 0..1 climb share: linear (the straight angled run) to 0.8, eased flat onto the rack by 1.2
	if t <= 0.8:
		return maxf(t, 0.0)
	if t >= 1.2:
		return 1.0
	var u := t - 0.8
	return 0.8 + u - u * u / 0.8


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


func _hazards(flat: Array, levels := false) -> Array:
	## what this tube must go over: [segment a, b (x z), clearance height of the tube's centre, half width]. The Locals'
	## lanes (a Local is 0.64 m tall, 0.78 wide) and the tubes already laid (go over them, resting on them)
	var out := []
	var bb := Rect2(flat[0], Vector2.ZERO)
	for q in flat:
		bb = bb.expand(q)
	bb = bb.grow(2.0)
	if wl.locals != null and not (connectors and wl.locals.walkways_wanted()):   # walkways: the tubes pass UNDER the Locals' lanes (Daniele 2026-11-11), never over
		for fk in wl.locals.feeds:
			var path: Array = wl.locals.feeds[fk]["path"]
			for k in range(1, path.size()):
				var a: Vector2 = path[k - 1]
				var b: Vector2 = path[k]
				if _meets(flat, a, b, 0.45 + PIPE_R + 0.1, bb):
					out.append([a, b, LANE_CLEAR, 0.45])
	for run in _laid:
		if levels:
			continue                                      # ortho: tube crossings are settled by the two levels, not by bridges
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
		var rad := PIPE_R
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
						var w: Dictionary = weights[int(c["pits"][k])]   # v3: each tube feeds from its own pit
						w[n["owner"]] = int(w.get(n["owner"], 0)) + 1
			var px := Color(col.r, col.g, col.b, fill)
			if _state.get_pixel(int(slots[k]), 0) != px:
				_state.set_pixel(int(slots[k]), 0, px)
				changed = true
			var b := Color(bp if live and k >= full_n and k < want_n else -1.0, 0, 0, 0)   # v2: building -> hologram
			if _state.get_pixel(int(slots[k]), 1) != b:
				_state.set_pixel(int(slots[k]), 1, b)
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
		var o := str(wl.sim.nodes[wl._tubes[i]["id"]]["owner"])
		for t in range(mini(int(c["n"]), (c.get("pits", []) as Array).size())):
			if int(c["pits"][t]) == k:                # v3: one tube per pit at most
				out[o] = int(out.get(o, 0)) + 1
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


static func _socket(vs: PackedVector3Array, ns: PackedVector3Array, cs: PackedColorArray, c: Vector3, flat_out: Vector3, side: Vector3) -> void:
	## v3: the coupling's axis is tilted SOCK_ANG up (the tube leaves it climbing to the rack); it starts inside the wall
	var out := flat_out * cos(SOCK_ANG) + Vector3.UP * sin(SOCK_ANG)
	var up := Vector3.UP * cos(SOCK_ANG) - flat_out * sin(SOCK_ANG)
	var back := -SOCK_R * sin(SOCK_ANG) - 0.04
	var n := 10
	var ring := func(r: float, d: float, k: int) -> Vector3:
		var a := TAU * k / n
		return c + (side * cos(a) + up * sin(a)) * r + out * d
	for k in range(n):
		var a := TAU * (k + 0.5) / n
		var rad := side * cos(a) + up * sin(a)
		_quad(vs, ns, cs, ring.call(SOCK_R, back, k), ring.call(SOCK_R, back, k + 1), ring.call(SOCK_R, SOCK_D, k + 1),
				ring.call(SOCK_R, SOCK_D, k), STEEL, rad)
		_quad(vs, ns, cs, ring.call(SOCK_RI, back, k), ring.call(SOCK_RI, back, k + 1), ring.call(SOCK_RI, SOCK_D, k + 1),
				ring.call(SOCK_RI, SOCK_D, k), STEEL_D, -rad)
		_quad(vs, ns, cs, ring.call(SOCK_RI, SOCK_D, k), ring.call(SOCK_RI, SOCK_D, k + 1), ring.call(SOCK_R, SOCK_D, k + 1),
				ring.call(SOCK_R, SOCK_D, k), STEEL_L, out)
		_tri(vs, ns, cs, c + out * 0.012, ring.call(SOCK_RI, 0.012, k), ring.call(SOCK_RI, 0.012, k + 1), RECESS, out)
