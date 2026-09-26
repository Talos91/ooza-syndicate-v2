class_name SeatAI
extends RefCounted
## Opponent AI - Alpha 11's decision loop (simulation.gd think / ai_balance.gd) on 2.0's rules, five
## levels (Rules.AI_LEVELS: Training, Casual, Standard, Veteran, Expert). No economy or combat cheats:
## it pays the player's costs and sees what the player sees, only less exactly at lower levels.
## Every `period` seconds: relays, (SIEGE) retreats, defend threatened nodes first, invest, then at
## most one offensive every `attack_gap` seconds, planned from up to `coordination` nearby nodes
## against a garrison it estimates (with `error`, refreshed every `observe` s, grown by `forecast`).
## Target choice never privileges the human (Daniele, Alpha 17: "all AIs work together to kill the
## human"): Alpha 11's rival adjustment prefers its own border, answers whoever attacks it, contains
## the strongest rival and steers away from a node somebody else is already attacking; players are
## left alone for the first `grace` seconds; the plan is drawn from the best `choice` plans.
## Relays (Daniele: "use switches properly"): level 1 fires when enemies are on a deck it can drop or
## pull in and none of its own are; level 2 fires ahead, for the lines that will be on the deck when it
## moves (RELAY_WARNING later); level 3 also opens a shorter route to where it wants to go. A rotation
## flings everyone on its deck (0.18.3): fired only for the kill, never with its own lines on it.
## Relay sense (0.18.7, Daniele: "the ai tends to avoid relay bridges all together and almost never build
## structure on relays"), level 1+: orders take the fastest route unless a hostile relay can change a deck
## on it before the whole line is across (0.18.6 waterfall: the rest would pour off the lip) - level 1
## assumes a hostile relay is always ready, level 2+ reads its cooldown and phase and who is about to
## capture a neutral one; never fires while an own line still has to cross (level 2+ counts the whole
## order it cuts, not only what is on the deck); keeps a garrison on the relays it holds, values them as
## targets, feeds them and builds a cannon (a busy front relay) or the forge there - the slot costs no vat.
## Level 2 opens routes too. Training and Casual (level 0) keep the plain behaviour.
## Skills (0.18.7, "the AI must not be skill-less"): every think it may cast one of its loadout's skills
## (its faction's Rules.FACTION_LOADOUT unless the match gave it another), at most one cast every
## Rules.AI_SKILL_GAP[level] s, each on a cheap heuristic of what it can see (_skills). It never reads
## another seat's decoy flag: a Ghost Line fools it as it fools a player.

var seat: String
var level := "Standard"
var cfg: Dictionary
var period := 2.5
var _t := 0.0
var _clock := 0.0
var _attack_after := 0.0
var _invest_after := 0.0
var _memory := {}                          # node id -> {"units", "next"}
var _busy := {}                            # node id -> true once it ordered a send this think
var _fed := {}                             # relay node id -> time until which units sent there are for its slot
var _route_risky := false                  # set by _route: the route it returned is at risk from a relay
var _skill_after := 0.0                    # no cast before this match time (Rules.AI_SKILL_GAP)
var casts := 0                             # skills cast this match (tests)
var rng := RandomNumberGenerator.new()


func _init(s: String, think_every := 2.5, lvl := "") -> void:
	## think_every is used only when no level is given; a level's own period (Rules.AI_LEVELS) always wins.
	seat = s
	level = lvl if Rules.AI_LEVELS.has(lvl) else "Standard"
	cfg = Rules.AI_LEVELS[level]
	period = cfg["period"] if lvl != "" else think_every
	rng.seed = hash(s + level)
	_t = rng.randf() * period                   # seats don't all think on the same frame


func think(sim: Sim, dt: float) -> void:
	_t += dt
	_clock = sim.time
	if _t < period or sim.over or sim.eliminated.has(seat):
		return
	_t = 0.0
	_busy = {}      # a send supersedes the node's earlier order: one order per node per think
	if int(cfg["relays"]) > 0:
		_relays(sim)
	_skills(sim)
	if Rules.bridge_combat and int(cfg["relays"]) > 0:   # RECALL is SIEGE only
		_retreats(sim)
	if sim.last_stand_active:
		_evacuate(sim)
	_defend(sim)
	_build(sim)
	if sim.time >= _attack_after:
		_attack(sim)


# ------------------------------------------------------------------ helpers
func _mine(sim: Sim) -> Array:
	return sim.nodes.filter(func(n): return n["owner"] == seat and not sim.collapsed.get(n["id"], false))


func _reserve(sim: Sim, n: Dictionary) -> float:
	## Keep what a neighbouring enemy could take (Alpha 11 reserve), plus a floor at home.
	var nearby := 0.0
	for link in sim.adj[n["id"]]:
		var o: Dictionary = sim.nodes[link[0]]
		if o["owner"] != "" and not sim.allied(o["owner"], seat):
			nearby = maxf(nearby, o["units"] * 0.15)
	return nearby + (4.0 * Rules.SCALE if n["id"] == sim.homes.get(seat, -1) else 0.0) + _relay_hold(sim, n)


func _incoming(sim: Sim, node_id: int, hostile: bool) -> float:
	var amount := 0.0
	for h in sim.hordes:
		if h["target"] != node_id or h.get("retreat", false):
			continue
		var enemy := not sim.allied(h["owner"], seat)
		if enemy == hostile:
			amount += maxf(h["units"], h["ordered"]) if h["streaming"] else h["units"]
	return amount


func _travel(sim: Sim, route: Array) -> float:
	var t := 0.0
	for i in range(route.size() - 1):
		t += sim.edge_cost(sim._edge_index(route[i], route[i + 1])) + 1.0
	return t


func _estimate(sim: Sim, n: Dictionary) -> float:
	## What it believes the garrison is: rounded, off by up to `error`, refreshed every `observe` s.
	var mem: Dictionary = _memory.get(n["id"], {})
	if mem.is_empty() or _clock >= float(mem["next"]):
		mem = {"units": maxf(0.0, float(n["units"]) * (1.0 + rng.randf_range(-cfg["error"], cfg["error"]))), "next": _clock + float(cfg["observe"])}
		_memory[n["id"]] = mem
	return mem["units"]


