class_name Sim
extends RefCounted
## Game state and rules, no visuals. Deterministic for a given sequence of sends, time steps and
## seed. Rules: Docs/Game Design/Ooze Syndicate 2.0/01 Rules/GAME-RULES.md (§5 hordes, §6 nodes,
## §7 bridges, §8 relays, §10 Last Stand). Baked map layouts and plazas, ring Last Stand,
## geometric contact everywhere, tug-of-war fronts, recall (SIEGE only), always-on goo corridors with
## a home advantage, transit fights the real garrison; BRAWL (bridge_combat off) lands Alpha 11 style.
## SIEGE IS DEACTIVATED since 0.18.7 (Rules.SIEGE_ON): every `Rules.bridge_combat` branch here is dormant
## and untested - BRAWL is the game. Kept, not removed, so SIEGE can be picked up again later.

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
var last_stand_corners: Array = []  # 0.18.7: home node ids of the match's seats in corner-cycle order
var _ls_corner_k := 0                # the corner the next planned drop aims at (carries across rings)
var _next_wave_at := 0.0
var very_last_stand_active := false  # 0.18.9: the post-ring stalemate breaker (Rules.VERY_LAST_STAND_TIME)
var very_last_stand_gap := 0.0       # this match's current interval, derived from the survivor count
                                      # and the time left to Rules.MATCH_HARD_END (Daniele: "the time
                                      # between falls is due to the number of nodes") - reuses
                                      # last_stand_warn / last_stand_queue / last_stand_warn_node /
                                      # last_stand_warn_t so the badges, camera, fx and net snapshot
                                      # need no separate plumbing
var rng := RandomNumberGenerator.new()
var _next_id := 1
# SKILLS 2.0 (0.18.7) - see the "skills" section at the end of this file for the API
var abilities_on := true             # Rules.abilities_on at setup (the match setting)
var loadouts: Dictionary = {}        # seat -> {"active": id, "map": id, "ultimate": id}
var skill_cd: Dictionary = {}        # seat -> {"active": s, "map": s} seconds of cooldown left
var ult_charge: Dictionary = {}      # seat -> 0..1 ultimate charge (1 = ready)
var ult_since: Dictionary = {}       # seat -> seconds since the match start or the last ultimate
var effects: Array = []              # active skill effects, see _add_effect()
var demolished: Dictionary = {}      # edge index -> seconds until the demolished deck rebuilds
var has_relays := false              # the map has at least one relay (Bypass / Relay Hack need one)
var _kill_credit: Dictionary = {}    # seat -> enemy units killed this step (ultimate charge)
var _fx_idx: Dictionary = {}         # "on:target" -> [effects] (rebuilt by _index_effects)
var _popped: Array = []              # decoys that touched an enemy this step (they dissolve)


func setup(map: Dictionary, positions: Dictionary, seats: Dictionary, seat_factions: Dictionary, seed_value: int = -1, seat_teams: Dictionary = {}, seat_loadouts: Dictionary = {}) -> void:
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
			"cannon_pull": {},      # horde id -> metres this burst has cut off its head (it stays the target)
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
	_setup_skills(seat_loadouts)


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
	## Units/s this vat makes now: tier x faction x skills (Spore Burst, Superbloom, Aegis; Echo jams it).
	return _base_production(n) * prod_mult(n)


func _base_production(n: Dictionary) -> float:
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
		if n["owner"] == "" or n["attachment"] != "cannon" or is_disrupted(n["id"]):
			n["cannon_burst"] = 0.0                       # (an Echo Split echo jams a cannon: no burst, no recharge)
			continue
		var stats: Dictionary = Rules.CANNON_STATS[n["cannon_tier"]]
		if n["cannon_burst"] > 0.0:
			var targets := _hordes_in_range(n, n["cannon_pull"])
			if targets.is_empty():
				n["cannon_burst"] = 0.0
				n["cannon_cd"] = stats["recharge"]
				continue
			var budget: float = minf(n["cannon_kill_left"], stats["kill"] / Rules.CANNON_BURST * dt)
			n["cannon_kill_left"] -= budget
			var each: float = budget / targets.size()
			for h in targets:
				var kill: float = minf(each * _cannon_mult(h), h["units"])   # Anchor: half kills on the caster's lines
				if _hit_head(n, h):
					n["cannon_pull"][h["id"]] = n["cannon_pull"].get(h["id"], 0.0) + _cut_front(h, kill)
				else:
					h["units"] -= kill                          # the tail is nearer: the line shortens from it
				if not h.get("decoy", false):                # a decoy draws the fire; its losses are not real
					combat_losses[h["owner"]] = combat_losses.get(h["owner"], 0.0) + kill
					_credit(n["owner"], h["owner"], kill)
				if h["units"] <= 0.0:
					_kill_horde(h, "cannon")
			n["cannon_target"] = _hit_point(n, targets[0])
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
		n["cannon_pull"] = {}
		n["cannon_target"] = _hit_point(n, in_range[0])
		events.append({"t": time, "type": "cannon_burst", "node": n["id"], "seat": n["owner"]})
		fx_events.append({"type": "cannon", "node": n["id"]})


# CANNONS KILL WHERE THE LASER HITS (Daniele, 0.18.7: "towers kills enemies blobs from the bottom instead
# of from the top"): the beam hits the end of the line nearest the tower - the head of a line coming at
# it, the tail of one leaving it - and the bodies die at that end.
func _hit_head(n: Dictionary, h: Dictionary) -> bool:
	## Is the line's head the end nearest this tower (else its tail)?
	var c: Vector3 = n["pos"]
	var head: Vector3 = sample(h, h["s"])[0]
	var tail: Vector3 = sample(h, h["s"] - chain_length(h))[0]
	return head.distance_squared_to(c) <= tail.distance_squared_to(c) + 0.01


func _hit_point(n: Dictionary, h: Dictionary) -> Vector3:
	## Where the beam lands on this line: the end it kills from.
	return sample(h, h["s"] if _hit_head(n, h) else h["s"] - chain_length(h))[0]


func _cut_front(h: Dictionary, kill: float) -> float:
	## `kill` units die at the head: the head pulls back by the length they took up and the tail stays
	## where it is (streaming, fighting, riding and queued lines alike; a capped SIEGE line only thins).
	## A line pouring in through a door keeps its head there - the ones at the door die instead of going
	## in. h["fcut"] counts the metres of line taken off the front, so the view keeps every surviving
	## body where it was and pops the front ones. Returns how far the head went back.
	var before := chain_length(h)
	var units_before: float = h["units"]
	h["units"] -= kill
	if h["state"] == "absorb":
		h["fcut"] = h.get("fcut", 0.0) + maxf(0.0, before - chain_length(h))
		return 0.0
	var back: float
	if before >= h["s"] - 0.001:                      # the tail is still at the door (a line pouring out
		back = kill * before / maxf(units_before, 0.001)   # denser than it walks): what they took of it
	else:
		back = before - full_length(maxf(h["units"], 0.0))
	back = clampf(back, 0.0, h["s"])
	h["s"] -= back
	h["fcut"] = h.get("fcut", 0.0) + back
	return back


func _hordes_in_range(n: Dictionary, pull := {}) -> Array:
	## Enemy lines whose head is within range. `pull` (a burst's horde id -> metres it cut off that
	## head): a line the burst is mowing down from the front stays its target while the head it had
	## is in range - the burst keeps its whole kill budget, as when it took the tail.
	var out := []
	for h in hordes:
		if allied(h["owner"], n["owner"]) or h["units"] <= 0.0:
			continue
		var p: Vector3 = sample(h, h["s"])[0]
		if (p - (n["pos"] as Vector3)).length() <= Rules.CANNON_RANGE + pull.get(h["id"], 0.0):
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
	return _states_of(prefix)


func _states_of(prefix: String) -> Array:
	## A remote or switch whose decks all share one state toggles them on / off (0.18.6: the maps 4.3
	## remotes each drive a single "m1" deck and did nothing when fired).
	var grp: Array = relay_groups.get(prefix, [])
	if grp.size() == 1 and prefix in ["m", "s"]:
		return [grp[0], "off"]
	return grp


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
	var grp: Array = _states_of(e["state"].substr(0, 1))
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
	if demolished.has(edge_index):                  # Demolish (0.18.7): the deck is gone until it rebuilds
		return false
	var e: Dictionary = edges[edge_index]
	if not e["retracts"] and e["state"] == "":
		return true
	var ctrl: int = edge_controller.get(edge_index, -1)
	var index := 0
	if ctrl >= 0:
		if edge_index in nodes[ctrl]["moving_edges"]:
			return false
		var held = anchor_state(edge_index)          # Anchor / Relay Aegis: the deck stays as it was
		if held != null:
			return held
		if is_bypassed(ctrl):                        # Bypass: the relay holds both states
			return true
		# a neutral relay sits at index 0 unless Relay Hack or Rewire fired it (0.18.7: it used to ignore
		# the index while unowned, which was the same thing - nobody could fire it)
		index = nodes[ctrl]["relay_index"]
	return _edge_open_at(edge_index, index)


func fire_relay(node_id: int) -> bool:
	## The owner's control over their relay (GAME-RULES sec8: "fire the switch"): starts the 3 s
	## warning; the authoritative tick then moves the deck and applies the per-kind troop fate.
	var n: Dictionary = nodes[node_id]
	if n["owner"] == "":
		return false
	return _fire_relay_by(n, n["owner"])


func _fire_relay_by(n: Dictionary, seat: String) -> bool:
	## Starts a relay's warning on behalf of `seat` (its owner, or a Relay Hack / Rewire caster).
	if n["relay"] == "" or n["relay_cd"] > 0.0 or n["relay_phase"] != "" or is_relay_locked(n["id"]):
		return false
	if relay_states(n).is_empty():
		return false
	n["relay_pending"] = relay_next_index(n)
	n["relay_phase"] = "warning"
	n["relay_t"] = Rules.RELAY_WARNING
	events.append({"t": time, "type": "relay_fired", "node": n["id"], "seat": seat, "index": n["relay_pending"]})
	fx_events.append({"type": "relay_warning", "node": n["id"]})
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
				n["relay_anim"]["progress"] = clampf(1.0 - n["relay_t"] / Rules.RELAY_MOVE, 0.0, 1.0)   # the view's deck motion
				if n["relay_t"] <= 0.0:
					_relay_apply(n)


