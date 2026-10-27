extends SeatAI
## Balance study opponents (tests/balance_study.gd, 2026-10-27; not used by the game): the stock SeatAI with ONE thing removed,
## so a win-rate gap against stock measures what that thing is worth to a strong AI.
##   stock      SeatAI exactly
##   noskills   never casts (no active, map or ultimate)
##   nomg       never builds a Machinegoon
##   noslot     never builds on a relay slot (no laser / forge / monster hub)
##   nomonster  never launches a monster (its hub may still be built)
##   noult      never casts its ultimate (active and map skills as stock; 2026-10-27 ultimates rework)

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
	return super(sim, id)
