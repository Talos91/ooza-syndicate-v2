extends SceneTree
## BALANCE PROBE (0.18.7 balance study - Daniele: "another thing we should revisit is balancing and here i
## need your superior ai mind... vat power up cost, production speed etc we need to balance better").
## A tool, not one of the five suites. Headless AI-vs-AI on the maps4 pool, plus the economy model:
##   Godot --headless --path . --script res://tests/balance_probe.gd -- --study=<study> [options]
## Studies:
##   payback    the economy model from Rules (shown units): vat upgrade, neutral capture, cannon, forge
##   capture    measured cost of taking a neutral of each tier (real Sim, send sizes, forge, factions)
##   travel     measured hop times per deck tier and home-to-neutral / home-to-home times
##   baseline   stock SeatAI vs itself (NULL mirror): when and what it builds, captures, match length
##   factions   each faction vs NULL, both seats (mirror pairs cancel map bias), stock SeatAI
##   openings   each forced habit (tests/balance_ai.gd) vs stock SeatAI, both seats, NULL mirror
##   report     read the JSON lines written by the match studies (--in=file,file,...) and print tables
## Options: --level=Standard|Expert (both seats)   --seeds=N (per map and seat)
##   --preset=<Rules.BALANCE_PRESETS key>   --override=<JSON dict of Rules.BALANCE_KEYS>
##   --variants=a,b,c (factions / strategies)   --vs=<strategy> (openings: the opponent, default stock)
##   --fair=1 (both AIs estimate garrisons with the defender's attack and garrison stats, balance_ai.gd)
##   --maps=C-01,M-03 (codes; default: every BRAWL 1v1 map in MapPool, no tutorials / debug)
##   --shard=k/n   --out=<file.jsonl>   --dt=0.1   --tag=<label>
## BRAWL only (Daniele, 0.18.7: "brawl is our game" - SIEGE is deactivated). Skills / abilities play as the
## game's default (off); the relay rule in force at run time applies (it may move these numbers).
## The Rules overrides are applied before every match (Rules.apply_balance), so any proposal can be A/B
## tested the same way; --preset=b187 is the 0.18.7 proposal. Matches play with the Last Stand ON and the
## 7:00 hard end, 0.1 s steps (test_ai_curve's step), AI randomness seeded per game.

const BalanceAI := preload("res://tests/balance_ai.gd")

var args := {}
var preset := ""
var overrides := {}
var brawl := true
var level := "Standard"
var dt := 0.1
var _maps := {}                                   # path -> parsed map (duplicated per match)
var _captures: Array = []                          # this match's captures (signal)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	preset = str(args.get("preset", ""))
	if args.has("override"):
		var o = JSON.parse_string(str(args["override"]))
		if o is Dictionary:
			overrides = o
		else:
			push_error("--override is not a JSON dictionary")
			quit(2)
			return
	brawl = true                                 # SIEGE is deactivated (0.18.7): BRAWL only
	level = str(args.get("level", "Standard"))
	dt = float(args.get("dt", "0.1"))
	_apply()
	match str(args.get("study", "payback")):
		"payback":
			_payback()
		"capture":
			_capture_study()
		"travel":
			_travel_study()
		"baseline", "factions", "openings":
			_matches(str(args["study"]))
		"report":
			_report()
		_:
			print("unknown --study")
	Rules.apply_balance("")
	quit(0)


func _apply() -> void:
	Rules.apply_balance(preset, overrides)
	Rules.bridge_combat = not brawl
	Rules.last_stand = true
	Rules.abilities_on = false                   # the game default (skills off until their UI ships)


static func sh(units: float) -> float:
	return units / Rules.SCALE


