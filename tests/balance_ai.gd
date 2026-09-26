extends SeatAI
## Balance probe opponents (tests/balance_probe.gd, 0.18.7 balance study - not used by the game): the
## stock SeatAI with one investment habit forced. "stock" is SeatAI exactly. The others change only
## _build (and, for "expand", the gap between offensives) - relays, defence, targets and estimates stay
## SeatAI's, so a win-rate gap measures the habit, not a different AI.
##   tech       first `opening` s: invests every think (no invest gap, no 60 %-of-cap gate), vats first
##   expand     first `opening` s: never invests, attacks every think (neutrals first by SeatAI's score)
##   cannon     all match: a cannon on every free slot it owns before anything else, then T2
##   forge      all match: a forge on its first free slot before anything else (no 3-vat rule)
##   noupgrade  never upgrades a vat          nocannon  never builds a cannon
##   noforge    never builds a forge          noattach  never builds a cannon or a forge
## fair = true (both seats, --fair=1): the garrison estimate also counts the defender's attack (forge,
## faction) and garrison stat and its own health - what a BRAWL attack really costs (OPEN-QUESTIONS 13:
## SeatAI under-sends against forge owners and tough factions). Off = SeatAI's estimate.

var strategy := "stock"
var opening := 75.0
var fair := false


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
		"stock":
			super(sim)
		"tech":
			if early:
				_invest(sim, {"greedy": true, "cannon": false, "forge": false})
			else:
				super(sim)
		"expand":
			if not early:
				super(sim)
		"cannon", "forge":
			if not _slot_first(sim, strategy):
				super(sim)
		"noupgrade":
			_invest(sim, {"vat": false})
		"nocannon":
			_invest(sim, {"cannon": false})
		"noforge":
			_invest(sim, {"forge": false})
		"noattach":
			_invest(sim, {"cannon": false, "forge": false})
		_:
			super(sim)


func _estimate(sim: Sim, n: Dictionary) -> float:
	var u: float = super(sim, n)
	if not fair:
		return u
	# BRAWL land(): each defender costs attack(defender) x health x garrison / (attack x health) attackers;
	# SeatAI already counts the defender's health and its own attack
	var owner: String = n["owner"]
	return u * (sim.attack_of(owner) if owner != "" else 1.0) * sim.stat(owner, "garrison") / sim.stat(seat, "health")


func _slot_first(sim: Sim, kind: String) -> bool:
	## The attachment first: build it on a free slot the moment it can pay; a cannon then climbs to
	## T2. True when it spent this think (or is saving for it and has a slot).
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
			if n["units"] >= cost + 10.0:
				return sim.build_attachment(n["id"], kind)
			return true                                # a slot to fill: save for it
	return false


func _invest(sim: Sim, allow: Dictionary) -> void:
	## SeatAI._build with switches: vat upgrades, cannons, forge each allowed or not; greedy = no gap
	## between investments and no 60 %-of-cap gate on upgrades.
	var greedy: bool = allow.get("greedy", false)
	if not greedy and sim.time < _invest_after:
		return
	var owned := _mine(sim)
	if allow.get("cannon", true):
		for n in owned:
			if n["build_kind"] != "" or _incoming(sim, n["id"], true) > 0.0 or _drops_soon(sim, n["id"]):
				continue
			var reserve := _reserve(sim, n) + 4.0 * Rules.SCALE
			if n["attachment"] == "cannon" and n["cannon_tier"] < 3 \
					and n["units"] >= Rules.CANNON_COST[n["cannon_tier"] + 1] + reserve and sim.upgrade_structure(n["id"]):
				_invest_after = sim.time + float(cfg["invest"])
				return
	var vats := owned.filter(func(n): return Sim.has_vat(n))
	if allow.get("vat", true):
		vats.sort_custom(func(a, b): return a["tier"] < b["tier"] if a["tier"] != b["tier"] else a["units"] > b["units"])
		if greedy:                                     # the best vat first: the home and the high tiers
			vats.sort_custom(func(a, b): return a["tier"] > b["tier"] if a["tier"] != b["tier"] else a["units"] > b["units"])
		for n in vats:
			if n["build_kind"] != "" or n["tier"] >= 4 or _incoming(sim, n["id"], true) > 0.0 or _drops_soon(sim, n["id"]):
				continue
			var gate: bool = greedy or n["units"] >= Rules.CAPS[n["tier"]] * 0.6
			var floor_units: float = Sim.vat_cost(n) + (2.0 * Rules.SCALE if greedy else _reserve(sim, n) + 4.0 * Rules.SCALE)
			if n["units"] >= floor_units and gate and sim.upgrade_vat(n["id"]):
				_invest_after = sim.time + float(cfg["invest"])
				return
	var has_forge := sim.has_forge(seat)
	for n in owned:
		if n["build_kind"] != "" or n["attachment"] != "" or n["relay"] == "" \
				or _incoming(sim, n["id"], true) > 0.0 or _drops_soon(sim, n["id"]):
			continue
		if allow.get("forge", true) and not has_forge and vats.size() >= 3 and "forge" in n["buildable"] \
				and n["units"] >= Rules.FORGE_COST + 10.0:
			sim.build_attachment(n["id"], "forge")
			_invest_after = sim.time + float(cfg["invest"])
			return
		if allow.get("cannon", true) and "cannon" in n["buildable"] and n["units"] >= Rules.CANNON_COST[1] + 10.0:
			sim.build_attachment(n["id"], "cannon")
			_invest_after = sim.time + float(cfg["invest"])
			return
