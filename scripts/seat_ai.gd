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