func _relay_begin_move(n: Dictionary) -> void:
	## The authoritative tick: the state changes, the affected decks start moving, and every deck that is
	## going away is gone for the troops right now (_relay_drop): whatever is on it falls.
	var old_index: int = n["relay_index"]
	var new_index: int = n["relay_pending"]
	var closing := []
	var opening := []
	for i in controlled_edges(n["id"]):
		if anchor_state(i) != null or is_bypassed(n["id"]):
			continue                                      # Anchor / Aegis lock the deck; Bypass keeps both states
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
	_relay_drop(n, closing, delta)
	n["relay_phase"] = "moving"
	n["relay_t"] = Rules.RELAY_MOVE
	events.append({"t": time, "type": "relay_tick", "node": n["id"], "seat": n["owner"], "index": new_index})
	fx_events.append({"type": "relay_tick", "node": n["id"]})


# RELAYS TAKE THE GROUND AWAY (Daniele, 0.18.7, replacing the per-kind troop fates: "when a switch happens
# units start to fall, no delay, no bridge = bridge down but until the bridge is there they can still try
# to reach the end, as per the rule, so since now switch activation is 1 sec, units on the bridge have 1 sec
# to clear the bridge then bye bye, this applies to all type of switch including the retract (currently
# retract brings unit to the retraction point while the idea is instead that it takes the ground away from
# under the feet, not pull the unit). other bridges are more straightforward: bridge there ok walk, bridge
# not there fall. rotation bridge when it starts moving, all on it falls"). During the warning the deck is
# there and walkable; the moment its motion starts it is gone for the troops, whatever the kind.
func _relay_drop(n: Dictionary, closing: Array, delta: float) -> void:
	## The motion starts: every line with bodies on a deck going away - any owner, the relay owner's own
	## included - loses them to the void, a fall loss exactly like walking off a missing deck. A line only
	## partly on it keeps the rest: the part behind the lip keeps its order and walks off it (the
	## waterfall, _check_missing_decks), the part already past the far pier made it. One fx per line:
	## a turning deck flings the bodies outward and sideways ("fling", Daniele 0.18.3: "shaken down into
	## the void as if the fall due to centrifugal power"); the other kinds drop them straight down where
	## they stand ("fall"). Both carry the node and the shown units for the HUD toast.
	var turn := signf(delta) if delta != 0.0 else 1.0
	for h in hordes.duplicate():
		var ranges := []
		for sp in h["spans"]:
			if sp["edge"] in closing and _overlap(h, sp["s0"], sp["s1"]) > 0.0:
				ranges.append([sp["s0"], sp["s1"], sp["edge"]])
		if ranges.is_empty():
			continue
		# tail-side deck first: cutting it only pulls the tail up, so the next range stays valid, and
		# only the last range can hold the head (the one cut that parks it at the lip)
		ranges.sort_custom(func(x, y): return x[0] < y[0])
		var seat: String = h["owner"]
		var faction: String = h["faction"]
		var acc := {"pts": [], "units": 0.0}
		for r in ranges:
			_cut_range(h, r[0], r[1], false, acc)
		if acc["units"] <= 0.0:
			continue
		if n["relay"] == "rotation":
			fx_events.append({"type": "fling", "node": n["id"], "seat": seat, "units": Rules.shown(acc["units"]),
					"faction": faction, "pts": acc["pts"], "centre": n["pos"], "turn": turn})
		else:
			fx_events.append({"type": "fall", "seat": seat, "faction": faction, "pts": acc["pts"], "units": acc["units"],
					"hid": h["id"], "pour": false, "relay": n["id"], "edge": ranges[0][2], "shown": Rules.shown(acc["units"])})


func _relay_apply(n: Dictionary) -> void:
	## Motion over: the new state's decks become walkable (they were closed while moving) and the
	## cooldown starts. The troops' fate was settled when the motion began (_relay_drop).
	n["moving_edges"] = []
	n["relay_phase"] = ""
	n["relay_cd"] = Rules.RELAY_COOLDOWN + maxf(n["relay_cd"], 0.0)   # (0 unless Relay Hack jammed it meanwhile)
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
	_reset_front(h)


static func _reset_front(h: Dictionary) -> void:
	## A new path: nothing cut off its front yet, not pouring (see _cut_front, _cut_range).
	h["fcut"] = 0.0          # metres of line taken off the head (cannon hits, walking off a lip): view identity
	h["pour"] = false        # the head is parked at the lip of a missing deck, the line walking off it
	h["pour_lip"] = -1.0     # arc length of that lip
	h["pour_k"] = 0.0        # fcut when the pour began: the view drops what walks off after it (Fx the rest)


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


const POUR_STEP := 1.0               # m: a head at most this far past a lip walked off it this step (view only)


func _cut_range(h: Dictionary, s0: float, s1: float, reroute := true, fling = null) -> void:
	## Units of the horde inside [s0, s1] of its path fall into the void. If the head itself was inside,
	## whatever is left behind the range is re-routed from the node before it (reroute true, Last Stand
	## drops) or walks on off the lip (reroute false, relays and missing decks: the order stands, 0.18.6);
	## if nothing is left, the horde is gone. `fling` (a {pts, units} Dictionary, relays): the fall is
	## counted the same, but its points and units go there for one fx per line (_relay_drop) instead of
	## a "fall" fx here. (0.18.7: a relay never carries troops into its node any more - the carry fate is gone.)
	if not (h in hordes):
		return
	var len := chain_length(h)
	var on := _overlap(h, s0, s1)
	if on <= 0.0:
		return
	var frac := clampf(on / maxf(len, 0.001), 0.0, 1.0)
	var units_on: float = h["units"] * frac
	# reroute false: the deck is gone but the order stands (Daniele, 0.18.6: "if someone retract a bridge
	# and your troops had order to go on said bridge they should go even if the bridge is no longer there
	# hence... waterfall"): the vat keeps sending and whatever is behind the deck marches off its lip
	var pours: bool = h["streaming"] and not reroute
	var head_in: bool = h["s"] >= s0 and h["s"] <= s1
	# THE POUR IS ONE MOTION (Daniele, 0.18.7: "the animation should be seamless and exaggerates so it looks
	# cooler"): a head that just walked over the lip (or was parked there last step) is the line walking
	# off it - the line's own view drops those bodies as they pass the lip (pour-tagged fall, no Fx
	# bodies); anything bigger is a stretch that was on the deck when it went (Fx drops it where it was)
	var walked: bool = not reroute and head_in and not (fling is Dictionary) and (h["s"] - s0 <= POUR_STEP \
			or (h.get("pour_prev", false) and absf(float(h.get("pour_lip", -1.0)) - s0) < 0.01))
	var survives: bool = pours or h["units"] - units_on >= 1.0
	if h["streaming"] and not pours:
		var src: Dictionary = nodes[h["route"][0]]
		if src["streaming"].get("hid", -1) == h["id"]:
			_end_streaming(src, "cut")
	var decoy: bool = h.get("decoy", false)          # a Ghost Line / echo falls like a real line but loses nothing real
	if not decoy:
		fall_losses[h["owner"]] = fall_losses.get(h["owner"], 0.0) + units_on
	var pts := []
	var k := 0.0
	while k <= on:
		pts.append(sample(h, minf(h["s"], s1) - k)[0])
		k += Rules.PATCH_SPACING
	if fling is Dictionary:
		(fling["pts"] as Array).append_array(pts)
		fling["units"] += units_on
		if not decoy:
			events.append({"t": time, "type": "fall", "seat": h["owner"], "units": units_on, "why": "relay"})
	else:
		fx_events.append({"type": "fall", "seat": h["owner"], "faction": h["faction"], "pts": pts, "units": units_on,
				"hid": h["id"], "pour": walked and survives})
		if not decoy:
			events.append({"t": time, "type": "fall", "seat": h["owner"], "units": units_on})
	h["units"] -= units_on
	if not reroute and not head_in and h["s"] > s1 and h["s"] - len < s0:
		_split_front(h, (h["units"] + units_on) * (h["s"] - s1) / maxf(len, 0.001))   # the deck went from under its middle
		head_in = true
	if not reroute and head_in:
		h["fcut"] = h.get("fcut", 0.0) + maxf(0.0, h["s"] - s0)   # what walked off (view: the rest keeps its place)
		h["s"] = s0                                       # the head waits at the lip; the next step pours more
		h["state"] = "move"
		if not walked:
			h["pour_k"] = h["fcut"]                       # the stretch on the deck fell with it (Fx); the rest walks off
		h["pour"] = true
		h["pour_lip"] = s0
	if pours and (decoy or nodes[h["route"][0]]["streaming"].get("hid", -1) == h["id"]):
		h["units"] = maxf(h["units"], 0.0)                   # the vat is still feeding this line
		return
	if h["units"] < 1.0:
		_kill_horde(h, "fall")
		return
	if reroute and h["s"] >= s0 and h["s"] <= s1:        # the head was inside: what's left is behind it
		var from_node := _node_before(h, s0)
		if from_node < 0 or collapsed.get(from_node, false):
			_kill_horde(h, "fall")
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


func _split_front(h: Dictionary, units_front: float) -> void:
	## A deck vanished under the middle of a line (0.18.7): the `units_front` past its far pier made it and
	## walk on as a finished line of their own; `h` keeps the part behind the lip (and the vat's order, if
	## any), its head brought back to the lip by _cut_range.
	if units_front < 0.5:
		return
	var f: Dictionary = h.duplicate()                 # same path (the packed arrays are shared copy-on-write)
	f["id"] = _next_id
	_next_id += 1
	f["units"] = units_front
	f["ordered"] = units_front
	f["start_units"] = maxf(units_front, 1.0)
	f["streaming"] = false
	f["fcut"] = 0.0
	f["pour"] = false
	f["pour_lip"] = -1.0
	f["pour_k"] = 0.0
	f.erase("pending_loss")
	h["units"] = maxf(0.0, h["units"] - units_front)
	hordes.append(f)
	# its fights were at the head, which is the new line now
	var hid: int = h["id"]
	for pair in fights:
		for q in range(2):
			if pair[q] == hid:
				pair[q] = f["id"]
		pair.sort()
	for key in fight_info.keys():
		var ids: PackedStringArray = key.split(":")
		if int(ids[0]) != hid and int(ids[1]) != hid:
			continue
		var info: Dictionary = fight_info[key]
		fight_info.erase(key)
		var other: int = int(ids[1]) if int(ids[0]) == hid else int(ids[0])
		if info["attacker"] == hid:
			info["attacker"] = f["id"]
		fight_info["%d:%d" % [mini(other, f["id"]), maxi(other, f["id"])]] = info
	events.append({"t": time, "type": "line_split", "seat": h["owner"], "units": units_front})


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


