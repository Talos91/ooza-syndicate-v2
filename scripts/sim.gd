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
var fight_info: Dictionary = {}      # "lo:hi" -> {kind: "frontline"/"rear", attacker: horde id} (for the view)
var relay_groups: Dictionary = {}    # "r"/"s"/"m" -> [sorted state keys]: rudimentary relay cycling
var collapsed: Dictionary = {}       # node id -> true once dropped by the rudimentary Last Stand
var last_stand_active := false
var last_stand_order: Array = []     # node ids, farthest-from-centre first (inward collapse only)
var last_stand_next := 0
var _last_stand_wave_t := 0.0
var _next_id := 1


func setup(map: Dictionary, positions: Dictionary, seats: Dictionary, seat_factions: Dictionary) -> void:
	factions = seat_factions
	for n in map["nodes"]:
		var id: int = n["id"]
		var owner: String = seats.get(id, "")
		# relay hubs have no vat of their own in the design (centreHasNoVat) - the switching/
		# retracting/rotating mechanic itself isn't built yet (BUILD-LOG SS7), so for now a relay
		# node is just a modest neutral waypoint rather than a fortress at the map's centre
		var tier := Rules.HOME_TIER if owner != "" \
				else (3 if (n["category"] == "final" or n["center"]) and n["category"] != "relay" else 1)
		nodes.append({
			"id": id, "pos": positions[id], "owner": owner, "tier": tier,
			"units": float(Rules.HOME_UNITS if owner != "" else Rules.NEUTRAL_UNITS[tier]),
			"category": n["category"], "center": n["center"],
			"streaming": {},        # {hid, remaining}: the one order the door is emitting
			"siege": {},            # seat -> units on the platform fighting the garrison (arrived)
			"siege_dir": {},        # seat -> unit vector from the tower to where they landed
			"transit": {},          # seat -> {"units", "hordes": [Horde]}: passing-through this frame
			"node_loss": {},        # seat -> units/s lost on this platform last step (view)
			"buildable": n.get("buildable", []),   # what the owner may place here (roster JSON)
			"attachment": "",       # "" / "cannon" / "forge" - single tier each for now
			"build_kind": "",       # "" / "vat" / "cannon" / "forge": what build_timer completes
			"build_timer": 0.0,     # seconds left on a vat upgrade or attachment build
			"cannon_cd": 0.0,       # seconds to the node's cannon's next burst
		})
		adj[id] = []
	for e in map["edges"]:
		# RUDIMENTARY relay cycling (Daniele, 2026-09-25): a relay-controlled deck's real behaviour
		# (fixed state order with warning, ride/fall/carry consequences) isn't built - here every
		# distinct state PREFIX on the map (r/rotation, s/switch, m/remote) cycles through its states
		# together every Rules.RELAY_PERIOD seconds, and a `retracts` deck toggles open/closed on
		# the same period, purely so a route can go around a currently-closed deck. Without this
		# every map past Two Piers would have gaps where those decks belong.
		var mods: int = {"S": 1, "M": 2, "L": 3}[e["tier"]]
		var st: String = e["state"] if e.get("state") != null else ""     # JSON stores "state": null
		edges.append({"a": int(e["from"]), "b": int(e["to"]), "modules": mods,
				"state": st, "retracts": e.get("retracts", false)})
		var i := edges.size() - 1
		adj[int(e["from"])].append([int(e["to"]), i])
		adj[int(e["to"])].append([int(e["from"]), i])
		if st != "":
			var prefix := st.substr(0, 1)
			if not relay_groups.has(prefix):
				relay_groups[prefix] = []
			if st not in relay_groups[prefix]:
				relay_groups[prefix].append(st)
	for k in relay_groups:
		(relay_groups[k] as Array).sort()


