class_name Sim
extends RefCounted
## Game state and rules, no visuals. Deterministic for a given sequence of sends, time steps and
## seed. Rules: Docs/Game Design/Ooze Syndicate 2.0/01 Rules/GAME-RULES.md (§5 hordes, §6 nodes,
## §7 bridges, §8 relays, §10 Last Stand). Baked map layouts and plazas, ring Last Stand,
## geometric contact everywhere, tug-of-war fronts, recall (SIEGE only), always-on goo corridors with
## a home advantage, transit fights the real garrison; BRAWL (bridge_combat off) lands Alpha 11 style.

signal captured(node_id: int, new_owner: String, old_owner: String)
signal finished(winner: String)

var nodes: Array = []          # see setup()
var edges: Array = []          # {a, b, modules, state, retracts}
var adj: Dictionary = {}       # node id -> Array of [neighbour id, edge index]
var hordes: Array = []         # see _new_horde()
var factions: Dictionary = {}  # seat -> faction
var homes: Dictionary = {}     # seat -> home node id
var teams: Dictionary = {}     # seat -> team id (team modes only; empty = everyone for themselves)
var time := 0.0
var over := false
var winner := ""
var events: Array = []         # telemetry: {t, type, ...}
var fx_events: Array = []      # for the view, drained every frame: falls, bursts, captures...
var combat_losses: Dictionary = {}   # seat -> units lost in combat
var fall_losses: Dictionary = {}     # seat -> units lost to falls (relays, Last Stand)
var fights: Array = []               # [horde id, horde id] contact pairs - a fight lasts to the death
var fight_info: Dictionary = {}      # "lo:hi" -> {kind: "frontline"/"rear", attacker: horde id} (for the view)
var relay_groups: Dictionary = {}    # "r"/"s"/"m" -> [sorted state keys]
var edge_controller: Dictionary = {} # edge index -> relay node id that fires it (-1 if none)
var _ctrl_edges: Dictionary = {}     # relay node id -> [edge indices] it fires (filled once in setup; read-only)
var collapsed: Dictionary = {}       # node id -> true once dropped by the Last Stand
var eliminated: Dictionary = {}      # seat -> true once the collapse took its last node
var last_stand_active := false
var last_stand_method := ""          # hidden until it starts, then revealed with the whole order
var last_stand_order: Array = []     # node ids in drop order (the final is never in it)
var last_stand_waves: Array = []     # maps 3.0: [[node ids]] - one ring per wave (plus relays / islands)
var last_stand_keep: Dictionary = {} # maps 3.0: node id -> true for the last ring (never falls)
var last_stand_warn: Dictionary = {} # node id -> true while under the 10 s warning
var v3 := false                      # a maps 3.0 map (baked layout, rings, plazas)
var _ring_orders: Dictionary = {}    # maps 3.0: method -> ring order (chaos: [orders])
var last_stand_final := -1
var last_stand_next := 0
var last_stand_warn_node := -1       # node under its 10 s warning (-1: none)
var last_stand_warn_t := 0.0         # seconds to the next drop (the ring's warning, then the gap between drops)
var last_stand_queue: Array = []     # the warned ring's platforms still to drop, in drop order (0.18.4)
var last_stand_wave := 20.0
var _next_wave_at := 0.0
var rng := RandomNumberGenerator.new()
var _next_id := 1


func setup(map: Dictionary, positions: Dictionary, seats: Dictionary, seat_factions: Dictionary, seed_value: int = -1, seat_teams: Dictionary = {}) -> void:
	factions = {}
	for id in seats:                                   # only seats actually in this match
		factions[seats[id]] = seat_factions.get(seats[id], "null")
	if factions.is_empty():
		factions = seat_factions
	teams = seat_teams
	rng.seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system()) % 100000
	_map_last_stand = map.get("lastStand", {})
	v3 = map.has("layout")
	if v3:
		_ring_orders = _map_last_stand.get("orders", {})
	for n in map["nodes"]:
		var id: int = n["id"]
		var owner: String = seats.get(id, "")
		if owner != "":
			homes[owner] = id
		var relay: String = n["relay"] if n.get("relay") != null else ""
		# a relay node has no vat (GAME-RULES sec6, centreHasNoVat): it is a modest neutral
		# waypoint that must be fed from elsewhere, never a fortress at the map's centre
		var neutral = n.get("neutral") if v3 else null
		var tier := Rules.HOME_TIER if owner != "" \
				else (clampi(int(neutral["tier"]), 1, 4) if neutral is Dictionary \
				else (1 if v3 else (3 if (n["category"] == "final" or n.get("center", false)) and relay == "" else 1)))
		var units := float(Rules.HOME_UNITS if owner != "" else Rules.NEUTRAL_UNITS[tier])
		nodes.append({
			"id": id, "pos": positions[id], "owner": owner, "tier": tier, "units": units,
			"category": n.get("category", "normal"), "center": n.get("center", false), "relay": relay,
			"ring": int(n.get("ring", 0)) if n.get("ring") != null else 0,
			"plaza": int(n["plaza"]) if n.get("plaza") != null else -1,
			"streaming": {},        # {hid, remaining}: the one order the door is emitting
			"siege": {},            # seat -> units on the platform fighting the garrison (arrived)
			"siege_dir": {},        # seat -> unit vector from the tower to where they landed
			"transit": {},          # seat -> {"units", "hordes": [Horde]}: passing-through this frame
			"node_loss": {},        # seat -> units/s lost on this platform last step (view)
			"buildable": n.get("buildable", []),   # what the owner may place here (roster JSON)
			"attachment": "",       # "" / "cannon" / "forge" (replaces the vat while present)
			"cannon_tier": 0,       # 1-3 once a cannon is built; double-tap upgrades it (Alpha 11)
			"build_kind": "",       # "" / "vat" / "cannon" / "forge" / "vat_restore": what completes
			"build_timer": 0.0,     # seconds left on the current build
			"build_target": {},     # {"kind", "tier"} the view shows growing while build_timer runs
			"swap_cd": 0.0,         # seconds before the attachment may be swapped again
			"cannon_cd": 0.0,       # seconds of recharge left after a burst
			"cannon_burst": 0.0,    # seconds left in the current burst (0 = not firing)
			"cannon_kill_left": 0.0,
			"cannon_target": Vector3.ZERO,
			"relay_index": 0,       # current position in this relay's state cycle (retract: 0 out / 1 in)
			"relay_pending": 0,     # the state a fired relay is moving to
			"relay_phase": "",      # "" / "warning" / "moving"
			"relay_t": 0.0,         # seconds left in the phase
			"relay_cd": 0.0,        # cooldown before the next fire
			"relay_anim": {},       # {"delta", "closing": [edge], "opening": [edge], "pairs": {c: o}}
			"moving_edges": [],     # edges in motion this moment (closed to new routes)
		})
		adj[id] = []
		if v3 and owner == "" and neutral is Dictionary and str(neutral.get("structure", "vat")) in ["cannon", "forge"]:
			var nd: Dictionary = nodes[-1]                # maps 3.0 strategic / relay nodes may start armed
			nd["attachment"] = neutral["structure"]
			nd["cannon_tier"] = clampi(tier - 1, 1, 3) if neutral["structure"] == "cannon" else 0
	var geo: Array = map["layout"]["edges"] if v3 else []
	for ek in range(map["edges"].size()):
		var e: Dictionary = map["edges"][ek]
		var mods: int = {"S": 1, "M": 2, "L": 3}[e["tier"]]
		var st: String = e["state"] if e.get("state") != null else ""     # JSON stores "state": null
		var retracts: bool = e.get("retracts", false) == true or st == "ret"   # maps 3.0 spells a retract "ret"
		if st == "ret":
			st = ""
		edges.append({"a": int(e["from"]), "b": int(e["to"]), "modules": mods,
				"state": st, "retracts": retracts, "overpass": e.get("overpass", false) == true,
				"geo": geo[ek] if v3 else {}, "plaza": false,
				"relay_node": int(e["relay"]) if v3 and e.get("relay") != null else -1})
		var i := edges.size() - 1
		adj[int(e["from"])].append([int(e["to"]), i])
		adj[int(e["to"])].append([int(e["from"]), i])
		if st != "":
			var prefix := st.substr(0, 1)
			if not relay_groups.has(prefix):
				relay_groups[prefix] = []
			if st not in relay_groups[prefix]:
				relay_groups[prefix].append(st)
	if v3:                                            # maps 3.0 plazas: every socket reaches every other
		var by_plaza := {}
		for n in nodes:
			if n["plaza"] >= 0:
				if not by_plaza.has(n["plaza"]):
					by_plaza[n["plaza"]] = []
				by_plaza[n["plaza"]].append(n["id"])
		for pid in by_plaza:
			var ids: Array = by_plaza[pid]
			for x in range(ids.size()):
				for y in range(x + 1, ids.size()):
					edges.append({"a": ids[x], "b": ids[y], "modules": 0, "state": "", "retracts": false,
							"overpass": false, "geo": {}, "plaza": true, "relay_node": -1})
					var pi := edges.size() - 1
					adj[ids[x]].append([ids[y], pi])
					adj[ids[y]].append([ids[x], pi])
	for k in relay_groups:
		(relay_groups[k] as Array).sort()
	var prefix_kind := {"r": "rotation", "s": "switch", "m": "remote"}
	for i in range(edges.size()):                    # which relay node governs each relay-controlled edge
		var e: Dictionary = edges[i]
		if e["state"] == "" and not e["retracts"]:
			continue
		if v3 and e["relay_node"] >= 0:                 # maps 3.0 names the controlling relay
			edge_controller[i] = e["relay_node"]
			continue
		var want: String = "retract" if e["retracts"] else prefix_kind[e["state"].substr(0, 1)]
		var ctrl := -1
		for end in [e["a"], e["b"]]:
			if nodes[end]["relay"] == want:
				ctrl = end
		if ctrl < 0 and want == "remote":                # a remote console is wired to decks elsewhere
			for n in nodes:
				if n["relay"] == "remote":
					ctrl = n["id"]
					break
		edge_controller[i] = ctrl
	_ctrl_edges = {}
	for i in edge_controller:                        # per-relay lists, ascending edge order (read-only)
		if not _ctrl_edges.has(edge_controller[i]):
			_ctrl_edges[edge_controller[i]] = []
		_ctrl_edges[edge_controller[i]].append(i)


var _map_last_stand: Dictionary = {}


func controlled_edges(node_id: int) -> Array:
	## The edges this relay fires. Cached at setup; callers must not modify the returned array.
	return _ctrl_edges.get(node_id, [])


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
	events.append({"t": time, "type": "send", "seat": h["owner"], "from": from_id, "to": to_id, "units": count,
			"target_owner": nodes[to_id]["owner"]})
	return h


# ------------------------------------------------------------------ structures (Alpha 11 logic)
static func has_vat(n: Dictionary) -> bool:
	return n["relay"] == "" and n["attachment"] == ""


static func vat_cost(n: Dictionary) -> int:
	return Rules.VAT_COST.get(n["tier"], 0) if n["tier"] < 4 else 0


static func build_progress(n: Dictionary) -> float:
	if n["build_kind"] == "":
		return 1.0
	return clampf(1.0 - n["build_timer"] / Rules.BUILD_SECONDS, 0.0, 1.0)


