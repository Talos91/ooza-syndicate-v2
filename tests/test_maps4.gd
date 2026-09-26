extends SceneTree
## Maps 4.x check (maps4/ holds maps 4.1):  Godot --headless --path . --script res://tests/test_maps4.gd
## Exit code 0 = all passed. For every map of the pool:
## - layout (re-checked here in game coordinates, independently of the Blender builder): deck edges
##   at least 0.3 m apart wherever two decks are at the same height, no deck over a foreign platform
##   or plaza unless it is raised, no piers that overlap, piers within 100 degrees (kit: 80, clamped;
##   steeper exits are reported), pocket docks
##   (maps 4.0) straight on the socket -> node line with no piers, the builder's own verification is
##   clean, the plaza GLB has every plate and every plaza pier (docks have none);
## - invariants Sim relies on: node ids are 0..N-1 in array order, one edge per node pair;
## - seats: every mode the map lists has its seats, the right count and (team modes) the right teams;
## - Last Stand (Daniele, Alpha 17): waves drop whole rings in the method's order, the order's last
##   ring never falls, a relay falls only once every ring it links to has fallen, and after every
##   wave the surviving map is one connected piece over fixed decks and plaza links; 0.18.7: the drops
##   cycle the starting corners from a seeded random one (opposite next), in every mode and method;
## - heights: a path over a raised deck climbs to it, and lines only meet on the same height.

const DECK_HW := 1.74                   # real deck half-width (builder D_PHYS)
const GAP := 0.3
const CLEAR_H := 3.5
const STEP := 0.75
const PLAYERS := {"1v1": 2, "2v2": 4, "3v3": 6, "2v2v2": 6, "FFA3": 3, "FFA4": 4, "FFA5": 5}
const TEAMS := {"2v2": [2, 2], "3v3": [3, 3], "2v2v2": [2, 2, 2]}

var failures := 0
var checks := 0


func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		print("FAIL  " + what)
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _z(g: Dictionary, s: float) -> float:
	var h: float = g["h"]
	if h == 0.0:
		return 0.0
	var L: float = g["L"]
	var p0: float = g["p0"]
	var p1: float = g["p1"]
	var r0: float = g["r0"]
	var r1: float = g["r1"]
	if s <= p0 or s >= L - p1:
		return 0.0
	if s < p0 + r0:
		return h * (s - p0) / r0
	if s > L - p1 - r1:
		return h * (L - p1 - s) / r1
	return h