# ------------------------------------------------------------------ orders
func send(from_id: int, to_id: int, fraction: float) -> Dictionary:
	## Order a send; returns the new horde or {} if the order is not possible.
	## Units leave the vat only as the door emits them into the line (Rules.door_rate); until then
	## they stay in the vat's count and are still the player's to order. A new send takes over the
	## previous order's not-yet-emitted part (Daniele, 2026-09-25).
	var src: Dictionary = nodes[from_id]
	if over or from_id == to_id or src["owner"] == "":
		return {}
	var count := floorf(src["units"] * fraction)
	if count < 1.0:
		return {}
	var route := find_route(from_id, to_id)
	if route.size() < 2:
		return {}
	if not src["streaming"].is_empty():
		_end_streaming(src, "superseded")
	var h := _new_horde(src["owner"], count, route)
	hordes.append(h)
	src["streaming"] = {"hid": h["id"], "remaining": count}
	events.append({"t": time, "type": "send", "seat": h["owner"], "from": from_id, "to": to_id, "units": count})
	horde_spawned.emit(h)
	return h


# ------------------------------------------------------------------ structures (rudimentary)
func upgrade_vat(node_id: int) -> bool:
	## Start a vat upgrade (T1->T2->T3->T4), Rules.BUILD_SECONDS to complete (GAME-RULES sec6).
	## Rudimentary: no unit/resource cost yet (army scale is still an open question).
	var n: Dictionary = nodes[node_id]
	if n["owner"] == "" or n["build_kind"] != "" or n["tier"] >= 4 or not ("vat" in n["buildable"]):
		return false
	n["build_kind"] = "vat"
	n["build_timer"] = Rules.BUILD_SECONDS
	events.append({"t": time, "type": "build_start", "node": node_id, "seat": n["owner"], "kind": "vat"})
	return true


func build_attachment(node_id: int, kind: String) -> bool:
	## Start building a cannon or forge in the node's attachment socket (single tier each, for now;
	## GAME-RULES sec6's swap/cooldown rules and cannon T2/T3 are a follow-up).
	var n: Dictionary = nodes[node_id]
	if n["owner"] == "" or n["build_kind"] != "" or n["attachment"] == kind or not (kind in n["buildable"]):
		return false
	n["build_kind"] = kind
	n["build_timer"] = Rules.BUILD_SECONDS
	events.append({"t": time, "type": "build_start", "node": node_id, "seat": n["owner"], "kind": kind})
	return true


func _step_structures(dt: float) -> void:
	## Vat upgrades and attachment builds complete after Rules.BUILD_SECONDS; a built cannon fires
	## a burst every Rules.CANNON_PERIOD, killing up to Rules.CANNON_KILL units of any enemy horde
	## within Rules.CANNON_RANGE outright (GAME-RULES sec6: "cannon body kills bypass HP" - Alpha
	## 11 precedent). Rudimentary: single tier each, no build/attachment cost yet.
	for n in nodes:
		if n["owner"] == "" or n["build_kind"] == "":
			continue
		n["build_timer"] -= dt
		if n["build_timer"] <= 0.0:
			var kind: String = n["build_kind"]
			n["build_kind"] = ""
			if kind == "vat":
				n["tier"] = mini(n["tier"] + 1, 4)
			else:
				n["attachment"] = kind
			events.append({"t": time, "type": "build_done", "node": n["id"], "seat": n["owner"], "kind": kind})
	for n in nodes:
		if n["owner"] == "" or n["attachment"] != "cannon":
			continue
		n["cannon_cd"] -= dt
		if n["cannon_cd"] > 0.0:
			continue
		n["cannon_cd"] = Rules.CANNON_PERIOD
		var hit := false
		var killed := []
		for h in hordes:
			if h["owner"] == n["owner"] or h["units"] <= 0.0:
				continue                                  # skip friendlies and hordes not out yet
			var p: Vector3 = sample(h, h["s"])[0]
			if (p - (n["pos"] as Vector3)).length() > Rules.CANNON_RANGE:
				continue
			var kill: float = minf(Rules.CANNON_KILL, h["units"])
			h["units"] -= kill
			combat_losses[h["owner"]] = combat_losses.get(h["owner"], 0.0) + kill
			hit = true
			if h["units"] <= 0.0:
				killed.append(h)
		if hit:
			events.append({"t": time, "type": "cannon_burst", "node": n["id"], "seat": n["owner"]})
		for h in killed:
			if h["streaming"]:
				var src: Dictionary = nodes[h["route"][0]]
				if src["streaming"].get("hid", -1) == h["id"]:
					_end_streaming(src, "destroyed")
			if h in hordes:
				hordes.erase(h)
				horde_removed.emit(h)
				events.append({"t": time, "type": "horde_destroyed", "seat": h["owner"], "units": h["start_units"]})