# ------------------------------------------------------------------ the economy model (shown units)
func _payback() -> void:
	print("ECONOMY MODEL (shown units)  preset '%s'  overrides %s" % [preset, JSON.stringify(overrides)])
	print("\nVats: cap, production, time to fill from empty")
	for t in range(1, 5):
		print("  T%d  cap %3.0f  prod %.2f/s  fills in %4.1f s" % [t, sh(Rules.CAPS[t]), sh(Rules.PROD[t]), Rules.CAPS[t] / Rules.PROD[t]])
	print("\nVat upgrade payback: build %.0f s + cost / extra production (below cap; at the cap the cost is" % Rules.BUILD_SECONDS)
	print("units the vat could not store anyway: payback = the build time). 'refill' = cost / old production.")
	var facs := ["null", "bloom", "ember", "vex", "solar"]
	var head := "  upgrade   cost  +prod/s(null)  " + "  ".join(facs.map(func(f): return "%6s" % f)) + "   refill  +cap"
	print(head)
	for t in range(1, 4):
		var cost: float = sh(Rules.VAT_COST[t])
		var d: float = sh(Rules.PROD[t + 1] - Rules.PROD[t])
		var cells := []
		for f in facs:
			cells.append("%5.1fs" % (Rules.BUILD_SECONDS + cost / maxf(d * Rules.stat(f, "production"), 0.001)))
		print("  T%d->T%d  %5.0f   %6.2f         %s   %5.1fs  +%3.0f" % [t, t + 1, cost, d, "  ".join(cells), cost / sh(Rules.PROD[t]),
				sh(Rules.CAPS[t + 1] - Rules.CAPS[t])])
	var c2: float = sh(Rules.VAT_COST[2] + Rules.VAT_COST[3])
	var d2: float = sh(Rules.PROD[4] - Rules.PROD[2])
	print("  home T2->T4 back to back: cost %.0f, +%.2f/s once T4, repaid %.0f s after the second build ends" % [c2, d2,
			maxf(0.0, (c2 - sh(Rules.PROD[3] - Rules.PROD[2]) * Rules.BUILD_SECONDS) / d2)])
	var ls_line := "  latest start that repays before the Last Stand (%d:%02d), NULL:" % [int(Rules.LAST_STAND_TIME) / 60, int(Rules.LAST_STAND_TIME) % 60]
	for t in range(1, 4):
		var pb: float = Rules.BUILD_SECONDS + sh(Rules.VAT_COST[t]) / sh(Rules.PROD[t + 1] - Rules.PROD[t])
		ls_line += "  T%d->T%d by %d:%02d" % [t, t + 1, int(Rules.LAST_STAND_TIME - pb) / 60, int(Rules.LAST_STAND_TIME - pb) % 60]
	print(ls_line)
	print("\nNeutral capture vs upgrade: BRAWL cost = garrison (one-for-one at baseline, / attack); the prize is")
	print("a vat of the neutral's tier (+its cap). Payback = cost / its production (+ the hop, see --study=travel).")
	print("  tier  garrison  cost BRAWL  cost +forge  prod/s  payback  payback(bloom/ember)   cap")
	for t in range(1, 5):
		var g: float = sh(Rules.NEUTRAL_UNITS[t])
		var p: float = sh(Rules.PROD[t])
		print("   T%d    %4.0f      %4.1f        %4.1f      %.2f   %5.1fs     %5.1fs / %5.1fs      %3.0f" % [t, g, g / Rules.stat("null", "attack"), g / (1.0 + Rules.forge_bonus), p, g / p,
				g / (p * Rules.stat("bloom", "production")), g / (p * Rules.stat("ember", "production")), sh(Rules.CAPS[t])])
	print("  (measured with the real Sim: --study=capture)")
	print("\nCannon: burst %.0f s, range %.0f m; sustained = kill / (burst + recharge) while a line stays in range" % [Rules.CANNON_BURST, Rules.CANNON_RANGE])
	var total := 0.0
	for t in range(1, 4):
		var st: Dictionary = Rules.CANNON_STATS[t]
		total += sh(Rules.CANNON_COST[t])
		var sustained: float = sh(st["kill"]) / (Rules.CANNON_BURST + st["recharge"])
		print("  T%d  cost %3.0f (total %3.0f)  kill %3.0f/burst  recharge %.1f s  peak %4.1f/s  sustained %4.1f/s  kills per unit spent (1 burst) %.2f  bursts to repay %.1f" % [
				t, sh(Rules.CANNON_COST[t]), total, sh(st["kill"]), st["recharge"], sh(st["kill"]) / Rules.CANNON_BURST, sustained,
				sh(st["kill"]) / total, total / sh(st["kill"])])
	print("  a door emits %.1f shown units/s: a line passing at full rate loses the sustained share" % sh(Rules.BRAWL_DOOR_RATE))
	print("\nForge: cost %.0f, +%.0f %% attack for everything its owner deals (and its garrisons deal back)." % [sh(Rules.FORGE_COST), Rules.forge_bonus * 100.0])
	var saved: float = Rules.forge_bonus / (1.0 + Rules.forge_bonus)
	print("  BRAWL: every attack costs %.0f %% less, so it repays after %.0f shown units spent attacking (+%.0f s build);" % [saved * 100.0, sh(Rules.FORGE_COST) / saved, Rules.BUILD_SECONDS])
	print("  and every defender kills %.2f attackers instead of 1.0" % (1.0 + Rules.forge_bonus))