func find_route(from_id: int, to_id: int, avoid := {}) -> Array:
	## Fastest route by deck travel time (Dijkstra; each node crossed costs a little). Skips
	## closed relay decks and nodes dropped by the Last Stand collapse. `avoid` (edge index -> true):
	## decks left out too (the AI's relay-aware routing, 0.18.7).
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
			if collapsed.get(nb, false) or not _edge_open(link[1]) or avoid.has(link[1]):
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
	var pos := pts[lo].lerp(pts[hi], t)
	var fwd := (pts[hi] - pts[lo]).normalized()
	return [pos, fwd, h["fast"][lo] == 1]


# ------------------------------------------------------------------ simulation step
func step(dt: float) -> void:
	if over:
		return
	time += dt
	_step_last_stand(dt)
	_step_very_last_stand(dt)
	if time >= Rules.MATCH_HARD_END and not over:
		_force_end()
	if over:
		return
	for n in nodes:                                   # production (vat nodes only), up to the cap
		if n["owner"] != "" and has_vat(n) and n["units"] < Rules.CAPS[n["tier"]]:
			_produce(n, dt)
		elif Rules.NEUTRAL_REGEN and n["owner"] == "" and has_vat(n) and not collapsed.get(n["id"], false) and n["units"] < Rules.NEUTRAL_UNITS.get(n["tier"], 0):
			n["units"] = minf(Rules.NEUTRAL_UNITS[n["tier"]], n["units"] + Rules.PROD[n["tier"]] * dt)   # a neutral village regrows to its garrison (0.18.9)
	_step_relays(dt)
	_step_structures(dt)
	_step_skills(dt)
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
	_emit_decoys(dt)
	_check_missing_decks()
	for h in hordes:
		if h["state"] == "move" and not h.get("blocked", false):
			var here := sample(h, h["s"])
			var fast_here: bool = here[2]
			var mult: float = Rules.platform_mult() if fast_here else 1.0
			var boost := skill_speed(h)                   # Surge / Rewire
			mult *= deck_slow(h) * boost                  # enemy goo (home advantage) or Mire, the stronger
			var ds: float = Rules.move_speed() * h.get("speed", 1.0) * stat(h["owner"], "speed") * mult * dt
			if h["streaming"]:                        # the head cannot outrun the door: the line stays attached
				ds = minf(ds, Rules.exit_rate() * Rules.metres_per_unit() * boost * dt)
			h["s"] += ds
			if h["s"] >= h["L"]:
				h["s"] = h["L"]
				h["state"] = "absorb"
	_detect_contacts()
	_pop_decoys()
	var dead := []
	for pair in fights:                               # every contact pair trades losses, to the death
		var a := _horde(pair[0])
		var b := _horde(pair[1])
		if a.is_empty() or b.is_empty():
			continue
		var la: float = (Rules.FIGHT_RATE_BASE + Rules.FIGHT_RATE_K * b["units"]) * dt * attack_of(b["owner"]) / stat(a["owner"], "health")
		var lb: float = (Rules.FIGHT_RATE_BASE + Rules.FIGHT_RATE_K * a["units"]) * dt * attack_of(a["owner"]) / stat(b["owner"], "health")
		a["pending_loss"] = a.get("pending_loss", 0.0) + la
		b["pending_loss"] = b.get("pending_loss", 0.0) + lb
		_blame(a, b["owner"], la)                     # who dealt it: the ultimate charge
		_blame(b, a["owner"], lb)
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
			_credit_blame(h, before - h["units"])
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
	_step_decoys()
	_step_charge(dt)
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
		if not (h in hordes):
			continue
		h["pour_prev"] = h.get("pour", false)             # parked at a lip last step (_cut_range: walking off)
		h["pour"] = false
		var head: float = h["s"]
		var tail: float = head - chain_length(h)
		for sp in h["spans"]:
			if not (h in hordes):
				break
			if head < sp["s0"] or tail > sp["s1"]:
				continue                                  # the line doesn't touch this deck
			var ei: int = sp["edge"]
			if is_edge_open(ei):                          # a deck in motion is not (0.18.7): going or not yet there
				continue
			# the vat keeps sending: an order across a deck that has gone is still obeyed, every unit
			# marches on and pours into the void (Daniele, 0.18.6: "they should go even if the bridge is
			# no longer there hence... waterfall")
			var head_on: bool = head >= sp["s0"] and head <= sp["s1"]
			_cut_range(h, sp["s0"], sp["s1"], false)
			if head_on and h in hordes:
				h["s"] = sp["s0"]                         # the head stays at the lip; the next step pours more
				h["state"] = "move"
				h["pour"] = true                          # (also when it did not move this step)
				h["pour_lip"] = sp["s0"]


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
		if h["state"] == "absorb" or h["units"] <= 0.0:
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
					if h.get("decoy", false) or other.get("decoy", false):
						# a Ghost Line never fights, blocks or queues: touched by an enemy line it dissolves
						if not allied(other["owner"], h["owner"]):
							for g in [h, other]:
								if g.get("decoy", false) and not g in _popped:
									_popped.append(g)
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
		if a.get("retreat", false) or b.get("retreat", false):
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
	if h.is_empty() or h["state"] == "absorb" or h.get("retreat", false):
		return false
	if h.get("decoy", false):                            # a recalled Ghost Line stops "emitting" too
		_decoy_done_streaming(h)
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
	_reset_front(h)
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
	if not a.get("retreat", false):
		a["state"] = "fight"
	if not b.get("retreat", false):
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
	if h.get("decoy", false):                          # a Ghost Line pours in and vanishes (skills section)
		_decoy_arrive(n, h)
		return
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
	var kill_per: float = att / (stat(d_seat, "health") * stat(d_seat, "garrison") * garrison_div(n))   # defenders per exchange (Fortify / Aegis divide it)
	var cost_per: float = (attack_of(d_seat) if d_seat != "" else 1.0) / hp_att          # attacker per exchange
	var ratio: float = kill_per / maxf(cost_per, 0.0001)                                  # defenders killed per attacker
	var garrison: float = n["units"]
	var killed: float = minf(garrison, x * ratio)
	var spent: float = minf(x, killed / maxf(ratio, 0.0001))
	n["units"] = garrison - killed
	combat_losses[seat] = combat_losses.get(seat, 0.0) + spent
	if d_seat != "":
		combat_losses[d_seat] = combat_losses.get(d_seat, 0.0) + killed
	_credit(seat, d_seat, killed)
	_credit(d_seat, seat, spent)
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
		if h["state"] == "absorb" or h.get("decoy", false):   # a decoy never fights a garrison (_step_decoys)
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
		var g_tough := stat(n["owner"], "garrison") * garrison_div(n)   # garrison strength: damage the garrison takes (Fortify / Aegis)
		var blame := {}                               # k -> {seat: share of what k faces} (ultimate charge)
		var g_from := {}                              # k -> garrison damage k dealt
		for k in force:
			# what k faces here: the garrison (unless allied) and every hostile seat on the platform
			var enemy: float = 0.0 if allied(k, n["owner"]) else n["units"] * g_attack
			var who := {n["owner"]: enemy}
			for j in force:
				if not allied(j, k):
					enemy += force[j] * attack_of(j)
					who[j] = who.get(j, 0.0) + force[j] * attack_of(j)
			if enemy <= 0.0:
				continue
			for j in who:
				who[j] = who[j] / enemy
			blame[k] = who
			# a near-empty garrison is a weak toll (Daniele, Alpha 14: "a weak one is easy to punch
			# through"): the flat base rate fades in over the first 20 units of what it faces
			loss[k] = (Rules.FIGHT_RATE_BASE * minf(1.0, enemy / 20.0) + Rules.FIGHT_RATE_K * enemy) * dt * mult / stat(k, "health")
			if n["units"] > 0.0 and force[k] > 0.0 and not allied(k, n["owner"]):
				var rate: float = (Rules.FIGHT_RATE_BASE + Rules.FIGHT_RATE_K * force[k]) * dt * mult * attack_of(k) / g_tough
				var siege_part: float = n["siege"].get(k, 0.0)
				var transit_part: float = n["transit"].get(k, {}).get("units", 0.0)
				g_loss_units += rate * ((siege_part + transit_part) / force[k])   # transit fights the garrison too
				g_from[k] = g_from.get(k, 0.0) + rate * ((siege_part + transit_part) / force[k])
		for k in loss:
			var actual: float = minf(loss[k], force[k])
			n["node_loss"][k] = actual / maxf(dt, 0.0001)
			combat_losses[k] = combat_losses.get(k, 0.0) + actual
			for j in blame.get(k, {}):
				_credit(j, k, actual * blame[k][j])
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
				for k in g_from:
					_credit(k, n["owner"], (before_g - n["units"]) * g_from[k] / g_loss_units)
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
	_capture_effects(n, seat)
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
	last_stand_corners = _corner_cycle()                  # drawn after the method and order: same seed, same picks
	_ls_corner_k = 0
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


func _corner_cycle() -> Array:
	## 0.18.7, Daniele: "last stand always starts from the same node - change the logic to start randomly
	## from one of the starting corners then move to the opposite, then another then another and then
	## back to the first until all nodes that are supposed to fall are gone; this makes it a bit more
	## fair, otherwise the first player usually loses all his nodes all together with no reaction time".
	## The corners are the home platforms of the seats in this match (a home that was taken or fell
	## keeps its place as the corner). The first is drawn from the match's seeded rng; each next one is
	## the unvisited corner farthest from the last visited (ties: farthest from all visited, then seat
	## order), so 1v1 alternates the two homes and four corners go start, opposite, then the other two.
	var seats := homes.keys()
	seats.sort()
	var left := []
	for s in seats:
		left.append(homes[s])
	if left.is_empty():
		return []
	var cycle := [left[rng.randi_range(0, left.size() - 1)]]
	left.erase(cycle[0])
	while not left.is_empty():
		var best: int = left[0]
		var best_key := Vector2(-INF, -INF)
		for id in left:
			var sum := 0.0
			for v in cycle:
				sum += _flat_dist(id, v)
			var key := Vector2(_flat_dist(id, cycle[-1]), sum)
			if key.x > best_key.x + 0.01 or (absf(key.x - best_key.x) <= 0.01 and key.y > best_key.y + 0.01):
				best_key = key
				best = id
		cycle.append(best)
		left.erase(best)
	return cycle


