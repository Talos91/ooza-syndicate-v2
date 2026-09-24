class_name Sim
extends RefCounted
## Game state and rules, no visuals. Deterministic for a given sequence of sends and time steps.
## Rules: Docs/Game Design/Ooze Syndicate 2.0/01 Rules/GAME-RULES.md (§5 hordes, §6 nodes, §7 bridges).

signal captured(node_id: int, new_owner: String, old_owner: String)
signal horde_spawned(h: Dictionary)
signal horde_removed(h: Dictionary)
signal finished(winner: String)

var nodes: Array = []          # {id, pos, owner, units, tier, category, center}
var edges: Array = []          # {a, b, modules}
var adj: Dictionary = {}       # node id -> Array of [neighbour id, edge index]
var hordes: Array = []         # see _new_horde()
var factions: Dictionary = {}  # seat -> faction
var time := 0.0
var over := false
var winner := ""
var events: Array = []         # telemetry: {t, type, ...}
var combat_losses: Dictionary = {}   # seat -> units lost in frontline combat
var fall_losses: Dictionary = {}     # seat -> units lost to falls (relays come later)
var _next_id := 1


func setup(map: Dictionary, positions: Dictionary, seats: Dictionary, seat_factions: Dictionary) -> void:
	factions = seat_factions
	for n in map["nodes"]:
		var id: int = n["id"]
		var owner: String = seats.get(id, "")
		var tier := Rules.HOME_TIER if owner != "" else (3 if n["category"] == "final" or n["center"] else 1)
		nodes.append({
			"id": id, "pos": positions[id], "owner": owner, "tier": tier,
			"units": float(Rules.HOME_UNITS if owner != "" else Rules.NEUTRAL_UNITS[tier]),
			"category": n["category"], "center": n["center"],
		})
		adj[id] = []
	for e in map["edges"]:
		if e.get("state") != null and e["state"] != "":
			continue                                  # relay-controlled decks: not in this slice
		var mods: int = {"S": 1, "M": 2, "L": 3}[e["tier"]]
		edges.append({"a": int(e["from"]), "b": int(e["to"]), "modules": mods})
		var i := edges.size() - 1
		adj[int(e["from"])].append([int(e["to"]), i])
		adj[int(e["to"])].append([int(e["from"]), i])


# ------------------------------------------------------------------ orders
func send(from_id: int, to_id: int, fraction: float) -> Dictionary:
	## Order a send; returns the new horde or {} if the order is not possible.
	var src: Dictionary = nodes[from_id]
	if over or from_id == to_id or src["owner"] == "":
		return {}
	var count := floorf(src["units"] * fraction)
	if count < 1.0:
		return {}
	var route := find_route(from_id, to_id)
	if route.size() < 2:
		return {}
	src["units"] -= count
	var h := _new_horde(src["owner"], count, route)
	hordes.append(h)
	events.append({"t": time, "type": "send", "seat": h["owner"], "from": from_id, "to": to_id, "units": count})
	horde_spawned.emit(h)
	return h


func find_route(from_id: int, to_id: int) -> Array:
	## Fastest route by deck travel time (Dijkstra; each node crossed costs a little).
	var dist := {from_id: 0.0}
	var prev := {}
	var open := [from_id]
	while not open.is_empty():
		open.sort_custom(func(x, y): return dist[x] < dist[y])
		var cur: int = open.pop_front()
		if cur == to_id:
			break
		for link in adj[cur]:
			var nb: int = link[0]
			var cost: float = dist[cur] + edges[link[1]]["modules"] * Rules.MODULE_SECONDS + 1.0
			if not dist.has(nb) or cost < dist[nb]:
				dist[nb] = cost
				prev[nb] = cur
				if nb not in open:
					open.append(nb)
	if not dist.has(to_id):
		return []
	var route := [to_id]
	while route[0] != from_id:
		route.push_front(prev[route[0]])
	return route


# ------------------------------------------------------------------ path geometry
func _new_horde(owner: String, units: float, route: Array) -> Dictionary:
	var path := build_path(route)
	var h := {
		"id": _next_id, "owner": owner, "faction": factions.get(owner, "null"), "units": units,
		"start_units": units, "route": route, "target": route[-1],
		"pts": path["pts"], "cum": path["cum"], "fast": path["fast"], "spans": path["spans"],
		"L": path["cum"][-1], "s": 0.0, "state": "move", "foe": 0,
	}
	_next_id += 1
	return h


