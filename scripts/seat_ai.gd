class_name SeatAI
extends RefCounted
## Simple opponent: every few seconds, from its strongest node, attack the cheapest node it can
## take with a 75% send, counting units it already has en route. No economy or combat cheats.
## Hazard-aware tiers (GAME-RULES §13) come with the relay maps.

var seat: String
var period := 2.5
var _t := 0.0


func _init(s: String, think_every := 2.5) -> void:
	seat = s
	period = think_every


func think(sim: Sim, dt: float) -> void:
	_t += dt
	if _t < period or sim.over:
		return
	_t = 0.0
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
			if n["owner"] == seat:
				continue
			var route := sim.find_route(src["id"], n["id"])
			if route.is_empty():
				continue
			var need: float = n["units"] * 1.15 + 8.0 - en_route.get(n["id"], 0.0)
			var score: float = need + route.size() * 6.0
			if floorf(src["units"] * 0.75) > need and score < best_score:
				best = n["id"]
				best_score = score
		if best >= 0:
			sim.send(src["id"], best, 0.75)
			return


func _build(sim: Sim) -> void:
	## Structure parity for AI vs AI (no economy/combat cheats): opportunistically upgrade a
	## flush home vat, and build one forge (a standing combat bonus) then cannons at any other
	## node that offers them and doesn't have one yet.
	for n in sim.nodes:
		if n["owner"] != seat or n["build_kind"] != "":
			continue
		if n["units"] >= Rules.CAPS[n["tier"]] * 0.9 and sim.upgrade_vat(n["id"]):
			return
	var has_forge := false
	for n in sim.nodes:
		if n["owner"] == seat and n["attachment"] == "forge":
			has_forge = true
	for n in sim.nodes:
		if n["owner"] != seat or n["build_kind"] != "" or n["attachment"] != "":
			continue
		if not has_forge and "forge" in n["buildable"]:
			sim.build_attachment(n["id"], "forge")
			return
		if "cannon" in n["buildable"]:
			sim.build_attachment(n["id"], "cannon")
			return
