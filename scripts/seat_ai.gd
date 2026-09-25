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
## moves (RELAY_WARNING later); level 3 also opens a shorter route to where it wants to go.

var seat: String
var level := "Standard"
var cfg: Dictionary
var period := 2.5
var _t := 0.0
var _clock := 0.0
var _attack_after := 0.0
var _invest_after := 0.0
var _memory := {}                          # node id -> {"units", "next"}
var rng := RandomNumberGenerator.new()


func _init(s: String, think_every := 2.5, lvl := "") -> void:
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
	if int(cfg["relays"]) > 0:
		_relays(sim)
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
	return nearby + (4.0 * Rules.SCALE if n["id"] == sim.homes.get(seat, -1) else 0.0)


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
				sim.send(doomed["id"], target, 1.0)


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
		var threat := _incoming(sim, target["id"], true)
		for k in target["siege"]:
			if not sim.allied(k, seat):
				threat += target["siege"][k]
		if threat <= 0.0:
			continue
		var need: float = threat * 1.1 + 4.0 * Rules.SCALE - target["units"] - _incoming(sim, target["id"], false)
		if need <= 0.0:
			continue
		var donors := _mine(sim).filter(func(n): return n["id"] != target["id"] and n["build_kind"] == "")
		donors.sort_custom(func(a, b): return (a["pos"] as Vector3).distance_to(target["pos"]) < (b["pos"] as Vector3).distance_to(target["pos"]))
		for donor in donors:
			if need <= 0.0:
				break
			var spare: float = donor["units"] - _reserve(sim, donor)
			if spare < 2.0 * Rules.SCALE or sim.find_route(donor["id"], target["id"]).is_empty():
				continue
			var frac := clampf(minf(need, spare) / maxf(donor["units"], 1.0), 0.1, 1.0)
			if not sim.send(donor["id"], target["id"], frac).is_empty():
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
			if donor["build_kind"] != "":
				continue
			var available: float = donor["units"] - _reserve(sim, donor)
			if available < 4.0 * Rules.SCALE:
				continue
			var route := sim.find_route(donor["id"], target["id"])
			if route.is_empty():
				continue
			donors.append({"node": donor, "available": available, "travel": _travel(sim, route)})
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
		score += _rival_adjustment(sim, target)
		if sim.last_stand_active and sim.is_final(target["id"]):
			score += 20.0                                 # the last ring is where the match is decided
		plans.append({"target": target, "donors": donors, "needed": needed, "score": score})
	if plans.is_empty():
		return
	plans.sort_custom(func(a, b): return a["score"] > b["score"])
	var plan: Dictionary = plans[rng.randi_range(0, mini(plans.size(), int(cfg["choice"])) - 1)]
	if int(cfg["relays"]) >= 3 and _open_route(sim, plan):
		return                                            # a shorter way opens first; send next time
	_attack_after = sim.time + float(cfg["attack_gap"])
	var need: float = plan["needed"]
	for d in plan["donors"]:
		var avail: float = d["available"]
		var portion := 0.5 if need <= avail * 0.5 else (0.75 if need <= avail * 0.75 else 1.0)
		var frac := clampf(avail * portion / maxf(d["node"]["units"], 1.0), 0.1, 1.0)
		if not sim.send(d["node"]["id"], plan["target"]["id"], frac).is_empty():
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


func _relays(sim: Sim) -> void:
	var lvl := int(cfg["relays"])
	for n in sim.nodes:
		if n["owner"] != seat or n["relay"] == "" or n["relay_cd"] > 0.0 or n["relay_phase"] != "":
			continue
		var closing := _closing(sim, n)
		if closing.is_empty():
			continue
		var now := _on_decks(sim, closing, 0.0)
		var later := _on_decks(sim, closing, Rules.RELAY_WARNING + Rules.RELAY_MOVE * 0.5) if lvl >= 2 else now
		var enemy: float = maxf(now[0], later[0]) if lvl >= 2 else now[0]
		var own: float = maxf(now[1], later[1])
		if enemy < 2.0 * Rules.SCALE or own > 0.5:        # never drop its own (or allied) lines
			continue
		if n["relay"] == "retract" and n["units"] < enemy * 1.3:
			continue                                      # it would pull in more than the garrison holds
		sim.fire_relay(n["id"])