# ------------------------------------------------------------------ capture cost (real Sim)
func _bench(path: String) -> Dictionary:
	## A 1v1 map with seat A's home and one of its neighbours; the neighbour is rebuilt as the test node.
	var m: Dictionary = MapBuilder.load_map(path)
	var seats := {}
	for s in m["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	var sim := Sim.new()
	_yaw(m)
	sim.setup(m, MapBuilder.layout(m), seats, {"A": str(args.get("attacker", "null")), "B": "null"}, 1)
	var home: int = sim.homes["A"]
	var target := -1
	for link in sim.adj[home]:
		if not sim.edges[link[1]]["plaza"] and sim.edges[link[1]]["state"] == "" and not sim.edges[link[1]]["retracts"]:
			target = link[0]
			break
	return {"sim": sim, "home": home, "target": target}


func _capture_once(tier: int, send: float, forge: bool, faction: String) -> Dictionary:
	args["attacker"] = faction
	var b := _bench("res://maps4/C-01-meridian-rotunda.json")
	var sim: Sim = b["sim"]
	var n: Dictionary = sim.nodes[b["target"]]
	n["owner"] = ""
	n["tier"] = tier
	n["units"] = float(Rules.NEUTRAL_UNITS[tier])
	n["attachment"] = ""
	var home: Dictionary = sim.nodes[b["home"]]
	home["units"] = 100000.0
	if forge:
		home["attachment"] = "forge"                  # the home's vat stops; it only has to send
	var h := sim.send(b["home"], b["target"], send / home["units"])
	var sent: float = h["ordered"] if not h.is_empty() else 0.0
	var t0 := sim.time
	var t_cap := -1.0
	while sim.time < t0 + 90.0:
		sim.step(dt)
		if t_cap < 0.0 and n["owner"] == "A":
			t_cap = sim.time - t0
		var left := false
		for hh in sim.hordes:
			if hh["owner"] == "A":
				left = true
		if not left and n["siege"].is_empty() and sim.time > t0 + 1.0:
			break
	var won: bool = n["owner"] == "A"
	# spent = attackers lost in combat (the prize vat produces meanwhile, so its garrison is no measure)
	return {"sent": sent, "spent": sim.combat_losses.get("A", 0.0), "won": won, "t": t_cap}


func _capture_study() -> void:
	_apply()
	print("\nCAPTURE COST BRAWL (shown units; send = multiple of the garrison; spent = attackers lost; t = send to capture)")
	print("  tier garrison |  x1.1 spent (t)  |  x1.5 spent (t)  |  x2 spent (t)  |  x3 spent (t)  | x2 +forge | x2 ember | x2 solar | min send")
	for tier in range(1, 5):
		var g: float = Rules.NEUTRAL_UNITS[tier]
		var line := "   T%d   %4.0f   " % [tier, sh(g)]
		for k in [1.1, 1.5, 2.0, 3.0]:
			var r := _capture_once(tier, g * k, false, "null")
			line += "| %5.1f %s (%4.1fs) " % [sh(r["spent"]), " " if r["won"] else "X", r["t"]]
		var rf := _capture_once(tier, g * 2.0, true, "null")
		var re := _capture_once(tier, g * 2.0, false, "ember")
		var rs := _capture_once(tier, g * 2.0, false, "solar")
		line += "|   %5.1f   |  %5.1f   |  %5.1f   " % [sh(rf["spent"]), sh(re["spent"]), sh(rs["spent"])]
		var lo := 1.0
		var hi := 12.0
		for i in range(14):                           # smallest send that takes it, x garrison
			var mid := (lo + hi) * 0.5
			if _capture_once(tier, g * mid, false, "null")["won"]:
				hi = mid
			else:
				lo = mid
		line += "| %5.1f (x%.2f)" % [sh(g * hi), hi]
		print(line)


# ------------------------------------------------------------------ travel times (real paths)
func _travel_study() -> void:
	_apply()
	var by_tier := {1: [], 2: [], 3: []}
	var neutral_hop := []
	var home_home := []
	for path in _pool():
		var m: Dictionary = MapBuilder.load_map(path)
		var seats := {}
		for s in m["seats"]["1v1"]:
			seats[int(s["node"])] = s["seat"]
		var sim := Sim.new()
		_yaw(m)
		sim.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "null"}, 1)
		for ei in range(sim.edges.size()):
			var e: Dictionary = sim.edges[ei]
			if e["plaza"]:
				continue
			var L: float = sim.build_path([e["a"], e["b"]])["cum"][-1]
			by_tier[e["modules"]].append(L / Rules.move_speed())
		var ha: int = sim.homes["A"]
		var best := INF
		for n in sim.nodes:
			if n["owner"] == "" and n["relay"] == "":
				var r := sim.find_route(ha, n["id"])
				if r.size() >= 2:
					best = minf(best, sim.build_path(r)["cum"][-1] / Rules.move_speed())
		neutral_hop.append(best)
		var rh := sim.find_route(ha, sim.homes["B"])
		if rh.size() >= 2:
			home_home.append(sim.build_path(rh)["cum"][-1] / Rules.move_speed())
	print("\nTRAVEL BRAWL (%.2f m/s; %d maps): seconds for the head, door to door" % [Rules.move_speed(), _pool().size()])
	for t in by_tier:
		print("  %s deck (%d m): mean %.1f s  min %.1f  max %.1f  (%d decks)" % [["", "S", "M", "L"][t], t * 4, _mean(by_tier[t]), _min(by_tier[t]), _max(by_tier[t]), by_tier[t].size()])
	print("  home -> nearest neutral vat: mean %.1f s   home -> enemy home: mean %.1f s (min %.1f, max %.1f)" % [_mean(neutral_hop), _mean(home_home), _min(home_home), _max(home_home)])
	print("  a send of N shown units also takes N / %.1f s to leave the door" % sh(Rules.exit_rate()))