func production(n: Dictionary) -> float:
	return Rules.PROD[n["tier"]] * stat(n["owner"], "production") if n["owner"] != "" and has_vat(n) else 0.0


func upgrade_vat(node_id: int) -> bool:
	## Start a vat upgrade (T1->T2->T3->T4), Rules.BUILD_SECONDS to complete (GAME-RULES sec6),
	## paid in units from the vat (Alpha 11: 10/20/30, x SCALE).
	var n: Dictionary = nodes[node_id]
	if n["owner"] == "" or n["build_kind"] != "" or n["tier"] >= 4 or not has_vat(n) \
			or not ("vat" in n["buildable"]) or n["units"] < vat_cost(n):
		return false
	n["units"] -= vat_cost(n)
	_start_build(n, "vat", {"kind": "vat", "tier": n["tier"] + 1})
	return true


func build_attachment(node_id: int, kind: String) -> bool:
	## Build a cannon or forge in the node's slot (GAME-RULES sec6). On a relay node the slot is
	## empty; on a final node it REPLACES the vat (vat <-> cannon/forge swap); cannon <-> forge is a
	## swap too. Swaps need the slot off its cooldown; everything is paid in units from the node.
	var n: Dictionary = nodes[node_id]
	if n["owner"] == "" or n["build_kind"] != "" or not (kind in n["buildable"]) or n["attachment"] == kind:
		return false
	var swapping: bool = n["attachment"] != "" or (n["relay"] == "" and n["tier"] > 0)
	if swapping and n["swap_cd"] > 0.0:
		return false
	var cost: int = Rules.CANNON_COST[1] if kind == "cannon" else Rules.FORGE_COST
	if n["units"] < cost:
		return false
	n["units"] -= cost
	_start_build(n, kind, {"kind": kind, "tier": 1})
	return true


func restore_vat(node_id: int) -> bool:
	## A final node's attachment gives way to its vat again (Alpha 11: RESTORE VAT, free, a build).
	var n: Dictionary = nodes[node_id]
	if n["owner"] == "" or n["build_kind"] != "" or n["attachment"] == "" or n["relay"] != "" \
			or not ("vat" in n["buildable"]) or n["swap_cd"] > 0.0:
		return false
	_start_build(n, "vat_restore", {"kind": "vat", "tier": n["tier"]})
	return true


func upgrade_structure(node_id: int) -> bool:
	## Alpha 11 convention (Daniele, 2026-09-25): double-tap upgrades whatever is already there - the
	## vat, or a built cannon's tier (T1->T2->T3, 25/35 x SCALE). A forge is single-tier.
	var n: Dictionary = nodes[node_id]
	if n["owner"] == "" or n["build_kind"] != "":
		return false
	if n["attachment"] == "cannon" and n["cannon_tier"] < 3:
		var cost: int = Rules.CANNON_COST[n["cannon_tier"] + 1]
		if n["units"] < cost:
			return false
		n["units"] -= cost
		_start_build(n, "cannon", {"kind": "cannon", "tier": n["cannon_tier"] + 1})
		return true
	if n["attachment"] == "":
		return upgrade_vat(node_id)
	return false


func upgrade_cost(n: Dictionary) -> int:
	## What a double-tap would cost here right now (HUD).
	if n["attachment"] == "cannon":
		return Rules.CANNON_COST.get(n["cannon_tier"] + 1, 0) if n["cannon_tier"] < 3 else 0
	if n["attachment"] == "":
		return vat_cost(n)
	return 0


func _start_build(n: Dictionary, kind: String, target: Dictionary) -> void:
	n["build_kind"] = kind
	n["build_timer"] = Rules.BUILD_SECONDS
	n["build_target"] = target
	events.append({"t": time, "type": "build_start", "node": n["id"], "seat": n["owner"], "kind": kind})


func _step_structures(dt: float) -> void:
	## Builds complete after Rules.BUILD_SECONDS. A built cannon bursts for CANNON_BURST seconds,
	## killing up to CANNON_STATS[tier].kill units of enemy hordes within CANNON_RANGE outright
	## (Alpha 11: body kills bypass HP), then recharges AFTER the burst.
	for n in nodes:
		if n["swap_cd"] > 0.0:
			n["swap_cd"] = maxf(0.0, n["swap_cd"] - dt)
		if n["owner"] == "" or n["build_kind"] == "":
			continue
		n["build_timer"] -= dt
		if n["build_timer"] <= 0.0:
			var kind: String = n["build_kind"]
			n["build_kind"] = ""
			n["build_target"] = {}
			if kind == "vat":
				n["tier"] = mini(n["tier"] + 1, 4)
			elif kind == "vat_restore":
				n["attachment"] = ""
				n["cannon_tier"] = 0
				n["swap_cd"] = Rules.SWAP_COOLDOWN
			elif kind == "cannon" and n["attachment"] == "cannon":
				n["cannon_tier"] = mini(n["cannon_tier"] + 1, 3)   # upgrading an existing cannon
			else:
				if n["attachment"] != "" or n["relay"] == "":       # a swap (cannon<->forge, vat->attachment)
					n["swap_cd"] = Rules.SWAP_COOLDOWN
				n["attachment"] = kind                             # a fresh attachment
				n["cannon_tier"] = 1 if kind == "cannon" else 0
				n["cannon_cd"] = 0.0
				n["cannon_burst"] = 0.0
			events.append({"t": time, "type": "build_done", "node": n["id"], "seat": n["owner"], "kind": kind})
			fx_events.append({"type": "build_done", "node": n["id"]})
	for n in nodes:
		if n["owner"] == "" or n["attachment"] != "cannon":
			n["cannon_burst"] = 0.0
			continue
		var stats: Dictionary = Rules.CANNON_STATS[n["cannon_tier"]]
		if n["cannon_burst"] > 0.0:
			var targets := _hordes_in_range(n)
			if targets.is_empty():
				n["cannon_burst"] = 0.0
				n["cannon_cd"] = stats["recharge"]
				continue
			var budget: float = minf(n["cannon_kill_left"], stats["kill"] / Rules.CANNON_BURST * dt)
			n["cannon_kill_left"] -= budget
			var each: float = budget / targets.size()
			for h in targets:
				var kill: float = minf(each, h["units"])
				h["units"] -= kill
				combat_losses[h["owner"]] = combat_losses.get(h["owner"], 0.0) + kill
				if h["units"] <= 0.0:
					_kill_horde(h, "cannon")
			n["cannon_target"] = sample(targets[0], targets[0]["s"])[0]
			n["cannon_burst"] -= dt
			if n["cannon_burst"] <= 0.0 or n["cannon_kill_left"] <= 0.0:
				n["cannon_burst"] = 0.0
				n["cannon_cd"] = stats["recharge"]
			continue
		n["cannon_cd"] -= dt
		if n["cannon_cd"] > 0.0:
			continue
		var in_range := _hordes_in_range(n)
		if in_range.is_empty():
			continue
		n["cannon_burst"] = Rules.CANNON_BURST
		n["cannon_kill_left"] = stats["kill"]
		n["cannon_target"] = sample(in_range[0], in_range[0]["s"])[0]
		events.append({"t": time, "type": "cannon_burst", "node": n["id"], "seat": n["owner"]})
		fx_events.append({"type": "cannon", "node": n["id"]})


func _hordes_in_range(n: Dictionary) -> Array:
	var out := []
	for h in hordes:
		if allied(h["owner"], n["owner"]) or h["units"] <= 0.0:
			continue
		var p: Vector3 = sample(h, h["s"])[0]
		if (p - (n["pos"] as Vector3)).length() <= Rules.CANNON_RANGE:
			out.append(h)
	return out


func forge_of(seat: String) -> float:
	## Forge multiplier for everything this seat's troops deal (Alpha 11: +50 attack on 100).
	if seat == "":
		return 1.0
	for n in nodes:
		if n["owner"] == seat and n["attachment"] == "forge":
			return 1.0 + Rules.forge_bonus
	return 1.0


func stat(seat: String, key: String) -> float:
	## The seat's faction stat (Rules.FACTION_STATS): speed, health, attack, production, garrison.
	return Rules.stat(factions.get(seat, "null"), key) if seat != "" else 1.0


func attack_of(seat: String) -> float:
	## Damage dealt: faction attack x forge.
	return stat(seat, "attack") * forge_of(seat)


func has_forge(seat: String) -> bool:
	return forge_of(seat) > 1.0


# ------------------------------------------------------------------ relays (GAME-RULES sec8)
func relay_states(n: Dictionary) -> Array:
	## The relay's fixed, visible state order (retract: out / in).
	if n["relay"] == "retract":
		return ["out", "retract"]
	var prefix: String = {"rotation": "r", "switch": "s", "remote": "m"}.get(n["relay"], "")
	return relay_groups.get(prefix, [])


func relay_state_key(n: Dictionary, index: int) -> String:
	var states := relay_states(n)
	if states.is_empty():
		return ""
	var k: String = states[index % states.size()]
	return k


func relay_next_index(n: Dictionary) -> int:
	var states := relay_states(n)
	return (n["relay_index"] + 1) % maxi(states.size(), 1)


func _edge_open_at(edge_index: int, index: int) -> bool:
	var e: Dictionary = edges[edge_index]
	if e["retracts"]:
		return index == 0
	var grp: Array = relay_groups.get(e["state"].substr(0, 1), [])
	if grp.is_empty():
		return true
	return grp[index % grp.size()] == e["state"]


func is_edge_open(edge_index: int) -> bool:
	## Is this deck currently usable / present? Closed while its relay is mid-motion, while its
	## state is not the current one, or when either end has collapsed.
	var e: Dictionary = edges[edge_index]
	if collapsed.get(e["a"], false) or collapsed.get(e["b"], false):
		return false
	return _edge_open(edge_index)


func _edge_open(edge_index: int) -> bool:
	var e: Dictionary = edges[edge_index]
	if not e["retracts"] and e["state"] == "":
		return true
	var ctrl: int = edge_controller.get(edge_index, -1)
	var index := 0
	if ctrl >= 0:
		if edge_index in nodes[ctrl]["moving_edges"]:
			return false
		if nodes[ctrl]["owner"] != "":
			index = nodes[ctrl]["relay_index"]
	return _edge_open_at(edge_index, index)


func fire_relay(node_id: int) -> bool:
	## The owner's control over their relay (GAME-RULES sec8: "fire the switch"): starts the 3 s
	## warning; the authoritative tick then moves the deck and applies the per-kind troop fate.
	var n: Dictionary = nodes[node_id]
	if n["owner"] == "" or n["relay"] == "" or n["relay_cd"] > 0.0 or n["relay_phase"] != "":
		return false
	if relay_states(n).is_empty():
		return false
	n["relay_pending"] = relay_next_index(n)
	n["relay_phase"] = "warning"
	n["relay_t"] = Rules.RELAY_WARNING
	events.append({"t": time, "type": "relay_fired", "node": node_id, "seat": n["owner"], "index": n["relay_pending"]})
	fx_events.append({"type": "relay_warning", "node": node_id})
	return true


