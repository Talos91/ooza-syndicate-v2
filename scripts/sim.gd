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
var fights: Array = []               # [horde id, horde id] contact pairs (frontline or rear)
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
		"L": path["cum"][-1], "s": 0.0, "state": "move", "speed": 1.0, "blocked": false,
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
		if h["state"] == "move" and not h.get("blocked", false):
			var fast_here: bool = sample(h, h["s"])[2]
			h["s"] += Rules.DECK_SPEED * h.get("speed", 1.0) * (Rules.NODE_SPEED_MULT if fast_here else 1.0) * dt
			if h["s"] >= h["L"]:
				h["s"] = h["L"]
				h["state"] = "absorb"
	_detect_contacts()
	var dead := []
	for pair in fights:                               # every contact pair trades losses
		var a := _horde(pair[0])
		var b := _horde(pair[1])
		if a.is_empty() or b.is_empty():
			continue
		a["pending_loss"] = a.get("pending_loss", 0.0) + (Rules.FIGHT_RATE_BASE + Rules.FIGHT_RATE_K * b["units"]) * dt
		b["pending_loss"] = b.get("pending_loss", 0.0) + (Rules.FIGHT_RATE_BASE + Rules.FIGHT_RATE_K * a["units"]) * dt
	for h in hordes:
		if h["state"] == "absorb":
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
	var alive := {}
	for h in hordes:
		alive[h["id"]] = true
	fights = fights.filter(func(p): return alive.has(p[0]) and alive.has(p[1]))
	var fighting := {}
	for p in fights:
		fighting[p[0]] = true
		fighting[p[1]] = true
	for h in hordes:                                  # no contact left: march on
		if h["state"] == "fight" and not fighting.has(h["id"]):
			h["state"] = "move"
	_check_end()


static func chain_length(h: Dictionary) -> float:
	## How much deck a horde occupies behind its head (matches HordeView's patch count).
	var n := clampi(ceili(h["units"] / Rules.UNITS_PER_PATCH), 1, Rules.MAX_PATCHES)
	return (n - 1) * Rules.PATCH_SPACING + 1.0


func _detect_contacts() -> void:
	## Hordes are blobs that block the deck, so contact happens from any direction (Daniele):
	##  enemy ahead, coming toward us  -> frontline
	##  enemy ahead, going our way     -> we hit its rear (it may be stuck, slower or queued)
	##  friend ahead, going our way    -> we queue at its tail (no passing through)
	##  friend coming toward us        -> squeeze past
	## A horde can be in several fights at once (front and rear). Same combat rates for a rear
	## attack - a rear-attack bonus is an open question.
	var occ := {}                                     # edge -> [{h, head, tail, dir, on, len}]
	for h in hordes:
		h["blocked"] = false
		if h["state"] == "absorb":
			continue
		var head_s: float = h["s"]
		var tail_s: float = head_s - chain_length(h)
		for sp in h["spans"]:
			if head_s < sp["s0"] or tail_s > sp["s1"]:
				continue
			var span_len: float = maxf(sp["s1"] - sp["s0"], 0.001)
			var dir := 1 if sp["forward"] else -1
			var fh := clampf((head_s - sp["s0"]) / span_len, 0.0, 1.0)
			var ft := clampf((tail_s - sp["s0"]) / span_len, 0.0, 1.0)
			if not occ.has(sp["edge"]):
				occ[sp["edge"]] = []
			occ[sp["edge"]].append({                  # edge coordinate: 0 at edge.a, 1 at edge.b
				"h": h, "dir": dir, "len": span_len, "on": head_s <= sp["s1"],
				"head": fh if dir == 1 else 1.0 - fh, "tail": ft if dir == 1 else 1.0 - ft,
			})
	for edge in occ:
		var list: Array = occ[edge]
		for x in list:
			if not x["on"]:
				continue                              # contact is made by a head on this deck
			var eps: float = Rules.FRONT_CONTACT / x["len"]
			for y in list:
				if x["h"] == y["h"]:
					continue
				var lo := minf(y["head"], y["tail"])
				var hi := maxf(y["head"], y["tail"])
				var near: float = lo if x["dir"] == 1 else hi
				var far: float = hi if x["dir"] == 1 else lo
				var gap: float = (near - x["head"]) * x["dir"]
				var ahead: float = (far - x["head"]) * x["dir"]
				if ahead <= 0.0 or gap > eps:
					continue
				if x["h"]["owner"] != y["h"]["owner"]:
					_engage(x["h"], y["h"], "frontline" if x["dir"] != y["dir"] else "rear")
				elif x["dir"] == y["dir"]:
					x["h"]["blocked"] = true


func _engage(a: Dictionary, b: Dictionary, kind: String) -> void:
	var pair := [mini(a["id"], b["id"]), maxi(a["id"], b["id"])]
	if pair in fights:
		return
	fights.append(pair)
	a["state"] = "fight"
	b["state"] = "fight"
	events.append({"t": time, "type": kind, "seats": [a["owner"], b["owner"]]})


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
