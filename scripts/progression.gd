class_name Progression
extends RefCounted
## PROGRESSION (01 Rules/PROGRESSION-DESIGN.md): XP / level, the wallet (SCRAP + SYNDICATE CHIPS), unlocks, per-faction
## plays / wins and the daily / weekly challenges. Offline first (Daniele, 2026-09-27): everything lives on the device in
## user://progress.cfg (static, like ArmyPresets); a browser with no storage still plays and `saved` reports false.
## Later the account mirrors it and server-hosted matches are paid by the server instead (§7).
##
## The interface other sessions call (agreed with Campaign and Tutorial, §10):
##   grant(source, amount, currency := "soft") -> bool     one-off, idempotent per source ("campaign:vex:04", "tutorial:3")
##   has_granted(source) -> bool
##   unlock(item, source) -> bool / is_unlocked(item) -> bool   ids "<family>:<id>[:faction]" (vat:faction:vex,
##                                                          vat:graduate, vat:biopod, machinegoon:spitter, monster:alt:vex,
##                                                          skill:mire)
##   spend(item, currency) -> bool                          buy an unlock at its Rules.PRICES price
##   record_match(result) -> Dictionary                     once per finished match: pays the lines, returns them for the
##                                                          result screen (result_from_sim builds `result`)
## Numbers: Rules.PROGRESSION / PRICES / CHALLENGES. Rules.UNLOCK_ALL_TESTING (or `unlock_all` for a session) opens
## every lock except the Graduate vat.

static var path := "user://progress.cfg"          # tests point this elsewhere
static var saved := true                          # false: the last save failed (no storage)
static var unlock_all: bool = Rules.UNLOCK_ALL_TESTING   # the Debug toggle flips it for a session
static var now_override := -1                     # tests: a fixed unix time (UTC)

static var wallet := {"soft": 0, "premium": 0}
static var xp := 0                                # total, all time
static var granted := {}                          # one-off source -> [currency, amount, unix]
static var ledger: Array = []                     # recent [unix, source, currency, amount], newest last
static var unlocks := {}                          # item -> source
static var factions := {}                         # faction -> {"plays", "wins", "vat_wins"}
static var first_win_day := ""                    # the UTC day of the last first-win bonus
static var challenges := {}                       # "daily" / "weekly" -> {"key", "list": [{id, target, progress, claimed, faction?}], "rerolled"}
static var history: Array = []                    # MATCH HISTORY (0.20.5): the last HISTORY_KEEP finished matches, newest last
static var _loaded := false

const FACTION_IDS := ["vex", "null", "bloom", "ember", "solar"]
const HISTORY_KEEP := 50
const STRUCTURE_FAMILIES := ["machinegoon", "laser", "forge", "monster_hub"]


# ------------------------------------------------------------------ save / load
static func load_all() -> void:
	_loaded = true
	wallet = {"soft": 0, "premium": 0}
	xp = 0
	granted = {}
	ledger = []
	unlocks = {}
	factions = {}
	first_win_day = ""
	challenges = {}
	history = []
	var cf := ConfigFile.new()
	if cf.load(path) != OK:                       # none yet, or no storage at all
		return
	for c in wallet:
		wallet[c] = maxi(0, int(cf.get_value("wallet", c, 0)))
	xp = maxi(0, int(cf.get_value("profile", "xp", 0)))
	first_win_day = str(cf.get_value("profile", "first_win_day", ""))
	granted = _dict(cf.get_value("wallet", "granted", {}))
	var l = cf.get_value("wallet", "ledger", [])
	ledger = l if l is Array else []
	unlocks = _dict(cf.get_value("unlocks", "items", {}))
	for f in FACTION_IDS:
		var d := _dict(cf.get_value("factions", f, {}))
		if not d.is_empty():
			factions[f] = {"plays": int(d.get("plays", 0)), "wins": int(d.get("wins", 0)), "vat_wins": int(d.get("vat_wins", 0))}
	var hl = cf.get_value("history", "matches", [])
	history = hl if hl is Array else []
	for kind in ["daily", "weekly"]:
		var ch := _dict(cf.get_value("challenges", kind, {}))
		if ch.has("key") and ch.get("list") is Array:
			challenges[kind] = ch


static func reload_all() -> void:
	## Re-read `path` (tests, and after an account sync later). Not reload(): that is GDScript's own.
	_loaded = false
	load_all()