func _step_relays(dt: float) -> void:
	for n in nodes:
		if n["relay"] == "":
			continue
		if n["relay_cd"] > 0.0:
			n["relay_cd"] = maxf(0.0, n["relay_cd"] - dt)
		match n["relay_phase"]:
			"warning":
				n["relay_t"] -= dt
				if n["relay_t"] <= 0.0:
					_relay_begin_move(n)
			"moving":
				n["relay_t"] -= dt
				var progress := clampf(1.0 - n["relay_t"] / Rules.RELAY_MOVE, 0.0, 1.0)
				_relay_update_riders(n, progress)
				if n["relay_t"] <= 0.0:
					_relay_apply(n)


func _relay_begin_move(n: Dictionary) -> void:
	## The authoritative tick: the state changes, the affected decks start moving; a turning deck
	## flings every horde on it into the void (_relay_fling), on the others they ride (_relay_board).
	var old_index: int = n["relay_index"]
	var new_index: int = n["relay_pending"]
	var closing := []
	var opening := []
	for i in controlled_edges(n["id"]):
		var was := _edge_open_at(i, old_index)
		var now := _edge_open_at(i, new_index)
		if was and not now:
			closing.append(i)
		elif now and not was:
			opening.append(i)
	n["relay_index"] = new_index
	n["moving_edges"] = closing + opening
	var pairs := {}
	var delta := 0.0
	if n["relay"] == "rotation":
		for c in closing:                                 # the deck pivots from its old pier to the nearest new one
			var a: int = _other_end(c, n["id"])
			var ang_a := _angle_from(n["pos"], nodes[a]["pos"])
			var best := -1
			var best_d := INF
			for o in opening:
				var b: int = _other_end(o, n["id"])
				var d := wrapf(_angle_from(n["pos"], nodes[b]["pos"]) - ang_a, -PI, PI)
				if absf(d) < absf(best_d):
					best_d = d
					best = o
			if best >= 0:
				pairs[c] = best
				delta = best_d
	n["relay_anim"] = {"delta": delta, "closing": closing, "opening": opening, "pairs": pairs, "progress": 0.0}
	if n["relay"] == "rotation":
		_relay_fling(n, closing, delta)                   # nobody rides a turning deck: it shakes them off
	else:
		_relay_board(n, closing)
	n["relay_phase"] = "moving"
	n["relay_t"] = Rules.RELAY_MOVE
	events.append({"t": time, "type": "relay_tick", "node": n["id"], "seat": n["owner"], "index": new_index})
	fx_events.append({"type": "relay_tick", "node": n["id"]})


func _relay_board(n: Dictionary, closing: Array) -> void:
	## Retract / switch / remote: every horde on a closing deck rides it (frozen in place, carried by
	## the deck's motion) until the motion ends and _relay_apply gives it the kind's fate.
	for h in hordes:                                      # riders: any horde overlapping a closing deck
		for sp in h["spans"]:                             # (an arriving horde's tail counts too)
			if sp["edge"] in closing and _overlap(h, sp["s0"], sp["s1"]) > 0.0:
				var ride := {"s0": sp["s0"], "s1": sp["s1"], "edge": sp["edge"], "kind": n["relay"],
						"shift": Vector3.ZERO, "sink": 0.0, "node": n["id"], "prev_state": h["state"]}
				if n["relay"] == "retract":
					var far: int = _other_end(sp["edge"], n["id"])
					ride["dir"] = ((n["pos"] - nodes[far]["pos"]) as Vector3).normalized()
					ride["len"] = edges[sp["edge"]]["modules"] * Rules.S
				h["ride"] = ride
				h["state"] = "ride"
				break


func _relay_fling(n: Dictionary, closing: Array, delta: float) -> void:
	## Rotation (Daniele, 0.18.3: "when a rotating bridge turns all units that are on it are shaken
	## down into the void as if the fall due to centrifugal power"): the moment the deck starts to
	## turn, every line with bodies on it - any owner, the relay owner's own included - loses them
	## to the void, a fall loss exactly like walking off a missing deck. A line only partly on it
	## keeps the rest: that part is behind a deck that is gone (re-routed from the pier before it
	## when the head was on the deck, as a dissolved switch deck leaves it). One "fling" fx per line:
	## the view throws the bodies outward and sideways, the HUD counts them (shown units).
	var turn := signf(delta) if delta != 0.0 else 1.0
	for h in hordes.duplicate():
		var ranges := []
		for sp in h["spans"]:
			if sp["edge"] in closing and _overlap(h, sp["s0"], sp["s1"]) > 0.0:
				ranges.append([sp["s0"], sp["s1"]])
		if ranges.is_empty():
			continue
		# tail-side deck first: cutting it only pulls the tail up, so the next range stays valid, and
		# only the last range can hold the head (the one cut that may re-route what is left)
		ranges.sort_custom(func(x, y): return x[0] < y[0])
		var seat: String = h["owner"]
		var faction: String = h["faction"]
		var acc := {"pts": [], "units": 0.0}
		for r in ranges:
			_cut_range(h, r[0], r[1], "fall", -1, true, acc)
		if acc["units"] <= 0.0:
			continue
		fx_events.append({"type": "fling", "node": n["id"], "seat": seat, "units": Rules.shown(acc["units"]),
				"faction": faction, "pts": acc["pts"], "centre": n["pos"], "turn": turn})


func _relay_update_riders(n: Dictionary, progress: float) -> void:
	n["relay_anim"]["progress"] = progress
	var eased := smoothstep(0.0, 1.0, progress)
	for h in hordes:
		if not h.has("ride") or h["ride"]["node"] != n["id"]:
			continue
		var r: Dictionary = h["ride"]
		match r["kind"]:
			"retract":
				r["shift"] = r["dir"] * r["len"] * eased
			_:
				r["sink"] = 6.0 * progress * progress      # the deck dissolves under it: it drops


func _relay_apply(n: Dictionary) -> void:
	## Motion over: apply the per-kind troop fate (GAME-RULES sec8) to every rider (a rotation has
	## none: _relay_fling shook its deck clear when it started to turn).
	var riders := []
	for h in hordes:
		if h.has("ride") and h["ride"]["node"] == n["id"]:
			riders.append(h)
	for h in riders:
		var r: Dictionary = h["ride"]
		h.erase("ride")
		h["state"] = "absorb" if r["prev_state"] == "absorb" and h["s"] >= h["L"] else "move"
		match n["relay"]:
			"retract":                                    # carried into the relay's node
				_cut_range(h, r["s0"], r["s1"], "carry", n["id"])
			_:                                            # switch / remote: fall
				_cut_range(h, r["s0"], r["s1"], "fall", -1)
	n["moving_edges"] = []
	n["relay_phase"] = ""
	n["relay_cd"] = Rules.RELAY_COOLDOWN
	fx_events.append({"type": "relay_done", "node": n["id"]})


func _set_route(h: Dictionary, route: Array) -> void:
	var path := build_path(route)
	h["route"] = route
	h["target"] = route[-1]
	h["pts"] = path["pts"]
	h["cum"] = path["cum"]
	h["fast"] = path["fast"]
	h["spans"] = path["spans"]
	h["node_spans"] = path["node_spans"]
	h["L"] = path["cum"][-1]


func _other_end(edge_index: int, node_id: int) -> int:
	var e: Dictionary = edges[edge_index]
	return e["b"] if e["a"] == node_id else e["a"]


static func _angle_from(c: Vector3, p: Vector3) -> float:
	return atan2(p.z - c.z, p.x - c.x)


func _overlap(h: Dictionary, s0: float, s1: float) -> float:
	## Metres of the horde's line inside [s0, s1] of its path.
	var head: float = h["s"]
	var tail: float = head - chain_length(h)
	return maxf(0.0, minf(head, s1) - maxf(tail, s0))


func _cut_range(h: Dictionary, s0: float, s1: float, fate: String, carry_node: int, reroute := true, fling = null) -> void:
	## Units of the horde inside [s0, s1] of its path are lost (fate "fall") or carried into a node
	## (fate "carry"). If the head itself was inside, whatever is left behind the range is re-routed
	## from the node before it; if nothing is left, the horde is gone. `fling` (a {pts, units}
	## Dictionary, rotation relays): the fall is counted the same, but its points and units go there
	## for one "fling" fx per line instead of a "fall" fx.
	if not (h in hordes):
		return
	var len := chain_length(h)
	var on := _overlap(h, s0, s1)
	if on <= 0.0:
		return
	var frac := clampf(on / maxf(len, 0.001), 0.0, 1.0)
	var units_on: float = h["units"] * frac
	if h["streaming"]:
		var src: Dictionary = nodes[h["route"][0]]
		if src["streaming"].get("hid", -1) == h["id"]:
			_end_streaming(src, "cut")
	if fate == "fall":
		fall_losses[h["owner"]] = fall_losses.get(h["owner"], 0.0) + units_on
		var pts := []
		var k := 0.0
		while k <= on:
			pts.append(sample(h, minf(h["s"], s1) - k)[0])
			k += Rules.PATCH_SPACING
		if fling is Dictionary:
			(fling["pts"] as Array).append_array(pts)
			fling["units"] += units_on
			events.append({"t": time, "type": "fall", "seat": h["owner"], "units": units_on, "why": "fling"})
		else:
			fx_events.append({"type": "fall", "seat": h["owner"], "faction": h["faction"], "pts": pts, "units": units_on})
			events.append({"t": time, "type": "fall", "seat": h["owner"], "units": units_on})
	elif fate == "carry" and carry_node >= 0:
		var n: Dictionary = nodes[carry_node]
		if allied(n["owner"], h["owner"]):
			n["units"] += units_on
		else:
			n["siege"][h["owner"]] = n["siege"].get(h["owner"], 0.0) + units_on
			if not n["siege_dir"].has(h["owner"]):
				n["siege_dir"][h["owner"]] = ((sample(h, h["s"])[0] - n["pos"]) as Vector3).normalized()
		events.append({"t": time, "type": "carried", "seat": h["owner"], "node": carry_node, "units": units_on})
	h["units"] -= units_on
	if h["units"] < 1.0:
		_kill_horde(h, fate)
		return
	if reroute and h["s"] >= s0 and h["s"] <= s1:        # the head was inside: what's left is behind it
		var from_node := _node_before(h, s0)
		if from_node < 0 or collapsed.get(from_node, false):
			_kill_horde(h, fate)
			return
		var route := find_route(from_node, h["target"])
		if route.size() < 2:                              # nowhere to go: it stays where it is
			_arrive(nodes[from_node], h, h["units"])
			h["units"] = 0.0
			_kill_horde(h, "absorbed")
			return
		_set_route(h, route)
		h["s"] = minf(chain_length(h), h["spans"][0]["s0"])
		h["ordered"] = h["units"]


func _node_before(h: Dictionary, s: float) -> int:
	## The route node whose platform precedes arc length s on the horde's path.
	var idx := 0
	for i in range(h["spans"].size()):
		if h["spans"][i]["s0"] < s:
			idx = i + 1
	return h["route"][mini(idx, h["route"].size() - 1)] if idx > 0 else h["route"][0]


func _kill_horde(h: Dictionary, why: String) -> void:
	if h["streaming"]:
		var src: Dictionary = nodes[h["route"][0]]
		if src["streaming"].get("hid", -1) == h["id"]:
			_end_streaming(src, "destroyed")
	if h in hordes:
		hordes.erase(h)
		events.append({"t": time, "type": "horde_destroyed", "seat": h["owner"], "units": h["start_units"], "why": why})