func _drops_soon(sim: Sim, node_id: int) -> bool:
	if not sim.last_stand_active:
		return false
	if sim.is_warned(node_id):
		return true
	if sim.v3:                                        # ring waves: this wave or the next
		var w := sim.drop_order_of(node_id)
		return w > 0 and w <= sim.last_stand_next + 1
	var i := sim.last_stand_order.find(node_id)
	return i >= 0 and i < sim.last_stand_next + 1


# ------------------------------------------------------------------ Last Stand
func _evacuate(sim: Sim) -> void:
	for doomed in sim.nodes:                          # every node of the warned wave
		if sim.is_warned(doomed["id"]) and doomed["owner"] == seat and doomed["units"] >= 5.0:
			var target := _nearest_safe(sim, doomed["id"])
			if target >= 0:
				if not _send(sim, doomed["id"], target, 1.0).is_empty():
					_busy[doomed["id"]] = true


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


# ------------------------------------------------------------------ defence first
func _defend(sim: Sim) -> void:
	for target in _mine(sim):
		if sim.is_warned(target["id"]):
			continue                                      # units sent there die with it
		var threat := _incoming(sim, target["id"], true)
		for k in target["siege"]:
			if not sim.allied(k, seat):
				threat += target["siege"][k]
		if threat <= 0.0:
			continue
		var need: float = threat * 1.1 + 4.0 * Rules.SCALE - target["units"] - _incoming(sim, target["id"], false)
		if need <= 0.0:
			continue
		var donors := _mine(sim).filter(func(n): return n["id"] != target["id"] and n["build_kind"] == "" and not _busy.has(n["id"]))
		donors.sort_custom(func(a, b): return (a["pos"] as Vector3).distance_to(target["pos"]) < (b["pos"] as Vector3).distance_to(target["pos"]))
		for donor in donors:
			if need <= 0.0:
				break
			if _busy.has(donor["id"]):
				continue                                  # already sent to an earlier target this think
			var spare: float = donor["units"] - _reserve(sim, donor)
			if spare < 2.0 * Rules.SCALE or _route(sim, donor["id"], target["id"], minf(need, spare)).is_empty():
				continue
			var frac := clampf(minf(need, spare) / maxf(donor["units"], 1.0), 0.1, 1.0)
			if not _send(sim, donor["id"], target["id"], frac).is_empty():
				_busy[donor["id"]] = true
				need -= donor["units"] * frac


# ------------------------------------------------------------------ offence
func _rival_adjustment(sim: Sim, target: Dictionary) -> float:
	## Alpha 11 rival_target_adjustment: never a universal priority on one player.
	var owner: String = target["owner"]
	if owner == "":
		return 0.0
	var outsiders := {}
	var outside_units := 0.0
	var local := 0.0
	var retaliation := 0.0
	for h in sim.hordes:
		var to: Dictionary = sim.nodes[h["target"]]
		if not sim.allied(h["owner"], seat) and not sim.allied(h["owner"], owner) and to["owner"] == owner:
			outsiders[h["owner"]] = true                # somebody else is already on them
			outside_units += h["units"]
			if h["target"] == target["id"]:
				local += h["units"]
		if h["owner"] == owner and to["owner"] == seat:
			retaliation = minf(14.0, retaliation + h["units"] / Rules.SCALE * 0.3)
	var congestion := minf(32.0, outside_units / Rules.SCALE * 0.2 + outsiders.size() * 7.0 + local / Rules.SCALE * 0.35)
	var strength := clampf((sim.seat_strength(owner) - sim.seat_strength(seat)) / Rules.SCALE * 0.035, -4.0, 8.0)
	var border := 0.0
	for link in sim.adj[target["id"]]:
		if sim.nodes[link[0]]["owner"] == seat:
			border = 5.0
			break
	return border + retaliation + strength - congestion


func _attack(sim: Sim) -> void:
	var owned := _mine(sim)
	var plans := []
	for target in sim.nodes:
		if sim.allied(target["owner"], seat) or sim.collapsed.get(target["id"], false) or _drops_soon(sim, target["id"]):
			continue
		if target["owner"] != "" and sim.time < float(cfg["grace"]):
			continue                                      # early game: take neutrals, leave players be
		var donors := []
		for donor in owned:
			if donor["build_kind"] != "" or _busy.has(donor["id"]):
				continue
			var available: float = donor["units"] - _reserve(sim, donor)
			if available < 4.0 * Rules.SCALE:
				continue
			var route := _route(sim, donor["id"], target["id"], available)
			if route.is_empty():
				continue
			donors.append({"node": donor, "available": available, "travel": _travel(sim, route), "risky": _route_risky})
		if donors.is_empty():
			continue
		donors.sort_custom(func(a, b): return a["travel"] < b["travel"])
		if donors.size() > int(cfg["coordination"]):
			donors.resize(int(cfg["coordination"]))
		var available := 0.0
		var travel := 0.0
		for d in donors:
			available += d["available"]
			travel = maxf(travel, d["travel"])
		var estimate := _estimate(sim, target)
		var growth := 0.0
		if target["owner"] != "" and Sim.has_vat(target):
			growth = sim.production(target) * travel * float(cfg["forecast"])
		var defenders := minf(estimate + growth, maxf(estimate, float(Rules.CAPS[target["tier"]])))
		var defence: float = sim.stat(target["owner"], "health") if target["owner"] != "" else 1.0
		var needed: float = (defenders + 3.0 * Rules.SCALE) * float(cfg["margin"]) * defence / maxf(sim.attack_of(seat), 0.1) \
				- _incoming(sim, target["id"], false)
		if needed <= 0.0 or available < needed:
			continue
		var score: float = 70.0 + target["tier"] * 8.0 + (12.0 if target["category"] == "strategic" else 0.0) \
				+ (18.0 if target["owner"] == "" else 0.0) - needed / Rules.SCALE * 0.6 - travel * 2.0
		score += _rival_adjustment(sim, target) + _relay_value(sim, target)
		if donors.any(func(d): return d["risky"]):
			score -= Rules.AI_RELAY_RISK                  # its only way in crosses a deck a rival can change
		if sim.last_stand_active and sim.is_final(target["id"]):
			score += 20.0                                 # the last ring is where the match is decided
		plans.append({"target": target, "donors": donors, "needed": needed, "score": score})
	if plans.is_empty():
		return
	plans.sort_custom(func(a, b): return a["score"] > b["score"])
	var plan: Dictionary = plans[rng.randi_range(0, mini(plans.size(), int(cfg["choice"])) - 1)]
	if int(cfg["relays"]) >= 2 and _open_route(sim, plan):
		return                                            # a shorter way opens first; send next time
	_attack_after = sim.time + float(cfg["attack_gap"])
	var need: float = plan["needed"]
	for d in plan["donors"]:
		var avail: float = d["available"]
		var portion := 0.5 if need <= avail * 0.5 else (0.75 if need <= avail * 0.75 else 1.0)
		var frac := clampf(avail * portion / maxf(d["node"]["units"], 1.0), 0.1, 1.0)
		if not _send(sim, d["node"]["id"], plan["target"]["id"], frac).is_empty():
			_busy[d["node"]["id"]] = true
			need -= d["node"]["units"] * frac
		if need <= 0.0:
			break