func _layout(m: Dictionary, path: String) -> void:
	var code: String = m["code"]
	var lay: Dictionary = m["layout"]
	var v: Dictionary = lay["verify"]
	var debug: bool = m.get("group", "") == "debug"   # D-04 meets two retract half-decks at one pier on purpose
	check((debug or (int(v["clashes"]) == 0 and int(v["over_platform"]) == 0)) and int(v["short"]) == 0 and int(v["ledge_hits"]) == 0,
			"%s: the builder's verification is clean %s" % [code, str(v)])
	var geo: Array = lay["edges"]
	var decks := []
	var steep := 0                                    # maps 4.0 ring nodes: exits spread past the kit's 80 degrees
	for k in range(geo.size()):
		var g: Dictionary = geo[k]
		var A := Vector2(g["A"][0], g["A"][1])
		var B := Vector2(g["B"][0], g["B"][1])
		decks.append({"A": A, "u": (B - A).normalized(), "L": float(g["L"]), "g": g, "e": m["edges"][k]})
		if g.get("dock", false):                      # maps 4.0 pocket dock: no piers, straight at the node
			var e: Dictionary = m["edges"][k]
			var plaza_end: int = int(e["from"]) if bool(g["plaza0"]) else int(e["to"])
			var node_end: int = int(e["to"]) if bool(g["plaza0"]) else int(e["from"])
			var sock := Vector2(lay["nodes"][str(plaza_end)][0], lay["nodes"][str(plaza_end)][1])
			var cen := Vector2(lay["nodes"][str(node_end)][0], lay["nodes"][str(node_end)][1])
			var rim := B if bool(g["plaza0"]) else A
			var lip := A if bool(g["plaza0"]) else B
			check(float(g["p0"]) == 0.0 and float(g["p1"]) == 0.0 and float(g["h"]) == 0.0, "%s: dock %d has no piers and stays on the ground" % [code, k])
			check(absf(rim.distance_to(cen) - Rules.R) < 0.05 and (float(g["L"]) < 0.01 or (lip - sock).normalized().dot((rim - sock).normalized()) > 0.9999),
					"%s: dock %d runs straight from the plaza to the node's rim" % [code, k])
		else:
			check(float(g["L"]) - float(g["p0"]) - float(g["p1"]) >= 0.0, "%s: deck %d leaves room for its piers" % [code, k])
			if float(g["h"]) == 0.0:                   # maps 4.1: a ground deck keeps its tier's honest length (Alpha 18:
				var honest: float = Rules.S * {"S": 1, "M": 2, "L": 3}[m["edges"][k]["tier"]]   # maps 4.0 ran 3.6x long)
				var off := absf(float(g["L"]) - float(g["p0"]) - float(g["p1"]) - honest)
				check(debug or off <= 2.5, "%s: deck %d is its tier's honest %.0f m (off by %.1f m)" % [code, k, honest, off])
				if off > 1.5:
					print("WARN  %s: deck %d is %.1f m off its honest %.0f m (pack drawing)" % [code, k, off, honest])
		var lean := maxf(absf(float(g["lean0"])), absf(float(g["lean1"])))
		check(lean <= 100.0, "%s: deck %d piers within 100 degrees (the kit clamps to 80)" % [code, k])
		if lean > 82.5:
			steep += 1
	if steep > 0:
		print("WARN  %s: %d deck(s) with piers past the kit's 80 degrees (clamped; pack layout)" % [code, steep])
	# deck against deck at full width, same height only
	var clashes := 0
	for i in range(decks.size()):
		var di: Dictionary = decks[i]
		for j in range(i + 1, decks.size()):
			var dj: Dictionary = decks[j]
			var n := maxi(2, int(di["L"] / STEP))
			for t in range(n + 1):
				var s: float = di["L"] * t / n
				var p: Vector2 = di["A"] + di["u"] * s
				var sj := clampf((p - dj["A"]).dot(dj["u"]), 0.0, dj["L"])
				var q: Vector2 = dj["A"] + dj["u"] * sj
				if p.distance_to(q) < 2.0 * DECK_HW + GAP and absf(_z(di["g"], s) - _z(dj["g"], sj)) < CLEAR_H:
					clashes += 1
					break
	if debug:                                         # debug maps: known planner leftovers are reported, not hidden
		check(clashes == int(v["clashes"]), "%s: game sees the builder's %d clash(es) (%d)" % [code, int(v["clashes"]), clashes])
		if clashes > 0:
			print("WARN  %s: %d deck clash(es) the approved planner leaves (debug map)" % [code, clashes])
	else:
		check(clashes == 0, "%s: no two decks at the same height closer than %.1f m (%d)" % [code, GAP, clashes])
	# deck against foreign platforms and plazas
	var over := 0
	for d in decks:
		var e: Dictionary = d["e"]
		var mine := [int(e["from"]), int(e["to"])]
		var mine_plazas := []
		for nd in m["nodes"]:
			if int(nd["id"]) in mine and nd.get("plaza") != null:
				mine_plazas.append(int(nd["plaza"]))
		var n := maxi(2, int(d["L"] / STEP))
		for t in range(n + 1):
			var s: float = d["L"] * t / n
			var p: Vector2 = d["A"] + d["u"] * s
			var z := _z(d["g"], s)
			for nd in m["nodes"]:
				if int(nd["id"]) in mine or nd.get("plaza") != null:
					continue
				var key := str(int(nd["id"]))
				var c := Vector2(lay["nodes"][key][0], lay["nodes"][key][1])
				if p.distance_to(c) < Rules.R + DECK_HW and z < CLEAR_H:
					over += 1
			for pid in lay["plazas"]:
				if int(pid) in mine_plazas:
					continue
				var pl: Dictionary = lay["plazas"][pid]
				var q := (p - Vector2(pl["c"][0], pl["c"][1])).rotated(-float(pl["phi"]))
				if pow(q.x / (float(pl["ax"]) + DECK_HW), 2) + pow(q.y / (float(pl["ay"]) + DECK_HW), 2) < 1.0 and z < CLEAR_H:
					over += 1
	if debug and int(v["over_platform"]) > 0:
		check(over > 0, "%s: game sees the builder's deck over a platform" % code)
		print("WARN  %s: %d deck(s) over a platform the planner leaves (debug map)" % [code, int(v["over_platform"])])
	else:
		check(over == 0, "%s: no deck crosses a foreign platform or plaza unless raised (%d samples)" % [code, over])
	# the plaza GLB carries every plate and every plaza-end pier
	if not (lay["plazas"] as Dictionary).is_empty():
		check(ResourceLoader.exists(lay["glb"]), "%s: plaza scene %s exists" % [code, lay["glb"]])
		if ResourceLoader.exists(lay["glb"]):
			var inst: Node = (load(lay["glb"]) as PackedScene).instantiate()
			var names := {}
			for c in inst.find_children("*", "", true, false):
				names[String(c.name)] = true
			inst.free()
			for pid in lay["plazas"]:
				check(names.has("Plaza_%s" % pid), "%s: plaza plate %s in the scene" % [code, pid])
			for k in range(geo.size()):
				for end in range(2):
					if bool(geo[k]["plaza%d" % end]) and not geo[k].get("dock", false):
						check(names.has("PlazaPier_%d_%d" % [k, end]), "%s: plaza pier %d.%d in the scene" % [code, k, end])