func _forge_mult(seat: String) -> float:
	## A seat with at least one forge deals more and takes less damage everywhere (GAME-RULES
	## sec6: "global bonus to attack and defense for all of its owner's troops"). Folded into one
	## defensive multiplier applied to damage THIS seat receives, for a simpler first pass.
	if seat == "":
		return 1.0
	for n in nodes:
		if n["owner"] == seat and n["attachment"] == "forge":
			return 1.0 - Rules.forge_bonus
	return 1.0


func _edge_open(e: Dictionary) -> bool:
	## Rudimentary relay cycling (see setup()): is this deck currently usable for a NEW route?
	## A horde already committed to a route keeps moving regardless - only fresh pathfinding sees this.
	if e["retracts"]:
		return int(time / Rules.RELAY_PERIOD) % 2 == 0
	var st: String = e["state"]
	if st == "":
		return true
	var grp: Array = relay_groups.get(st.substr(0, 1), [])
	if grp.is_empty():
		return true
	return grp[int(time / Rules.RELAY_PERIOD) % grp.size()] == st


func find_route(from_id: int, to_id: int) -> Array:
	## Fastest route by deck travel time (Dijkstra; each node crossed costs a little). Skips
	## currently-closed relay decks and nodes dropped by the Last Stand collapse.
	if collapsed.get(from_id, false) or collapsed.get(to_id, false):
		return []
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
			if collapsed.get(nb, false) or not _edge_open(edges[link[1]]):
				continue
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
		"id": _next_id, "owner": owner, "faction": factions.get(owner, "null"),
		"units": 0.0,                                 # units OUT of the vat (the line); grows as the door emits
		"ordered": units, "start_units": units, "streaming": true,
		"route": route, "target": route[-1],
		"pts": path["pts"], "cum": path["cum"], "fast": path["fast"], "spans": path["spans"],
		"node_spans": path["node_spans"],
		"L": path["cum"][-1], "s": 0.0, "state": "move", "speed": 1.0, "blocked": false,
	}
	_next_id += 1
	return h