# ------------------------------------------------------------------ relays
func _closing(sim: Sim, n: Dictionary) -> Array:
	var out := []
	var next_index: int = sim.relay_next_index(n)
	for i in sim.controlled_edges(n["id"]):
		if sim._edge_open_at(i, n["relay_index"]) and not sim._edge_open_at(i, next_index):
			out.append(i)
	return out


func _opening(sim: Sim, n: Dictionary) -> Array:
	var out := []
	var next_index: int = sim.relay_next_index(n)
	for i in sim.controlled_edges(n["id"]):
		if not sim._edge_open_at(i, n["relay_index"]) and sim._edge_open_at(i, next_index):
			out.append(i)
	return out


func _on_decks(sim: Sim, edges: Array, ahead: float) -> Array:
	## [enemy units, own units] on these decks now, or `ahead` seconds from now (level 2+).
	var enemy := 0.0
	var own := 0.0
	for h in sim.hordes:
		var v: float = Rules.move_speed() * sim.stat(h["owner"], "speed") * h.get("speed", 1.0)
		var shift: float = v * ahead if h["state"] == "move" else 0.0
		var head: float = minf(h["s"] + shift, h["L"])
		var tail: float = head - Sim.chain_length(h)
		for sp in h["spans"]:
			if sp["edge"] in edges and head > sp["s0"] and tail < sp["s1"]:
				if h["owner"] == seat or sim.allied(h["owner"], seat):
					own += h["units"]
				else:
					enemy += h["units"]
				break
	return [enemy, own]


func _fling_toll(sim: Sim, edges: Array, ahead: float) -> Array:
	## [enemy units, own or allied units] that a rotation turning `ahead` seconds from now would
	## fling: only the part of each line that is on these decks then.
	var enemy := 0.0
	var own := 0.0
	for h in sim.hordes:
		var v: float = Rules.move_speed() * sim.stat(h["owner"], "speed") * h.get("speed", 1.0)
		var shift: float = v * ahead if h["state"] == "move" and not h.get("blocked", false) else 0.0
		var head: float = minf(h["s"] + shift, h["L"])
		var length := Sim.chain_length(h)
		var on := 0.0
		for sp in h["spans"]:
			if sp["edge"] in edges:
				on += maxf(0.0, minf(head, sp["s1"]) - maxf(head - length, sp["s0"]))
		if on <= 0.0:
			continue
		var units: float = h["units"] * clampf(on / maxf(length, 0.001), 0.0, 1.0)
		if h["owner"] == seat or sim.allied(h["owner"], seat):
			own += units
		else:
			enemy += units
	return [enemy, own]


func _fling_cost(sim: Sim, edges: Array) -> float:
	## Own and allied units a rotation fired now would cost: on the deck now, at the tick
	## (RELAY_WARNING), or walking onto it during the turn (they walk off the lip into the void).
	var cost := 0.0
	for ahead in [0.0, Rules.RELAY_WARNING, Rules.RELAY_WARNING + Rules.RELAY_MOVE]:
		cost = maxf(cost, _fling_toll(sim, edges, ahead)[1])
	return cost


func _relays(sim: Sim) -> void:
	var lvl := int(cfg["relays"])
	for n in sim.nodes:
		if n["owner"] != seat or n["relay"] == "" or n["relay_cd"] > 0.0 or n["relay_phase"] != "":
			continue
		var closing := _closing(sim, n)
		if closing.is_empty():
			# 0.18.7: a retract left in / a remote left off after a kill blocks its own shortcut - put
			# the deck back, unless a rival order is still pouring off its lip (it would walk across)
			if _cut_toll(sim, _opening(sim, n), 0.0)[0] <= 0.5:
				sim.fire_relay(n["id"])
			continue
		# 0.18.7: with the 0.18.6 waterfall an own line routed across the deck is lost too, not only
		# the part on it - never fire while an own or allied line still has to cross it at the tick
		var cut := _cut_toll(sim, closing, Rules.RELAY_WARNING)
		if cut[1] > 0.5:
			continue
		if n["relay"] == "rotation":
			# Daniele (0.18.3): the turn flings every body on the deck into the void, the owner's own
			# too. Fire for the kill at the tick (level 2+: where the lines will be RELAY_WARNING from
			# now, and every hostile order it cuts), only if it kills more enemy than it costs, and never
			# with an own or allied body on the deck at any point until the turn is over.
			var kill: float = cut[0] if lvl >= 2 else _fling_toll(sim, closing, 0.0)[0]
			var cost := _fling_cost(sim, closing)
			if kill >= 2.0 * Rules.SCALE and cost <= 0.5 and kill > cost:
				sim.fire_relay(n["id"])
			continue
		var now := _on_decks(sim, closing, 0.0)
		var later := _on_decks(sim, closing, Rules.RELAY_WARNING + Rules.RELAY_MOVE * 0.5) if lvl >= 2 else now
		var enemy: float = cut[0] if lvl >= 2 else now[0]  # level 2+: the whole order it cuts pours away
		var own: float = maxf(now[1], later[1])
		if enemy < 2.0 * Rules.SCALE or own > 0.5:        # never drop its own (or allied) lines
			continue                                      # (0.18.7: a retract drops them too, it carries nobody in)
		# 0.18.7 assumes the relay-fall rule (Daniele): when the motion starts everything still on a deck
		# that goes away falls, retract included - nobody is carried into the relay node any more, so a
		# retract is a kill tool like a switch and needs no garrison to take its riders in
		sim.fire_relay(n["id"])