func _seats(m: Dictionary) -> void:
	var code: String = m["code"]
	for md in m["modes"]:
		var list: Array = m["seats"].get(md, [])
		check(not list.is_empty(), "%s: seats for %s" % [code, md])
		check(list.size() == PLAYERS.get(md, -1), "%s: %s has %d seats (want %d)" % [code, md, list.size(), PLAYERS.get(md, -1)])
		var ids := {}
		for s in list:
			ids[int(s["node"])] = true
		check(ids.size() == list.size(), "%s: %s seats on distinct nodes" % [code, md])
		if TEAMS.has(md):
			var per := {}
			for s in list:
				if s.get("team") != null:
					per[int(s["team"])] = per.get(int(s["team"]), 0) + 1
			var sizes := per.values()
			sizes.sort()
			check(sizes == TEAMS[md], "%s: %s teams %s" % [code, md, str(sizes)])


func _invariants(m: Dictionary) -> void:
	## What Sim silently assumes: nodes[id] is node id (ids 0..N-1 in array order), and one edge per
	## node pair (find_route picks a link, the path builder re-resolves the pair's first edge).
	var code: String = m["code"]
	for i in range(m["nodes"].size()):
		check(int(m["nodes"][i]["id"]) == i, "%s: node ids are 0..N-1 in array order (index %d has id %s)" % [code, i, str(m["nodes"][i]["id"])])
	var md: String = m["modes"][0]
	var seats := {}
	for s in m["seats"][md]:
		seats[int(s["node"])] = s["seat"]
	var sim := Sim.new()
	sim.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "ember", "C": "vex", "D": "solar", "E": "bloom", "F": "null"}, 1)
	for id in sim.adj:
		var seen := {}
		for link in sim.adj[id]:
			check(not seen.has(link[0]), "%s: one edge per node pair, plaza links included (%d-%d)" % [code, id, link[0]])
			seen[link[0]] = true


func _connected(sim: Sim, gone: Dictionary) -> bool:
	var start := -1
	for n in sim.nodes:
		if not gone.get(n["id"], false):
			start = n["id"]
			break
	if start < 0:
		return true
	var seen := {start: true}
	var open := [start]
	while not open.is_empty():
		var cur: int = open.pop_front()
		for link in sim.adj[cur]:
			var e: Dictionary = sim.edges[link[1]]
			if e["state"] != "" or e["retracts"] or gone.get(link[0], false) or seen.has(link[0]):
				continue
			seen[link[0]] = true
			open.append(link[0])
	for n in sim.nodes:
		if not gone.get(n["id"], false) and not seen.has(n["id"]):
			return false
	return true