static func save_all() -> bool:
	var cf := ConfigFile.new()
	for c in wallet:
		cf.set_value("wallet", c, wallet[c])
	cf.set_value("wallet", "granted", granted)
	cf.set_value("wallet", "ledger", ledger)
	cf.set_value("profile", "xp", xp)
	cf.set_value("profile", "first_win_day", first_win_day)
	cf.set_value("unlocks", "items", unlocks)
	for f in factions:
		cf.set_value("factions", f, factions[f])
	for kind in challenges:
		cf.set_value("challenges", kind, challenges[kind])
	cf.set_value("history", "matches", history)
	saved = cf.save(path) == OK
	return saved


static func _ensure() -> void:
	if not _loaded:
		load_all()


static func _dict(v) -> Dictionary:
	return v if v is Dictionary else {}


# ------------------------------------------------------------------ wallet
static func balance(currency := "soft") -> int:
	_ensure()
	return int(wallet.get(currency, 0))


static func grant(source: String, amount: int, currency := "soft") -> bool:
	## A one-off payment: the same source pays once, ever (a campaign mission, a tutorial lesson, a level reward, a
	## challenge claim). false = already paid (or a bad call) - nothing changes.
	_ensure()
	if source == "" or amount <= 0 or not wallet.has(currency) or granted.has(source):
		return false
	granted[source] = [currency, amount, _now()]
	_pay(source, amount, currency)
	save_all()
	return true


static func has_granted(source: String) -> bool:
	_ensure()
	return granted.has(source)


static func _pay(source: String, amount: int, currency: String) -> void:
	## Every balance change goes through here (a ledger line); no save - the caller saves once.
	wallet[currency] = maxi(0, int(wallet.get(currency, 0)) + amount)
	ledger.append([_now(), source, currency, amount])
	var keep: int = Rules.PROGRESSION["ledger_keep"]
	if ledger.size() > keep:
		ledger = ledger.slice(ledger.size() - keep)


# ------------------------------------------------------------------ unlocks
static func is_unlocked(item: String) -> bool:
	_ensure()
	var p := item.split(":")
	if p.size() < 2:
		return false
	if item == "vat:graduate":                    # the tutorial's reward, locked even while testing
		return unlocks.has(item) or TutorialDirector.all_done()
	if p[1] == "default" or unlock_all or unlocks.has(item):
		return true
	if p[0] == "skill":
		return p[1] in Rules.PROGRESSION["free_skills"] or p[1] in Rules.FACTION_ULTIMATE_ID.values()
	if p[0] == "vat" and p[1] == "faction" and p.size() == 3:
		return faction_stats(p[2])["vat_wins"] >= int(Rules.PROGRESSION["faction_vat_wins"])
	return false


static func unlock(item: String, source: String) -> bool:
	## Records an unlock from a path other than buying (campaign, tutorial, wins). false = already owned for real
	## (the testing switch doesn't count) or a bad id.
	_ensure()
	if source == "" or unlocks.has(item) or price(item).is_empty() and item != "vat:graduate":
		return false
	unlocks[item] = source
	save_all()
	return true


static func owns(item: String) -> bool:
	## Owned for real (recorded, free or earned) - ignores the testing switch. The ARMIES page uses it to show what a
	## player would still have to earn once the locks turn on.
	var keep := unlock_all
	unlock_all = false
	var r := is_unlocked(item)
	unlock_all = keep
	return r


static func cosmetic_item(family: String, id: String, faction := "") -> String:
	## An ARMIES > COSMETICS pick (Cosmetics.OPTIONS[family] id) as an unlock id: the faction set and the monster alt
	## are per faction ("vat:faction:bloom", "monster:alt:bloom"), everything else is "<family>:<id>".
	if family == "vat" and id == "faction" or family == "monster" and id == "alt":
		return "%s:%s:%s" % [family, id, faction if faction != "" else "null"]
	return "%s:%s" % [family, id]


