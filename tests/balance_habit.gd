extends SeatAI
## Balance study opponents (tests/balance_study.gd, 2026-10-27; not used by the game): the stock SeatAI with ONE thing removed,
## so a win-rate gap against stock measures what that thing is worth to a strong AI.
##   stock      SeatAI exactly
##   noskills   never casts (no active, map or ultimate)
##   nomg       never builds a Machinegoon
##   noslot     never builds on a relay slot (no laser / forge / monster hub)
##   nomonster  never launches a monster (its hub may still be built)

##   mgeager    (bal-02321 re-check, ported to googatling 2026-11-06) a Machinegoon / Googatling on EVERY frontline vat,
##              highest tier first: no 4-vat minimum, no 1-per-3 cap

var habit := "stock"


func _init(s: String, lvl: String, h: String, seed_value: int) -> void:
	super(s, 2.5, lvl)
	habit = h
	cfg = cfg.duplicate()
	rng.seed = hash(s + lvl + str(seed_value))
	_t = rng.randf() * period


func _skills(sim: Sim) -> void:
	if habit == "noskills":
		return
	super(sim)


func _build_machinegoon(sim: Sim, owned: Array, vats: Array) -> bool:
	if habit == "nomg":
		return false
	if habit == "mgeager":
		var best := {}
		for n in vats:
			if n["id"] == sim.homes.get(seat, -1) or n["build_kind"] != "" or _drops_soon(sim, n["id"]) 					or sim.can_build(n["id"], seat, "machinegoon") != "" or n["node_kind"] != "common":
				continue
			var front := false
			for link in sim.adj[n["id"]]:
				if _hostile(sim, sim.nodes[link[0]]["owner"]):
					front = true
					break
			if not front or n["units"] < sim.build_cost(n, "machinegoon") + _reserve(sim, n):
				continue
			if best.is_empty() or n["tier"] > best["tier"]:
				best = n
		if best.is_empty() or not _order(sim.build(best["id"], seat, "machinegoon")):
			return false
		_invest_after = sim.time + float(cfg["invest"])
		return true
	return super(sim, owned, vats)


func _slot_kind(sim: Sim, n: Dictionary) -> String:
	if habit == "noslot":
		return ""
	return super(sim, n)


func _monsters(sim: Sim) -> void:
	if habit == "nomonster":
		return
	super(sim)