func _last_stand(m: Dictionary) -> void:
	var code: String = m["code"]
	var md: String = m["modes"][0]
	var seats := {}
	for s in m["seats"][md]:
		seats[int(s["node"])] = s["seat"]
	var methods: Array = m["lastStand"].get("methods", [])
	if methods.is_empty():                            # tutorials: the pack gives them no Last Stand
		var s0 := Sim.new()
		s0.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "ember", "C": "vex", "D": "solar", "E": "bloom", "F": "null"}, 1)
		while s0.time < Rules.LAST_STAND_TIME + 5.0:
			s0.step(0.5)
		check(not s0.last_stand_active, "%s: a map without Last Stand methods never collapses" % code)
		return
	for method in methods:
		var orders: Array = [m["lastStand"]["orders"][method]] if method != "chaos" else m["lastStand"]["orders"]["chaos"]
		for oi in range(orders.size()):
			var order: Array = orders[oi]
			var sim := Sim.new()
			sim.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "ember", "C": "vex", "D": "solar", "E": "bloom", "F": "null"}, 1)
			sim._map_last_stand = {"methods": [method], "orders": {method: order if method != "chaos" else [order]}}
			sim._ring_orders = sim._map_last_stand["orders"]
			sim._start_rings()
			var keep_ring: int = int(order[-1])
			var fallen_rings := {}
			var gone := {}
			var ok_rings := true
			var ok_relays := true
			var ok_conn := true
			var k := 0
			var ok_steps := true
			for w in sim.last_stand_waves:
				sim.collapsed = gone.duplicate()             # 0.18.4: a ring falls platform by platform - every
				var step_gone := gone.duplicate()           # single drop keeps the rest connected
				var seq: Array = sim._drop_sequence(w)
				if seq.size() != (w as Array).size():
					ok_steps = false
				for id in seq:
					step_gone[id] = true
					if not _connected(sim, step_gone):
						ok_steps = false
				sim.collapsed = {}
				while k < order.size() - 1 and not (w as Array).any(func(id): return sim.nodes[id]["ring"] == int(order[k]) and sim.nodes[id]["relay"] == ""):
					fallen_rings[int(order[k])] = true      # a ring may have gone entirely with an earlier wave
					k += 1
				if k < order.size() - 1:
					fallen_rings[int(order[k])] = true
					k += 1
				for id in w:
					gone[id] = true
					if sim.last_stand_keep.has(id):
						ok_rings = false
				for id in w:                              # a relay: all its rings gone, or it would be an island
					if sim.nodes[id]["relay"] == "":
						continue
					var waiting := false
					var anchored := false
					for link in sim.adj[id]:
						var nb: Dictionary = sim.nodes[link[0]]
						if not fallen_rings.has(nb["ring"]) and not gone.get(nb["id"], false):
							waiting = true
						var le: Dictionary = sim.edges[link[1]]
						if not gone.get(nb["id"], false) and le["state"] == "" and not le["retracts"]:
							anchored = true
					if waiting and anchored:
						ok_relays = false
				if not _connected(sim, gone):
					ok_conn = false
			var tag := "%s %s#%d" % [code, method, oi]
			check(ok_rings, "%s: the last ring (%d) never falls" % [tag, keep_ring])
			check(ok_relays, "%s: relays fall only after all their rings" % tag)
			check(ok_conn, "%s: the surviving map stays connected after every wave" % tag)
			check(ok_steps, "%s: every single platform drop keeps the rest connected" % tag)
			var survivors := sim.nodes.filter(func(n): return not gone.get(n["id"], false))
			check(not survivors.is_empty() and survivors.all(func(n): return sim.last_stand_keep.has(n["id"]) or n["relay"] != ""),
					"%s: at the end only the last ring (and relays tied to it) remains" % tag)


func _side(sim: Sim, id: int) -> int:
	## The corner (a home in the match's corner cycle) a platform is nearest to; ties go to the earlier corner.
	var best := -1
	var best_d := INF
	for c in sim.last_stand_corners:
		var d := sim._flat_dist(id, c)
		if d < best_d - 0.01:
			best_d = d
			best = c
	return best