func _open_route(sim: Sim, plan: Dictionary) -> bool:
	## Level 2+ (0.18.7; level 3 before): fire one of its relays if the next state gives the plan a
	## faster route that no rival relay can take away before the line is across.
	var src: int = plan["donors"][0]["node"]["id"]
	var dst: int = plan["target"]["id"]
	var units: float = plan["donors"][0]["available"]
	var base := _route(sim, src, dst, units)
	var t0 := _travel(sim, base) if not base.is_empty() else INF
	if _route_risky:
		t0 += Rules.AI_RELAY_DETOUR                   # a risky way in is worth replacing
	for n in sim.nodes:
		if n["owner"] != seat or n["relay"] == "" or n["relay_cd"] > 0.0 or n["relay_phase"] != "":
			continue
		var closing := _closing(sim, n)
		if _cut_toll(sim, closing, Rules.RELAY_WARNING)[1] > 0.5:
			continue                                      # an own line still has to cross a deck it closes
		if n["relay"] == "rotation" and _fling_cost(sim, closing) > 0.5:
			continue                                      # the turn would fling its own lines
		var keep: int = n["relay_index"]
		n["relay_index"] = sim.relay_next_index(n)
		var alt := _route(sim, src, dst, units)
		var alt_risky := _route_risky
		n["relay_index"] = keep
		if not alt.is_empty() and not alt_risky and _travel(sim, alt) < t0 - 3.0:
			sim.fire_relay(n["id"])
			return true
	return false


func _cut_toll(sim: Sim, edges: Array, ahead: float) -> Array:
	## [hostile units, own or allied units] a change of these decks at the tick `ahead` s from now
	## costs (0.18.6 waterfall): every line whose route still has one of them to cross loses what has
	## not passed it - the part on it falls (relay-fall rule, every kind), the rest pours off the lip -
	## plus what its vat has still to send.
	var enemy := 0.0
	var own := 0.0
	for h in sim.hordes:
		var v: float = Rules.move_speed() * sim.stat(h["owner"], "speed") * h.get("speed", 1.0)
		var shift: float = v * ahead if h["state"] == "move" and not h.get("blocked", false) else 0.0
		var head: float = minf(h["s"] + shift, h["L"])
		var length := maxf(Sim.chain_length(h), 0.001)
		var tail: float = head - length
		var lost := 0.0
		for sp in h["spans"]:                             # spans run along the path: the first deck not yet passed
			if sp["edge"] in edges and tail < sp["s1"]:
				lost = h["units"] if head < sp["s0"] else h["units"] * clampf((minf(head, sp["s1"]) - tail) / length, 0.0, 1.0)
				if h["streaming"]:
					var src: Dictionary = sim.nodes[h["route"][0]]
					if src["streaming"].get("hid", -1) == h["id"]:
						lost += float(src["streaming"]["remaining"])
				break
		if lost <= 0.0:
			continue
		if h["owner"] == seat or sim.allied(h["owner"], seat):
			own += lost
		else:
			enemy += lost
	return [enemy, own]


# ------------------------------------------------------------------ relay-aware routing (0.18.7)
func _send(sim: Sim, from_id: int, to_id: int, fraction: float) -> Dictionary:
	## sim.send over _route: the order takes the fastest path no rival relay can cut before the line
	## is across (the host's own find_route with those decks left out; the route travels in snapshots).
	var route := _route(sim, from_id, to_id, floorf(sim.nodes[from_id]["units"] * fraction))
	if route.size() < 2:
		return {}
	var h := sim.send(from_id, to_id, fraction)
	if not h.is_empty() and h["route"] != route:
		sim._set_route(h, route)
	return h


func _route(sim: Sim, from_id: int, to_id: int, units: float) -> Array:
	## The fastest route, or (level 1+) the fastest one whose relay decks no rival can change before a
	## line of `units` is across it - if that detour costs at most AI_RELAY_DETOUR s or doubles the
	## trip. Otherwise the fastest route with _route_risky set (attack plans price it; defence and
	## evacuation take it anyway). Level 0 routes like sim.send.
	_route_risky = false
	var route := sim.find_route(from_id, to_id)
	if int(cfg["relays"]) <= 0 or route.size() < 2:
		return route
	var bad := _risky_decks(sim, route, units)
	if bad.is_empty():
		return route
	var limit := maxf(_travel(sim, route) * 2.0, _travel(sim, route) + Rules.AI_RELAY_DETOUR)
	var avoid := {}
	for _pass in range(4):
		for ei in bad:
			avoid[ei] = true
		var alt := sim.find_route(from_id, to_id, avoid)
		if alt.size() < 2 or _travel(sim, alt) > limit:
			break
		bad = _risky_decks(sim, alt, units)
		if bad.is_empty():
			return alt
	_route_risky = true
	return route


func _risky_decks(sim: Sim, route: Array, units: float) -> Array:
	## Relay decks on this route that someone hostile can change before the line's tail is over them
	## (the door emits `units` at Rules.exit_rate(); the crossing estimate gets AI_RELAY_SLACK/PAD).
	## Assumes the relay-fall rule (0.18.7): the deck stays walkable through the 1 s warning and is lost
	## the moment the motion starts (the tick) - whatever is on it falls, whatever is routed over it
	## pours off the lip - so the line is safe only if its tail is across before the earliest tick.
	## The controller's reaction time is taken as zero (the conservative reading: a player can fire the
	## instant the line shows).
	var out := []
	var emit := maxf(units, 0.0) / maxf(Rules.exit_rate(), 0.1)
	var t := 0.0
	for i in range(route.size() - 1):
		var ei := sim._edge_index(route[i], route[i + 1])
		var cross := sim.edge_cost(ei) + 1.0
		var c: int = sim.edge_controller.get(ei, -1)
		if c >= 0 and _flip_at(sim, sim.nodes[c], ei) < (t + cross) * Rules.AI_RELAY_SLACK + Rules.AI_RELAY_PAD + emit:
			out.append(ei)
		t += cross
	return out