func _flat_dist(a: int, b: int) -> float:
	var pa: Vector3 = nodes[a]["pos"]
	var pb: Vector3 = nodes[b]["pos"]
	return Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z))


func _drop_sequence(wave: Array) -> Array:
	## The order a ring's platforms fall in, one at a time (0.18.4): each drop is a platform whose loss
	## leaves every other standing platform connected over fixed decks (the rule for falling bridges -
	## never an island), relays after the ring's other platforms. 0.18.7: each drop aims at the next
	## corner of the cycle (_corner_cycle, carried across rings) and takes the safe platform closest to
	## it, preferring one that is not on the previous drop's side (nearest the same corner) so no player
	## loses two platforms in a row while another side still has a safe one; with no safe platform it
	## takes the least unsafe closest and the cycle still moves on. Ties (and a match with no corners)
	## fall back to the far side of the last ring first.
	var gone := collapsed.duplicate()
	var left: Array = wave.duplicate()
	var depth := _keep_depth()
	var out := []
	var prev_side := -1
	while not left.is_empty():
		var corner: int = last_stand_corners[_ls_corner_k % last_stand_corners.size()] if not last_stand_corners.is_empty() else -1
		var best := -1
		var best_tier := 99
		var best_d := INF
		var best_depth := -1
		for id in left:
			var trial := gone.duplicate()
			trial[id] = true
			var tier := 2 if nodes[id]["relay"] != "" else 0
			if not _islands(trial).is_empty():
				tier += 4                                  # would strand another platform: only as a last resort
			if prev_side >= 0 and nearest_corner(id) == prev_side:
				tier += 1                                  # the same side twice in a row: only if no other side can go
			var d: float = _flat_dist(id, corner) if corner >= 0 else 0.0
			var dep: int = depth.get(id, 0)
			var better := tier < best_tier
			if tier == best_tier:
				if d < best_d - 0.01:
					better = true
				elif d <= best_d + 0.01:
					better = dep > best_depth or (dep == best_depth and id < best)
			if better:
				best_tier = tier
				best_d = d
				best_depth = dep
				best = id
		out.append(best)
		left.erase(best)
		gone[best] = true
		prev_side = nearest_corner(best)
		if not last_stand_corners.is_empty():
			_ls_corner_k = (_ls_corner_k + 1) % last_stand_corners.size()
	return out


func nearest_corner(id: int) -> int:
	## The Last Stand corner (a home in last_stand_corners) a platform lies nearest to, ties to the
	## earlier corner of the cycle; -1 with no corners.
	var best := -1
	var best_d := INF
	for c in last_stand_corners:
		var d := _flat_dist(id, c)
		if d < best_d - 0.01:
			best_d = d
			best = c
	return best


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
	if very_last_stand_active:
		return false                                       # nothing is safe any more once it starts
	return last_stand_keep.has(id) if v3 else id == last_stand_final


# ---------------------------------------------------------- Very Last Stand (Daniele, 0.18.9)
# "Very Last Stand: at 6 every 10 sec a node with 2 or 1 connection falls randomly until only 1 node
# is left" - a stalemate breaker for whatever the ring Last Stand left standing (or, on a map with no
# Last Stand at all, the whole map): the surviving ring can otherwise hold to the 7:00 hard end.
# Follow-up: "whatever the number of nodes left, they drop one by one in the same time span until one
# is left at 7; the time between falls is due to the number of nodes" - the interval is derived, not
# fixed, so the last drop lands exactly at Rules.MATCH_HARD_END. It reuses the ring machinery's own
# fields (last_stand_warn / last_stand_queue / last_stand_warn_node / last_stand_warn_t) so the
# badges, the camera zoom, the fx and the net snapshot need no changes.
func _step_very_last_stand(dt: float) -> void:
	if over:
		return
	if not Rules.last_stand:
		return
	if not very_last_stand_active:
		if time < Rules.VERY_LAST_STAND_TIME:
			return
		_start_very_last_stand()
		return
	if last_stand_warn_node >= 0 or _vls_surviving().size() <= 1:
		return
	_vls_queue_next()


func _start_very_last_stand() -> void:
	very_last_stand_active = true
	last_stand_active = true             # a tutorial never ran the ring collapse: this is its Last Stand
	events.append({"t": time, "type": "very_last_stand"})
	fx_events.append({"type": "very_last_stand"})
	_vls_queue_next()


func _vls_surviving() -> Array:
	var out := []
	for n in nodes:
		if not collapsed.get(n["id"], false):
			out.append(n["id"])
	return out


func _vls_open_links(id: int, gone: Dictionary) -> int:
	## Decks to other surviving platforms - a relay deck counts only while it is actually open.
	var c := 0
	for link in adj[id]:
		var e: Dictionary = edges[link[1]]
		if e["state"] != "" or e["retracts"] or gone.get(link[0], false):
			continue
		c += 1
	return c


func _vls_pick(gone: Dictionary) -> int:
	## The next platform to fall: a random pick (seeded) among surviving platforms with 1 or 2 open
	## connections whose drop leaves everyone else still connected; if every such platform would
	## strand something, the least-stranding one (the island rule from _drop_sequence).
	var survivors := []
	for n in nodes:
		if not gone.get(n["id"], false):
			survivors.append(n["id"])
	var candidates := []
	for id in survivors:
		if _vls_open_links(id, gone) <= 2:
			candidates.append(id)
	candidates.sort()
	var safe := []
	for id in candidates:
		var trial := gone.duplicate()
		trial[id] = true
		if _islands(trial).is_empty():
			safe.append(id)
	if not safe.is_empty():
		return safe[rng.randi_range(0, safe.size() - 1)]
	var pool: Array = candidates if not candidates.is_empty() else survivors.duplicate()   # no 1-2-conn
	pool.sort()                                                                            # platform at
	var best_stranded := 999999                                                            # all: fall back
	var ties := []                                                                         # to any survivor
	for id in pool:
		var trial := gone.duplicate()
		trial[id] = true
		var stranded: int = _islands(trial).size()
		if stranded < best_stranded:
			best_stranded = stranded
			ties = [id]
		elif stranded == best_stranded:
			ties.append(id)
	return ties[rng.randi_range(0, ties.size() - 1)]


func _vls_queue_next() -> void:
	var survivors := _vls_surviving()
	if survivors.size() <= 1:
		last_stand_warn_node = -1
		last_stand_warn_t = 0.0
		last_stand_warn = {}
		last_stand_queue = []
		return
	very_last_stand_gap = (Rules.MATCH_HARD_END - time) / float(survivors.size() - 1)
	var gone := collapsed.duplicate()
	var id := _vls_pick(gone)
	var batch := [id]
	gone[id] = true
	for extra in _islands(gone):            # this pick would strand others too (the rare fallback case)
		if not extra in batch:
			batch.append(extra)
			gone[extra] = true
	last_stand_warn = {}
	for bid in batch:
		last_stand_warn[bid] = true
	last_stand_queue = batch
	last_stand_warn_node = batch[0]
	last_stand_warn_t = very_last_stand_gap
	for bid in batch:
		fx_events.append({"type": "collapse_warning", "node": bid})
	events.append({"t": time, "type": "collapse_warning", "nodes": batch.duplicate(), "very_last_stand": true})


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
		_relay_apply(n)                     # finish the tick: the view restores the decks
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
			_cut_range(h, lo, hi)
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
					if not h.get("decoy", false):
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
		if not h.get("decoy", false):                 # a seat is never kept alive by a Ghost Line
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
		if h["owner"] == seat and not h.get("decoy", false):
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


# ================================================================== SKILLS 2.0 (0.18.7)
# Daniele (0.18.7): "time to add armies presets and skills (its own new menu item where you select what
# skill each of your factions will use, follow the skill file from faction ultimates and ability pool)".
# Rules: SKILLS-2.0-DRAFT.md draft 2 (approved; ultimates = the sec5.2 rebalance). Numbers: Rules.SKILLS.
# Every skill works in BRAWL and SIEGE. A seat's loadout is fixed at setup (faction -> ultimate, plus
# one active and one map skill; missing -> Rules.FACTION_LOADOUT; a relay skill on a map without relays
# -> the faction's "map_no_relays" skill).
#
# PUBLIC API (dock, targeting UI, AI and Net use only these; everything else here is internal)
#   skill_id(seat, slot) -> String        slot: "active" | "map" | "ultimate"; "" if none
#   cooldown(seat, slot) -> float         seconds left; ultimate: seconds of charge left (0 = ready)
#   charge(seat) -> float                 ultimate charge 0..1 (1 = ready)
#   rewire_left(seat) -> int              Rewire is running: relay fires left (then the ultimate slot fires relays)
#   cast_check(seat, slot, target) -> String   "" = castable, else a short reason for a toast
#   can_cast(seat, slot, target) -> bool
#   cast(seat, slot, target) -> bool      validates (cast_check), applies, starts the cooldown / spends the charge
#   targets_for(seat, slot) -> Array      every target cast_check accepts now (Ghost Line: its source nodes;
#                                         a no-target skill: [null] when castable)
#   effects_on(on, target) -> Array       active effects on "node" | "edge" | "horde" | "relay" | "seat"
#   is_ghost_for(h, viewer) -> bool       draw this horde as a ghost for `viewer` (only its owner knows)
#   node_under_attack(node_id, seat) -> bool   hostile units on its platform or a hostile line bound for it
#   garrison_div(n), prod_mult(n), skill_speed(h), deck_slow(h), anchor_state(edge), is_bypassed(relay),
#   is_relay_locked(relay), is_disrupted(node)   the rule lookups, for readouts
# TARGET SHAPES (Rules.SKILLS[id].target)
#   own_line: horde id  |  own_vat, own_node: node id  |  deck, fixed_deck: edge index  |  relay: node id
#   enemy_relay: relay node id (fire) or [relay node id, "jam"] / [id, "fire"]
#   vat_to_node: [source node id, destination node id] or [src, dst, fraction 0..1] (default SKILLS.ghost_line.fraction)
#   none: null (anything). Rewire running: the ultimate slot takes a relay node id (any relay, once each).
# STATE (all in snapshots)
#   loadouts[seat] = {"active", "map", "ultimate"}; skill_cd[seat] = {"active": s, "map": s};
#   ult_charge[seat] 0..1; ult_since[seat] s; demolished[edge] = s until it rebuilds;
#   effects = [{"id": skill id, "seat": caster, "on": "node"|"edge"|"horde"|"relay"|"seat", "target": id or seat,
#       "t": s left, "dur": s total, ...extras}]. Extras: scorch "left" (sim units it may still kill), "kills";
#       demolish "phase" "warning" (3 s) / "down" (20 s); anchor and Aegis decks "open" (the frozen state);
#       relay_hack "mode" "fire" / "jam"; rewire "fires" left, "fired" [relay ids]; superbloom "left" (extra
#       sim units still allowed; -1 = uncapped); relay_aegis "center" (the node cast on); an Echo Split jam
#       is {"id": "echo_split", "on": "node"}.
#   Decoys (Ghost Line, echoes) are ordinary hordes with h["decoy"] = true (echoes also "echo"); they stream,
#   move, fall, draw cannon fire and pour in like real lines, but never fight, block, capture or defend: an
#   enemy line touching one or (SIEGE) a hostile waypoint dissolves it; landing ends it (an echo landing on an
#   enemy node jams its vat and cannon). Net strips those keys from the broadcast snapshot and tells only
#   the owner (a private "ghosts" packet). A decoy never sets its node's n["streaming"] (the SIEGE door
#   puddle reads that): a view that wants the puddle for every line should draw it from h["streaming"].
# FX EVENTS (sim.fx_events; a key "private": seat = only that seat may see it - Net forwards it to that seat
# only, views must skip it unless it is theirs)
#   {"type": "skill", "id", "seat", "slot", "target", "pos": Vector3, "affects": [seats hit]}   every cast
#       (Ghost Line's is private and carries "hid"; a Rewire relay fire has "fire": relay id)
#   {"type": "ghosts", "seat", "hids": [...], "private": seat}   Echo Split: which new lines are echoes
#   {"type": "skill_end", "id", "seat", "on", "target"}          an effect ran out
#   {"type": "demolish", "edge", "seat"} the deck goes | {"type": "deck_rebuilt", "edge"} |
#   {"type": "demolish_failed", "edge", "seat"} (anchored at the end of the warning)
#   {"type": "relay_settle", "node", "closing": [edges]}          Bypass / Anchor ended: those decks go now
#   {"type": "meltdown", "node", "seat", "hid", "sacrificed", "killed" (shown units), "captured": bool}
#   {"type": "disrupt", "node", "seat"} an echo jammed a node | {"type": "ghost_end", "hid", "seat", "why"}
# EVENTS (sim.events, telemetry): {"type": "skill", "id", "seat", "slot", "target", "affects"},
#   {"type": "skill_end", "id", "seat", "kills" (sim units, Scorch)}, {"type": "meltdown", ...}.