func build_path(route: Array) -> Dictionary:
	## Centre line a horde follows: out of the tank bottoms, along each deck, onto the platform of
	## EVERY node it passes (an order passing through a node always counts as passing through it -
	## Daniele, 2026-09-25: no free glide past a contested or hostile waypoint), and onto the
	## destination's platform at the end.
	var pts := []                                   # plain Arrays: lambdas capture them by reference
	var fast := []                                  # 1 = node/pier segment (fast), 0 = deck
	var spans := []                                 # {edge, s0, s1, forward}
	var node_spans := []                            # {node, s0, s1}: intermediate nodes only
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
		var node_s0 := _length(pts)                 # b's platform starts here for every route node
		add.call(b["pos"] - d * (Rules.R - 0.5), true)
		var a_in := atan2(-d.z, -d.x)               # direction from b's centre back toward a
		var a_out: float
		if i + 1 < route.size() - 1:
			var d2 := (nodes[route[i + 2]]["pos"] - b["pos"]).normalized() as Vector3
			a_out = atan2(d2.z, d2.x)
			for p in _arc(b["pos"], a_in, a_out, Rules.ARC_R):
				add.call(p, true)
			add.call(b["pos"] + d2 * (Rules.R - 0.5), true)
			node_spans.append({"node": route[i + 1], "s0": node_s0, "s1": _length(pts)})
		else:
			# destination: straight onto the platform from this side, up to the tower's footprint -
			# the whole platform is the node, every side is an entrance
			add.call(b["pos"] - d * Rules.ARC_R, true)
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + (pts[k] as Vector3).distance_to(pts[k - 1]))
	return {"pts": PackedVector3Array(pts), "cum": cum, "fast": PackedByteArray(fast), "spans": spans,
			"node_spans": node_spans}


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
	_step_last_stand(dt)
	if time >= Rules.MATCH_HARD_END and not over:
		_force_end()
	if over:
		return
	for n in nodes:                                   # production, up to the vat cap
		if n["owner"] != "" and n["units"] < Rules.CAPS[n["tier"]]:
			n["units"] = minf(Rules.CAPS[n["tier"]], n["units"] + Rules.PROD[n["tier"]] * dt)
	_step_structures(dt)
	for n in nodes:                                   # the door emits the current order into its line
		if n["streaming"].is_empty():
			continue
		var h := _horde(n["streaming"]["hid"])
		if h.is_empty() or h["owner"] != n["owner"]:
			_end_streaming(n, "lost")
			continue
		var x: float = minf(n["streaming"]["remaining"], minf(Rules.door_rate * dt, n["units"]))
		n["units"] -= x
		h["units"] += x
		n["streaming"]["remaining"] -= x
		if n["streaming"]["remaining"] <= 0.001 or n["units"] <= 0.0:
			_end_streaming(n, "done")
	for h in hordes:
		if h["state"] == "move" and not h.get("blocked", false):
			var fast_here: bool = sample(h, h["s"])[2]
			var ds: float = Rules.deck_speed * h.get("speed", 1.0) * (Rules.node_speed_mult if fast_here else 1.0) * dt
			if h["streaming"]:                        # the head cannot outrun the door: the line stays attached
				ds = minf(ds, Rules.door_rate * Rules.METRES_PER_UNIT * dt)
			h["s"] += ds
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
		a["pending_loss"] = a.get("pending_loss", 0.0) + (Rules.FIGHT_RATE_BASE + Rules.FIGHT_RATE_K * b["units"]) * dt * _forge_mult(a["owner"])
		b["pending_loss"] = b.get("pending_loss", 0.0) + (Rules.FIGHT_RATE_BASE + Rules.FIGHT_RATE_K * a["units"]) * dt * _forge_mult(b["owner"])
	for h in hordes:
		if h["state"] == "absorb":
			# the line keeps pouring in through the door: units enter as fast as the tail advances
			var len := chain_length(h)
			var tail_fast: bool = sample(h, h["L"] - len)[2]
			var tail_speed := Rules.deck_speed * (Rules.node_speed_mult if tail_fast else 1.0)
			var rate: float = tail_speed * h["units"] / maxf(len, 0.5)
			var x := minf(h["units"], maxf(rate, 4.0) * dt)
			h["units"] -= x
			_arrive(nodes[h["target"]], h, x)
			if h["units"] <= 0.0 and not h["streaming"]:
				dead.append(h)
	for h in _node_fights(dt):
		if h not in dead:
			dead.append(h)
	for h in hordes:                                  # apply combat losses simultaneously
		h["loss_rate"] = 0.0                          # units/s lost this step (drives the view's shrink and splash)
		if h.has("pending_loss"):
			var before: float = h["units"]
			h["units"] = maxf(0.0, h["units"] - h["pending_loss"])
			combat_losses[h["owner"]] = combat_losses.get(h["owner"], 0.0) + before - h["units"]
			h["loss_rate"] = (before - h["units"]) / maxf(dt, 0.0001)
			h.erase("pending_loss")
			if h["units"] <= 0.0:
				dead.append(h)
				events.append({"t": time, "type": "horde_destroyed", "seat": h["owner"], "units": h["start_units"]})
	for h in dead:
		if h in hordes and h["streaming"]:            # the rest of the order never left: it stays in the vat
			var src: Dictionary = nodes[h["route"][0]]
			if src["streaming"].get("hid", -1) == h["id"]:
				_end_streaming(src, "destroyed")
		if h in hordes:
			hordes.erase(h)
			horde_removed.emit(h)
	var alive := {}
	for h in hordes:
		alive[h["id"]] = true
	fights = fights.filter(func(p): return alive.has(p[0]) and alive.has(p[1]))
	for key in fight_info.keys():
		var ids: PackedStringArray = key.split(":")
		if not (alive.has(int(ids[0])) and alive.has(int(ids[1]))):
			fight_info.erase(key)
	var fighting := {}
	for p in fights:
		fighting[p[0]] = true
		fighting[p[1]] = true
	for h in hordes:                                  # no contact left: march on
		if h["state"] == "fight" and not fighting.has(h["id"]):
			h["state"] = "move"
	_check_end()