func _flip_at(sim: Sim, r: Dictionary, ei: int) -> float:
	## Earliest seconds from now at which deck `ei` of relay `r` can be taken away by someone hostile
	## (INF: nobody can). Its own or an ally's relay: only a fire already under way. Level 1 treats a
	## rival relay as always ready; level 2+ reads its cooldown and phase, and a neutral relay that a
	## rival line is about to capture.
	var lvl := int(cfg["relays"])
	var owner: String = r["owner"]
	var states := sim.relay_states(r)
	if states.is_empty():
		return INF
	if owner != "" and (owner == seat or sim.allied(owner, seat)):
		if r["relay_phase"] == "warning" and not sim._edge_open_at(ei, r["relay_pending"]):
			return r["relay_t"]
		return INF
	var tick := INF
	var idx := sim.relay_next_index(r)
	if owner == "":
		if lvl < 2:
			return INF
		for h in sim.hordes:                             # a rival line about to take it
			if h["target"] == r["id"] and not h.get("retreat", false) and not sim.allied(h["owner"], seat) \
					and maxf(h["units"], h["ordered"]) > r["units"]:
				var v: float = Rules.move_speed() * sim.stat(h["owner"], "speed")
				tick = minf(tick, (h["L"] - h["s"]) / maxf(v, 0.1) + Rules.RELAY_WARNING)
		if tick == INF:
			return INF
	else:
		match r["relay_phase"]:
			"warning":
				tick = r["relay_t"]
				idx = r["relay_pending"]
			"moving":
				tick = r["relay_t"] + (Rules.RELAY_COOLDOWN if lvl >= 2 else 0.0) + Rules.RELAY_WARNING
			_:
				tick = (r["relay_cd"] if lvl >= 2 else 0.0) + Rules.RELAY_WARNING
	var period := Rules.RELAY_WARNING + Rules.RELAY_MOVE + Rules.RELAY_COOLDOWN
	for _k in range(states.size()):                      # the first fire that closes this deck
		if not sim._edge_open_at(ei, idx):
			return tick
		tick += period
		idx = (idx + 1) % states.size()
	return INF


func _deck_traffic(sim: Sim, n: Dictionary) -> float:
	## Hostile units whose route still crosses one of this relay's decks or passes through it.
	var decks := sim.controlled_edges(n["id"])
	var amount := 0.0
	for h in sim.hordes:
		if h["owner"] == seat or sim.allied(h["owner"], seat):
			continue
		var tail: float = h["s"] - Sim.chain_length(h)
		for sp in h["spans"]:
			if sp["edge"] in decks and tail < sp["s1"]:
				amount += maxf(h["units"], h["ordered"])
				break
	return amount


func _relay_value(sim: Sim, target: Dictionary) -> float:
	## Target-score bonus for a relay node (level 1+): control of the shortcuts, more for one with
	## rival traffic over its decks, and (level 2+) for a rival's relay that can cut its own lines.
	var lvl := int(cfg["relays"])
	if lvl <= 0 or target["relay"] == "":
		return 0.0
	if lvl == 1:
		return Rules.AI_RELAY_VALUE * 0.5
	var v := Rules.AI_RELAY_VALUE + minf(10.0, _deck_traffic(sim, target) / Rules.SCALE * 0.3)
	if target["owner"] != "":
		v += 4.0
	return v


func _relay_hold(sim: Sim, n: Dictionary) -> float:
	## Level 1+: a relay node never grows, so it keeps a garrison (AI_RELAY_HOLD) and, while units are
	## on their way for its slot, the price of that build too.
	if n["relay"] == "" or int(cfg["relays"]) <= 0:
		return 0.0
	var hold := Rules.AI_RELAY_HOLD
	if float(_fed.get(n["id"], -1.0)) > _clock and n["attachment"] == "" and n["build_kind"] == "":
		hold += float(Rules.FORGE_COST if _slot_kind(sim, n) == "forge" else Rules.CANNON_COST[1])
	return hold


func _retreats(sim: Sim) -> void:
	## SIEGE: recall a line being shoved back and badly outnumbered (the player's mid-fight choice).
	for key in sim.fight_info:
		var ids: PackedStringArray = key.split(":")
		var a := sim._horde(int(ids[0]))
		var b := sim._horde(int(ids[1]))
		if a.is_empty() or b.is_empty():
			continue
		var mine := a if a["owner"] == seat else (b if b["owner"] == seat else {})
		if mine.is_empty() or mine.get("retreat", false) or mine["state"] == "absorb":
			continue                                      # recall() refuses these: try the next fight
		var theirs := b if mine == a else a
		if sim.power_of(mine) < 0.4 * sim.power_of(theirs) and mine["units"] > 15.0:
			if sim.recall(mine["id"]):
				return


# ------------------------------------------------------------------ investment
func _build(sim: Sim) -> void:
	## Same costs and slots as the player. One investment per `invest` seconds, never on a node
	## under attack or about to drop in the Last Stand: upgrades, a forge once it has three vats,
	## cannons on free relay slots.
	if sim.time < _invest_after:
		return
	var owned := _mine(sim)
	for n in owned:
		if n["build_kind"] != "" or _incoming(sim, n["id"], true) > 0.0 or _drops_soon(sim, n["id"]):
			continue
		var reserve := _reserve(sim, n) + 4.0 * Rules.SCALE
		if n["attachment"] == "cannon" and n["cannon_tier"] < 3 \
				and n["units"] >= Rules.CANNON_COST[n["cannon_tier"] + 1] + reserve and sim.upgrade_structure(n["id"]):
			_invest_after = sim.time + float(cfg["invest"])
			return
	var vats := owned.filter(func(n): return Sim.has_vat(n))
	if int(cfg["relays"]) >= 2:                           # level 2+: a busy front relay's cannon comes first
		if _build_relay_slot(sim, owned, true):
			return
		_feed_relay_slot(sim, owned, vats, 8.0)
	vats.sort_custom(func(a, b): return a["tier"] < b["tier"] if a["tier"] != b["tier"] else a["units"] > b["units"])
	for n in vats:
		if n["build_kind"] != "" or n["tier"] >= 4 or _incoming(sim, n["id"], true) > 0.0 or _drops_soon(sim, n["id"]):
			continue
		if n["units"] >= Sim.vat_cost(n) + _reserve(sim, n) + 4.0 * Rules.SCALE and n["units"] >= Rules.CAPS[n["tier"]] * 0.6 \
				and sim.upgrade_vat(n["id"]):
			_invest_after = sim.time + float(cfg["invest"])
			return
	if _build_relay_slot(sim, owned, false):
		return
	if int(cfg["relays"]) >= 1:
		_feed_relay_slot(sim, owned, vats, 5.0)