func _setup_skills(seat_loadouts: Dictionary) -> void:
	abilities_on = Rules.abilities_on
	has_relays = false
	for n in nodes:
		if n["relay"] != "" and not relay_states(n).is_empty():
			has_relays = true
	loadouts = {}
	skill_cd = {}
	ult_charge = {}
	ult_since = {}
	effects = []
	demolished = {}
	_kill_credit = {}
	_index_effects()
	for seat in factions:
		var f: String = factions[seat]
		var want = seat_loadouts.get(seat, {})
		if not want is Dictionary:
			want = {}
		var lo := {"active": Rules.skill_slot_id(f, want, "active"), "map": Rules.skill_slot_id(f, want, "map"),
				"ultimate": Rules.skill_slot_id(f, want, "ultimate")}
		if not has_relays and Rules.SKILLS[lo["map"]].get("needs_relays", false):
			lo["map"] = str(Rules.FACTION_LOADOUT.get(f, Rules.FACTION_LOADOUT["null"])["map_no_relays"])
		loadouts[seat] = lo
		skill_cd[seat] = {"active": 0.0, "map": 0.0}
		ult_charge[seat] = 0.0
		ult_since[seat] = 0.0


# ------------------------------------------------------------------ queries
func skill_id(seat: String, slot: String) -> String:
	return str(loadouts.get(seat, {}).get(slot, ""))


func cooldown(seat: String, slot: String) -> float:
	if slot == "ultimate":
		var c := charge(seat)
		if c >= 1.0:
			return 0.0
		return maxf((1.0 - c) * Rules.ULT_CHARGE_TIME, Rules.ULT_MIN_TIME - float(ult_since.get(seat, 0.0)))
	return float(skill_cd.get(seat, {}).get(slot, 0.0))


func charge(seat: String) -> float:
	return float(ult_charge.get(seat, 0.0))


func rewire_left(seat: String) -> int:
	for e in _fx_seat.get(seat, []):
		if e["id"] == "rewire":
			return int(e["fires"])
	return 0


func effects_on(on: String, target) -> Array:
	match on:
		"node":
			return _fx_node.get(target, [])
		"edge":
			return _fx_edge.get(target, [])
		"horde":
			return _fx_horde.get(target, [])
		"relay":
			return _fx_relay.get(target, [])
		"seat":
			return _fx_seat.get(target, [])
	return []


static func is_ghost_for(h: Dictionary, viewer: String) -> bool:
	return h.get("decoy", false) and h["owner"] == viewer


func node_under_attack(node_id: int, seat: String) -> bool:
	var n: Dictionary = nodes[node_id]
	for k in n["siege"]:
		if n["siege"][k] > 0.0 and not allied(k, seat):
			return true
	for k in n["transit"]:
		if not allied(k, seat):
			return true
	for h in hordes:                                   # (a Ghost Line counts: nobody can tell it apart)
		if h["target"] == node_id and not allied(h["owner"], seat) and not h.get("retreat", false):
			return true
	return false


# effect lookups used by the rules (cheap: the index dicts are empty when nothing is active)
var _fx_node: Dictionary = {}
var _fx_edge: Dictionary = {}
var _fx_horde: Dictionary = {}
var _fx_relay: Dictionary = {}
var _fx_seat: Dictionary = {}


func _index_effects() -> void:
	_fx_node = {}
	_fx_edge = {}
	_fx_horde = {}
	_fx_relay = {}
	_fx_seat = {}
	for e in effects:
		var d: Dictionary = {"node": _fx_node, "edge": _fx_edge, "horde": _fx_horde, "relay": _fx_relay, "seat": _fx_seat}.get(e["on"], {})
		var k = e["target"]
		if not d.has(k):
			d[k] = []
		d[k].append(e)


func anchor_state(ei: int):
	## The frozen presence of an anchored deck (Anchor, Relay Aegis), or null when it is not anchored.
	if _fx_edge.is_empty() or not _fx_edge.has(ei):
		return null
	for e in _fx_edge[ei]:
		if e.has("open"):
			return e["open"]
	return null


func is_bypassed(relay_id: int) -> bool:
	if _fx_relay.is_empty():
		return false
	for e in _fx_relay.get(relay_id, []):
		if e["id"] == "bypass":
			return true
	return false


func is_relay_locked(relay_id: int) -> bool:
	## Relay Aegis locks the relays among its nodes: nobody can fire them (nor hack them) while it lasts.
	if _fx_node.is_empty():
		return false
	for e in _fx_node.get(relay_id, []):
		if e["id"] == "relay_aegis":
			return true
	return false


func is_disrupted(node_id: int) -> bool:
	if _fx_node.is_empty():
		return false
	for e in _fx_node.get(node_id, []):
		if e["id"] == "echo_split":
			return true
	return false


func garrison_div(n: Dictionary) -> float:
	## Fortify / Relay Aegis: the garrison takes this many times less damage (the strongest applies).
	if _fx_node.is_empty() or n["owner"] == "":
		return 1.0
	var d := 1.0
	for e in _fx_node.get(n["id"], []):
		if e.has("div") and allied(e["seat"], n["owner"]):
			d = maxf(d, float(e["div"]))
	return d


func prod_mult(n: Dictionary) -> float:
	return _prod_info(n)[0]


func _prod_info(n: Dictionary) -> Array:
	## [production multiplier, the Superbloom effect it comes from or null]: Spore Burst, Superbloom and
	## Relay Aegis do not stack (the strongest applies); an Echo Split jam stops the vat.
	if n["owner"] == "" or (_fx_node.is_empty() and _fx_seat.is_empty()):
		return [1.0, null]
	if is_disrupted(n["id"]):
		return [0.0, null]
	var m := 1.0
	for e in _fx_node.get(n["id"], []):
		if e["id"] == "spore_burst" and e["seat"] == n["owner"]:
			m = maxf(m, float(e["mult"]))
		elif e["id"] == "relay_aegis" and allied(e["seat"], n["owner"]):
			m = maxf(m, float(e["prod"]))
	var bloom = null
	for e in _fx_seat.get(n["owner"], []):
		if e["id"] == "superbloom" and float(e["left"]) != 0.0 and float(e["mult"]) > m:
			m = float(e["mult"])
			bloom = e
	return [m, bloom]


func _produce(n: Dictionary, dt: float) -> void:
	var base := _base_production(n)
	var info := _prod_info(n)
	var cap: float = Rules.CAPS[n["tier"]]
	var before: float = n["units"]
	var bloom = info[1]
	var add: float = base * float(info[0]) * dt
	if bloom != null and float(bloom["left"]) > 0.0:      # Superbloom "cap": at most `left` extra units in all
		var extra: float = minf(add - base * dt, float(bloom["left"]))
		add = base * dt + extra
	n["units"] = minf(cap, before + add)
	if bloom != null and float(bloom["left"]) > 0.0:
		bloom["left"] = maxf(0.0, float(bloom["left"]) - maxf(0.0, n["units"] - before - base * dt))


func skill_speed(h: Dictionary) -> float:
	## Surge / Rewire speed multiplier (they do not stack).
	var m := 1.0
	if not _fx_horde.is_empty():
		for e in _fx_horde.get(h["id"], []):
			if e["id"] == "surge":
				m = maxf(m, float(e["mult"]))
	if not _fx_seat.is_empty():
		for e in _fx_seat.get(h["owner"], []):
			if e["id"] == "rewire":
				m = maxf(m, float(e["mult"]))
	return m


func deck_slow(h: Dictionary) -> float:
	## Speed factor of the deck under the head: SIEGE enemy goo (Rules.GOO_SLOW) or an enemy Mire; with both,
	## the stronger slow applies (no stacking; draft sec4, Daniele 0.18.7).
	var goo := Rules.bridge_combat
	if not goo and _fx_edge.is_empty():
		return 1.0
	var sp := _current_span(h)
	if sp.is_empty():
		return 1.0
	var slow := 1.0
	if goo:
		var g := goo_owner(sp["edge"])
		if g != "" and not allied(g, h["owner"]):
			slow = Rules.GOO_SLOW
	for e in _fx_edge.get(sp["edge"], []):
		if e["id"] == "mire" and not allied(e["seat"], h["owner"]):
			slow = minf(slow, float(e["slow"]))
	return slow