static func full_length(units: float) -> float:
	## Length of a horde's line once it has fully left its vat.
	return clampf(units * Rules.METRES_PER_UNIT, 1.0, Rules.MAX_CHAIN)


static func chain_length(h: Dictionary) -> float:
	## Deck a horde occupies behind its head. While it is still streaming out of its vat the tail is
	## at the source, so the line is only as long as the head has travelled.
	return minf(full_length(h["units"]), maxf(h["s"], 1.0))


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
		h.erase("blocked_by")
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
					x["h"]["blocked_by"] = y["h"]["id"]   # queued at this friend's tail


func _engage(a: Dictionary, b: Dictionary, kind: String) -> void:
	var pair := [mini(a["id"], b["id"]), maxi(a["id"], b["id"])]
	if pair in fights:
		return
	fights.append(pair)
	fight_info["%d:%d" % [pair[0], pair[1]]] = {"kind": kind, "attacker": a["id"]}   # a's head made the contact
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


func _end_streaming(n: Dictionary, why: String) -> void:
	## The door stops emitting this order. Whatever never left stays in the vat. A horde with
	## nothing out yet disappears; one already out on the deck becomes a finished order of what left.
	var st: Dictionary = n["streaming"]
	n["streaming"] = {}
	if st.is_empty():
		return
	var h := _horde(st["hid"])
	if h.is_empty():
		return
	h["streaming"] = false
	h["ordered"] = h["units"]
	h["start_units"] = maxf(h["units"], 1.0)
	if why != "done":
		events.append({"t": time, "type": "order_" + why, "seat": h["owner"], "left_inside": st["remaining"]})
	if h["units"] <= 0.0:
		hordes.erase(h)
		horde_removed.emit(h)


func _arrive(n: Dictionary, h: Dictionary, x: float) -> void:
	## The line pours onto the platform. Own node: reinforce the garrison. Otherwise the units sit
	## on the platform as a siege and fight the garrison there (see _node_fights); the whole
	## platform is the node.
	var owner: String = h["owner"]
	if n["owner"] == owner:
		n["units"] += x
		return
	n["siege"][owner] = n["siege"].get(owner, 0.0) + x
	if not n["siege_dir"].has(owner):
		var landing: Vector3 = sample(h, h["L"] - 2.0)[0]
		n["siege_dir"][owner] = ((landing - n["pos"]) as Vector3).normalized()


func _register_transit() -> void:
	## An order passing through a node always counts as passing through that node (Daniele,
	## 2026-09-25): no free glide past a contested or hostile waypoint. Every node a horde's line
	## currently overlaps - not just its final target - counts its present units as an attacking
	## force this frame, UNLESS that node is already the horde's owner (a friendly waypoint is a
	## pure pass-through, matching GAME-RULES §6: troops passing through don't count against cap).
	## Transient: rebuilt fresh every step, never carried over by itself (see _node_fights).
	for n in nodes:
		n["transit"] = {}
	for h in hordes:
		if h["state"] == "absorb":
			continue
		for ns in h["node_spans"]:
			var n: Dictionary = nodes[ns["node"]]
			if n["owner"] == h["owner"]:
				continue
			var head_s: float = h["s"]
			var tail_s: float = head_s - chain_length(h)
			if head_s < ns["s0"] or tail_s > ns["s1"]:
				continue
			var t: Dictionary = n["transit"].get(h["owner"], {"units": 0.0, "hordes": []})
			t["units"] += h["units"]
			(t["hordes"] as Array).append(h)
			n["transit"][h["owner"]] = t