func build_path(route: Array) -> Dictionary:
	## Centre line a horde follows: out of the tank bottoms, along each deck, AROUND the centre
	## structure of every node it passes, and in through the destination's door.
	var pts := []                                   # plain Arrays: lambdas capture them by reference
	var fast := []                                  # 1 = node/pier segment (fast), 0 = deck
	var spans := []                                 # {edge, s0, s1, forward}
	var add := func(p: Vector3, is_fast: bool) -> void:
		pts.append(p)
		fast.append(1 if is_fast else 0)
	var a: Dictionary = nodes[route[0]]
	var d := (nodes[route[1]]["pos"] - a["pos"]).normalized() as Vector3
	add.call(a["pos"] + d * Rules.EXIT_R, true)
	add.call(a["pos"] + d * (Rules.R - 0.5), true)
	for i in range(route.size() - 1):
		a = nodes[route[i]]
		var b: Dictionary = nodes[route[i + 1]]
		d = (b["pos"] - a["pos"]).normalized()
		add.call(a["pos"] + d * (Rules.R + Rules.PIER), false)
		var s0 := _length(pts)
		add.call(b["pos"] - d * (Rules.R + Rules.PIER), true)
		var ei := _edge_index(route[i], route[i + 1])
		spans.append({"edge": ei, "s0": s0, "s1": _length(pts), "forward": edges[ei]["a"] == route[i]})
		add.call(b["pos"] - d * (Rules.R - 0.5), true)
		var a_in := atan2(-d.z, -d.x)               # direction from b's centre back toward a
		var a_out: float
		if i + 1 < route.size() - 1:
			var d2 := (nodes[route[i + 2]]["pos"] - b["pos"]).normalized() as Vector3
			a_out = atan2(d2.z, d2.x)
			for p in _arc(b["pos"], a_in, a_out, Rules.ARC_R):
				add.call(p, true)
			add.call(b["pos"] + d2 * (Rules.R - 0.5), true)
		else:
			var door: Vector3 = b["pos"] + Rules.DOOR
			a_out = atan2(Rules.DOOR.z, Rules.DOOR.x)
			for p in _arc(b["pos"], a_in, a_out, Rules.ARC_R):
				add.call(p, true)
			add.call(door + Vector3(0, 0, 0.9), true)
			add.call(door, true)
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + (pts[k] as Vector3).distance_to(pts[k - 1]))
	return {"pts": PackedVector3Array(pts), "cum": cum, "fast": PackedByteArray(fast), "spans": spans}


func _arc(c: Vector3, a0: float, a1: float, r: float) -> Array:
	var delta := wrapf(a1 - a0, -PI, PI)
	var steps := maxi(2, int(absf(delta) / deg_to_rad(12.0)))
	var out := []
	for k in range(steps + 1):
		var a := a0 + delta * k / steps
		out.append(c + Vector3(cos(a), 0.0, sin(a)) * r)
	return out


func _length(pts: Array) -> float:
	var total := 0.0
	for k in range(1, pts.size()):
		total += (pts[k] as Vector3).distance_to(pts[k - 1])
	return total


func _edge_index(x: int, y: int) -> int:
	for link in adj[x]:
		if link[0] == y:
			return link[1]
	return -1


static func sample(h: Dictionary, s: float) -> Array:
	## [position, unit tangent, is_fast] at arc length s along a horde's path.
	var cum: PackedFloat32Array = h["cum"]
	var pts: PackedVector3Array = h["pts"]
	s = clampf(s, 0.0, cum[-1])
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := maxf(cum[hi] - cum[lo], 0.0001)
	var t := (s - cum[lo]) / seg
	return [pts[lo].lerp(pts[hi], t), (pts[hi] - pts[lo]).normalized(), h["fast"][lo] == 1]