func _cannon_mult(h: Dictionary) -> float:
	## Anchor (and Aegis decks): the caster's lines on it take half the cannon kills.
	if _fx_edge.is_empty():
		return 1.0
	var sp := _current_span(h)
	if sp.is_empty():
		return 1.0
	for e in _fx_edge.get(sp["edge"], []):
		if e.has("open") and allied(e["seat"], h["owner"]):
			return float(Rules.SKILLS["anchor"]["cannon_mult"])
	return 1.0


# ------------------------------------------------------------------ ultimate charge
func _credit(killer: String, victim: String, units: float) -> void:
	## An enemy combat kill (troops, garrison, cannon, Scorch) speeds the killer's ultimate. Neutrals,
	## allies, decoys, sacrifices, ultimate kills and falls never reach here.
	if killer == "" or victim == "" or units <= 0.0 or allied(killer, victim):
		return
	_kill_credit[killer] = _kill_credit.get(killer, 0.0) + units


func _blame(h: Dictionary, seat: String, amount: float) -> void:
	var b: Dictionary = h.get("blame", {})
	b[seat] = b.get(seat, 0.0) + amount
	h["blame"] = b


func _credit_blame(h: Dictionary, actual: float) -> void:
	var b: Dictionary = h.get("blame", {})
	h.erase("blame")
	var total := 0.0
	for s in b:
		total += b[s]
	if total <= 0.0:
		return
	for s in b:
		_credit(s, h["owner"], actual * b[s] / total)


func _step_charge(dt: float) -> void:
	for seat in ult_charge:
		if eliminated.has(seat):
			continue
		ult_since[seat] = float(ult_since[seat]) + dt
		var gain: float = dt / Rules.ULT_CHARGE_TIME \
				+ Rules.shown_f(_kill_credit.get(seat, 0.0)) * Rules.ULT_KILL_SECONDS / Rules.ULT_CHARGE_TIME
		ult_charge[seat] = minf(minf(1.0, float(ult_charge[seat]) + gain), float(ult_since[seat]) / Rules.ULT_MIN_TIME)
	_kill_credit = {}


# ------------------------------------------------------------------ casting
func can_cast(seat: String, slot: String, target = null) -> bool:
	return cast_check(seat, slot, target) == ""


func cast_check(seat: String, slot: String, target = null) -> String:
	if over:
		return "The match is over"
	if not abilities_on:
		return "Abilities are off in this match"
	if not loadouts.has(seat) or eliminated.has(seat):
		return "No skills for this seat"
	if not slot in ["active", "map", "ultimate"]:
		return "No such slot"
	var id := skill_id(seat, slot)
	if not Rules.SKILLS.has(id):
		return "No skill in that slot"
	var sk: Dictionary = Rules.SKILLS[id]
	if slot == "ultimate":
		if id == "rewire" and rewire_left(seat) > 0:
			return _check_rewire_fire(seat, target)
		if charge(seat) < 1.0:
			return "%s charging - %d %%" % [sk["name"], int(charge(seat) * 100.0)]
	elif cooldown(seat, slot) > 0.0:
		return "%s ready in %d s" % [sk["name"], int(ceil(cooldown(seat, slot)))]
	if sk.get("needs_relays", false) and not has_relays:
		return "No relays on this map"
	return _target_check(seat, id, target)


static func _as_int(v) -> int:
	if v is int:
		return v
	if v is float and is_finite(v) and v == floorf(v):
		return int(v)
	return -999999


func _node_ok(id: int) -> bool:
	return id >= 0 and id < nodes.size() and not collapsed.get(id, false)


func _deck_ok(ei: int) -> bool:
	if ei < 0 or ei >= edges.size():
		return false
	var e: Dictionary = edges[ei]
	return not e["plaza"] and not collapsed.get(e["a"], false) and not collapsed.get(e["b"], false)


func _deck_moving(ei: int) -> bool:
	var ctrl: int = edge_controller.get(ei, -1)
	return ctrl >= 0 and ei in nodes[ctrl]["moving_edges"]


func _relay_target(target) -> Array:
	## [relay node id, mode] from a relay target (id, [id], [id, "jam"|"fire"]).
	if target is Array and not (target as Array).is_empty():
		var mode := str(target[1]) if (target as Array).size() > 1 and target[1] is String else "fire"
		return [_as_int(target[0]), mode]
	return [_as_int(target), "fire"]


func _target_check(seat: String, id: String, target) -> String:
	var sk: Dictionary = Rules.SKILLS[id]
	match id:
		"surge":
			var h := _horde(_as_int(target))
			if h.is_empty() or h["owner"] != seat:
				return "Pick one of your lines"
			if h["state"] == "absorb":
				return "That line has already arrived"
		"core_meltdown":
			var h := _horde(_as_int(target))
			if h.is_empty() or h["owner"] != seat or h.get("decoy", false):
				return "Pick one of your attacking lines"
			var n: Dictionary = nodes[h["target"]]
			if allied(n["owner"], seat) or collapsed.get(n["id"], false) or h.get("retreat", false):
				return "That line is not attacking"
			if h["state"] != "absorb" and float(h["L"]) - float(h["s"]) > float(sk["range"]):
				return "Wait until the line reaches its target"
			if h["units"] < float(sk["min_shown"]) * Rules.SCALE:
				return "The line needs at least %d units" % int(sk["min_shown"])
		"spore_burst":
			var i := _as_int(target)
			if not _node_ok(i) or nodes[i]["owner"] != seat or not has_vat(nodes[i]):
				return "Pick one of your vats"
		"fortify", "relay_aegis":
			var i := _as_int(target)
			if not _node_ok(i) or nodes[i]["owner"] != seat:
				return "Pick one of your nodes"
		"scorch", "mire":
			if not _deck_ok(_as_int(target)):
				return "Pick a deck"
		"anchor":
			var ei := _as_int(target)
			if not _deck_ok(ei):
				return "Pick a deck"
			if demolished.has(ei):
				return "That deck is gone"
			if _deck_moving(ei):
				return "That deck is moving"
		"demolish":
			var ei := _as_int(target)
			if not _deck_ok(ei):
				return "Pick a deck"
			var e: Dictionary = edges[ei]
			if e["state"] != "" or e["retracts"]:
				return "Pick a deck no relay moves"
			if demolished.has(ei) or effects_on("edge", ei).any(func(x): return x["id"] == "demolish"):
				return "That deck is already coming down"
			if anchor_state(ei) != null:
				return "That deck is anchored"
		"bypass":
			var i := _as_int(target)
			if not _node_ok(i) or nodes[i]["relay"] == "" or relay_states(nodes[i]).is_empty():
				return "Pick a relay"
			if nodes[i]["relay_phase"] == "moving":
				return "That relay is moving"
			if is_relay_locked(i):
				return "That relay is locked"
			if is_bypassed(i):
				return "That relay is already bypassed"
		"relay_hack":
			var rt := _relay_target(target)
			var i: int = rt[0]
			if not _node_ok(i) or nodes[i]["relay"] == "" or relay_states(nodes[i]).is_empty():
				return "Pick a relay"
			if nodes[i]["owner"] != "" and allied(nodes[i]["owner"], seat):
				return "Pick an enemy or neutral relay"
			if is_relay_locked(i):
				return "That relay is locked"
			if rt[1] == "fire":
				if nodes[i]["relay_phase"] != "":
					return "That relay is already switching"
				if nodes[i]["relay_cd"] > 0.0:
					return "That relay is on cooldown - jam it instead"
			elif rt[1] != "jam":
				return "Fire or jam"
		"ghost_line":
			if not target is Array or (target as Array).size() < 2:
				return "Pick a source and a destination"
			var src := _as_int(target[0])
			var dst := _as_int(target[1])
			if not _node_ok(src) or nodes[src]["owner"] != seat:
				return "Start from one of your nodes"
			if not _node_ok(dst) or dst == src:
				return "Pick a destination"
			if floorf(nodes[src]["units"] * _ghost_fraction(target)) < 1.0:
				return "No units to copy"
			if find_route(src, dst).size() < 2:
				return "No route to that node"
		"echo_split":
			if _echo_plan(seat).is_empty():
				return "Echo Split needs your lines on the move"
		"superbloom":
			if Rules.SUPERBLOOM_MODE == "under_attack" and not nodes.any(func(n): return n["owner"] == seat and node_under_attack(n["id"], seat)):
				return "Superbloom needs one of your nodes under attack"
	return ""


func _ghost_fraction(target) -> float:
	if target is Array and (target as Array).size() > 2 and (target[2] is float or target[2] is int):
		return clampf(float(target[2]), 0.01, 1.0)
	return float(Rules.SKILLS["ghost_line"]["fraction"])


func _check_rewire_fire(seat: String, target) -> String:
	var i := _as_int(target)
	if not _node_ok(i) or nodes[i]["relay"] == "" or relay_states(nodes[i]).is_empty():
		return "Rewire: pick a relay to fire"
	for e in _fx_seat.get(seat, []):
		if e["id"] == "rewire" and i in e["fired"]:
			return "Rewire already fired that relay"
	if is_relay_locked(i):
		return "That relay is locked"
	if nodes[i]["relay_phase"] != "":
		return "That relay is already switching"
	if nodes[i]["relay_cd"] > 0.0:
		return "That relay is on cooldown"
	return ""