func _node_fights(dt: float) -> Array:
	## Units on a platform fight the garrison (and each other) at the frontline rates, whether they
	## arrived (persistent siege) or are merely passing through this frame (transit). When the
	## garrison is beaten down and one side is left, the node flips to it; a transiting horde that
	## captures a node this way ends its journey there, becoming the new garrison. Returns hordes
	## whose whole transiting force was wiped out before it could pass (destroyed en route).
	_register_transit()
	var destroyed := []
	for n in nodes:
		n["node_loss"] = {}
		var seats := {}
		for k in n["siege"]:
			seats[k] = true
		for k in n["transit"]:
			seats[k] = true
		if seats.is_empty():
			continue
		var mult: float = Rules.node_fight_mult
		var force := {}                              # seat -> arrived + transiting units this frame
		for k in seats:
			force[k] = n["siege"].get(k, 0.0) + n["transit"].get(k, {}).get("units", 0.0)
		var total_att := 0.0
		for k in force:
			total_att += force[k]
		var loss := {}
		var g_loss := 0.0
		for k in force:
			var enemy: float = n["units"] + total_att - force[k]
			if enemy <= 0.0:
				continue
			loss[k] = (Rules.FIGHT_RATE_BASE + Rules.FIGHT_RATE_K * enemy) * dt * mult * _forge_mult(k)
			if n["units"] > 0.0:
				g_loss += (Rules.FIGHT_RATE_BASE + Rules.FIGHT_RATE_K * force[k]) * dt * mult * _forge_mult(n["owner"])
		for k in loss:
			var actual: float = minf(loss[k], force[k])
			n["node_loss"][k] = actual / maxf(dt, 0.0001)
			combat_losses[k] = combat_losses.get(k, 0.0) + actual
			var persistent: float = n["siege"].get(k, 0.0)     # spend against arrivals first...
			var take_persistent: float = minf(persistent, actual)
			if take_persistent > 0.0:
				n["siege"][k] = persistent - take_persistent
				if n["siege"][k] <= 0.0:
					n["siege"].erase(k)
					n["siege_dir"].erase(k)
			var remaining: float = actual - take_persistent     # ...then against transiting hordes
			if remaining > 0.0 and n["transit"].has(k):
				var tt: Dictionary = n["transit"][k]
				var tt_units: float = maxf(tt["units"], 0.0001)
				for hh in tt["hordes"]:
					hh["units"] = maxf(0.0, hh["units"] - (hh["units"] / tt_units) * remaining)
					if hh["units"] <= 0.0 and hh not in destroyed:
						destroyed.append(hh)
						events.append({"t": time, "type": "horde_destroyed", "seat": hh["owner"], "units": hh["start_units"]})
				tt["units"] = maxf(0.0, tt_units - remaining)
		if g_loss > 0.0:
			var before_g: float = n["units"]
			n["units"] = maxf(0.0, before_g - g_loss)
			if n["owner"] != "":
				combat_losses[n["owner"]] = combat_losses.get(n["owner"], 0.0) + before_g - n["units"]
				n["node_loss"][n["owner"]] = (before_g - n["units"]) / maxf(dt, 0.0001)
		if n["units"] <= 0.0:
			# capture needs an ARRIVAL, not just transit: a horde merely passing through can grind
			# the garrison down to nothing (real combat, real losses, can even wipe the transiting
			# force out first) but doesn't stop to hold the place - it isn't its order's target, so
			# it fights on through with whatever it has left, and the drained node stays open for
			# whoever actually arrives there next (Daniele, 2026-09-25: this is what keeps note 8's
			# rear-attack/reinforcement routes from being hijacked into conquering a waypoint)
			# a garrison-less node with several sides simultaneously arrived (a shared contested hub
			# both seats keep sending small orders at) does NOT stay in permanent limbo: the side
			# holding more ground there right now takes it, same as two hordes on a deck end up with
			# one side holding the field - found via the starter seven's Strait, where node 0 sat at
			# owner "" forever with both seats' small arrivals cancelling each other out every frame
			var present := {}
			for k in n["siege"]:
				if n["siege"][k] > 0.0:
					present[k] = true
			if present.size() >= 1:
				var old: String = n["owner"]
				var winner_seat: String = present.keys()[0]
				for k in present.keys():
					if n["siege"][k] > n["siege"][winner_seat]:
						winner_seat = k
				if not n["streaming"].is_empty():
					_end_streaming(n, "lost")
				n["owner"] = winner_seat
				n["units"] = n["siege"][winner_seat]
				n["siege"] = {}
				n["siege_dir"] = {}
				events.append({"t": time, "type": "capture", "node": n["id"], "seat": winner_seat, "from": old})
				captured.emit(n["id"], winner_seat, old)
	return destroyed