static func price(item: String) -> Dictionary:
	## {"soft": n, "premium": m} for a buyable item ({} = not buyable: defaults, free skills, ultimates, Graduate, bad ids).
	var p := item.split(":")
	if p.size() < 2 or p[1] == "default":
		return {}
	match p[0]:
		"skill":
			if p[1] in Rules.PROGRESSION["free_skills"] or not (p[1] in Rules.ACTIVE_SKILLS or p[1] in Rules.MAP_SKILLS):
				return {}
			return Rules.PRICES["skill"]
		"vat":
			if p[1] == "faction":
				return Rules.PRICES["vat_faction"] if p.size() == 3 and p[2] in FACTION_IDS else {}
			return Rules.PRICES["vat_line"] if Cosmetics.SKIN_LINE.has(p[1]) else {}
		"monster":
			return Rules.PRICES["monster_alt"] if p[1] == "alt" and p.size() == 3 and p[2] in FACTION_IDS else {}
	if p[0] in STRUCTURE_FAMILIES and p[1] in (Cosmetics.OPTIONS.get(p[0], []) as Array):
		return Rules.PRICES["structure"]
	return {}


static func spend(item: String, currency := "soft") -> bool:
	## Buys `item` with `currency` at its price. false = not sold for that currency, already owned, or too poor.
	_ensure()
	var cost := int(price(item).get(currency, 0))
	if cost <= 0 or owns(item) or balance(currency) < cost:
		return false
	_pay("buy:" + item, -cost, currency)
	unlocks[item] = "buy:" + currency
	save_all()
	return true


# ------------------------------------------------------------------ XP and level
static func level_for(total_xp: int) -> Dictionary:
	## {"level", "into" (XP into this level), "need" (XP this level takes)}; level 1 at 0 XP.
	var lv := 1
	var left := total_xp
	while true:
		var need: int = int(Rules.PROGRESSION["level_base"]) + int(Rules.PROGRESSION["level_step"]) * (lv - 1)
		if left < need:
			return {"level": lv, "into": left, "need": need}
		left -= need
		lv += 1
	return {}


static func level() -> int:
	_ensure()
	return int(level_for(xp)["level"])


static func _add_xp(amount: int, lines: Array) -> void:
	## Adds XP; each level reached pays its one-off reward (source "level:<n>") and adds a line.
	var before := level_for(xp)["level"] as int
	xp += amount
	var after := level_for(xp)["level"] as int
	for lv in range(before + 1, after + 1):
		var line := {"what": "LEVEL %d" % lv, "soft": 0, "premium": 0, "xp": 0, "level_up": lv}
		var src := "level:%d" % lv
		if not granted.has(src):
			var soft: int = Rules.PROGRESSION["level_soft"]
			granted[src] = ["soft", soft, _now()]
			_pay(src, soft, "soft")
			line["soft"] = soft
			if lv % int(Rules.PROGRESSION["level_premium_every"]) == 0:
				var chips: int = Rules.PROGRESSION["level_premium"]
				granted[src + ":premium"] = ["premium", chips, _now()]
				_pay(src + ":premium", chips, "premium")
				line["premium"] = chips
		lines.append(line)


# ------------------------------------------------------------------ factions
static func faction_stats(faction: String) -> Dictionary:
	_ensure()
	return factions.get(faction, {"plays": 0, "wins": 0, "vat_wins": 0})


# ------------------------------------------------------------------ matches
static func result_from_sim(sim: Sim, seat: String, info := {}) -> Dictionary:
	## The result record_match wants, for `seat`, read from a finished Sim. info: "online" (bool: a server-hosted room),
	## "ai_level" (the strongest AI opponent's Rules.AI_LEVELS name, "" when no AI), "left_early", "tutorial",
	## "campaign" (a mission: XP and challenges, no per-match SCRAP - its own one-off reward pays - and no faction-vat win).
	return {
		"faction": str(sim.factions.get(seat, "null")),
		"won": sim.winner != "" and (sim.winner == seat or sim.allied(seat, sim.winner)),
		"relay_map": sim.has_relays,
		"online": bool(info.get("online", false)),
		"ai_level": str(info.get("ai_level", "")),
		"left_early": bool(info.get("left_early", false)),
		"tutorial": bool(info.get("tutorial", false)),
		"campaign": bool(info.get("campaign", false)),
		"stats": seat_stats(sim, seat),
	}