func _corners(m: Dictionary) -> void:
	## 0.18.7 (Daniele): the collapse starts at a random starting corner, then the opposite one, then the
	## others, and back - one platform per corner in turn. For every mode, method (and chaos order) and
	## seeds 1..8, the real collapse is run from the reveal to its last drop: (a) every drop keeps the rest
	## connected, (b) two drops in a row lie nearer different corners whenever the ring has platforms
	## near several corners and one on another side could fall safely, (c) the first corner and the first drop are not always the same
	## across the seeds, (d) the collapse ends before the hard end.
	var code: String = m["code"]
	var methods: Array = m["lastStand"].get("methods", [])
	if methods.is_empty():
		return
	for md in m["modes"]:
		var seats := {}
		for s in m["seats"][md]:
			seats[int(s["node"])] = s["seat"]
		for method in methods:
			var orders: Array = [m["lastStand"]["orders"][method]] if method != "chaos" else m["lastStand"]["orders"]["chaos"]
			for oi in range(orders.size()):
				var tag := "%s %s %s#%d" % [code, md, method, oi]
				var starts := {}
				var first_sides := {}
				var first_spread := false
				var ok_conn := true
				var ok_alt := true
				var ok_corners := true
				var alt_miss := ""
				var latest := 0.0
				var drops_any := false
				for seed in range(1, 9):
					var sim := Sim.new()
					sim.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "ember", "C": "vex", "D": "solar", "E": "bloom", "F": "null"}, seed)
					sim._map_last_stand = {"methods": [method], "orders": {method: orders[oi] if method != "chaos" else [orders[oi]]}}
					sim._ring_orders = sim._map_last_stand["orders"]
					sim.time = Rules.LAST_STAND_TIME
					sim._start_rings()
					var homes := sim.homes.values()
					homes.sort()
					var cyc := sim.last_stand_corners.duplicate()
					cyc.sort()
					if cyc != homes:
						ok_corners = false
					if sim.last_stand_corners.size() >= 2:          # the second corner is the one farthest from the first
						var c0: int = sim.last_stand_corners[0]
						for c in sim.last_stand_corners:
							if sim._flat_dist(c0, c) > sim._flat_dist(c0, sim.last_stand_corners[1]) + 0.01:
								ok_corners = false
					if sim.last_stand_waves.is_empty():
						continue
					drops_any = true
					starts[sim.last_stand_corners[0]] = true
					var ring_count := 0
					var seen := {}
					var guard := 0
					while (not sim.last_stand_queue.is_empty() or sim.last_stand_next < sim.last_stand_waves.size()) and guard < 4000:
						guard += 1
						if ring_count < sim.last_stand_next:        # a ring was just warned: its queue is the real order
							ring_count = sim.last_stand_next
							var q: Array = sim.last_stand_queue
							var sides := {}
							for id in q:
								if sim.nodes[id]["relay"] == "":
									sides[_side(sim, id)] = true
							if ring_count == 1 and not q.is_empty():
								first_sides[_side(sim, q[0])] = true
								first_spread = first_spread or sides.size() >= 2
							var down := sim.collapsed.duplicate()
							for i in range(q.size() - 1):            # consecutive drops: another side whenever one can go
								down[q[i]] = true
								if sides.size() < 2 or sim.nodes[q[i + 1]]["relay"] != "" or _side(sim, q[i]) != _side(sim, q[i + 1]):
									continue
								for x in q.slice(i + 1):
									if sim.nodes[x]["relay"] != "" or _side(sim, x) == _side(sim, q[i]):
										continue
									var trial := down.duplicate()
									trial[x] = true
									if _connected(sim, trial):
										ok_alt = false
										alt_miss = "seed %d ring %d: %d then %d, both nearest %d, while %d could go" % [seed, ring_count, q[i], q[i + 1], _side(sim, q[i]), x]
										break
							if q.size() >= 2 and sides.size() >= 2:
								_pairs += 1
								if _side(sim, q[0]) != _side(sim, q[1]):
									_pairs_alt += 1
						sim.time += 0.25
						sim._step_rings(0.25)
						for id in sim.collapsed:
							if not seen.has(id):
								seen[id] = true
								latest = maxf(latest, sim.time)
								if not _connected(sim, sim.collapsed):
									ok_conn = false
				if not drops_any:
					continue
				check(ok_corners, "%s: the corners are the match's homes, the second the farthest from the first" % tag)
				check(ok_conn, "%s: every drop of the corner cycle keeps the rest connected" % tag)
				check(ok_alt, "%s: consecutive drops of a ring alternate corners whenever another side can fall (%s)" % [tag, alt_miss])
				check(starts.size() >= 2, "%s: across seeds 1..8 the collapse does not always start at the same corner %s" % [tag, str(starts.keys())])
				if first_spread:
					check(first_sides.size() >= 2, "%s: across seeds 1..8 the first drop is not always nearest the same corner %s" % [tag, str(first_sides.keys())])
				check(latest < Rules.MATCH_HARD_END, "%s: the collapse ends before the hard end (%.0f s)" % [tag, latest])
				_latest_end = maxf(_latest_end, latest)