func _step_last_stand(dt: float) -> void:
	## RUDIMENTARY Last Stand (GAME-RULES sec10, Daniele 2026-09-25): starts at 3:00, always the
	## "inward" method (rim collapses first, the centre is never dropped) regardless of what the
	## map actually lists as eligible - real per-map method choice, the hidden reveal, waves-per-
	## map and "everything on a falling node/deck dies" are a later pass. This exists purely so a
	## match on any starter map is guaranteed to end instead of turtling forever.
	if over:
		return
	if not last_stand_active:
		if time < Rules.LAST_STAND_TIME:
			return
		last_stand_active = true
		var centre := Vector3.ZERO
		for n in nodes:
			if n["center"]:
				centre = n["pos"]
		var candidates := []
		for n in nodes:
			if not n["center"]:
				candidates.append(n["id"])
		candidates.sort_custom(func(a, b):
			return nodes[a]["pos"].distance_to(centre) > nodes[b]["pos"].distance_to(centre))
		last_stand_order = candidates
		events.append({"t": time, "type": "last_stand", "method": "inward"})
		return
	if last_stand_next >= last_stand_order.size():
		return
	_last_stand_wave_t += dt
	if _last_stand_wave_t < Rules.LAST_STAND_WAVE:
		return
	_last_stand_wave_t = 0.0
	var id: int = last_stand_order[last_stand_next]
	last_stand_next += 1
	collapsed[id] = true
	var n: Dictionary = nodes[id]
	var old: String = n["owner"]
	if not n["streaming"].is_empty():
		_end_streaming(n, "collapsed")
	n["owner"] = ""
	n["units"] = 0.0
	n["siege"] = {}
	n["siege_dir"] = {}
	n["transit"] = {}
	events.append({"t": time, "type": "collapse", "node": id, "from": old})


func _force_end() -> void:
	## Safety net (Daniele 2026-09-25): the real end condition is conquest, but a placeholder AI on
	## a placeholder relay/Last Stand pass can still turtle past 7:00 - decide it outright rather
	## than run forever, exactly as GAME-RULES sec10 intends once "the whole order is revealed".
	over = true
	var best := ""
	var best_v := -1.0
	for s in factions.keys():
		var v := seat_strength(s)
		if v > best_v:
			best_v = v
			best = s
	winner = best
	events.append({"t": time, "type": "end", "winner": winner, "forced": true})
	finished.emit(winner)


func _check_end() -> void:
	var alive := {}
	for n in nodes:
		if n["owner"] != "":
			alive[n["owner"]] = true
		for k in n["siege"]:
			alive[k] = true
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
		total += n["siege"].get(seat, 0.0)
	for h in hordes:
		if h["owner"] == seat:
			total += h["units"]
	return total