static func seat_stats(sim: Sim, seat: String) -> Dictionary:
	## One seat's counters from sim.events - the same function on the device (local rewards) and on the match host
	## (the PROGRESSION-DESIGN §7a report), so both count alike. Unit counts at Alpha 11 scale (Rules.shown).
	## void_drops: enemy units that fell off decks this seat's relays moved (the relay fall events' "by", main 62b342a).
	var st := {"sends": 0, "captures": 0, "nodes_lost": 0, "home_lost": false, "relay_fires": 0, "void_drops": 0,
			"monster_launches": 0, "monster_kicks": 0, "monster_kicked": 0, "skills": 0, "out_at_s": -1.0,
			"units_lost_combat": Rules.shown(float(sim.combat_losses.get(seat, 0.0))),
			"units_lost_falls": Rules.shown(float(sim.fall_losses.get(seat, 0.0)))}
	var home: int = int(sim.homes.get(seat, -1))
	var dropped := 0.0
	var kicked := 0.0
	for e in sim.events:
		match str(e.get("type", "")):
			"send":
				if e.get("seat") == seat:
					st["sends"] += 1
			"capture", "collapse":
				if e.get("seat") == seat and e["type"] == "capture":
					st["captures"] += 1
				if e.get("from") == seat and e.get("seat") != seat:
					st["nodes_lost"] += 1
					if int(e.get("node", -2)) == home:
						st["home_lost"] = true
			"relay_fired":
				if e.get("seat") == seat:
					st["relay_fires"] += 1
			"fall":
				if e.get("by") == seat and not sim.allied(str(e.get("seat", "")), seat):   # enemies only: the firer's
					dropped += float(e.get("units", 0.0))                                   # own / allies' lines fall too
			"monster_launch":
				if e.get("seat") == seat:
					st["monster_launches"] += 1
			"monster_kick":
				if e.get("seat") == seat and e.get("seat_hit") != seat:
					st["monster_kicks"] += 1
					kicked += float(e.get("units", 0.0))
			"skill":
				if e.get("seat") == seat:
					st["skills"] += 1
			"eliminated":
				if e.get("seat") == seat and st["out_at_s"] < 0.0:
					st["out_at_s"] = snappedf(float(e.get("t", 0.0)), 0.1)
	st["void_drops"] = Rules.shown(dropped)
	st["monster_kicked"] = Rules.shown(kicked)
	return st


static func placements(sim: Sim, strength := {}) -> Dictionary:
	## seat -> place (1 = best). Winners (the winning seat and its team-mates) first; then survivors by `strength`
	## (seat -> final strength, the host's number; missing = 0); then seats in reverse order of going out (sim.events
	## "eliminated"). Team-mates share their team's best place. A draw has no winners.
	var out_t := {}
	for e in sim.events:
		if e.get("type") == "eliminated" and not out_t.has(e.get("seat")):
			out_t[e["seat"]] = float(e.get("t", 0.0))
	var seats: Array = sim.factions.keys()
	var score := func(s: String) -> float:
		if sim.winner != "" and (s == sim.winner or sim.allied(s, sim.winner)):
			return 1e12
		if not out_t.has(s):
			return 1e9 + float(strength.get(s, 0.0))
		return float(out_t[s])
	seats.sort_custom(func(a, b): return score.call(a) > score.call(b))
	var place := {}
	var team_place := {}
	var next := 1
	for s in seats:
		var t = sim.teams.get(s, null)
		if t != null and team_place.has(t):
			place[s] = team_place[t]
			continue
		place[s] = next
		if t != null:
			team_place[t] = next
		next += 1
	return place


static func history_entry(sim: Sim, seat: String, info := {}) -> Dictionary:
	## One MATCH HISTORY line for this device's log: when, map, mode, online or not (room_key "ROOM-ROUND" joins it
	## to the server's record), how long, the result, and every seat (faction, team, name or AI level, you).
	## info: "map", "mode", "online", "room_key", "names" {seat: name}, "ai" {seat: level}.
	var players := []
	var names: Dictionary = info.get("names", {})
	var ai: Dictionary = info.get("ai", {})
	for s in sim.factions.keys():
		players.append({"seat": s, "faction": str(sim.factions[s]), "team": sim.teams.get(s, null),
				"name": str(names.get(s, "")), "ai_level": str(ai.get(s, "")), "is_me": s == seat,
				"won": sim.winner != "" and (sim.winner == s or sim.allied(s, sim.winner))})
	return {"t": _now(), "map": str(info.get("map", "")), "mode": str(info.get("mode", "")),
			"online": bool(info.get("online", false)), "room_key": str(info.get("room_key", "")),
			"duration_s": snappedf(sim.time, 0.1), "draw": sim.winner == "",
			"won": sim.winner != "" and (sim.winner == seat or sim.allied(seat, sim.winner)), "players": players}