func _slot_kind(sim: Sim, n: Dictionary) -> String:
	## What goes in an empty relay slot: the forge (one per seat, once it holds three vats), else a cannon.
	if not sim.has_forge(seat) and "forge" in n["buildable"] \
			and _mine(sim).filter(func(x): return Sim.has_vat(x)).size() >= 3:
		return "forge"
	return "cannon" if "cannon" in n["buildable"] else ""


func _slot_value(sim: Sim, n: Dictionary, kind: String) -> float:
	## How much a structure on this relay slot is worth. Level 0: any slot alike. Level 1+: the forge
	## 10; a cannon 1 (it still guards the node), +5 on the border, + rival traffic over its decks
	## (0.18.7: "a cannon on a relay node guarding a busy deck"). Only slots worth 5+ get fed.
	if int(cfg["relays"]) <= 0 or kind == "forge":
		return 10.0
	var v := 1.0 + minf(10.0, _deck_traffic(sim, n) / Rules.SCALE * 0.5)
	for link in sim.adj[n["id"]]:
		var o: String = sim.nodes[link[0]]["owner"]
		if o != "" and not sim.allied(o, seat):
			v += 5.0
			break
	return v


func _build_relay_slot(sim: Sim, owned: Array, busy_only: bool) -> bool:
	## Build on an empty relay slot it can pay for (Same costs as the player; the slot costs no vat),
	## keeping the relay's garrison. busy_only: only a slot worth 8+ (a busy front relay).
	var best := {}
	var best_v := 0.0
	for n in owned:
		if n["build_kind"] != "" or n["attachment"] != "" or n["relay"] == "" \
				or _incoming(sim, n["id"], true) > 0.0 or _drops_soon(sim, n["id"]):
			continue                                      # only empty relay slots: never give up a vat
		var kind := _slot_kind(sim, n)
		if kind == "":
			continue
		var keep: float = Rules.AI_RELAY_HOLD if int(cfg["relays"]) >= 1 else 10.0
		if kind == "forge" and n["units"] < Rules.FORGE_COST + keep and int(cfg["relays"]) <= 0 and "cannon" in n["buildable"]:
			kind = "cannon"                               # level 0: whatever it can pay for now
		var cost: float = Rules.FORGE_COST if kind == "forge" else Rules.CANNON_COST[1]
		var v := _slot_value(sim, n, kind)
		if kind == "cannon" and v >= 5.0:
			keep = 10.0                                   # a front cannon guards its own relay
		if n["units"] < cost + keep or v <= 0.0 or (busy_only and v < 8.0):
			continue
		if v > best_v:
			best_v = v
			best = {"node": n, "kind": kind}
	if best.is_empty() or not sim.build_attachment(best["node"]["id"], best["kind"]):
		return false
	_fed.erase(best["node"]["id"])
	_invest_after = sim.time + float(cfg["invest"])
	return true


func _feed_relay_slot(sim: Sim, owned: Array, vats: Array, worth: float) -> void:
	## Level 1+: a relay never grows, so a player sends it the price of its structure first. One relay
	## at a time: the best-valued empty slot worth `worth`+, fed from the nearest vat that can spare it.
	for id in _fed.keys():
		if float(_fed[id]) > _clock and sim.nodes[id]["owner"] == seat and sim.nodes[id]["attachment"] == "":
			return                                        # still on its way
	var best := {}
	var best_v := 0.0
	for n in owned:
		if n["build_kind"] != "" or n["attachment"] != "" or n["relay"] == "" \
				or _incoming(sim, n["id"], true) > 0.0 or _drops_soon(sim, n["id"]):
			continue
		var kind := _slot_kind(sim, n)
		var v := _slot_value(sim, n, kind) if kind != "" else 0.0
		if v >= worth and v > best_v:
			best_v = v
			best = {"node": n, "kind": kind}
	if best.is_empty():
		return
	var slot: Dictionary = best["node"]
	var cost: float = Rules.FORGE_COST if best["kind"] == "forge" else Rules.CANNON_COST[1]
	var need: float = cost + Rules.AI_RELAY_HOLD + 2.0 * Rules.SCALE - slot["units"] - _incoming(sim, slot["id"], false)
	if need <= 0.0:
		return
	var pick := {}
	var pick_t := INF
	for d in vats:
		if _busy.has(d["id"]) or d["build_kind"] != "" or _incoming(sim, d["id"], true) > 0.0:
			continue
		if d["units"] - _reserve(sim, d) - 4.0 * Rules.SCALE < need:
			continue
		var route := _route(sim, d["id"], slot["id"], need)
		if route.is_empty() or _route_risky:
			continue
		var t := _travel(sim, route)
		if t < pick_t:
			pick_t = t
			pick = d
	if pick.is_empty():
		return
	var frac := clampf(need * 1.1 / maxf(pick["units"], 1.0), 0.05, 1.0)
	if not _send(sim, pick["id"], slot["id"], frac).is_empty():
		_busy[pick["id"]] = true
		_fed[slot["id"]] = _clock + pick_t + 12.0


# ------------------------------------------------------------------ skills (0.18.7)
# One cheap heuristic per skill; `_pick` returns [target] or [] (nothing worth it now). The ultimate is
# looked at first, then the active and the map skill; one cast per think, then Rules.AI_SKILL_GAP.
func _skills(sim: Sim) -> void:
	if not sim.abilities_on or sim.over:
		return
	if sim.skill_id(seat, "ultimate") == "rewire" and sim.rewire_left(seat) > 0:
		_rewire_fires(sim)                            # Rewire running: its relay fires are free
	if sim.time < _skill_after:
		return
	for slot in ["ultimate", "active", "map"]:
		var id := sim.skill_id(seat, slot)
		if id == "" or (slot == "ultimate" and (sim.charge(seat) < 1.0 or sim.rewire_left(seat) > 0)) \
				or (slot != "ultimate" and sim.cooldown(seat, slot) > 0.0):
			continue
		var pick := _pick(sim, id)
		if pick.is_empty():
			continue
		if sim.cast(seat, slot, pick[0]):
			casts += 1
			_skill_after = sim.time + float(Rules.AI_SKILL_GAP.get(level, 9.0))
			return