# ------------------------------------------------------------------ routing
func edge_cost(ei: int) -> float:
	## Seconds to cross a link. maps 3.0: its drawn length at the constant speed (plaza links: socket to
	## socket); legacy maps: the tier's modules.
	var e: Dictionary = edges[ei]
	if not v3:
		return e["modules"] * Rules.MODULE_SECONDS
	if e["plaza"]:
		return (nodes[e["a"]]["pos"] as Vector3).distance_to(nodes[e["b"]]["pos"]) / Rules.move_speed()
	return float(e["geo"]["L"]) / Rules.move_speed()


func find_route(from_id: int, to_id: int) -> Array:
	## Fastest route by deck travel time (Dijkstra; each node crossed costs a little). Skips
	## closed relay decks and nodes dropped by the Last Stand collapse.
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
			if collapsed.get(nb, false) or not _edge_open(link[1]):
				continue
			var cost: float = dist[cur] + edge_cost(link[1]) + 1.0
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
	var h := {
		"id": _next_id, "owner": owner, "faction": factions.get(owner, "null"),
		"units": 0.0,                                 # units OUT of the vat (the line); grows as the door emits
		"ordered": units, "start_units": units, "streaming": true,
		"s": 0.0, "state": "move", "speed": 1.0, "blocked": false,
	}
	_set_route(h, route)
	_next_id += 1
	return h


func build_path(route: Array) -> Dictionary:
	if v3:
		return _build_path3(route)
	return _build_path_legacy(route)


func exit_of(ei: int, node_id: int) -> Vector3:
	## maps 3.0: where edge ei leaves node_id's footprint (the baked rim exit); plaza links leave a
	## socket at the tower's footprint toward the other socket.
	var e: Dictionary = edges[ei]
	if e["plaza"]:
		var o: Vector3 = nodes[_other_end(ei, node_id)]["pos"]
		var p: Vector3 = nodes[node_id]["pos"]
		return p + (o - p).normalized() * Rules.ARC_R
	var g: Dictionary = e["geo"]
	var q: Array = g["A"] if e["a"] == node_id else g["B"]
	return Vector3(q[0], 0.0, q[1])


func deck_line(ei: int) -> Array:
	## A deck's centre line rim to rim, a to b, with its ramps (views: goo corridors, trims).
	## Plaza links have no deck: [].
	var e: Dictionary = edges[ei]
	if e.get("plaza", false):
		return []
	if v3:
		return [exit_of(ei, e["a"])] + deck_points(ei, e["a"]) + [exit_of(ei, e["b"])]
	var pa: Vector3 = nodes[e["a"]]["pos"]
	var pb: Vector3 = nodes[e["b"]]["pos"]
	var dir := (pb - pa).normalized()
	return [pa + dir * Rules.R] + deck_points(ei, e["a"]) + [pb - dir * Rules.R]


func _build_path3(route: Array) -> Dictionary:
	## maps 3.0: out of the node (SIEGE: toward the exit; BRAWL: Alpha 11's front door round the ring),
	## to the deck's baked rim exit, along the pier, up / down the baked ramps, across, and at every
	## node on the way round its tower to the next exit; plaza links cross the plate socket to socket.
	var pts := []
	var fast := []
	var spans := []
	var node_spans := []
	var add := func(p: Vector3, f: int) -> void:
		pts.append(p)
		fast.append(f)
	var brawl := not Rules.bridge_combat
	var front := Rules.front_dir()
	var a_front := atan2(front.z, front.x)
	var ring: float = Rules.BRAWL_RING if brawl else Rules.ARC_R
	var a0: Dictionary = nodes[route[0]]
	var ex0 := exit_of(_edge_index(route[0], route[1]), route[0])
	var d0 := ((ex0 - a0["pos"]) as Vector3).normalized()
	if brawl:
		add.call(a0["pos"] + front * Rules.EXIT_R, 1)
		for p in _arc(a0["pos"], a_front, atan2(d0.z, d0.x), ring):
			add.call(p, 1)
	else:
		add.call(a0["pos"] + d0 * Rules.EXIT_R, 1)
	add.call(ex0, 1)
	for i in range(route.size() - 1):
		var b: Dictionary = nodes[route[i + 1]]
		var ei := _edge_index(route[i], route[i + 1])
		var e: Dictionary = edges[ei]
		var s0 := _length(pts)
		if not e["plaza"]:
			var deck := deck_points(ei, route[i])     # one speed everywhere (Daniele: "units speed is always constant")
			for k in range(deck.size()):
				add.call(deck[k], 0 if k < deck.size() - 1 else 1)
		var ex_in := exit_of(ei, route[i + 1])
		add.call(ex_in, 1)
		spans.append({"edge": ei, "s0": s0, "s1": _length(pts), "forward": e["a"] == route[i]})
		var node_s0 := _length(pts)
		var din := ((ex_in - b["pos"]) as Vector3).normalized()
		if i + 1 < route.size() - 1:
			var ex_out := exit_of(_edge_index(route[i + 1], route[i + 2]), route[i + 1])
			var dout := ((ex_out - b["pos"]) as Vector3).normalized()
			for p in _arc(b["pos"], atan2(din.z, din.x), atan2(dout.z, dout.x), ring):
				add.call(p, 1)
			add.call(ex_out, 1)
			node_spans.append({"node": route[i + 1], "s0": node_s0, "s1": _length(pts)})
		elif brawl:                                   # Alpha 11: round the ring to the front door, then in
			for p in _arc(b["pos"], atan2(din.z, din.x), a_front, ring):
				add.call(p, 1)
			add.call(b["pos"] + front * Rules.EXIT_R, 1)
		else:                                         # onto the platform up to the tower's footprint
			add.call(b["pos"] + din * Rules.ARC_R, 1)
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + (pts[k] as Vector3).distance_to(pts[k - 1]))
	return {"pts": PackedVector3Array(pts), "cum": cum, "fast": PackedByteArray(fast), "spans": spans,
			"node_spans": node_spans}


func _build_path_legacy(route: Array) -> Dictionary:
	## Centre line a horde follows: out of the tank bottoms, along each deck, onto the platform of
	## EVERY node it passes (an order passing through a node always counts as passing through it),
	## and onto the destination's platform at the end.
	var pts := []                                   # plain Arrays: lambdas capture them by reference
	var fast := []                                  # 1 = node/pier segment (fast), 0 = deck
	var spans := []                                 # {edge, s0, s1, forward}
	var node_spans := []                            # {node, s0, s1}: intermediate nodes only
	var add := func(p: Vector3, is_fast: bool) -> void:
		pts.append(p)
		fast.append(1 if is_fast else 0)
	var a: Dictionary = nodes[route[0]]
	var d := (nodes[route[1]]["pos"] - a["pos"]).normalized() as Vector3
	var brawl := not Rules.bridge_combat
	var front := Rules.front_dir()
	var a_front := atan2(front.z, front.x)
	if brawl:                                       # Alpha 11: out of the front door, round the ring to the bridge
		add.call(a["pos"] + front * Rules.EXIT_R, true)
		for p in _arc(a["pos"], a_front, atan2(d.z, d.x), Rules.BRAWL_RING):
			add.call(p, true)
	else:
		add.call(a["pos"] + d * Rules.EXIT_R, true)
	add.call(a["pos"] + d * (Rules.R - 0.5), true)
	for i in range(route.size() - 1):
		a = nodes[route[i]]
		var b: Dictionary = nodes[route[i + 1]]
		d = (b["pos"] - a["pos"]).normalized()
		var ei := _edge_index(route[i], route[i + 1])
		var deck := deck_points(ei, route[i])
		add.call(deck[0], false)
		var s0 := _length(pts)
		for k in range(1, deck.size() - 1):
			add.call(deck[k], false)                 # overpass: up the ramp, along the raised span
		add.call(deck[-1], true)
		spans.append({"edge": ei, "s0": s0, "s1": _length(pts), "forward": edges[ei]["a"] == route[i]})
		var node_s0 := _length(pts)                 # b's platform starts here for every route node
		add.call(b["pos"] - d * (Rules.R - 0.5), true)
		var a_in := atan2(-d.z, -d.x)               # direction from b's centre back toward a
		var a_out: float
		if i + 1 < route.size() - 1:
			var d2 := (nodes[route[i + 2]]["pos"] - b["pos"]).normalized() as Vector3
			a_out = atan2(d2.z, d2.x)
			for p in _arc(b["pos"], a_in, a_out, Rules.BRAWL_RING if brawl else Rules.ARC_R):
				add.call(p, true)
			add.call(b["pos"] + d2 * (Rules.R - 0.5), true)
			node_spans.append({"node": route[i + 1], "s0": node_s0, "s1": _length(pts)})
		else:
			# destination: straight onto the platform from this side, up to the tower's footprint -
			# the whole platform is the node, every side is an entrance
			if brawl:                                   # Alpha 11: round the ring to the front door, then in
				for p in _arc(b["pos"], a_in, a_front, Rules.BRAWL_RING):
					add.call(p, true)
				add.call(b["pos"] + front * Rules.EXIT_R, true)
			else:
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


func deck_points(ei: int, from_id: int) -> Array:
	if v3:
		return _deck_points3(ei, from_id)
	return _deck_points_legacy(ei, from_id)


func _deck_points3(ei: int, from_id: int) -> Array:
	## maps 3.0: pier end to pier end along the baked exits, up the ramp to the planner's height
	## (+4 / +8 overpass, -4 underpass), flat, and down - the pieces MapBuilder lays for it.
	var e: Dictionary = edges[ei]
	if e["plaza"]:
		return [exit_of(ei, from_id), exit_of(ei, _other_end(ei, from_id))]
	var g: Dictionary = e["geo"]
	var A := Vector3(g["A"][0], 0.0, g["A"][1])
	var B := Vector3(g["B"][0], 0.0, g["B"][1])
	var u := (B - A).normalized()
	var h: float = g["h"]
	var out := [A + u * float(g["p0"])]
	if h != 0.0:
		out.append(A + u * (float(g["p0"]) + float(g["r0"])) + Vector3.UP * h)
		out.append(B - u * (float(g["p1"]) + float(g["r1"])) + Vector3.UP * h)
	out.append(B - u * float(g["p1"]))
	if from_id != e["a"]:
		out.reverse()
	return out


func _deck_points_legacy(ei: int, from_id: int) -> Array:
	## A deck's centre line from its pier end at from_id to the far pier end. An overpass rises
	## OVERPASS_H over its first module, runs raised, and comes down over its last - the same shape
	## as the kit's Deck_Overpass_Ramp / Span / Ramp that MapBuilder lays for it.
	var e: Dictionary = edges[ei]
	var pa: Vector3 = nodes[from_id]["pos"]
	var pb: Vector3 = nodes[_other_end(ei, from_id)]["pos"]
	var d := (pb - pa).normalized()
	var p0 := pa + d * (Rules.R + Rules.PIER)
	var p1 := pb - d * (Rules.R + Rules.PIER)
	var out := [p0]
	if e["overpass"] and e["modules"] >= 2 and e["state"] == "" and not e["retracts"]:
		for k in range(1, e["modules"]):
			out.append(p0.lerp(p1, float(k) / e["modules"]) + Vector3.UP * Rules.OVERPASS_H)
	out.append(p1)
	return out