# ------------------------------------------------------------------ AI vs AI matches
func _pool() -> Array:
	var want: Array = Array(str(args.get("maps", "")).split(",", false))
	var out := []
	for p in MapPool.all():
		var m: Dictionary = _map(p)
		var code: String = str(m.get("code", ""))
		if not m["seats"].has("1v1"):
			continue
		if not want.is_empty():
			if code in want:
				out.append(p)
			continue
		if str(m.get("group", "")) in ["tutorial", "debug"]:
			continue
		var cm: String = str(m.get("combatMode", "both"))
		if cm == "both" or cm == "brawl":
			out.append(p)
	return out


func _map(path: String) -> Dictionary:
	if not _maps.has(path):
		_maps[path] = MapBuilder.load_map(path)
	return _maps[path]


func _yaw(m: Dictionary) -> void:
	## main.gd: every structure faces the camera, which looks along the map's short side (BRAWL doors).
	var pos := MapBuilder.layout(m)
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for k in pos:
		lo = lo.min(pos[k])
		hi = hi.max(pos[k])
	Rules.view_yaw = PI / 2.0 if (hi - lo).z > (hi - lo).x else 0.0


func _matches(study: String) -> void:
	var seeds := int(args.get("seeds", "4"))
	var variants: Array = []
	match study:
		"baseline":
			variants = ["stock"]
		"factions":
			variants = ["vex", "bloom", "ember", "solar", "null"]
		"openings":
			variants = ["tech", "expand", "cannon", "forge", "noupgrade", "noattach", "stock"]
	if args.has("variants"):
		variants = Array(str(args["variants"]).split(",", false))
	var jobs := []
	for path in _pool():
		for v in variants:
			for seed_i in range(seeds):
				for vseat in ["A", "B"]:
					jobs.append([path, v, seed_i, vseat])
	var shard := str(args.get("shard", "0/1")).split("/")
	var k := int(shard[0])
	var nsh := int(shard[1])
	var out_path := str(args.get("out", "user://balance_probe.jsonl"))
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	var t_start := Time.get_ticks_msec()
	var done := 0
	var results := []
	for j in range(jobs.size()):
		if j % nsh != k:
			continue
		var job: Array = jobs[j]
		var spec := {}
		var other := "B" if job[3] == "A" else "A"
		if study == "factions":
			spec[job[3]] = {"faction": job[1], "strategy": "stock"}
			spec[other] = {"faction": "null", "strategy": "stock"}
		else:
			spec[job[3]] = {"faction": "null", "strategy": job[1]}
			spec[other] = {"faction": "null", "strategy": str(args.get("vs", "stock"))}
		var rec := _play(job[0], spec, 1000 + int(job[2]) * 7919 + (j / 2) * 13)
		rec["study"] = study
		rec["variant"] = job[1]
		rec["vseat"] = job[3]
		rec["seed"] = job[2]
		rec["tag"] = str(args.get("tag", ""))
		f.store_line(JSON.stringify(rec))
		results.append(rec)
		done += 1
	f.close()
	print("%d matches in %.0f s -> %s" % [done, (Time.get_ticks_msec() - t_start) / 1000.0, ProjectSettings.globalize_path(out_path)])
	_summarise(results)