func cast(seat: String, slot: String, target = null) -> bool:
	## A player's (or the AI's) cast: validated by cast_check, then applied at once. Returns false and
	## changes nothing when it is not possible.
	if cast_check(seat, slot, target) != "":
		return false
	var id := skill_id(seat, slot)
	var sk: Dictionary = Rules.SKILLS[id]
	var ev := {"type": "skill", "id": id, "seat": seat, "slot": slot, "target": target}
	if slot == "ultimate" and id == "rewire" and rewire_left(seat) > 0:
		var r := _as_int(target)
		for e in _fx_seat.get(seat, []):
			if e["id"] == "rewire":
				e["fires"] = int(e["fires"]) - 1
				(e["fired"] as Array).append(r)
		_fire_relay_by(nodes[r], seat)
		ev["fire"] = r
		ev["pos"] = nodes[r]["pos"]
		ev["affects"] = _hostile_list(seat, [nodes[r]["owner"]])
		_cast_done(ev)
		return true
	ev["pos"] = _target_pos(sk["target"], target, seat)
	ev["affects"] = []
	match id:
		"surge":
			var hid := _as_int(target)
			_drop_effects("horde", hid, "surge")
			_add_effect(id, seat, "horde", hid, sk["dur"], {"mult": sk["mult"]})
		"spore_burst":
			_drop_effects("node", _as_int(target), id)
			_add_effect(id, seat, "node", _as_int(target), sk["dur"], {"mult": sk["mult"]})
		"fortify":
			_drop_effects("node", _as_int(target), id)
			_add_effect(id, seat, "node", _as_int(target), sk["dur"], {"div": sk["div"]})
		"scorch":
			var ei := _as_int(target)
			_add_effect(id, seat, "edge", ei, sk["dur"], {"left": float(sk["cap_shown"]) * Rules.SCALE, "kills": 0.0})
			ev["affects"] = _deck_seats(seat, ei)
		"mire":
			var ei := _as_int(target)
			_drop_effects("edge", ei, id)
			_add_effect(id, seat, "edge", ei, sk["dur"], {"slow": sk["slow"]})
			ev["affects"] = _deck_seats(seat, ei)
		"anchor":
			var ei := _as_int(target)
			var held = anchor_state(ei)
			_add_effect(id, seat, "edge", ei, sk["dur"], {"open": held if held != null else _edge_open(ei), "cannon_mult": sk["cannon_mult"]})
		"demolish":
			var ei := _as_int(target)
			_add_effect(id, seat, "edge", ei, sk["warn"], {"phase": "warning"})
			ev["affects"] = _deck_seats(seat, ei)
		"bypass":
			_add_effect(id, seat, "relay", _as_int(target), sk["dur"])
			ev["affects"] = _hostile_list(seat, [nodes[_as_int(target)]["owner"]])
		"relay_hack":
			var rt := _relay_target(target)
			var n: Dictionary = nodes[rt[0]]
			if rt[1] == "jam":
				n["relay_cd"] = maxf(n["relay_cd"], 0.0) + float(sk["jam"])
				_add_effect(id, seat, "relay", n["id"], n["relay_cd"], {"mode": "jam"})
			else:
				_fire_relay_by(n, seat)
				_add_effect(id, seat, "relay", n["id"], Rules.RELAY_WARNING, {"mode": "fire"})
			ev["affects"] = _hostile_list(seat, [n["owner"]])
		"ghost_line":
			var src := _as_int(target[0])
			var count := floorf(nodes[src]["units"] * _ghost_fraction(target))
			var g := _spawn_decoy(seat, src, _as_int(target[1]), count, false)
			ev["hid"] = g.get("id", -1)
			ev["private"] = seat                         # nobody else may learn it is a ghost
		"echo_split":
			var hids := []
			for p in _echo_plan(seat):
				var g := _spawn_decoy(seat, p[0], p[1], p[2], true)
				if not g.is_empty():
					hids.append(g["id"])
			ev["count"] = hids.size()
			ev["affects"] = _hostile_list(seat, factions.keys())
			fx_events.append({"type": "ghosts", "seat": seat, "hids": hids, "private": seat})
		"rewire":
			_add_effect(id, seat, "seat", seat, sk["dur"], {"mult": sk["mult"], "fires": int(sk["fires"]), "fired": []})
			ev["affects"] = _hostile_list(seat, factions.keys())
		"superbloom":
			var left: float = float(sk["cap_shown"]) * Rules.SCALE if Rules.SUPERBLOOM_MODE == "cap" else -1.0
			_add_effect(id, seat, "seat", seat, sk["dur"], {"mult": sk["mult"], "left": left})
		"core_meltdown":
			var hm := _horde(_as_int(target))
			ev["affects"] = _hostile_list(seat, [nodes[hm["target"]]["owner"]])
			_meltdown(seat, hm)
		"relay_aegis":
			_aegis(seat, _as_int(target))
	if slot == "ultimate":
		ult_charge[seat] = 0.0
		ult_since[seat] = 0.0
	else:
		skill_cd[seat][slot] = float(sk["cd"])
	_cast_done(ev)
	return true


func _cast_done(ev: Dictionary) -> void:
	fx_events.append(ev)
	var tel := ev.duplicate()
	tel.erase("pos")
	tel["t"] = time
	events.append(tel)


func targets_for(seat: String, slot: String) -> Array:
	## Every target cast_check accepts right now, for the targeting UI (call it on a tap, not per frame).
	var id := skill_id(seat, slot)
	if not Rules.SKILLS.has(id):
		return []
	var kind: String = Rules.SKILLS[id]["target"]
	if slot == "ultimate" and id == "rewire" and rewire_left(seat) > 0:
		kind = "relay"
	var cands := []
	match kind:
		"own_line":
			for h in hordes:
				if h["owner"] == seat:
					cands.append(h["id"])
		"own_vat", "own_node":
			for n in nodes:
				if n["owner"] == seat:
					cands.append(n["id"])
		"deck", "fixed_deck":
			cands = range(edges.size())
		"relay", "enemy_relay":
			for n in nodes:
				if n["relay"] != "":
					cands.append(n["id"])
		"vat_to_node":
			var out := []
			if cast_check(seat, slot, [-1, -1]) == "Start from one of your nodes":   # slot ready: list the sources
				for n in nodes:
					if n["owner"] == seat and not collapsed.get(n["id"], false) and floorf(n["units"] * _ghost_fraction(null)) >= 1.0:
						out.append(n["id"])
			return out
		_:
			return [null] if cast_check(seat, slot, null) == "" else []
	if kind == "enemy_relay":                         # fire where it can, else offer the jam
		var out := []
		for c in cands:
			if cast_check(seat, slot, c) == "":
				out.append(c)
			elif cast_check(seat, slot, [c, "jam"]) == "":
				out.append([c, "jam"])
		return out
	return cands.filter(func(t): return cast_check(seat, slot, t) == "")


# ------------------------------------------------------------------ effects over time
func _add_effect(id: String, seat: String, on: String, target, dur: float, extra := {}) -> Dictionary:
	var e := {"id": id, "seat": seat, "on": on, "target": target, "t": float(dur), "dur": float(dur)}
	e.merge(extra)
	effects.append(e)
	_index_effects()
	return e


func _drop_effects(on: String, target, id: String) -> void:
	## A recast on the same target refreshes the effect instead of stacking it.
	var before := effects.size()
	effects = effects.filter(func(e): return not (e["on"] == on and e["target"] == target and e["id"] == id))
	if effects.size() != before:
		_index_effects()


func _step_skills(dt: float) -> void:
	for seat in skill_cd:
		var cd: Dictionary = skill_cd[seat]
		for k in cd:
			if cd[k] > 0.0:
				cd[k] = maxf(0.0, cd[k] - dt)
	if effects.is_empty():
		return
	var ended := []
	for e in effects:
		e["t"] = float(e["t"]) - dt
		if e["id"] == "scorch":
			_burn(e, dt)
		if e["id"] == "demolish" and e.get("phase", "") == "down":
			demolished[e["target"]] = maxf(float(e["t"]), 0.0)
		if float(e["t"]) <= 0.0 or (e["on"] == "horde" and _horde(e["target"]).is_empty()):
			ended.append(e)
	for e in ended:
		_end_effect(e)


func _end_effect(e: Dictionary) -> void:
	effects = effects.filter(func(x): return not is_same(x, e))
	_index_effects()
	fx_events.append({"type": "skill_end", "id": e["id"], "seat": e["seat"], "on": e["on"], "target": e["target"]})
	events.append({"t": time, "type": "skill_end", "id": e["id"], "seat": e["seat"], "kills": e.get("kills", 0.0)})
	match e["id"]:
		"demolish":
			var ei: int = e["target"]
			if e.get("phase", "") == "warning":
				if anchor_state(ei) != null or not _deck_ok(ei):
					fx_events.append({"type": "demolish_failed", "edge": ei, "seat": e["seat"]})
					events.append({"t": time, "type": "demolish_failed", "edge": ei, "seat": e["seat"]})
				else:                                     # the deck is gone: lines on it and ordered across it pour off (0.18.6 waterfall)
					var down: float = Rules.SKILLS["demolish"]["down"]
					demolished[ei] = down
					_add_effect("demolish", e["seat"], "edge", ei, down, {"phase": "down"})
					fx_events.append({"type": "demolish", "edge": ei, "seat": e["seat"]})
			else:
				demolished.erase(ei)
				fx_events.append({"type": "deck_rebuilt", "edge": ei})
		"anchor", "relay_aegis":
			if e["on"] == "edge":
				_settle_edge(e["target"], bool(e["open"]))
		"bypass":
			_settle_bypass(e["target"])


func _settle_edge(ei: int, was_open: bool) -> void:
	## An anchor ends: a relay deck no longer where its relay says goes now; its riders fall (_settle).
	var ctrl: int = edge_controller.get(ei, -1)
	if ctrl < 0 or anchor_state(ei) != null:
		return
	if was_open and not _edge_open(ei):
		_settle(nodes[ctrl], [ei])


func _settle_bypass(relay_id: int) -> void:
	var n: Dictionary = nodes[relay_id]
	var closing := []
	for i in controlled_edges(relay_id):
		if anchor_state(i) == null and not i in n["moving_edges"] and not _edge_open(i) and not collapsed.get(edges[i]["a"], false) \
				and not collapsed.get(edges[i]["b"], false):
			closing.append(i)
	if not closing.is_empty():
		_settle(n, closing)


func _settle(n: Dictionary, closing: Array) -> void:
	## Bypass / Anchor over: the decks that go away drop everything on them at once (Daniele, 0.18.7: every
	## relay kind drops its riders, no "carried in"; a rotation flings them as its turn does).
	_relay_drop(n, closing, 0.0)                          # the same fate as a relay's own tick
	fx_events.append({"type": "relay_settle", "node": n["id"], "closing": closing})


func _burn(e: Dictionary, dt: float) -> void:
	## Scorch: every enemy line on the deck loses `rate` of the units it has on it per second, up to the
	## cast's total (Alpha 11: 25 HP/s per unit, 1000 HP).
	var ei: int = e["target"]
	var rate: float = Rules.SKILLS["scorch"]["rate"]
	for h in hordes.duplicate():
		if float(e["left"]) <= 0.0:
			return
		if allied(h["owner"], e["seat"]) or h["units"] <= 0.0:
			continue
		var on := 0.0
		for sp in h["spans"]:
			if sp["edge"] == ei:
				on += _overlap(h, sp["s0"], sp["s1"])
		if on <= 0.0:
			continue
		var units_on: float = h["units"] * clampf(on / maxf(chain_length(h), 0.001), 0.0, 1.0)
		var loss: float = minf(minf(rate * units_on * dt / stat(h["owner"], "health"), float(e["left"])), h["units"])
		e["left"] = float(e["left"]) - loss
		h["units"] -= loss
		if not h.get("decoy", false):
			combat_losses[h["owner"]] = combat_losses.get(h["owner"], 0.0) + loss
			_credit(e["seat"], h["owner"], loss)
			e["kills"] = float(e["kills"]) + loss
		if h["units"] <= 0.0 and not h["streaming"]:
			_kill_horde(h, "scorch")