static func level_of(p: Vector3) -> int:
	## maps 3.0: "lines only meet on the same height" - decks sit at 0, +4, -4 or +8 m (ramps between).
	return roundi(p.y / 3.0)


static func overpass_at(h: Dictionary, s: float, edge_list: Array) -> int:
	## The overpass edge a horde's line is on at arc length s, or -1 (any other deck, pier, platform).
	for sp in h["spans"]:
		if s >= sp["s0"] and s <= sp["s1"]:
			return sp["edge"] if edge_list[sp["edge"]]["overpass"] else -1
	return -1


static func sample(h: Dictionary, s: float) -> Array:
	## [position, unit tangent, is_fast] at arc length s along a horde's path, including the
	## motion of a deck it is riding (retract pull, dissolve drop; nobody rides a rotation).
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
	var pos := pts[lo].lerp(pts[hi], t)
	var fwd := (pts[hi] - pts[lo]).normalized()
	if h.has("ride"):
		var r: Dictionary = h["ride"]
		if s >= r["s0"] - 0.01 and s <= r["s1"] + 0.01:
			match r["kind"]:
				"retract":
					pos += r["shift"]
				_:
					pos.y -= r["sink"]
	return [pos, fwd, h["fast"][lo] == 1]


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
	for n in nodes:                                   # production (vat nodes only), up to the cap
		if n["owner"] != "" and has_vat(n) and n["units"] < Rules.CAPS[n["tier"]]:
			n["units"] = minf(Rules.CAPS[n["tier"]], n["units"] + production(n) * dt)
	_step_relays(dt)
	_step_structures(dt)
	for n in nodes:                                   # the door emits the current order into its line
		if n["streaming"].is_empty():
			continue
		var h := _horde(n["streaming"]["hid"])
		if h.is_empty() or h["owner"] != n["owner"]:
			_end_streaming(n, "lost")
			continue
		var x: float = minf(n["streaming"]["remaining"], minf(Rules.exit_rate() * dt, n["units"]))
		n["units"] -= x
		h["units"] += x
		n["streaming"]["remaining"] -= x
		if n["streaming"]["remaining"] <= 0.001 or n["units"] <= 0.0:
			_end_streaming(n, "done")
	_check_missing_decks()
	for h in hordes:
		if h["state"] == "move" and not h.get("blocked", false):
			var here := sample(h, h["s"])
			var fast_here: bool = here[2]
			var mult: float = Rules.platform_mult() if fast_here else 1.0
			if Rules.bridge_combat and on_enemy_goo(h):
				mult *= Rules.GOO_SLOW                    # enemy goo: slower (home advantage)
			var ds: float = Rules.move_speed() * h.get("speed", 1.0) * stat(h["owner"], "speed") * mult * dt
			if h["streaming"]:                        # the head cannot outrun the door: the line stays attached
				ds = minf(ds, Rules.exit_rate() * Rules.metres_per_unit() * dt)
			h["s"] += ds
			if h["s"] >= h["L"]:
				h["s"] = h["L"]
				h["state"] = "absorb"
	_detect_contacts()
	var dead := []
	for pair in fights:                               # every contact pair trades losses, to the death
		var a := _horde(pair[0])
		var b := _horde(pair[1])
		if a.is_empty() or b.is_empty():
			continue
		a["pending_loss"] = a.get("pending_loss", 0.0) + (Rules.FIGHT_RATE_BASE + Rules.FIGHT_RATE_K * b["units"]) * dt * attack_of(b["owner"]) / stat(a["owner"], "health")
		b["pending_loss"] = b.get("pending_loss", 0.0) + (Rules.FIGHT_RATE_BASE + Rules.FIGHT_RATE_K * a["units"]) * dt * attack_of(a["owner"]) / stat(b["owner"], "health")
	_tug_of_war(dt)
	for h in hordes:
		if h["state"] == "absorb":
			# the line keeps pouring in through the door: units enter as fast as the tail advances
			var len := chain_length(h)
			var tail := sample(h, h["L"] - len)
			var tail_speed: float = Rules.move_speed() * (Rules.platform_mult() if tail[2] else 1.0)
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
		elif h["state"] == "move" and fighting.has(h["id"]) and not h.get("retreat", false):
			h["state"] = "fight"
	_check_end()


func _check_missing_decks() -> void:
	## A horde never walks across a deck that is no longer there (Daniele, Alpha 12/14 playtests:
	## "the enemy crossed a bridge even if there was no bridge"; "when units are crossing a bridge
	## and the bridge changes they still don't consistently fall"). Every deck the line overlaps is
	## checked each step - not only the one under its head - so a tail still on a deck that has
	## dissolved, retracted or collapsed falls too, and a line that walked onto a deck while it was
	## moving falls once the motion ends. A head reaching the lip of a missing deck walks off it:
	## the line pours into the void at deck speed.
	for h in hordes.duplicate():
		if not (h in hordes) or h.has("ride"):
			continue
		var head: float = h["s"]
		var tail: float = head - chain_length(h)
		for sp in h["spans"]:
			if not (h in hordes):
				break
			if head < sp["s0"] or tail > sp["s1"]:
				continue                                  # the line doesn't touch this deck
			var ei: int = sp["edge"]
			var ctrl: int = edge_controller.get(ei, -1)
			if ctrl >= 0 and ei in nodes[ctrl]["moving_edges"] and nodes[ctrl]["relay"] != "rotation":
				continue                                  # mid-motion: the tick decides its fate (a turning deck
				                                          # flung its lines at the tick: it is gone right away)
			if is_edge_open(ei):
				continue
			if h["streaming"]:
				var src: Dictionary = nodes[h["route"][0]]
				if src["streaming"].get("hid", -1) == h["id"]:
					_end_streaming(src, "void")
			if not (h in hordes):
				break
			var head_on: bool = head >= sp["s0"] and head <= sp["s1"]
			_cut_range(h, sp["s0"], sp["s1"], "fall", -1, false)
			if head_on and h in hordes:
				h["s"] = sp["s0"]                         # the head stays at the lip; the next step pours more
				h["state"] = "move"


func _current_span(h: Dictionary) -> Dictionary:
	for sp in h["spans"]:
		if h["s"] >= sp["s0"] and h["s"] <= sp["s1"]:
			return sp
	return {}



static func full_length(units: float) -> float:
	## Length of a horde's line once it has fully left its vat.
	return clampf(units * Rules.metres_per_unit(), 1.0, Rules.max_chain())


static func chain_length(h: Dictionary) -> float:
	## Deck a horde occupies behind its head. While it is still streaming out of its vat the tail is
	## at the source, so the line is only as long as the head has travelled.
	return minf(full_length(h["units"]), maxf(h["s"], 1.0))


func _detect_contacts() -> void:
	## Geometric contact, anywhere on the board (Alpha 12 - Daniele: "whenever an enemy crosses the
	## hitbox of a unit they fight... always a combat to death"): every patch of every line goes into
	## a spatial hash; a horde's HEAD within Rules.CONTACT_R of an enemy patch engages it (frontline
	## if the two heads face each other, rear if it caught the enemy's body or tail); a friend's
	## body ahead going the same way blocks (queue, no passing through).
	_contact_now = {}
	_detect_contacts_inner()
	# fights are to the death, EXCEPT that a retreating horde breaks off once out of contact
	for key in fight_info.keys():
		if _contact_now.has(key):
			continue
		var ids: PackedStringArray = key.split(":")
		var a := _horde(int(ids[0]))
		var b := _horde(int(ids[1]))
		if a.get("retreat", false) or b.get("retreat", false):
			fight_info.erase(key)
			fights = fights.filter(func(p): return not (p[0] == int(ids[0]) and p[1] == int(ids[1])))


func _detect_contacts_inner() -> void:
	if not Rules.bridge_combat:                      # Alpha 11 mode: no fights or queues in transit
		for h in hordes:
			h["blocked"] = false
			h.erase("blocked_by")
		return
	var grid := {}
	var cell := Rules.CONTACT_CELL
	for h in hordes:
		h["blocked"] = false
		h.erase("blocked_by")
		if h["state"] == "absorb" or h["units"] <= 0.0:
			continue
		var n := clampi(int(chain_length(h) / Rules.PATCH_SPACING) + 1, 1, Rules.MAX_PATCHES)
		for k in range(n):
			var s: float = h["s"] - k * Rules.PATCH_SPACING
			if s < 0.0:
				break
			var smp := sample(h, s)
			var p: Vector3 = smp[0]
			var key := Vector2i(floori(p.x / cell), floori(p.z / cell))
			if not grid.has(key):
				grid[key] = []
			grid[key].append([h, k, p, smp[1], level_of(p) if v3 else overpass_at(h, s, edges)])
	for h in hordes:
		if h["state"] == "absorb" or h["state"] == "ride" or h["units"] <= 0.0:
			continue
		var smp := sample(h, h["s"])
		var p: Vector3 = smp[0]
		var fwd: Vector3 = smp[1]
		var over := level_of(p) if v3 else overpass_at(h, h["s"], edges)   # lines only meet on the same height
		var key := Vector2i(floori(p.x / cell), floori(p.z / cell))
		var best_friend := {}
		var best_d := INF
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var list: Array = grid.get(key + Vector2i(dx, dz), [])
				for y in list:
					var other: Dictionary = y[0]
					if other["id"] == h["id"] or y[4] != over:
						continue
					var d: float = p.distance_to(y[2])
					if d > Rules.CONTACT_R:
						continue
					if not allied(other["owner"], h["owner"]):
						var kind := "frontline" if (y[1] == 0 and fwd.dot(y[3]) < 0.0) else "rear"
						_engage(h, other, kind)
					elif y[1] > 0 and fwd.dot(y[3]) > 0.3 and fwd.dot(y[2] - p) > 0.0 \
							and other.get("blocked_by", -1) != h["id"] and d < best_d:
						best_d = d
						best_friend = other
		if not best_friend.is_empty():
			h["blocked"] = true
			h["blocked_by"] = best_friend["id"]           # queued at this friend's tail


func power_of(h: Dictionary) -> float:
	## Fighting weight at a contact: units x attack (faction x forge) x health, and a line standing
	## on enemy goo pushes at Rules.GOO_PUSH of that (the front slides toward it: home advantage).
	var p: float = h["units"] * attack_of(h["owner"]) * stat(h["owner"], "health")
	return p * (Rules.GOO_PUSH if Rules.bridge_combat and on_enemy_goo(h) else 1.0)


func _tug_of_war(dt: float) -> void:
	## TUG-OF-WAR (Daniele, Alpha 13 playtest - bridge-combat mode): the front no longer stands
	## still while both blobs shrink; it SLIDES toward the weaker side at a speed set by the gap in
	## numbers - Rules.TUG_SPEED x deck speed at total dominance, zero when even. Frontline: the
	## stronger head advances, the weaker is shoved back along its own path. Rear attack: both move
	## the same way (a stronger pursuer shoves the caught line forward; a stronger caught line
	## shoves the pursuer back). A retreating horde moves under its own power and is never shoved;
	## a riding horde (relay in motion) belongs to the deck. Pushing a fight onto a relay deck, then
	## dropping or rotating it, is the big moment this is for.
	for key in fight_info:
		var info: Dictionary = fight_info[key]
		var ids: PackedStringArray = key.split(":")
		var a := _horde(int(ids[0]))
		var b := _horde(int(ids[1]))
		if a.is_empty() or b.is_empty():
			continue
		if a.get("retreat", false) or b.get("retreat", false) or a.has("ride") or b.has("ride"):
			continue
		var pa := power_of(a)
		var pb := power_of(b)
		if pa + pb <= 0.0:
			continue
		var v: float = Rules.TUG_SPEED * Rules.deck_speed * (pa - pb) / (pa + pb) * dt
		if info["kind"] == "frontline":
			_shift(a, v)
			_shift(b, -v)
		else:
			var att := a if info["attacker"] == a["id"] else b
			var oth := b if att == a else a
			var s: float = v if att == a else -v            # >0: the attacker is winning
			_shift(att, s)
			_shift(oth, s)