func _play(path: String, spec: Dictionary, seed_value: int) -> Dictionary:
	_apply()
	var m: Dictionary = _map(path).duplicate(true)
	var seats := {}
	for s in m["seats"]["1v1"]:
		seats[int(s["node"])] = s["seat"]
	var factions := {}
	for seat in spec:
		factions[seat] = spec[seat]["faction"]
	_yaw(m)
	var sim := Sim.new()
	sim.setup(m, MapBuilder.layout(m), seats, factions, seed_value)
	_captures = []
	sim.captured.connect(func(id: int, new_owner: String, old_owner: String):
		_captures.append({"t": snappedf(sim.time, 0.1), "seat": new_owner, "from": old_owner, "tier": sim.nodes[id]["tier"]}))
	var ais := []
	for seat in spec:
		var ai = BalanceAI.new(seat, level, spec[seat]["strategy"], seed_value)
		ai.fair = str(args.get("fair", "0")) == "1"
		ais.append(ai)
	var idle := {}                                    # seat+minute -> [vat-seconds at cap, vat-seconds]
	var snaps := {}
	var next_snap := 60.0
	while not sim.over:
		for ai in ais:
			ai.think(sim, dt)
		sim.step(dt)
		for n in sim.nodes:
			if n["owner"] == "" or not Sim.has_vat(n):
				continue
			var minute := mini(int(sim.time / 60.0), 6)
			var key: String = "%s%d" % [n["owner"], minute]
			var cell: Array = idle.get(key, [0.0, 0.0])
			cell[1] += dt
			if n["units"] >= Rules.CAPS[n["tier"]] - 0.01:
				cell[0] += dt
			idle[key] = cell
		if sim.time >= next_snap:
			var s := {}
			for seat in spec:
				var nodes := 0
				var prod := 0.0
				var tiers := 0
				for n in sim.nodes:
					if n["owner"] == seat:
						nodes += 1
						prod += sim.production(n)
						tiers += n["tier"] if Sim.has_vat(n) else 0
				s[seat] = {"str": snappedf(sh(sim.seat_strength(seat)), 0.1), "nodes": nodes, "prod": snappedf(sh(prod), 0.01), "tiers": tiers}
			snaps[str(int(next_snap))] = s
			next_snap += 60.0
	var builds := []
	var forced := false
	var bursts := {}
	for e in sim.events:
		if e["type"] == "cannon_burst":
			bursts[e["seat"]] = bursts.get(e["seat"], 0) + 1
		elif e["type"] == "build_start":
			builds.append({"t": snappedf(e["t"], 0.1), "seat": e["seat"], "kind": e["kind"]})
		elif e["type"] == "end" and e.get("forced", false):
			forced = true
	var idle_out := {}
	for key in idle:
		idle_out[key] = snappedf(idle[key][0] / maxf(idle[key][1], 0.001), 0.001)
	var losses := {}
	for seat in spec:
		losses[seat] = [snappedf(sh(sim.combat_losses.get(seat, 0.0)), 0.1), snappedf(sh(sim.fall_losses.get(seat, 0.0)), 0.1)]
	return {"map": str(m.get("code", "")), "mode": "brawl", "level": level, "preset": preset,
			"override": JSON.stringify(overrides), "spec": spec, "winner": sim.winner, "t": snappedf(sim.time, 0.1),
			"forced": forced, "ls": sim.last_stand_active, "builds": builds, "captures": _captures, "snaps": snaps,
			"idle": idle_out, "losses": losses, "bursts": bursts, "fair": str(args.get("fair", "0")) == "1",
			"vs": str(args.get("vs", "stock"))}