static func merge_history(local: Array, online: Array) -> Array:
	## One list, newest first: this device's log plus the server's rounds (Account.match_history), a round played here
	## shown once (its local line, tagged ONLINE; the server's match_id starts with its room_key).
	var here := {}
	for h in local:
		if str(h.get("room_key", "")) != "":
			here[str(h["room_key"])] = true
	var out := []
	for h in local:
		out.append(h)
	for m in online:
		var parts := str(m.get("match_id", "")).split("-")
		var key := "%s-%s" % [parts[0], parts[1]] if parts.size() >= 2 else ""
		if key != "" and here.has(key):
			continue
		out.append(_from_server(m))
	out.sort_custom(func(a, b): return int(a.get("t", 0)) > int(b.get("t", 0)))
	return out


static func _from_server(m: Dictionary) -> Dictionary:
	## A server round (my_matches) as a MATCH HISTORY line.
	var players := []
	var me_won := false
	for s in m.get("seats", []):
		if not s is Dictionary:
			continue
		players.append({"seat": str(s.get("seat", "")), "faction": str(s.get("faction", "")), "team": s.get("team"),
				"name": str(s.get("name", "")) if s.get("name") != null else "", "ai_level": str(s.get("ai_level", "")) if s.get("ai_level") != null else "",
				"is_me": s.get("is_me") == true, "won": s.get("won") == true})   # null-safe: bool(null) crashes
		if s.get("is_me") == true:
			me_won = s.get("won") == true
	var outcome: Dictionary = m.get("outcome", {}) if m.get("outcome") is Dictionary else {}
	var t := int(Time.get_unix_time_from_datetime_string(str(m.get("started_at", "")).substr(0, 19)))
	return {"t": t, "map": str(m.get("map", "")), "mode": str(m.get("mode", "")), "online": true,
			"room_key": "", "duration_s": float(m.get("duration_s", 0.0)) if m.get("duration_s") != null else 0.0,
			"draw": outcome.get("draw") == true, "won": me_won, "players": players}


static func full_pay(result: Dictionary) -> bool:
	## Online, or the strongest AI is Veteran / Expert (Daniele: easy AI pays XP only).
	return bool(result.get("online", false)) or str(result.get("ai_level", "")) in Rules.PROGRESSION["full_pay_ai"]


static func record_match(result: Dictionary) -> Dictionary:
	## Once per finished match. Returns {"lines": [{what, soft, premium, xp, level_up?}], "xp_before", "xp_after",
	## "challenges": [ids newly complete], "unlocked": [items]} for the result screen. Tutorial lessons and matches
	## left early pay nothing.
	_ensure()
	var out := {"lines": [], "xp_before": xp, "xp_after": xp, "challenges": [], "unlocked": []}
	if result.get("tutorial", false) or result.get("left_early", false):
		return out
	if result.get("history") is Dictionary:              # MATCH HISTORY: every finished match, paid or not
		history.append(result["history"])
		if history.size() > HISTORY_KEEP:
			history = history.slice(history.size() - HISTORY_KEEP)
	var lines: Array = out["lines"]
	var P := Rules.PROGRESSION
	var mission := bool(result.get("campaign", false))
	var pay := full_pay(result) and not mission             # a mission's SCRAP is its own one-off reward (Campaign)
	var won := bool(result.get("won", false))
	var f := str(result.get("faction", "null"))
	var src := "match:%d" % _now()
	var gained_xp := 0
	var line := {"what": "MATCH FINISHED", "soft": P["finish_soft"] if pay else 0, "premium": 0, "xp": P["finish_xp"]}
	lines.append(line)
	if won:
		lines.append({"what": "WIN", "soft": P["win_soft"] if pay else 0, "premium": 0, "xp": P["win_xp"]})
		var today := day_key()
		if first_win_day != today:
			first_win_day = today
			lines.append({"what": "FIRST WIN OF THE DAY", "soft": P["first_win_soft"] if pay else 0, "premium": 0,
					"xp": P["first_win_xp"]})
	for l in lines:
		if int(l["soft"]) > 0:
			_pay(src, int(l["soft"]), "soft")
		gained_xp += int(l["xp"])
	# faction stats (a faction vat by wins: online wins, or offline wins vs Veteran / Expert)
	var fs := faction_stats(f).duplicate()
	fs["plays"] += 1
	if won:
		fs["wins"] += 1
		if full_pay(result) and not mission:
			fs["vat_wins"] += 1
	factions[f] = fs
	var vat := "vat:faction:" + f
	if won and full_pay(result) and not mission and fs["vat_wins"] == int(P["faction_vat_wins"]) and not unlocks.has(vat):
		unlocks[vat] = "wins:" + f
		out["unlocked"].append(vat)
	# challenges
	out["challenges"] = _progress_challenges(match_stats(result))
	_add_xp(gained_xp, lines)
	out["xp_after"] = xp
	save_all()
	return out