func _open_route(sim: Sim, plan: Dictionary) -> bool:
	## Level 3: fire one of its relays if the next state gives the plan a faster route.
	var src: int = plan["donors"][0]["node"]["id"]
	var dst: int = plan["target"]["id"]
	var base := sim.find_route(src, dst)
	var t0 := _travel(sim, base) if not base.is_empty() else INF
	for n in sim.nodes:
		if n["owner"] != seat or n["relay"] == "" or n["relay_cd"] > 0.0 or n["relay_phase"] != "":
			continue
		var closing := _closing(sim, n)
		if _on_decks(sim, closing, Rules.RELAY_WARNING)[1] > 0.5:
			continue
		var keep: int = n["relay_index"]
		n["relay_index"] = sim.relay_next_index(n)
		var alt := sim.find_route(src, dst)
		n["relay_index"] = keep
		if not alt.is_empty() and _travel(sim, alt) < t0 - 3.0:
			sim.fire_relay(n["id"])
			return true
	return false


func _retreats(sim: Sim) -> void:
	## SIEGE: recall a line being shoved back and badly outnumbered (the player's mid-fight choice).
	for key in sim.fight_info:
		var ids: PackedStringArray = key.split(":")
		var a := sim._horde(int(ids[0]))
		var b := sim._horde(int(ids[1]))
		if a.is_empty() or b.is_empty():
			continue
		var mine := a if a["owner"] == seat else (b if b["owner"] == seat else {})
		if mine.is_empty():
			continue
		var theirs := b if mine == a else a
		if sim.power_of(mine) < 0.4 * sim.power_of(theirs) and mine["units"] > 15.0:
			sim.recall(mine["id"])
			return


# ------------------------------------------------------------------ investment
func _build(sim: Sim) -> void:
	## Same costs and slots as the player. One investment per `invest` seconds, never on a node
	## under attack: upgrades, a forge once it has three vats, cannons on free relay slots.
	if sim.time < _invest_after:
		return
	var owned := _mine(sim)
	for n in owned:
		if n["build_kind"] != "" or _incoming(sim, n["id"], true) > 0.0:
			continue
		var reserve := _reserve(sim, n) + 4.0 * Rules.SCALE
		if n["attachment"] == "cannon" and n["cannon_tier"] < 3 \
				and n["units"] >= Rules.CANNON_COST[n["cannon_tier"] + 1] + reserve and sim.upgrade_structure(n["id"]):
			_invest_after = sim.time + float(cfg["invest"])
			return
	var vats := owned.filter(func(n): return Sim.has_vat(n))
	vats.sort_custom(func(a, b): return a["tier"] < b["tier"] if a["tier"] != b["tier"] else a["units"] > b["units"])
	for n in vats:
		if n["build_kind"] != "" or n["tier"] >= 4 or _incoming(sim, n["id"], true) > 0.0:
			continue
		if n["units"] >= Sim.vat_cost(n) + _reserve(sim, n) + 4.0 * Rules.SCALE and n["units"] >= Rules.CAPS[n["tier"]] * 0.6 \
				and sim.upgrade_vat(n["id"]):
			_invest_after = sim.time + float(cfg["invest"])
			return
	var has_forge := sim.has_forge(seat)
	for n in owned:
		if n["build_kind"] != "" or n["attachment"] != "" or n["relay"] == "":
			continue                                      # only empty relay slots: never give up a vat
		if not has_forge and vats.size() >= 3 and "forge" in n["buildable"] and n["units"] >= Rules.FORGE_COST + 10.0:
			sim.build_attachment(n["id"], "forge")
			_invest_after = sim.time + float(cfg["invest"])
			return
		if "cannon" in n["buildable"] and n["units"] >= Rules.CANNON_COST[1] + 10.0:
			sim.build_attachment(n["id"], "cannon")
			_invest_after = sim.time + float(cfg["invest"])
			return