# ------------------------------------------------------------------ statistics
static func wilson(w: float, n: float) -> Array:
	## 95 % Wilson interval of a win share (draws count half).
	if n <= 0.0:
		return [0.0, 0.0, 0.0]
	var z := 1.96
	var p := w / n
	var c := (p + z * z / (2.0 * n)) / (1.0 + z * z / n)
	var h := z * sqrt(p * (1.0 - p) / n + z * z / (4.0 * n * n)) / (1.0 + z * z / n)
	return [p, c - h, c + h]


func _summarise(results: Array) -> void:
	var cells := {}
	for r in results:
		var key := "%s | %s | %s%s | %s | %s" % [r["study"], r["mode"], r["level"], " fair" if r.get("fair", false) else "",
				r["preset"] if r["preset"] != "" else "default", r["variant"] + ("" if r.get("vs", "stock") == "stock" else " v " + r["vs"])]
		if not cells.has(key):
			cells[key] = []
		cells[key].append(r)
	var keys := cells.keys()
	keys.sort()
	print("\n%-58s %5s  %-22s %6s %6s %6s %6s %6s" % ["study | mode | level | preset | variant", "n", "variant win % [95% CI]", "len s", "<3:00", "LS", "7:00", "draw"])
	for key in keys:
		var rs: Array = cells[key]
		var w := 0.0
		var draws := 0
		var lens := []
		var early := 0
		var ls := 0
		var hard := 0
		for r in rs:
			if r["winner"] == r["vseat"]:
				w += 1.0
			elif r["winner"] == "":
				w += 0.5
				draws += 1
			lens.append(float(r["t"]))
			if float(r["t"]) < Rules.LAST_STAND_TIME:
				early += 1
			if r["ls"]:
				ls += 1
			if r["forced"]:
				hard += 1
		var ci := wilson(w, rs.size())
		var n := float(rs.size())
		print("%-58s %5d  %5.1f  [%4.1f - %4.1f]   %6.0f %5.0f%% %5.0f%% %5.0f%% %5.0f%%" % [key, rs.size(), ci[0] * 100.0, ci[1] * 100.0, ci[2] * 100.0,
				_mean(lens), early / n * 100.0, ls / n * 100.0, hard / n * 100.0, draws / n * 100.0])
	_timeline(results)


