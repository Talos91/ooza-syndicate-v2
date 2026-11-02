extends SeatAI
## Balance study opponents (tests/balance_study.gd, 2026-10-27; not used by the game): the stock SeatAI with ONE thing removed,
## so a win-rate gap against stock measures what that thing is worth to a strong AI.
##   stock      SeatAI exactly
##   noskills   never casts (no active, map or ultimate)
##   nomg       never builds a Machinegoon
##   noslot     never builds on a relay slot (no laser / forge / monster hub)
##   nomonster  never launches a monster (its hub may still be built)
##   noult      never casts its ultimate (active and map skills as stock; 2026-10-27 ultimates rework)
##   noactive   never casts its active skill; nomap: never casts its map skill (bal-audit 2026-11-02: per-skill lift)
##   mgfront    builds its Machinegoon on any frontline vat, not only one that keeps taking small raids (bal-audit)
##   mgeager    (bal-02321 re-check) a Machinegoon on EVERY frontline vat, highest tier first: no 4-vat minimum, no 1-per-3 cap
##   mgall      (bal-02321 re-check) a Machinegoon on every vat but its home, frontline or not, highest tier first

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
	if habit in ["mgeager", "mgall"]:
		var best := {}
		for n in vats:
			if n["id"] == sim.homes.get(seat, -1) or n["build_kind"] != "" or _drops_soon(sim, n["id"]) 					or sim.can_build(n["id"], seat, "machinegoon") != "" or n["node_kind"] != "common":
				continue
			if habit == "mgeager":
				var front := false
				for link in sim.adj[n["id"]]:
					if _hostile(sim, sim.nodes[link[0]]["owner"]):
						front = true
						break
				if not front:
					continue
			if n["units"] < sim.build_cost(n, "machinegoon") + _reserve(sim, n):
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


func _pick(sim: Sim, id: String) -> Array:
	if habit == "noult" and id == sim.skill_id(seat, "ultimate"):
		return []
	if habit == "noactive" and id == sim.skill_id(seat, "active"):
		return []
	if habit == "nomap" and id == sim.skill_id(seat, "map"):
		return []
	return super(sim, id)


func _trickled(n: Dictionary) -> bool:
	if habit == "mgfront":
		return true
	return super(n)