func _shift(h: Dictionary, ds: float) -> void:
	if h["state"] == "absorb":
		return
	h["s"] = clampf(h["s"] + ds, 1.0, h["L"])


func recall(hid: int) -> bool:
	## RECALL / RETREAT (Daniele: "one mid-fight choice, so committing troops isn't permanent"):
	## the horde turns round and flows back the way it came to the node it left. Nothing still in
	## the vat leaves. It keeps moving even while an enemy is on it - a pursuer still trades losses
	## with its tail - so a retreat under pressure costs, but it gets out. A horde that has only
	## just left pours straight back in.
	if not Rules.bridge_combat:                       # BRAWL is Alpha 11: an order, once sent, is committed
		return false
	var h := _horde(hid)
	if h.is_empty() or h["state"] == "absorb" or h.get("retreat", false) or h.has("ride"):
		return false
	if h["streaming"]:
		var src: Dictionary = nodes[h["route"][0]]
		if src["streaming"].get("hid", -1) == h["id"]:
			_end_streaming(src, "recalled")
	if not (h in hordes):
		return true
	var old_s: float = h["s"]
	var origin: int = h["route"][0]
	if old_s < Rules.R + Rules.PIER:                        # still on its own platform: straight back in
		_arrive(nodes[origin], h, h["units"])
		h["units"] = 0.0
		_kill_horde(h, "recalled")
		events.append({"t": time, "type": "recall", "seat": h["owner"], "units": 0.0})
		return true
	var len := chain_length(h)
	var cum: PackedFloat32Array = h["cum"]
	var pts: PackedVector3Array = h["pts"]
	var fast: PackedByteArray = h["fast"]
	var back_pts := [sample(h, old_s)[0]]
	var back_fast := [1 if sample(h, old_s)[2] else 0]
	for k in range(cum.size() - 1, -1, -1):
		if cum[k] < old_s:
			back_pts.append(pts[k])
			back_fast.append(fast[maxi(k - 1, 0)])
	var m := 0
	for sp in h["spans"]:
		if sp["s0"] < old_s:
			m += 1
	var new_spans := []
	for i in range(m - 1, -1, -1):
		var sp: Dictionary = h["spans"][i]
		new_spans.append({"edge": sp["edge"], "s0": old_s - minf(sp["s1"], old_s), "s1": old_s - sp["s0"], "forward": not sp["forward"]})
	var new_ns := []
	for i in range(h["node_spans"].size() - 1, -1, -1):
		var ns: Dictionary = h["node_spans"][i]
		if ns["s0"] < old_s:
			new_ns.append({"node": ns["node"], "s0": old_s - minf(ns["s1"], old_s), "s1": old_s - ns["s0"]})
	var new_route := []
	for i in range(m, -1, -1):
		new_route.append(h["route"][i])
	var new_cum := PackedFloat32Array([0.0])
	for k in range(1, back_pts.size()):
		new_cum.append(new_cum[k - 1] + (back_pts[k] as Vector3).distance_to(back_pts[k - 1]))
	h["pts"] = PackedVector3Array(back_pts)
	h["cum"] = new_cum
	h["fast"] = PackedByteArray(back_fast)
	h["spans"] = new_spans
	h["node_spans"] = new_ns
	h["route"] = new_route
	h["target"] = origin
	h["L"] = new_cum[-1]
	h["s"] = minf(len, h["L"])                              # the old tail is the new head
	h["state"] = "move"
	h["retreat"] = true
	h["ordered"] = h["units"]
	for key in fight_info.keys():                           # it breaks off its fights
		var ids: PackedStringArray = key.split(":")
		if int(ids[0]) == hid or int(ids[1]) == hid:
			fight_info.erase(key)
	fights = fights.filter(func(p): return p[0] != hid and p[1] != hid)
	events.append({"t": time, "type": "recall", "seat": h["owner"], "units": h["units"]})
	fx_events.append({"type": "recall", "hid": hid})
	return true


var _contact_now := {}                            # pair keys in contact this step


func _engage(a: Dictionary, b: Dictionary, kind: String) -> void:
	var lo := mini(a["id"], b["id"])
	var hi := maxi(a["id"], b["id"])
	var key := "%d:%d" % [lo, hi]
	if _contact_now.has(key):                     # already engaged this step (the first call decided it)
		return
	_contact_now[key] = true
	var pair := [lo, hi]
	if pair in fights:
		return
	fights.append(pair)
	fight_info[key] = {"kind": kind, "attacker": a["id"]}   # a's head made the contact
	if a["state"] != "ride" and not a.get("retreat", false):
		a["state"] = "fight"
	if b["state"] != "ride" and not b.get("retreat", false):
		b["state"] = "fight"
	events.append({"t": time, "type": kind, "seats": [a["owner"], b["owner"]]})


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


func _arrive(n: Dictionary, h: Dictionary, x: float) -> void:
	## The line pours onto the platform. Own node: reinforce the garrison. Otherwise the units sit
	## on the platform as a siege and fight the garrison there (see _node_fights); the whole
	## platform is the node.
	var owner: String = h["owner"]
	if allied(n["owner"], owner):                      # own or an ally's node: reinforce it
		n["units"] += x
		return
	if not Rules.bridge_combat:
		_land_classic(n, owner, x)
		return
	n["siege"][owner] = n["siege"].get(owner, 0.0) + x
	if not n["siege_dir"].has(owner):
		var landing: Vector3 = sample(h, h["L"] - 2.0)[0]
		n["siege_dir"][owner] = ((landing - n["pos"]) as Vector3).normalized()


func _land_classic(n: Dictionary, seat: String, x: float) -> void:
	## CLASSIC MODE (bridge combat OFF) = Alpha 11's core rule (Daniele: "exactly the core rule of
	## Alpha 11"; "units wait outside - they should just go in"). Each unit is resolved the moment it
	## reaches the target (Alpha 11 simulation.gd land()): it trades blows with the garrison until one
	## of them is gone - an attacker kills attack / (health x garrison) defenders before dying, and takes
	## the defender's attack / its own health per exchange. At baseline that is one-for-one. When the
	## garrison reaches zero the survivors take the node. Nothing sits outside as a siege.
	var att: float = attack_of(seat)
	var hp_att: float = stat(seat, "health")
	var d_seat: String = n["owner"]
	var kill_per: float = att / (stat(d_seat, "health") * stat(d_seat, "garrison"))   # defenders per exchange
	var cost_per: float = (attack_of(d_seat) if d_seat != "" else 1.0) / hp_att          # attacker per exchange
	var ratio: float = kill_per / maxf(cost_per, 0.0001)                                  # defenders killed per attacker
	var garrison: float = n["units"]
	var killed: float = minf(garrison, x * ratio)
	var spent: float = minf(x, killed / maxf(ratio, 0.0001))
	n["units"] = garrison - killed
	combat_losses[seat] = combat_losses.get(seat, 0.0) + spent
	if d_seat != "":
		combat_losses[d_seat] = combat_losses.get(d_seat, 0.0) + killed
	var left: float = x - spent
	if n["units"] <= 0.0001 and left > 0.0001:
		var old: String = n["owner"]
		_capture(n, seat, left)
		events.append({"t": time, "type": "capture", "node": n["id"], "seat": seat, "from": old})
		captured.emit(n["id"], seat, old)


func _register_transit() -> void:
	## An order passing through a node always counts as passing through it, unless the node is the
	## horde's own or an ally's (pure pass-through, GAME-RULES §6) or neutral (a free glide). There
	## is no hidden shield: a passing force fights the garrison itself. BRAWL: waypoints are free.
	for n in nodes:
		n["transit"] = {}
	if not Rules.bridge_combat:                        # classic (Alpha 11): waypoints are free
		return
	for h in hordes:
		if h["state"] == "absorb":
			continue
		for idx in range(h["node_spans"].size()):
			var ns: Dictionary = h["node_spans"][idx]
			var n: Dictionary = nodes[ns["node"]]
			if allied(n["owner"], h["owner"]) or n["owner"] == "":
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
	## arrived (persistent siege) or are passing through this frame (transit); both fight the real
	## garrison. When the garrison is beaten down the node flips to the strongest arrived side
	## (transit alone never captures). Returns hordes wiped out en route.
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
		var total_att_w := 0.0                        # attack-weighted, for the damage they deal
		for k in force:
			total_att += force[k]
			total_att_w += force[k] * attack_of(k)
		var loss := {}
		var g_loss_units := 0.0                       # arrivals (siege) fight the real garrison
		var g_attack := attack_of(n["owner"])
		var g_tough := stat(n["owner"], "garrison")   # garrison strength: damage the garrison takes
		for k in force:
			# what k faces here: the garrison (unless allied) and every hostile seat on the platform
			var enemy: float = 0.0 if allied(k, n["owner"]) else n["units"] * g_attack
			for j in force:
				if not allied(j, k):
					enemy += force[j] * attack_of(j)
			if enemy <= 0.0:
				continue
			# a near-empty garrison is a weak toll (Daniele, Alpha 14: "a weak one is easy to punch
			# through"): the flat base rate fades in over the first 20 units of what it faces
			loss[k] = (Rules.FIGHT_RATE_BASE * minf(1.0, enemy / 20.0) + Rules.FIGHT_RATE_K * enemy) * dt * mult / stat(k, "health")
			if n["units"] > 0.0 and force[k] > 0.0 and not allied(k, n["owner"]):
				var rate: float = (Rules.FIGHT_RATE_BASE + Rules.FIGHT_RATE_K * force[k]) * dt * mult * attack_of(k) / g_tough
				var siege_part: float = n["siege"].get(k, 0.0)
				var transit_part: float = n["transit"].get(k, {}).get("units", 0.0)
				g_loss_units += rate * ((siege_part + transit_part) / force[k])   # transit fights the garrison too
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
		if g_loss_units > 0.0:                         # arrivals damage the real garrison
			var before_g: float = n["units"]
			n["units"] = maxf(0.0, before_g - g_loss_units)
			if n["owner"] != "":
				combat_losses[n["owner"]] = combat_losses.get(n["owner"], 0.0) + before_g - n["units"]
				n["node_loss"][n["owner"]] = (before_g - n["units"]) / maxf(dt, 0.0001)
		if n["units"] <= 0.0:
			# capture needs an ARRIVAL, not just transit; with several sides arrived at once the side
			# holding more ground there right now takes it (Strait's shared hub used to stall forever)
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
				_capture(n, winner_seat, n["siege"][winner_seat])
				events.append({"t": time, "type": "capture", "node": n["id"], "seat": winner_seat, "from": old})
				captured.emit(n["id"], winner_seat, old)
	return destroyed


