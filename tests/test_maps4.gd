extends SceneTree
## Maps 4.0 check:  Godot --headless --path . --script res://tests/test_maps4.gd
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
##   wave the surviving map is one connected piece over fixed decks and plaza links;
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
			for w in sim.last_stand_waves:
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
			var survivors := sim.nodes.filter(func(n): return not gone.get(n["id"], false))
			check(not survivors.is_empty() and survivors.all(func(n): return sim.last_stand_keep.has(n["id"]) or n["relay"] != ""),
					"%s: at the end only the last ring (and relays tied to it) remains" % tag)


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


func _run() -> void:
	var pool := MapPool.all()
	check(pool.size() == 109 - MapPool.WITHHELD.size(), "maps 4.0: 100 maps + 9 debug maps in the pool, minus the withheld (%d)" % pool.size())
	for path in pool:
		var m := MapBuilder.load_map(path)
		check(m.has("layout"), "%s: baked layout present" % path)
		if not m.has("layout"):
			continue
		_layout(m, path)
		_invariants(m)
		_seats(m)
		_last_stand(m)
	_heights()
	print("\n%d checks - %s" % [checks, "ALL PASSED (0 failed)" if failures == 0 else "%d FAILED" % failures])
	quit(1 if failures > 0 else 0)