func _hostile(sim: Sim, owner: String) -> bool:
	return owner != "" and not sim.allied(owner, seat)


func _my_lines(sim: Sim) -> Array:
	return sim.hordes.filter(func(h): return h["owner"] == seat and not h.get("decoy", false) and h["state"] != "absorb" \
			and not h.get("retreat", false))


func _threat(sim: Sim, n: Dictionary) -> float:
	var threat := _incoming(sim, n["id"], true)
	for k in n["siege"]:
		if not sim.allied(k, seat):
			threat += n["siege"][k]
	return threat


func _deck_units(sim: Sim, ei: int) -> Array:
	## [hostile units, own or allied units] on deck ei now.
	var hostile := 0.0
	var own := 0.0
	for h in sim.hordes:
		var len := Sim.chain_length(h)
		for sp in h["spans"]:
			if sp["edge"] != ei:
				continue
			var on: float = maxf(0.0, minf(h["s"], sp["s1"]) - maxf(h["s"] - len, sp["s0"]))
			if on > 0.0:
				var u: float = h["units"] * clampf(on / maxf(len, 0.001), 0.0, 1.0)
				if sim.allied(h["owner"], seat):
					own += u
				else:
					hostile += u
	return [hostile, own]


func _own_route_uses(sim: Sim, ei: int) -> bool:
	## Will one of its own (or allied) lines still cross deck ei?
	for h in sim.hordes:
		if not sim.allied(h["owner"], seat):
			continue
		for sp in h["spans"]:
			if sp["edge"] == ei and sp["s1"] > h["s"] - Sim.chain_length(h):
				return true
	return false