func _capture(n: Dictionary, seat: String, garrison: float) -> void:
	if not n["streaming"].is_empty():
		_end_streaming(n, "lost")
	if n["relay_phase"] == "warning":                  # capturing a relay during its warning cancels
		n["relay_phase"] = ""                          # the pending switch (GAME-RULES sec8)
		n["relay_t"] = 0.0
	n["build_kind"] = ""                               # construction is cancelled by capture
	n["build_target"] = {}
	# conquest costs a tier (Daniele: "if a vat or tower is conquered it gets downgraded one tier,
	# minimum 1") - both modes. A forge is single-tier and is kept as it is.
	if n["owner"] != "" and n["owner"] != seat:
		if n["attachment"] == "cannon":
			n["cannon_tier"] = maxi(1, n["cannon_tier"] - 1)
		elif Sim.has_vat(n):
			n["tier"] = maxi(1, n["tier"] - 1)
	n["owner"] = seat
	n["units"] = garrison
	n["siege"] = {}
	n["siege_dir"] = {}
	fx_events.append({"type": "capture", "node": n["id"], "seat": seat})


# ------------------------------------------------------------------ Last Stand (GAME-RULES sec10)
func bonded(edge_index: int) -> bool:
	## The goo corridor between two adjacent nodes of one player - always on (Daniele, Alpha 14:
	## "goo corridors appear between any two adjacent nodes you own"). Capture either end and it
	## drains (the view animates the drain).
	var e: Dictionary = edges[edge_index]
	var a: Dictionary = nodes[e["a"]]
	var b: Dictionary = nodes[e["b"]]
	return a["owner"] != "" and a["owner"] == b["owner"] and is_edge_open(edge_index)


func goo_owner(edge_index: int) -> String:
	## Whose goo covers this deck ("" = none).
	return nodes[edges[edge_index]["a"]]["owner"] if bonded(edge_index) else ""


func on_enemy_goo(h: Dictionary) -> bool:
	## Is this horde's head on a deck covered in another player's goo? (Alpha 14 home advantage:
	## enemies on your goo are slower and the tug-of-war front pushes toward them.)
	var sp := _current_span(h)
	if sp.is_empty():
		return false
	var g := goo_owner(sp["edge"])
	return g != "" and not allied(g, h["owner"])


func _step_last_stand(dt: float) -> void:
	if over:
		return
	if not last_stand_active:
		if not Rules.last_stand:
			return
		if time < Rules.LAST_STAND_TIME:
			return
		if v3 and ((_map_last_stand.get("methods", []) as Array).is_empty()):
			return                                        # maps 3.0 tutorials have no Last Stand
		_start_last_stand()
		return
	if v3:
		_step_rings(dt)
		return
	if last_stand_warn_node >= 0:
		last_stand_warn_t -= dt
		if last_stand_warn_t <= 0.0:
			_drop_node(last_stand_warn_node)
			last_stand_warn_node = -1
	elif last_stand_next < last_stand_order.size() and time >= _next_wave_at:
		last_stand_warn_node = last_stand_order[last_stand_next]
		last_stand_next += 1
		last_stand_warn_t = Rules.LAST_STAND_WARNING
		_next_wave_at += last_stand_wave
		events.append({"t": time, "type": "collapse_warning", "node": last_stand_warn_node})
		fx_events.append({"type": "collapse_warning", "node": last_stand_warn_node})


func _start_last_stand() -> void:
	if v3:
		_start_rings()
		return
	_start_last_stand_legacy()


# ---------------------------------------------------------------- maps 3.0: ring Last Stand
# Daniele, Alpha 17: "Last Stand no longer works with a designated first and last node but with the
# rings designed on the maps; a relay only falls when all its connecting rings already fell (it skips
# the rule until the others have gone); and Last Stand NEVER leaves platforms unconnected -
# especially important for chaos." Each wave drops one whole ring in the order of the revealed method
# (the map's orders; chaos: one of its connected orders); the order's last ring never falls; a relay
# waits until every ring it links to has fallen; anything a wave would cut off from the surviving map
# (fixed decks and plaza links only - never counting on a relay deck) falls with that wave.
func _start_rings() -> void:
	last_stand_active = true
	var methods: Array = (_map_last_stand.get("methods", []) as Array).filter(func(m): return _ring_orders.has(m))
	if methods.is_empty():                             # the map has no Last Stand (maps 3.0 tutorials)
		last_stand_waves = []
		last_stand_method = ""
		return
	last_stand_method = methods[rng.randi_range(0, methods.size() - 1)]
	var order: Array = []
	if last_stand_method == "chaos":
		var all: Array = _ring_orders.get("chaos", [])
		order = all[rng.randi_range(0, all.size() - 1)] if not all.is_empty() else []
	else:
		order = _ring_orders.get(last_stand_method, [])
	if order.is_empty():                                 # a map without orders: rings from the outside in
		var rs := {}
		for n in nodes:
			rs[n["ring"]] = true
		order = rs.keys()
		order.sort()
		order.reverse()
		last_stand_method = "inward"
	var keep_ring: int = int(order[-1])
	last_stand_keep = {}
	for n in nodes:
		if n["ring"] == keep_ring:
			last_stand_keep[n["id"]] = true
	last_stand_final = last_stand_keep.keys()[0] if not last_stand_keep.is_empty() else -1
	last_stand_waves = _plan_waves(order)
	last_stand_order = []
	for w in last_stand_waves:
		last_stand_order.append_array(w)
	last_stand_next = 0
	last_stand_wave = clampf((Rules.MATCH_HARD_END - 90.0 - Rules.LAST_STAND_TIME) / maxf(last_stand_waves.size(), 1.0),
			Rules.LAST_STAND_WAVE_MIN, Rules.LAST_STAND_WAVE_MAX)
	events.append({"t": time, "type": "last_stand", "method": last_stand_method, "order": order.duplicate(),
			"waves": last_stand_waves.duplicate(true)})
	fx_events.append({"type": "last_stand", "method": last_stand_method})
	_next_wave_at = time + last_stand_wave
	_warn_wave()                                          # the first warning starts with the reveal


func _plan_waves(order: Array) -> Array:
	## The whole collapse, planned at the reveal so the badges can show it: ring by ring, relays held
	## back until every ring they link to has gone, and nothing ever left as an island.
	var gone := collapsed.duplicate()
	var fallen_rings := {}
	var waves := []
	var held := []                                        # relays waiting for their rings
	for k in range(order.size() - 1):
		var r: int = int(order[k])
		fallen_rings[r] = true
		var wave := []
		for n in nodes:
			if gone.get(n["id"], false) or last_stand_keep.has(n["id"]):
				continue
			if n["ring"] == r:
				if n["relay"] != "":
					if not n["id"] in held:
						held.append(n["id"])
				else:
					wave.append(n["id"])
		for id in held.duplicate():                        # a relay goes once all its rings have fallen
			var ready := true
			for link in adj[id]:
				var nb: Dictionary = nodes[link[0]]
				if not fallen_rings.has(nb["ring"]) and not gone.get(nb["id"], false) and not nb["id"] in wave:
					ready = false
			if ready:
				wave.append(id)
				held.erase(id)
		for id in wave:
			gone[id] = true
		for id in _islands(gone):                          # never leave a platform unconnected
			if not id in wave:
				wave.append(id)
				gone[id] = true
				held.erase(id)
		if not wave.is_empty():
			waves.append(wave)
	return waves


func _islands(gone: Dictionary) -> Array:
	## Surviving nodes cut off from the surviving map's main part (the one holding the most of the last
	## ring, then the most nodes), over fixed decks and plaza links only.
	var comp := {}
	var groups := []
	for n in nodes:
		var id: int = n["id"]
		if gone.get(id, false) or comp.has(id):
			continue
		var g := [id]
		comp[id] = groups.size()
		var open := [id]
		while not open.is_empty():
			var cur: int = open.pop_front()
			for link in adj[cur]:
				var e: Dictionary = edges[link[1]]
				if e["state"] != "" or e["retracts"]:
					continue                              # a relay deck may be switched away
				var nb: int = link[0]
				if gone.get(nb, false) or comp.has(nb):
					continue
				comp[nb] = groups.size()
				g.append(nb)
				open.append(nb)
		groups.append(g)
	if groups.size() <= 1:
		return []
	var best := 0
	var best_score := -1
	for gi in range(groups.size()):
		var keep_n := 0
		for id in groups[gi]:
			if last_stand_keep.has(id):
				keep_n += 1
		var score: int = keep_n * 1000 + (groups[gi] as Array).size()
		if score > best_score:
			best_score = score
			best = gi
	var out := []
	for gi in range(groups.size()):
		if gi != best:
			out.append_array(groups[gi])
	return out


func _warn_wave() -> void:
	last_stand_warn = {}
	last_stand_warn_node = -1
	if last_stand_next >= last_stand_waves.size():
		return
	for id in last_stand_waves[last_stand_next]:
		if not collapsed.get(id, false):
			last_stand_warn[id] = true
			fx_events.append({"type": "collapse_warning", "node": id})
	last_stand_queue = _drop_sequence(last_stand_warn.keys())
	last_stand_warn_node = last_stand_queue[0] if not last_stand_queue.is_empty() else -1
	last_stand_warn_t = Rules.LAST_STAND_WARNING
	events.append({"t": time, "type": "collapse_warning", "nodes": last_stand_queue.duplicate()})
	last_stand_next += 1


func _drop_sequence(wave: Array) -> Array:
	## The order a ring's platforms fall in, one at a time (0.18.4): each drop is a platform whose loss
	## leaves every other standing platform connected over fixed decks (the rule for falling bridges -
	## never an island), relays after the ring's other platforms, the farthest from the last ring first.
	var gone := collapsed.duplicate()
	var left: Array = wave.duplicate()
	var depth := _keep_depth()
	var out := []
	while not left.is_empty():
		var best := -1
		var best_score := -INF
		for id in left:
			var trial := gone.duplicate()
			trial[id] = true
			var score: float = depth.get(id, 0) * 10.0 - (1000.0 if nodes[id]["relay"] != "" else 0.0)
			if not _islands(trial).is_empty():
				score -= 100000.0                          # would strand another platform: only as a last resort
			if score > best_score or (score == best_score and id < best):
				best_score = score
				best = id
		out.append(best)
		left.erase(best)
		gone[best] = true
	return out


func _keep_depth() -> Dictionary:
	## Hops from the last ring (the one that never falls) over fixed decks: the Last Stand collapses
	## from the far side toward it.
	var dist := {}
	var open := []
	for id in last_stand_keep:
		dist[id] = 0
		open.append(id)
	while not open.is_empty():
		var cur: int = open.pop_front()
		for link in adj[cur]:
			var e: Dictionary = edges[link[1]]
			if e["state"] != "" or e["retracts"] or dist.has(link[0]):
				continue
			dist[link[0]] = dist[cur] + 1
			open.append(link[0])
	return dist


func drop_in(id: int) -> float:
	## Seconds until a warned platform drops (its place in the ring's queue), or -1.
	var k := last_stand_queue.find(id)
	return last_stand_warn_t + k * Rules.LAST_STAND_DROP_GAP if k >= 0 else -1.0


