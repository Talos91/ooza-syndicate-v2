extends SeatAI
## Balance probe opponents (tests/balance_probe.gd, 0.18.7 balance study - not used by the game): the
## stock SeatAI with one investment habit forced. "stock" is SeatAI exactly. The others change only what
## it builds (and, for "expand", the gap between offensives) - relays, defence, targets, estimates and
## SeatAI's own _build stay in charge wherever the habit allows, so a win-rate gap measures the habit.
##   tech       first `opening` s: upgrades a vat every think (no invest gap, no 60 %-of-cap gate), best vat first
##   expand     first `opening` s: never invests, attacks every think (neutrals first by SeatAI's score)
##   cannon     all match: a cannon on a free slot the moment it can pay, before anything else, then T2
##   forge      all match: a forge on a free slot the moment it can pay, before anything else (no 3-vat rule)
##   noupgrade  never upgrades a vat          nocannon  never builds a cannon
##   noforge    never builds a forge          noattach  never builds a cannon or a forge
## fair = true (--fair=1): the garrison estimate also counts the defender's attack (forge, faction) and
## garrison stat and its own health - what a BRAWL attack really costs (OPEN-QUESTIONS 13: SeatAI
## under-sends against forge owners and tough factions). Off = SeatAI's estimate.

var strategy := "stock"
var opening := 75.0
var fair := false
var _in_build := false


func _init(s: String, lvl: String, strat: String, seed_value: int) -> void:
	super(s, 2.5, lvl)
	strategy = strat
	cfg = cfg.duplicate()                         # Rules.AI_LEVELS is shared: never write into it
	rng.seed = hash(s + lvl + str(seed_value))    # a different game every seed (SeatAI seeds by seat only)
	_t = rng.randf() * period


func think(sim: Sim, dt: float) -> void:
	if strategy == "expand" and sim.time < opening:
		_attack_after = minf(_attack_after, sim.time)   # an offensive every think in the opening
	super(sim, dt)


func _build(sim: Sim) -> void:
	var early: bool = sim.time < opening
	match strategy:
		"tech":
			if early:
				_greedy_upgrade(sim)
				return
		"expand":
			if early:
				return
		"cannon", "forge":
			if _slot_first(sim, strategy):
				return
	_in_build = true
	super(sim)
	_in_build = false


func _drops_soon(sim: Sim, node_id: int) -> bool:
	## "noupgrade": SeatAI._build skips vats it thinks are about to fall - the one hook into its vat loop
	## (only while it builds; its cannon and relay-slot loops never look at vat nodes).
	if _in_build and strategy == "noupgrade" and sim.nodes[node_id]["owner"] == seat and Sim.has_vat(sim.nodes[node_id]):
		return true
	return super(sim, node_id)


func _slot_kind(sim: Sim, n: Dictionary) -> String:
	## What SeatAI puts in (or feeds) an empty relay slot, minus the kinds this habit never builds.
	var kind: String = super(sim, n)
	if strategy == "forge" and "forge" in n["buildable"] and not sim.has_forge(seat):
		return "forge"                                # no 3-vat rule
	if strategy == "cannon" and "cannon" in n["buildable"]:
		return "cannon"
	var no_cannon: bool = strategy in ["nocannon", "noattach"]
	var no_forge: bool = strategy in ["noforge", "noattach"]
	if kind == "forge" and no_forge:
		kind = "cannon" if "cannon" in n["buildable"] and not no_cannon else ""
	if kind == "cannon" and no_cannon:
		kind = ""
	return kind


func _estimate(sim: Sim, n: Dictionary) -> float:
	var u: float = super(sim, n)
	if not fair:
		return u
	# BRAWL land(): each defender costs attack(defender) x health x garrison / (attack x health) attackers;
	# SeatAI already counts the defender's health and its own attack
	var owner: String = n["owner"]
	return u * (sim.attack_of(owner) if owner != "" else 1.0) * sim.stat(owner, "garrison") / sim.stat(seat, "health")


func _greedy_upgrade(sim: Sim) -> void:
	var vats := _mine(sim).filter(func(n): return Sim.has_vat(n))
	vats.sort_custom(func(a, b): return a["tier"] > b["tier"] if a["tier"] != b["tier"] else a["units"] > b["units"])
	for n in vats:
		if n["build_kind"] != "" or n["tier"] >= 4 or _incoming(sim, n["id"], true) > 0.0:
			continue
		if n["units"] >= Sim.vat_cost(n) + 2.0 * Rules.SCALE and sim.upgrade_vat(n["id"]):
			_invest_after = sim.time + float(cfg["invest"])
			return


func _slot_first(sim: Sim, kind: String) -> bool:
	## The attachment first: build it on a free slot the moment it can pay; a cannon then climbs to
	## T2. True when it spent this think.
	for n in _mine(sim):
		if n["build_kind"] != "" or _incoming(sim, n["id"], true) > 0.0:
			continue
		if kind == "cannon" and n["attachment"] == "cannon" and n["cannon_tier"] < 2:
			if n["units"] >= Rules.CANNON_COST[n["cannon_tier"] + 1] + 10.0 and sim.upgrade_structure(n["id"]):
				return true
		if n["attachment"] == "" and n["relay"] != "" and kind in n["buildable"]:
			if kind == "forge" and sim.has_forge(seat):
				continue
			var cost: int = Rules.CANNON_COST[1] if kind == "cannon" else Rules.FORGE_COST
			if n["units"] >= cost + 10.0 and sim.build_attachment(n["id"], kind):
				_invest_after = sim.time + float(cfg["invest"])
				return true
	return false                                       # nothing to pay yet: SeatAI's _build (it feeds the slot)