static func match_stats(result: Dictionary) -> Dictionary:
	## What one match adds to each challenge stat.
	var won := bool(result.get("won", false))
	var st: Dictionary = result.get("stats", {})
	return {
		"finish": 1, "win": 1 if won else 0,
		"win_as": str(result.get("faction", "")) if won else "",
		"win_factions": str(result.get("faction", "")) if won else "",
		"captures": int(st.get("captures", 0)), "relay_fires": int(st.get("relay_fires", 0)),
		"monster_kicked": int(st.get("monster_kicked", 0)), "skills": int(st.get("skills", 0)),
		"void_drops": int(st.get("void_drops", 0)),
		"win_relay_map": 1 if won and result.get("relay_map", false) else 0,
		"win_home_kept": 1 if won and not st.get("home_lost", false) else 0,
	}


# ------------------------------------------------------------------ challenges
static func day_key(t := -1) -> String:
	## The UTC day, "YYYY-MM-DD" (Daniele: reset 00:00 UTC).
	return Time.get_date_string_from_unix_time(_now() if t < 0 else t)


static func week_key(t := -1) -> String:
	## The UTC Monday that starts this week (weekly reset Monday 00:00 UTC). 1970-01-01 was a Thursday.
	var days := int(floor(float(_now() if t < 0 else t) / 86400.0))
	return Time.get_date_string_from_unix_time((days - posmod(days + 3, 7)) * 86400)


static func seconds_to_reset(kind: String) -> int:
	var t := _now()
	var days := int(floor(float(t) / 86400.0))
	var next := (days + 1) * 86400 if kind == "daily" else (days - posmod(days + 3, 7) + 7) * 86400
	return next - t


static func current_challenges(kind: String) -> Array:
	## Today's (this week's) challenges, rolled when the day (week) changed. Each: {id, text, target, progress,
	## claimed, done, soft, premium, xp}. The pick is seeded by the day, so every player gets the same set.
	_ensure()
	_roll(kind)
	var out := []
	for c in challenges[kind]["list"]:
		var d := _def(kind, c["id"])
		var text := str(d.get("text", c["id"]))
		if d.get("faction", false):
			text = text % str(c.get("faction", "vex")).to_upper()
		out.append({"id": c["id"], "text": text, "target": int(c["target"]), "progress": mini(int(c["progress"]), int(c["target"])),
				"claimed": bool(c["claimed"]), "done": int(c["progress"]) >= int(c["target"]),
				"soft": Rules.PROGRESSION[kind + "_soft"], "xp": Rules.PROGRESSION[kind + "_xp"],
				"premium": Rules.PROGRESSION.get(kind + "_premium", 0)})
	return out


static func claim(kind: String, id: String) -> Dictionary:
	## Pays a finished challenge once. Returns the paid line ({} = not finished, already claimed, unknown).
	_ensure()
	_roll(kind)
	for c in challenges[kind]["list"]:
		if c["id"] != id or c["claimed"] or int(c["progress"]) < int(c["target"]):
			continue
		var src := "%s:%s:%s" % [kind, challenges[kind]["key"], id]
		if granted.has(src):
			return {}
		c["claimed"] = true
		var P := Rules.PROGRESSION
		var line := {"what": "CHALLENGE", "soft": int(P[kind + "_soft"]), "premium": int(P.get(kind + "_premium", 0)),
				"xp": int(P[kind + "_xp"])}
		granted[src] = ["soft", line["soft"], _now()]
		_pay(src, line["soft"], "soft")
		if line["premium"] > 0:
			granted[src + ":premium"] = ["premium", line["premium"], _now()]
			_pay(src + ":premium", line["premium"], "premium")
		var lines := [line]
		_add_xp(line["xp"], lines)
		line["levels"] = lines.slice(1)
		save_all()
		return line
	return {}