func _capture_effects(n: Dictionary, seat: String) -> void:
	## A node changes hands: the old owner's protection on it ends; an echo jam ends if its caster's side took it.
	if _fx_node.is_empty() or not _fx_node.has(n["id"]):
		return
	var id: int = n["id"]
	effects = effects.filter(func(e):
		if e["on"] != "node" or e["target"] != id:
			return true
		if e["id"] in ["spore_burst", "fortify", "relay_aegis"]:
			return allied(e["seat"], seat)
		if e["id"] == "echo_split":
			return not allied(e["seat"], seat)
		return true)
	_index_effects()


# ------------------------------------------------------------------ skill effects that act at once
func _meltdown(seat: String, h: Dictionary) -> void:
	## Core Meltdown (sec5.2): sacrifice share of the line (at least min_shown, no upper cap); each unit
	## sacrificed kills kills_per defenders (cap_shown at most; Fortify / Aegis divide it); a garrison at zero
	## -> the rest of the line (and its siege there) captures. No charge from any of it.
	var sk: Dictionary = Rules.SKILLS["core_meltdown"]
	var n: Dictionary = nodes[h["target"]]
	var sac: float = minf(h["units"], maxf(h["units"] * float(sk["share"]), float(sk["min_shown"]) * Rules.SCALE))
	h["units"] -= sac
	combat_losses[seat] = combat_losses.get(seat, 0.0) + sac
	var kills: float = minf(minf(sac * float(sk["kills_per"]), float(sk["cap_shown"]) * Rules.SCALE) / garrison_div(n), n["units"])
	n["units"] -= kills
	if n["owner"] != "":
		combat_losses[n["owner"]] = combat_losses.get(n["owner"], 0.0) + kills
	var took := false
	if n["units"] <= 0.0001:
		n["units"] = 0.0
		var rest: float = h["units"] + n["siege"].get(seat, 0.0)
		if rest > 0.0:
			if h["streaming"]:
				_end_streaming(nodes[h["route"][0]], "done")    # what never left stays in the vat
			hordes.erase(h)
			var old: String = n["owner"]
			_capture(n, seat, rest)
			events.append({"t": time, "type": "capture", "node": n["id"], "seat": seat, "from": old})
			captured.emit(n["id"], seat, old)
			took = true
	if not took and h["units"] <= 0.0 and h in hordes:
		_kill_horde(h, "meltdown")
	fx_events.append({"type": "meltdown", "node": n["id"], "seat": seat, "hid": h["id"], "sacrificed": Rules.shown(sac),
			"killed": Rules.shown(kills), "captured": took})
	events.append({"t": time, "type": "meltdown", "node": n["id"], "seat": seat, "sacrificed": sac, "killed": kills, "captured": took})


func _aegis(seat: String, id: int) -> void:
	## Relay Aegis: the node and its adjacent own nodes (over open decks) are shielded and produce more; the
	## decks between them are anchored and the relays among them locked, for `dur` seconds.
	var sk: Dictionary = Rules.SKILLS["relay_aegis"]
	var group := [id]
	for link in adj[id]:
		var nb: int = link[0]
		if nodes[nb]["owner"] == seat and not collapsed.get(nb, false) and is_edge_open(link[1]) and not nb in group:
			group.append(nb)
	for g in group:
		_drop_effects("node", g, "relay_aegis")
		_add_effect("relay_aegis", seat, "node", g, sk["dur"], {"div": sk["div"], "prod": sk["prod"], "center": id})
	for ei in range(edges.size()):
		var e: Dictionary = edges[ei]
		if e["plaza"] or not (e["a"] in group and e["b"] in group) or _deck_moving(ei):
			continue
		var held = anchor_state(ei)
		_add_effect("relay_aegis", seat, "edge", ei, sk["dur"], {"open": held if held != null else _edge_open(ei), "center": id})


# ------------------------------------------------------------------ decoys (Ghost Line, Echo Split)
func _spawn_decoy(seat: String, src: int, dst: int, count: float, echo: bool) -> Dictionary:
	var route := find_route(src, dst)
	if route.size() < 2 or count < 1.0:
		return {}
	var h := _new_horde(seat, count, route)            # looks like any send: streams out, same fields
	h["decoy"] = true
	h["ghost_left"] = count
	if echo:
		h["echo"] = true
	hordes.append(h)
	return h


func _echo_plan(seat: String) -> Array:
	## [[source, destination, units]] for Echo Split: the biggest own lines on the move (echoes at most), each
	## echoed from its own source toward the enemy node nearest its target (another route).
	var lines := hordes.filter(func(h): return h["owner"] == seat and not h.get("decoy", false) and h["state"] in ["move", "fight"] \
			and not h.get("retreat", false) and h["units"] >= 1.0)
	lines.sort_custom(func(a, b): return a["units"] > b["units"])
	var out := []
	for h in lines:
		if out.size() >= int(Rules.SKILLS["echo_split"]["echoes"]):
			break
		var src: int = h["route"][0]
		if nodes[src]["owner"] != seat or collapsed.get(src, false):
			continue
		var tp: Vector3 = nodes[h["target"]]["pos"]
		var cands := nodes.filter(func(n): return n["id"] != h["target"] and n["id"] != src and not collapsed.get(n["id"], false) \
				and n["owner"] != "" and not allied(n["owner"], seat))
		cands.sort_custom(func(a, b): return (a["pos"] as Vector3).distance_to(tp) < (b["pos"] as Vector3).distance_to(tp))
		for n in cands:
			if find_route(src, n["id"]).size() >= 2:
				out.append([src, n["id"], floorf(h["units"])])
				break
	return out


func _emit_decoys(dt: float) -> void:
	## A decoy streams out of its vat at the door rate like a real order (without touching the vat).
	for h in hordes:
		if not h.get("decoy", false) or float(h.get("ghost_left", 0.0)) <= 0.0:
			continue
		var src: Dictionary = nodes[h["route"][0]]
		if src["owner"] != h["owner"] or collapsed.get(src["id"], false):
			_decoy_done_streaming(h)
			continue
		var x: float = minf(h["ghost_left"], Rules.exit_rate() * dt)
		h["units"] += x
		h["ghost_left"] -= x
		if h["ghost_left"] <= 0.001:
			_decoy_done_streaming(h)


func _decoy_done_streaming(h: Dictionary) -> void:
	h["ghost_left"] = 0.0
	if h["streaming"]:
		h["streaming"] = false
		h["ordered"] = h["units"]
		h["start_units"] = maxf(h["units"], 1.0)


func _decoy_arrive(n: Dictionary, h: Dictionary) -> void:
	## A decoy pours in and vanishes: nothing reinforces, nothing attacks. An echo landing on an enemy node
	## jams its vat and cannon (Echo Split's payload, Alpha 11 Hostile Takeover).
	if h.get("landed", false):
		return
	h["landed"] = true
	if h.get("echo", false) and n["owner"] != "" and not allied(n["owner"], h["owner"]) and not collapsed.get(n["id"], false):
		_drop_effects("node", n["id"], "echo_split")
		_add_effect("echo_split", h["owner"], "node", n["id"], Rules.SKILLS["echo_split"]["disrupt"])
		fx_events.append({"type": "disrupt", "node": n["id"], "seat": h["owner"]})
		events.append({"t": time, "type": "disrupt", "node": n["id"], "seat": h["owner"], "victim": n["owner"]})
	fx_events.append({"type": "ghost_end", "hid": h["id"], "seat": h["owner"], "why": "landed", "node": n["id"]})


func _step_decoys() -> void:
	## SIEGE: a decoy reaching a hostile waypoint's platform dissolves (it never fights a garrison).
	if Rules.bridge_combat:
		for h in hordes:
			if not h.get("decoy", false) or h["state"] == "absorb":
				continue
			for ns in h["node_spans"]:
				var n: Dictionary = nodes[ns["node"]]
				if h["s"] >= ns["s0"] and h["s"] <= ns["s1"] and n["owner"] != "" and not allied(n["owner"], h["owner"]):
					if not h in _popped:
						_popped.append(h)
					break
	_pop_decoys()


func _pop_decoys() -> void:
	for g in _popped:
		if g in hordes:
			fx_events.append({"type": "ghost_end", "hid": g["id"], "seat": g["owner"], "why": "contact"})
			_kill_horde(g, "ghost")
	_popped = []


# ------------------------------------------------------------------ helpers for events
func _hostile_list(seat: String, seats: Array) -> Array:
	var out := []
	for s in seats:
		if str(s) != "" and not allied(str(s), seat) and not str(s) in out:
			out.append(str(s))
	return out


func _deck_seats(seat: String, ei: int) -> Array:
	## Hostile seats a deck skill touches: the owners of its ends and of the lines on it.
	var seats := [nodes[edges[ei]["a"]]["owner"], nodes[edges[ei]["b"]]["owner"]]
	for h in hordes:
		for sp in h["spans"]:
			if sp["edge"] == ei and _overlap(h, sp["s0"], sp["s1"]) > 0.0:
				seats.append(h["owner"])
				break
	return _hostile_list(seat, seats)


func _target_pos(kind: String, target, seat: String) -> Vector3:
	match kind:
		"own_line":
			var h := _horde(_as_int(target))
			return sample(h, h["s"])[0] if not h.is_empty() else Vector3.ZERO
		"deck", "fixed_deck":
			var line := deck_line(_as_int(target))
			return (line[0] as Vector3).lerp(line[-1], 0.5) if not line.is_empty() else Vector3.ZERO
		"vat_to_node":
			return nodes[_as_int(target[0])]["pos"]
		"enemy_relay":
			return nodes[_relay_target(target)[0]]["pos"]
		"none":
			return nodes[homes[seat]]["pos"] if homes.has(seat) else Vector3.ZERO
	var i := _as_int(target)
	return nodes[i]["pos"] if i >= 0 and i < nodes.size() else Vector3.ZERO