func _pick(sim: Sim, id: String) -> Array:
	match id:
		"surge":                                      # the biggest line still well short of its target
			var best := {}
			for h in _my_lines(sim):
				if h["units"] >= 10.0 * Rules.SCALE and float(h["L"]) - float(h["s"]) > 15.0 \
						and (best.is_empty() or h["units"] > best["units"]):
					best = h
			return [best["id"]] if not best.is_empty() else []
		"spore_burst":                                # the most productive vat that has room to fill
			var best := {}
			for n in _mine(sim):
				if Sim.has_vat(n) and n["units"] < Rules.CAPS[n["tier"]] * 0.6 and not sim.is_disrupted(n["id"]) \
						and (best.is_empty() or n["tier"] > best["tier"]):
					best = n
			return [best["id"]] if not best.is_empty() else []
		"fortify":                                    # a node under heavy attack
			var best := {}
			var best_t := 0.0
			for n in _mine(sim):
				var t := _threat(sim, n)
				if t >= 10.0 * Rules.SCALE and t >= n["units"] * 0.5 and t > best_t and sim.garrison_div(n) <= 1.0:
					best = n
					best_t = t
			return [best["id"]] if not best.is_empty() else []
		"relay_aegis":                                # the same, preferring a node with own neighbours
			var best := {}
			var best_s := 0.0
			for n in _mine(sim):
				var t := _threat(sim, n)
				if t < 12.0 * Rules.SCALE or t < n["units"] * 0.6 or sim.garrison_div(n) > 1.0:
					continue
				var s: float = t
				for link in sim.adj[n["id"]]:
					if sim.nodes[link[0]]["owner"] == seat:
						s += 5.0 * Rules.SCALE
				if s > best_s:
					best = n
					best_s = s
			return [best["id"]] if not best.is_empty() else []
		"scorch":                                     # the deck with the most enemy bodies on it
			var best := -1
			var best_u := 8.0 * Rules.SCALE
			var seen := {}
			for h in sim.hordes:
				if not _hostile(sim, h["owner"]):
					continue
				for sp in h["spans"]:
					if seen.has(sp["edge"]):
						continue
					seen[sp["edge"]] = true
					var u: float = _deck_units(sim, sp["edge"])[0]
					if u > best_u:
						best_u = u
						best = sp["edge"]
			return [best] if best >= 0 else []
		"mire":                                       # the deck under the biggest line coming for its nodes
			var best := {}
			for h in sim.hordes:
				if not _hostile(sim, h["owner"]) or not sim.allied(sim.nodes[h["target"]]["owner"], seat) \
						or h["units"] < 8.0 * Rules.SCALE or h["state"] != "move":
					continue
				if best.is_empty() or h["units"] > best["units"]:
					best = h
			if best.is_empty():
				return []
			var sp := sim._current_span(best)
			return [sp["edge"]] if not sp.is_empty() else []
		"demolish":                                   # a fixed deck an enemy line will reach in 3-8 s
			for h in sim.hordes:
				if not _hostile(sim, h["owner"]) or h["units"] < 10.0 * Rules.SCALE or h["state"] != "move":
					continue
				var v: float = Rules.move_speed() * sim.stat(h["owner"], "speed")
				for sp in h["spans"]:
					var e: Dictionary = sim.edges[sp["edge"]]
					if e["plaza"] or e["state"] != "" or e["retracts"] or sp["s0"] <= h["s"]:
						continue
					var eta: float = (sp["s0"] - h["s"]) / maxf(v, 0.1)
					if eta >= Rules.SKILLS["demolish"]["warn"] and eta <= 8.0 and not _own_route_uses(sim, sp["edge"]) \
							and sim.can_cast(seat, "map", sp["edge"]):
						return [sp["edge"]]
			return []
		"anchor":                                     # save its own line from a Demolish, a relay or a cannon
			for e in sim.effects:
				if e["id"] == "demolish" and e.get("phase", "") == "warning" and not sim.allied(e["seat"], seat) \
						and _own_route_uses(sim, e["target"]):
					return [e["target"]]
			for n in sim.nodes:
				if n["relay"] == "" or n["relay_phase"] != "warning" or not _hostile(sim, n["owner"]):
					continue
				for ei in sim.controlled_edges(n["id"]):
					if sim._edge_open(ei) and not sim._edge_open_at(ei, n["relay_pending"]) \
							and _deck_units(sim, ei)[1] >= 5.0 * Rules.SCALE and sim.can_cast(seat, "map", ei):
						return [ei]
			for h in _my_lines(sim):
				if h["units"] < 15.0 * Rules.SCALE:
					continue
				var sp := sim._current_span(h)
				if sp.is_empty():
					continue
				for n in sim.nodes:
					if n["attachment"] == "cannon" and _hostile(sim, n["owner"]) \
							and (Sim.sample(h, h["s"])[0] as Vector3).distance_to(n["pos"]) <= Rules.CANNON_RANGE:
						return [sp["edge"]]
			return []
		"bypass":                                     # a relay about to drop or fling its own lines
			for n in sim.nodes:
				if n["relay"] == "" or n["relay_phase"] != "warning":
					continue
				var own := 0.0
				for ei in sim.controlled_edges(n["id"]):
					if sim._edge_open(ei) and not sim._edge_open_at(ei, n["relay_pending"]):
						own += _deck_units(sim, ei)[1]
				if own >= 5.0 * Rules.SCALE and sim.can_cast(seat, "map", n["id"]):
					return [n["id"]]
			return []
		"relay_hack":                                 # fire an enemy relay for the kill, or jam one that threatens it
			for n in sim.nodes:
				if n["relay"] == "" or (n["owner"] != "" and sim.allied(n["owner"], seat)):
					continue
				var closing := _closing(sim, n)
				if closing.is_empty():
					continue
				var toll: Array = _fling_toll(sim, closing, Rules.RELAY_WARNING) if n["relay"] == "rotation" \
						else _on_decks(sim, closing, Rules.RELAY_WARNING)
				if toll[0] >= 6.0 * Rules.SCALE and toll[1] <= 0.5 and sim.can_cast(seat, "map", n["id"]):
					return [n["id"]]
				if _hostile(sim, n["owner"]) and toll[1] >= 8.0 * Rules.SCALE and sim.can_cast(seat, "map", [n["id"], "jam"]):
					return [[n["id"], "jam"]]
			return []
		"ghost_line":                                 # a bluff at an armed enemy node (it draws the fire)
			if sim.time < float(cfg["grace"]):
				return []
			var src := {}
			for n in _mine(sim):
				if n["units"] >= 12.0 * Rules.SCALE and not _drops_soon(sim, n["id"]) and (src.is_empty() or n["units"] > src["units"]):
					src = n
			if src.is_empty():
				return []
			var best := -1
			var best_s := -INF
			for n in sim.nodes:
				if not _hostile(sim, n["owner"]) or sim.collapsed.get(n["id"], false):
					continue
				var s: float = -(n["pos"] as Vector3).distance_to(src["pos"]) + (40.0 if n["attachment"] == "cannon" else 0.0)
				if s > best_s and sim.can_cast(seat, "active", [src["id"], n["id"]]):
					best_s = s
					best = n["id"]
			return [[src["id"], best]] if best >= 0 else []
		"echo_split":                                 # several of its lines on the move
			var lines := _my_lines(sim).filter(func(h): return _hostile(sim, sim.nodes[h["target"]]["owner"]) or sim.nodes[h["target"]]["owner"] == "")
			var total := 0.0
			for h in lines:
				total += h["units"]
			return [null] if lines.size() >= 2 or total >= 25.0 * Rules.SCALE else []
		"superbloom":                                 # several vats well below their cap
			var low := 0
			for n in _mine(sim):
				if Sim.has_vat(n) and n["units"] < Rules.CAPS[n["tier"]] * 0.5:
					low += 1
			return [null] if low >= 3 or (low >= 2 and Rules.SUPERBLOOM_MODE == "under_attack") else []
		"rewire":                                     # a relay kill is on, or a big push is under way
			var kill := 0.0
			for n in sim.nodes:
				if n["relay"] != "" and n["relay_phase"] == "" and n["relay_cd"] <= 0.0:
					var closing := _closing(sim, n)
					if not closing.is_empty():
						var toll: Array = _fling_toll(sim, closing, Rules.RELAY_WARNING)
						if toll[1] <= 0.5:
							kill += toll[0]
			var push := 0.0
			for h in _my_lines(sim):
				push += h["units"]
			return [null] if kill >= 8.0 * Rules.SCALE or push >= 30.0 * Rules.SCALE else []
		"core_meltdown":                              # an arriving line the meltdown turns into a capture
			var sk: Dictionary = Rules.SKILLS["core_meltdown"]
			for h in _my_lines(sim) + sim.hordes.filter(func(x): return x["owner"] == seat and x["state"] == "absorb" and not x.get("decoy", false)):
				if not sim.can_cast(seat, "ultimate", h["id"]):
					continue
				var n: Dictionary = sim.nodes[h["target"]]
				var g := _estimate(sim, n) if n["owner"] != "" else float(n["units"])
				var sac: float = minf(h["units"], maxf(h["units"] * float(sk["share"]), float(sk["min_shown"]) * Rules.SCALE))
				var kills: float = minf(sac * float(sk["kills_per"]), float(sk["cap_shown"]) * Rules.SCALE)
				if kills >= g or (h["units"] - sac > (g - kills) * 1.05 and h["units"] < g * 1.3):
					return [h["id"]]
			return []
	return []


func _rewire_fires(sim: Sim) -> void:
	## While Rewire runs: fire any relay (enemy ones too) that drops or flings more enemy than own.
	for n in sim.nodes:
		if n["relay"] == "" or not sim.can_cast(seat, "ultimate", n["id"]):
			continue
		var closing := _closing(sim, n)
		if closing.is_empty():
			continue
		var toll: Array = _fling_toll(sim, closing, Rules.RELAY_WARNING) if n["relay"] == "rotation" \
				else _on_decks(sim, closing, Rules.RELAY_WARNING)
		if toll[0] >= 4.0 * Rules.SCALE and toll[1] <= 0.5 and sim.cast(seat, "ultimate", n["id"]):
			casts += 1
			return