func _step_rings(dt: float) -> void:
	if not last_stand_queue.is_empty():
		last_stand_warn_t -= dt
		if last_stand_warn_t <= 0.0:
			var id: int = last_stand_queue.pop_front()
			last_stand_warn.erase(id)
			if not collapsed.get(id, false):
				_drop_node(id)
			while not last_stand_queue.is_empty() and collapsed.get(last_stand_queue[0], false):
				last_stand_warn.erase(last_stand_queue.pop_front())   # taken by an earlier cut
			if last_stand_queue.is_empty():
				last_stand_warn = {}
				last_stand_warn_node = -1
				_next_wave_at = maxf(_next_wave_at, time + Rules.LAST_STAND_DROP_GAP)   # the next ring waits
			else:
				last_stand_warn_node = last_stand_queue[0]
				last_stand_warn_t = Rules.LAST_STAND_DROP_GAP
	elif last_stand_next < last_stand_waves.size() and time >= _next_wave_at:
		_next_wave_at += last_stand_wave
		_warn_wave()


func is_warned(id: int) -> bool:
	return last_stand_warn.has(id) if v3 else last_stand_warn_node == id


func is_final(id: int) -> bool:
	return last_stand_keep.has(id) if v3 else id == last_stand_final


func _start_last_stand_legacy() -> void:
	## The hidden method is revealed with the whole order. inward: rim first, the centre final
	## survives; outward: centre first, the map's outward final survives; chaos: a seeded random
	## order (home nodes never before the end), the inward final survives.
	last_stand_active = true
	var methods: Array = _map_last_stand.get("methods", ["inward"])
	if methods.is_empty():
		methods = ["inward"]
	var outward_final = _map_last_stand.get("outwardFinal")
	if outward_final == null:
		methods = methods.filter(func(m): return m != "outward")
	last_stand_method = methods[rng.randi_range(0, methods.size() - 1)]
	var inward_final: int = int(_map_last_stand.get("inwardFinal", 0)) if _map_last_stand.get("inwardFinal") != null else 0
	last_stand_final = int(outward_final) if last_stand_method == "outward" else inward_final
	var centre := Vector3.ZERO
	for n in nodes:
		if n["center"]:
			centre = n["pos"]
	var order := _collapse_order(last_stand_method, centre)
	if order.is_empty() and last_stand_method == "chaos":
		# chaos would have to cut the map into islands or drop a home early (e.g. a line map like
		# Two Piers) - Daniele: "chaos cannot activate on maps like Two Piers; we can't leave
		# isolated nodes". Fall back to inward.
		last_stand_method = "inward"
		last_stand_final = inward_final
		order = _collapse_order("inward", centre)
	last_stand_order = order
	last_stand_next = 0
	last_stand_wave = clampf((Rules.MATCH_HARD_END - 90.0 - Rules.LAST_STAND_TIME) / maxf(order.size(), 1.0),
			Rules.LAST_STAND_WAVE_MIN, Rules.LAST_STAND_WAVE_MAX)
	events.append({"t": time, "type": "last_stand", "method": last_stand_method, "order": order.duplicate(), "final": last_stand_final})
	fx_events.append({"type": "last_stand", "method": last_stand_method})
	_next_wave_at = time + last_stand_wave
	if not order.is_empty():                              # the first warning starts with the reveal
		last_stand_warn_node = order[0]
		last_stand_next = 1
		last_stand_warn_t = Rules.LAST_STAND_WARNING
		events.append({"t": time, "type": "collapse_warning", "node": last_stand_warn_node})
		fx_events.append({"type": "collapse_warning", "node": last_stand_warn_node})


func _collapse_order(method: String, centre: Vector3) -> Array:
	## Builds the drop order for a method so that NO drop ever cuts the remaining map into islands
	## (every surviving node keeps a physical path to the final). Preference per method: inward =
	## farthest from the centre first, outward = nearest first, chaos = seeded random with home
	## nodes never before the end. Returns [] if the method cannot be honoured on this map.
	var remaining := []
	for n in nodes:
		if n["id"] != last_stand_final and not collapsed.get(n["id"], false):
			remaining.append(n["id"])
	var pref := remaining.duplicate()
	match method:
		"outward":
			pref = _ring_order(pref, centre, false)
		"chaos":
			for i in range(pref.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp = pref[i]
				pref[i] = pref[j]
				pref[j] = tmp
		_:
			pref = _ring_order(pref, centre, true)
	var order := []
	var gone := collapsed.duplicate()
	while not remaining.is_empty():
		var pick := -1
		for pass_homes in [false, true]:
			if method != "chaos" and not pass_homes:
				continue                                  # only chaos keeps homes for the end
			for id in pref:
				if not (id in remaining):
					continue
				if not pass_homes and id in homes.values():
					continue
				gone[id] = true
				var ok := _connected_to(last_stand_final, gone)
				gone.erase(id)
				if ok:
					pick = id
					break
			if pick >= 0:
				break
		if pick < 0:
			return []
		order.append(pick)
		remaining.erase(pick)
		gone[pick] = true
	if method == "chaos":
		# "home nodes never before the end" can't hold literally on maps whose homes are leaves;
		# homes are kept as late as connectivity allows, and chaos is only offered where no home
		# has to fall in the first half of the order (otherwise it is just inward with noise)
		for k in range(order.size() / 2):
			if order[k] in homes.values():
				return []
	return order


func _connected_to(root: int, gone: Dictionary) -> bool:
	## Every node not in `gone` can still reach `root` over physical decks (relay states ignored).
	var seen := {root: true}
	var open := [root]
	while not open.is_empty():
		var cur: int = open.pop_front()
		for link in adj[cur]:
			var nb: int = link[0]
			if seen.has(nb) or gone.get(nb, false):
				continue
			seen[nb] = true
			open.append(nb)
	for n in nodes:
		if not gone.get(n["id"], false) and not seen.has(n["id"]):
			return false
	return true


func drop_order_of(node_id: int) -> int:
	## 1-based position in the revealed drop order, 0 if not in it (final, or not revealed yet).
	## maps 3.0: the wave the node falls in.
	if not last_stand_active:
		return 0
	if v3:
		for w in range(last_stand_waves.size()):
			if node_id in last_stand_waves[w]:
				return w + 1
		return 0
	var i := last_stand_order.find(node_id)
	return i + 1 if i >= 0 else 0


func _drop_node(id: int) -> void:
	## Everything on a falling node or its decks dies (GAME-RULES sec10): garrison, siege, every
	## horde portion on the platform or on a deck attached to it. The attachment goes with it.
	var n: Dictionary = nodes[id]
	if n["relay_phase"] == "moving":
		_relay_apply(n)                     # finish the tick: riders get their per-kind fate, the view restores the decks
	collapsed[id] = true
	var old: String = n["owner"]
	if not n["streaming"].is_empty():
		_end_streaming(n, "collapsed")
	if old != "" and n["units"] > 0.0:
		fall_losses[old] = fall_losses.get(old, 0.0) + n["units"]
	for k in n["siege"]:
		fall_losses[k] = fall_losses.get(k, 0.0) + n["siege"][k]
	n["owner"] = ""
	n["units"] = 0.0
	n["siege"] = {}
	n["siege_dir"] = {}
	n["transit"] = {}
	n["attachment"] = ""
	n["cannon_tier"] = 0
	n["build_kind"] = ""
	n["build_target"] = {}
	n["relay_phase"] = ""
	n["moving_edges"] = []
	for h in hordes.duplicate():
		if not (h in hordes):
			continue
		var lo := INF
		var hi := -INF
		for i in range(h["spans"].size()):
			var sp: Dictionary = h["spans"][i]
			var e: Dictionary = edges[sp["edge"]]
			if e["a"] == id or e["b"] == id:
				lo = minf(lo, sp["s0"])
				hi = maxf(hi, sp["s1"])
		for ns in h["node_spans"]:
			if ns["node"] == id:
				lo = minf(lo, ns["s0"])
				hi = maxf(hi, ns["s1"])
		var sps: Array = h["spans"]                   # empty after a recall that never left the plaza
		if h["target"] == id:
			lo = minf(lo, sps[-1]["s1"] if not sps.is_empty() else 0.0)
			hi = maxf(hi, h["L"])
		if h["route"][0] == id:
			lo = 0.0
			hi = maxf(hi, sps[0]["s0"] if not sps.is_empty() else h["L"])
		if lo <= hi:
			h.erase("ride")
			if h["state"] == "ride":
				h["state"] = "move"
			_cut_range(h, lo, hi, "fall", -1)
	events.append({"t": time, "type": "collapse", "node": id, "from": old})
	fx_events.append({"type": "collapse", "node": id, "from": old})   # the view pours the old owner's goo
	for seat in factions.keys():                        # losing your last node to the collapse = defeat
		if eliminated.has(seat):
			continue
		var owns := false
		for m in nodes:
			if m["owner"] == seat:
				owns = true
		if not owns:
			eliminated[seat] = true
			for h in hordes.duplicate():
				if h["owner"] == seat:
					fall_losses[seat] = fall_losses.get(seat, 0.0) + h["units"]
					_kill_horde(h, "eliminated")
			for m in nodes:
				m["siege"].erase(seat)
				m["siege_dir"].erase(seat)
			events.append({"t": time, "type": "eliminated", "seat": seat})


func _force_end() -> void:
	## Safety net: still undecided at 7:00 -> the stronger side (team) wins outright; its strongest
	## seat is named the winner. Without teams every seat is its own side.
	over = true
	var side_total := {}
	var side_seat := {}
	for s in factions.keys():
		var side = teams.get(s, s)
		var v := seat_strength(s)
		side_total[side] = side_total.get(side, 0.0) + v
		if not side_seat.has(side) or v > seat_strength(side_seat[side]):
			side_seat[side] = s
	var best := ""
	var best_v := -1.0
	for side in side_total:
		if side_total[side] > best_v:
			best_v = side_total[side]
			best = side_seat[side]
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
	for s in eliminated:
		alive.erase(s)
	var sides := {}                                   # team modes: one side per team
	for s in alive:
		sides[teams.get(s, s)] = s
	if sides.size() <= 1 and time > 1.0:
		over = true
		winner = sides.values()[0] if sides.size() == 1 else ""
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


func allied(a: String, b: String) -> bool:
	## Same seat, or team-mates in a team mode (2v2). Neutral ("") is nobody's ally.
	if a == "" or b == "":
		return false
	if a == b:
		return true
	return teams.has(a) and teams.has(b) and teams[a] == teams[b]


func _ring_order(ids: Array, centre: Vector3, far_first: bool) -> Array:
	## Inward / outward order by distance from the centre, but nodes on the same ring (within 4 m -
	## symmetric maps have many) come in a seeded random order, so the first node to fall differs
	## from match to match (Daniele, Alpha 14 playtest: "it's always the same node falling first").
	var rings := {}
	for id in ids:
		var key := int(round(nodes[id]["pos"].distance_to(centre) / 4.0))
		if not rings.has(key):
			rings[key] = []
		rings[key].append(id)
	var keys := rings.keys()
	keys.sort()
	if far_first:
		keys.reverse()
	var out := []
	for k in keys:
		var ring: Array = rings[k]
		for i in range(ring.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = ring[i]
			ring[i] = ring[j]
			ring[j] = tmp
		out.append_array(ring)
	return out