# ------------------------------------------------------------------ simulation step
func step(dt: float) -> void:
	if over:
		return
	time += dt
	for n in nodes:                                   # production, up to the vat cap
		if n["owner"] != "" and n["units"] < Rules.CAPS[n["tier"]]:
			n["units"] = minf(Rules.CAPS[n["tier"]], n["units"] + Rules.PROD[n["tier"]] * dt)
	for h in hordes:
		if h["state"] == "move":
			var fast_here: bool = sample(h, h["s"])[2]
			h["s"] += Rules.DECK_SPEED * (Rules.NODE_SPEED_MULT if fast_here else 1.0) * dt
			if h["s"] >= h["L"]:
				h["s"] = h["L"]
				h["state"] = "absorb"
	_detect_frontlines()
	var dead := []
	for h in hordes:
		if h["state"] == "fight":
			var foe := _horde(h["foe"])
			if foe.is_empty():
				h["state"] = "move"
				continue
			var loss: float = (Rules.FIGHT_RATE_BASE + Rules.FIGHT_RATE_K * foe["units"]) * dt
			h["pending_loss"] = h.get("pending_loss", 0.0) + loss
		elif h["state"] == "absorb":
			var rate := Rules.UNITS_PER_PATCH * Rules.DECK_SPEED * Rules.NODE_SPEED_MULT / Rules.PATCH_SPACING
			var x := minf(h["units"], rate * dt)
			h["units"] -= x
			_arrive(nodes[h["target"]], h["owner"], x)
			if h["units"] <= 0.0:
				dead.append(h)
	for h in hordes:                                  # apply combat losses simultaneously
		if h.has("pending_loss"):
			var before: float = h["units"]
			h["units"] = maxf(0.0, h["units"] - h["pending_loss"])
			combat_losses[h["owner"]] = combat_losses.get(h["owner"], 0.0) + before - h["units"]
			h.erase("pending_loss")
			if h["units"] <= 0.0:
				dead.append(h)
				events.append({"t": time, "type": "horde_destroyed", "seat": h["owner"], "units": h["start_units"]})
	for h in dead:
		if h in hordes:
			hordes.erase(h)
			horde_removed.emit(h)
	for h in hordes:                                  # survivors of a finished fight march on
		if h["state"] == "fight" and _horde(h["foe"]).is_empty():
			h["state"] = "move"
			h["foe"] = 0
	_check_end()


func _detect_frontlines() -> void:
	## Opposing hordes whose heads meet on the same deck stop at a frontline and fight (§5).
	for i in range(hordes.size()):
		var a: Dictionary = hordes[i]
		if a["state"] != "move":
			continue
		var ea := _current_span(a)
		if ea.is_empty():
			continue
		for j in range(hordes.size()):
			var b: Dictionary = hordes[j]
			if i == j or b["owner"] == a["owner"] or b["state"] == "absorb":
				continue
			var eb := _current_span(b)
			if eb.is_empty() or eb["edge"] != ea["edge"] or eb["forward"] == ea["forward"]:
				continue
			var pa: Vector3 = sample(a, a["s"])[0]
			var pb: Vector3 = sample(b, b["s"])[0]
			if pa.distance_to(pb) <= Rules.FRONT_CONTACT or _passed(a, b, ea, eb):
				a["state"] = "fight"
				b["state"] = "fight"
				a["foe"] = b["id"]
				b["foe"] = a["id"]
				events.append({"t": time, "type": "frontline", "seats": [a["owner"], b["owner"]]})


func _passed(a: Dictionary, b: Dictionary, ea: Dictionary, eb: Dictionary) -> bool:
	## Heads crossed within one step (both progress fractions along the deck sum past 1).
	var fa: float = (a["s"] - ea["s0"]) / maxf(ea["s1"] - ea["s0"], 0.001)
	var fb: float = (b["s"] - eb["s0"]) / maxf(eb["s1"] - eb["s0"], 0.001)
	return fa + fb >= 1.0


func _current_span(h: Dictionary) -> Dictionary:
	for sp in h["spans"]:
		if h["s"] >= sp["s0"] and h["s"] <= sp["s1"]:
			return sp
	return {}


func _horde(id: int) -> Dictionary:
	for h in hordes:
		if h["id"] == id:
			return h
	return {}


func _arrive(n: Dictionary, owner: String, x: float) -> void:
	## Own node: reinforce. Neutral or enemy: the garrison is beaten down, then the node flips (§5).
	if n["owner"] == owner:
		n["units"] += x
		return
	n["units"] -= x
	if n["units"] < 0.0:
		var old: String = n["owner"]
		n["owner"] = owner
		n["units"] = -n["units"]
		events.append({"t": time, "type": "capture", "node": n["id"], "seat": owner, "from": old})
		captured.emit(n["id"], owner, old)


func _check_end() -> void:
	var alive := {}
	for n in nodes:
		if n["owner"] != "":
			alive[n["owner"]] = true
	for h in hordes:
		alive[h["owner"]] = true
	if alive.size() <= 1 and time > 1.0:
		over = true
		winner = alive.keys()[0] if alive.size() == 1 else ""
		events.append({"t": time, "type": "end", "winner": winner})
		finished.emit(winner)


func seat_strength(seat: String) -> float:
	var total := 0.0
	for n in nodes:
		if n["owner"] == seat:
			total += n["units"]
	for h in hordes:
		if h["owner"] == seat:
			total += h["units"]
	return total
