class_name SeatAI
extends RefCounted
## Opponent: every `period` seconds, from its strongest node, attack the cheapest node it can take
## with a 75% send, counting units already en route; keeps a garrison reserve and builds with the
## same costs the player pays. No economy or combat cheats. Levels (Rules.AI_LEVELS) change only
## how often it thinks, how much margin it wants and whether it uses relays as weapons.
## Hazard-aware relay use (Alpha 12): a relay is fired to drop or redirect enemy hordes on the
## decks it controls, to pull them in early only if the garrison can take them, or to open routes
## - never on a blind timer (which left nodes isolated on the old build).

var seat: String
var period := 2.5
var margin := 1.15
var use_relays := true
var _t := 0.0


func _init(s: String, think_every := 2.5, level := "") -> void:
	seat = s
	period = think_every
	if level != "" and Rules.AI_LEVELS.has(level):
		var cfg: Dictionary = Rules.AI_LEVELS[level]
		period = cfg["period"]
		margin = cfg["margin"]
		use_relays = cfg["relays"]


func think(sim: Sim, dt: float) -> void:
	_t += dt
	if _t < period or sim.over or sim.eliminated.has(seat):
		return
	_t = 0.0
	if use_relays:
		_relays(sim)
	_build(sim)
	var mine := sim.nodes.filter(func(n): return n["owner"] == seat and n["units"] >= 25.0)
	mine.sort_custom(func(a, b): return a["units"] > b["units"])
	var en_route := {}
	for h in sim.hordes:
		if h["owner"] == seat:
			en_route[h["target"]] = en_route.get(h["target"], 0.0) + h["ordered"]
	for n in sim.nodes:                               # units already fighting on that platform
		en_route[n["id"]] = en_route.get(n["id"], 0.0) + n["siege"].get(seat, 0.0)
	for src in mine:
		var best := -1
		var best_score := INF
		for n in sim.nodes:
			if n["owner"] == seat or sim.collapsed.get(n["id"], false):
				continue
			if sim.last_stand_active and (sim.last_stand_warn_node == n["id"] or _drops_soon(sim, n["id"])):
				continue                                  # don't pour troops onto a node about to fall
			var route := sim.find_route(src["id"], n["id"])
			if route.is_empty():
				continue
			var need: float = (n["units"] + n["shield"]) * margin + 8.0 - en_route.get(n["id"], 0.0)
			var score: float = need + route.size() * 6.0
			if sim.last_stand_active and n["id"] == sim.last_stand_final:
				score -= 40.0                             # the final is where the match is decided
			if floorf(src["units"] * 0.75) > need and score < best_score:
				best = n["id"]
				best_score = score
		if best >= 0:
			sim.send(src["id"], best, 0.75)
			return
	# Last Stand: evacuate a node under warning toward the nearest safe own node
	if sim.last_stand_active and sim.last_stand_warn_node >= 0:
		var doomed: Dictionary = sim.nodes[sim.last_stand_warn_node]
		if doomed["owner"] == seat and doomed["units"] >= 5.0:
			var target := _nearest_safe(sim, doomed["id"])
			if target >= 0:
				sim.send(doomed["id"], target, 1.0)


func _drops_soon(sim: Sim, node_id: int) -> bool:
	var i := sim.last_stand_order.find(node_id)
	return i >= 0 and i < sim.last_stand_next + 1


func _nearest_safe(sim: Sim, from_id: int) -> int:
	var best := -1
	var best_len := INF
	for n in sim.nodes:
		if n["id"] == from_id or sim.collapsed.get(n["id"], false) or _drops_soon(sim, n["id"]):
			continue
		var route := sim.find_route(from_id, n["id"])
		if route.is_empty():
			continue
		var score: float = route.size() + (0.0 if n["owner"] == seat else 3.0)
		if score < best_len:
			best_len = score
			best = n["id"]
	return best


func _relays(sim: Sim) -> void:
	for n in sim.nodes:
		if n["owner"] != seat or n["relay"] == "" or n["relay_cd"] > 0.0 or n["relay_phase"] != "":
			continue
		var closing := []
		var next_index: int = sim.relay_next_index(n)
		for i in sim.controlled_edges(n["id"]):
			if sim._edge_open_at(i, n["relay_index"]) and not sim._edge_open_at(i, next_index):
				closing.append(i)
		var enemy_on := 0.0
		var own_on := 0.0
		for h in sim.hordes:
			for sp in h["spans"]:
				if sp["edge"] in closing and sim._overlap(h, sp["s0"], sp["s1"]) > 0.0:
					if h["owner"] == seat:
						own_on += h["units"]
					else:
						enemy_on += h["units"]
		var fire := false
		if enemy_on > own_on + 5.0:
			if n["relay"] == "retract":                   # pulls them straight into my garrison
				fire = n["units"] > enemy_on * 1.5
			else:                                         # switch/remote drop them, rotation strands them
				fire = true
		elif own_on < 1.0 and enemy_on < 1.0:
			# open routes: does the next state reach more of the map from my strongest node?
			var before := sim.reachable_from(n["id"])
			n["relay_index"] = next_index
			var after := sim.reachable_from(n["id"])
			n["relay_index"] = (next_index - 1 + sim.relay_states(n).size()) % sim.relay_states(n).size()
			fire = after > before
		if fire:
			sim.fire_relay(n["id"])


func _build(sim: Sim) -> void:
	## Structure parity with the player: same costs, same slots. Upgrades a vat once it can pay and
	## keep a reserve, builds one forge (a standing combat bonus), then cannons where allowed.
	for n in sim.nodes:
		if n["owner"] != seat or n["build_kind"] != "":
			continue
		var reserve: float = 20.0 if n["id"] != sim.homes.get(seat, -1) else 40.0
		if n["attachment"] == "cannon" and n["cannon_tier"] < 3 \
				and n["units"] >= Rules.CANNON_COST[n["cannon_tier"] + 1] + reserve and sim.upgrade_structure(n["id"]):
			return
		if Sim.has_vat(n) and n["tier"] < 4 and n["units"] >= Sim.vat_cost(n) + reserve \
				and n["units"] >= Rules.CAPS[n["tier"]] * 0.6 and sim.upgrade_vat(n["id"]):
			return
	var has_forge := sim.has_forge(seat)
	for n in sim.nodes:
		if n["owner"] != seat or n["build_kind"] != "" or n["attachment"] != "" or n["relay"] == "":
			continue                                      # only empty relay slots: never give up a vat
		if not has_forge and "forge" in n["buildable"] and n["units"] >= Rules.FORGE_COST + 10.0:
			sim.build_attachment(n["id"], "forge")
			return
		if "cannon" in n["buildable"] and n["units"] >= Rules.CANNON_COST[1] + 10.0:
			sim.build_attachment(n["id"], "cannon")
			return