func _timeline(results: Array) -> void:
	## When and what the AI builds and takes (every seat of every match; stock seats only).
	var first_up := []
	var ups := {60: [], 120: [], 180: []}
	var first_cannon := []
	var first_forge := []
	var neut := {60: [], 120: []}
	var att := {"cannon": 0, "forge": 0}
	var seats := 0
	var idle := {}
	var tiers_at := {}
	var burst_n := 0
	var cannon_seats := 0
	for r in results:
		for seat in r["spec"]:
			if r["spec"][seat]["strategy"] != "stock":
				continue
			seats += 1
			burst_n += int(r.get("bursts", {}).get(seat, 0))
			var fu := INF
			var fc := INF
			var ff := INF
			var count := {60: 0, 120: 0, 180: 0}
			for b in r["builds"]:
				if b["seat"] != seat:
					continue
				if b["kind"] == "vat":
					fu = minf(fu, b["t"])
					for lim in count:
						if b["t"] < lim:
							count[lim] += 1
				elif b["kind"] == "cannon":
					fc = minf(fc, b["t"])
				elif b["kind"] == "forge":
					ff = minf(ff, b["t"])
			if fu < INF:
				first_up.append(fu)
			for lim in count:
				ups[lim].append(count[lim])
			if fc < INF:
				cannon_seats += 1
				first_cannon.append(fc)
				att["cannon"] += 1
			if ff < INF:
				first_forge.append(ff)
				att["forge"] += 1
			for lim in neut:
				var c := 0
				for cp in r["captures"]:
					if cp["seat"] == seat and cp["from"] == "" and cp["t"] < lim:
						c += 1
				neut[lim].append(c)
			for minute in range(0, 7):
				var v = r["idle"].get("%s%d" % [seat, minute])
				if v != null:
					if not idle.has(minute):
						idle[minute] = []
					idle[minute].append(float(v))
			for st in r["snaps"]:
				if r["snaps"][st].has(seat):
					if not tiers_at.has(st):
						tiers_at[st] = {"nodes": [], "prod": [], "str": []}
					tiers_at[st]["nodes"].append(float(r["snaps"][st][seat]["nodes"]))
					tiers_at[st]["prod"].append(float(r["snaps"][st][seat]["prod"]))
					tiers_at[st]["str"].append(float(r["snaps"][st][seat]["str"]))
	if seats == 0:
		return
	print("\nSTOCK AI TIMELINE (%d seats)" % seats)
	print("  first vat upgrade: %.0f%% of seats, mean at %.0f s (median %.0f)" % [first_up.size() * 100.0 / seats, _mean(first_up), _median(first_up)])
	print("  vat upgrades started by 1:00 %.2f   by 2:00 %.2f   by 3:00 %.2f (per seat)" % [_mean(ups[60]), _mean(ups[120]), _mean(ups[180])])
	print("  cannon built by %.0f%% of seats (first at %.0f s)   forge by %.0f%% (first at %.0f s)" % [att["cannon"] * 100.0 / seats, _mean(first_cannon), att["forge"] * 100.0 / seats, _mean(first_forge)])
	print("  cannon bursts: %.1f per seat that built a cannon" % (burst_n / maxf(cannon_seats, 1.0)))
	print("  neutrals taken by 1:00 %.2f   by 2:00 %.2f (per seat)" % [_mean(neut[60]), _mean(neut[120])])
	var line := "  vat-time at the cap by minute:"
	for minute in range(0, 7):
		if idle.has(minute):
			line += "  %d:00 %.0f%%" % [minute, _mean(idle[minute]) * 100.0]
	print(line)
	var ks := tiers_at.keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	for st in ks:
		print("  at %s s: nodes %.1f  production %.2f/s  strength %.0f (seats still playing: %d)" % [st, _mean(tiers_at[st]["nodes"]), _mean(tiers_at[st]["prod"]), _mean(tiers_at[st]["str"]), tiers_at[st]["nodes"].size()])


func _report() -> void:
	var results := []
	for p in str(args.get("in", "")).split(",", false):
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			print("cannot read ", p)
			continue
		while not f.eof_reached():
			var line := f.get_line()
			if line.strip_edges() == "":
				continue
			var r = JSON.parse_string(line)
			if r is Dictionary:
				results.append(r)
	print("%d matches read" % results.size())
	_summarise(results)


static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / a.size()


static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


static func _min(a: Array) -> float:
	return a.min() if not a.is_empty() else 0.0


static func _max(a: Array) -> float:
	return a.max() if not a.is_empty() else 0.0