static func reroll(id: String) -> bool:
	## Swaps one unclaimed, unfinished daily challenge for another from the pool; once per UTC day.
	_ensure()
	_roll("daily")
	var ch: Dictionary = challenges["daily"]
	if ch.get("rerolled", false):
		return false
	var list: Array = ch["list"]
	var taken := list.map(func(c): return c["id"])
	for i in list.size():
		if list[i]["id"] != id or list[i]["claimed"] or int(list[i]["progress"]) >= int(list[i]["target"]):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(ch["key"] + ":reroll")
		var pool: Array = (Rules.CHALLENGES["daily"] as Array).filter(func(d): return not d["id"] in taken)
		if pool.is_empty():
			return false
		list[i] = _fresh(pool[rng.randi() % pool.size()], rng)
		ch["rerolled"] = true
		save_all()
		return true
	return false


static func _roll(kind: String) -> void:
	var key := day_key() if kind == "daily" else week_key()
	if challenges.has(kind) and challenges[kind].get("key") == key:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind + ":" + key)
	var pool: Array = (Rules.CHALLENGES[kind] as Array).duplicate()
	var list := []
	for i in mini(int(Rules.PROGRESSION[kind + "_count"]), pool.size()):
		var d: Dictionary = pool.pop_at(rng.randi() % pool.size())
		list.append(_fresh(d, rng))
	challenges[kind] = {"key": key, "list": list, "rerolled": false}
	save_all()


static func _fresh(d: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var c := {"id": d["id"], "target": int(d["target"]), "progress": 0, "claimed": false}
	if d.get("faction", false):
		c["faction"] = FACTION_IDS[rng.randi() % FACTION_IDS.size()]
	if d["stat"] == "win_factions":
		c["seen"] = []
	return c


static func _def(kind: String, id: String) -> Dictionary:
	for d in Rules.CHALLENGES[kind]:
		if d["id"] == id:
			return d
	return {}


static func _progress_challenges(add: Dictionary) -> Array:
	## Adds one match to every current challenge; returns the ids that just finished.
	var done := []
	for kind in ["daily", "weekly"]:
		_roll(kind)
		for c in challenges[kind]["list"]:
			if c["claimed"] or int(c["progress"]) >= int(c["target"]):
				continue
			var d := _def(kind, c["id"])
			var stat := str(d.get("stat", ""))
			var v = add.get(stat, 0)
			match stat:
				"win_as":
					v = 1 if v == c.get("faction", "") else 0
				"win_factions":
					var seen: Array = c.get("seen", [])
					if str(v) != "" and not str(v) in seen:
						seen.append(str(v))
					c["seen"] = seen
					v = seen.size() - int(c["progress"])
			c["progress"] = int(c["progress"]) + int(v)
			if int(c["progress"]) >= int(c["target"]):
				done.append(c["id"])
	return done


# ------------------------------------------------------------------ texts
static func amount_text(amount: int, currency := "soft", sign := true) -> String:
	## "+140 SCRAP" / "-1 250 SCRAP" (groups of three, the design docs' style); sign false: "1 250 SCRAP".
	var s := str(absi(amount))
	var g := ""
	while s.length() > 3:
		g = " " + s.substr(s.length() - 3) + g
		s = s.substr(0, s.length() - 3)
	return (("+" if amount >= 0 else "-") if sign else "") + s + g + " " + str(Rules.CURRENCY_SHORT.get(currency, currency.to_upper()))


static func claimable() -> int:
	## Finished, unclaimed challenges (the main menu's CHALLENGES badge).
	var n := 0
	for kind in ["daily", "weekly"]:
		for c in current_challenges(kind):
			if c["done"] and not c["claimed"]:
				n += 1
	return n


static func duration_text(seconds: int) -> String:
	## "13 h 20 min" / "3 d 14 h" (the CHALLENGES page's reset timers).
	var m := int(seconds / 60.0)
	if m >= 24 * 60:
		return "%d d %d h" % [m / (24 * 60), (m / 60) % 24]
	return "%d h %02d min" % [m / 60, m % 60] if m >= 60 else "%d min" % maxi(m, 1)


static func third_skill_line() -> String:
	## The tutorial's final screen: said only when the SCRAP really covers a skill.
	return "Enough SCRAP for a 3rd skill - ARMIES" if balance("soft") >= int(Rules.PRICES["skill"]["soft"]) else ""


static func _now() -> int:
	return now_override if now_override >= 0 else int(Time.get_unix_time_from_system())