var _latest_end := 0.0
var _pairs := 0          # rings (all runs) with platforms near several corners
var _pairs_alt := 0      # ... whose first two drops lie nearer different corners


func _heights() -> void:
	## A raised deck crossing a ground deck: paths follow the height and the two lines never meet.
	for path in MapPool.all():
		var m := MapBuilder.load_map(path)
		var geo: Array = m["layout"]["edges"]
		for i in range(geo.size()):
			if float(geo[i]["h"]) <= 0.0 or m["edges"][i].get("state") != null:
				continue
			var sim := Sim.new()
			var md: String = m["modes"][0]
			var seats := {}
			for s in m["seats"][md]:
				seats[int(s["node"])] = s["seat"]
			sim.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "ember", "C": "vex", "D": "solar", "E": "bloom", "F": "null"}, 1)
			var e: Dictionary = sim.edges[i]
			var top := -INF
			for p in sim.build_path([e["a"], e["b"]])["pts"]:
				top = maxf(top, (p as Vector3).y)
			check(absf(top - float(geo[i]["h"])) < 0.01, "%s: the path over deck %d climbs to %+.0f m" % [m["code"], i, float(geo[i]["h"])])
			check(Sim.level_of(Vector3(0, float(geo[i]["h"]), 0)) != Sim.level_of(Vector3.ZERO), "%s: a raised line is on another level" % m["code"])
			return


func _drop_timing() -> void:
	## 0.18.4: after the ring's 10 s warning its platforms drop one at a time, LAST_STAND_DROP_GAP apart.
	for path in MapPool.all():
		var m := MapBuilder.load_map(path)
		if (m["lastStand"].get("methods", []) as Array).is_empty():
			continue
		var md: String = m["modes"][0]
		var seats := {}
		for st in m["seats"][md]:
			seats[int(st["node"])] = st["seat"]
		var sim := Sim.new()
		sim.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "ember", "C": "vex", "D": "solar", "E": "bloom", "F": "null"}, 1)
		sim._start_rings()
		if sim.last_stand_waves.is_empty() or (sim.last_stand_waves[0] as Array).size() < 2:
			continue
		var warned_at := sim.time
		var drops := []
		var seen := {}
		while sim.time < warned_at + 60.0 and drops.size() < 3:
			sim._step_rings(0.1)
			sim.time += 0.1
			for id in sim.collapsed:
				if not seen.has(id):
					seen[id] = true
					drops.append([id, sim.time])
		check(drops.size() >= 2 and absf(float(drops[0][1]) - warned_at - Rules.LAST_STAND_WARNING) < 0.25,
				"%s: the ring's first platform drops after the %d s warning" % [m["code"], int(Rules.LAST_STAND_WARNING)])
		if drops.size() >= 2:
			check(absf(float(drops[1][1]) - float(drops[0][1]) - Rules.LAST_STAND_DROP_GAP) < 0.25,
					"%s: the next platform drops %d s later, not with it (%.1f s)" % [m["code"], int(Rules.LAST_STAND_DROP_GAP), float(drops[1][1]) - float(drops[0][1])])
		return


func _run() -> void:
	var pool := MapPool.all()
	var baked := Array(DirAccess.get_files_at(MapPool.DIR)).filter(func(f): return f.trim_suffix(".remap").ends_with(".json")).size()
	check(pool.size() == baked - MapPool.WITHHELD.size() and pool.size() > 0, "every baked map is in the pool except the withheld (%d of %d)" % [pool.size(), baked])
	for path in pool:
		var m := MapBuilder.load_map(path)
		check(m.has("layout"), "%s: baked layout present" % path)
		if not m.has("layout"):
			continue
		_layout(m, path)
		_invariants(m)
		_seats(m)
		_last_stand(m)
		_corners(m)
	print("Last Stand corner cycle: the latest collapse ends at %d:%02d; %d of %d multi-corner rings open on two sides (the rest: only one side could fall safely)" % [
			int(_latest_end) / 60, int(_latest_end) % 60, _pairs_alt, _pairs])
	_heights()
	_drop_timing()
	print("\n%d checks - %s" % [checks, "ALL PASSED (0 failed)" if failures == 0 else "%d FAILED" % failures])
	quit(1 if failures > 0 else 0)
