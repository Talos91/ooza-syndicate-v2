class_name MissionDirector
extends RefCounted
## One campaign mission in play (CAMPAIGN-DESIGN.md §4 / §5 / §7b): stages the board, tracks the objective (what
## wins and what loses), the par clock, the start nodes (★★★) and the optional objective, and says when the mission
## is over. Pure Sim logic, like TutorialDirector: no Node, headless-testable (tests/test_mission.gd). The rival
## stays a normal SeatAI at the mission's level (main.gd); nothing here scripts a seat.
##
##   MissionDirector.new(key)       the mission (Campaign.mission(key)); a test may pass its own mission dict
##   pin_settings(pins)             before sim.setup (main): the match settings the mission / lesson plays with -
##                                  never SETUP's or a room's (audit 2026-09-28); put back by restore_settings()
##   begin(sim, map, seat)          right after sim.setup: stage.rival_units (shown units) onto the rival's home,
##                                  the mission's pins (mission_pins: ABILITIES on, LAST STAND on, stage.hide_counts),
##                                  remembers the nodes `seat` starts with; state "briefing"
##   start()                        the briefing's START: the objective runs from here
##   step(dt)                       every frame after sim.step: reads sim.events, objective.collapse_at
##                                  (sim.start_last_stand_now()), decides win / lose
##   on_event(ev)                   every sim.fx_events entry (only a pulse for the HUD: counts come from sim.events)
##   on_captured(node, new_owner, old_owner)   main's hook
##   signals: changed (a counter moved), completed(result)
##       result = {key, won, time, stars, objective, lost_start, reason}
##   readouts for the HUD: objective_line(), par_line(), optional_line(), optional_ok(), optional_locked(), pulse
## Objectives (m.objective.kind): conquest (you win the match), drops {n, limit} (rival units your relays drop into
## the void reach n; lose at the limit), survive {t} (still in at t), monster_take (your monster takes a node),
## outlast {collapse_at, n} (win the collapse with n+ units). Every kind loses when you are out, when the rival
## wins, or when objective.limit passes; a match that ends before a non-conquest objective is met is lost.
## Optional objectives (m.optional.kind): no_vat_lost, drops_fires {n, fires}, machinegoon_t3, before_ultimate,
## no_skill {skill}, monster_kicks {n}, units_at_end {n}, fires {n}, home_kept; an unknown kind is never met.
## A node counts as lost when it is captured from you (handovers included); a Last Stand drop is not a loss to the
## rival and does not count (the conservative reading: the docs are silent - reported to Daniele).

signal changed
signal completed(result: Dictionary)

const HUMAN := "A"
const PULSE := 0.6                                   # seconds the objective line glows when its progress moves

const PIN_KEYS := ["abilities_on", "last_stand", "hide_enemy_counts"]   # the Rules match settings pin_settings() may pin
static var _pinned_before := {}                      # those Rules settings before a mission / lesson pinned its own

var key := ""
var m: Dictionary = {}
var sim: Sim
var map: Dictionary
var seat := HUMAN
var state := "idle"                                  # idle / briefing / running / complete
var result := {}
var version := 0
var pulse := 0.0                                     # > 0: the objective line just moved (the HUD glows it)
var start_nodes: Array = []                          # node ids `seat` owned at begin()
var lost_start := false                              # one of them was captured (★★★ gone)
var vat_lost := false
var home_lost := false
var drops := 0.0                                     # rival units (internal) your relays dropped into the void
var drops_fires_at := -1                             # drops_fires: relay fires used when the drops reached its n
var fires := 0                                       # your relay fires
var kicks := 0.0                                     # rival units (internal) your monster kicked off the decks
var monster_took := false
var rival_ult := false                               # a rival seat cast its ultimate
var skills_cast := {}                                # your skill ids cast
var collapse_started := false
var _ev_cursor := 0


func _init(k := "", data := {}) -> void:
	key = k
	m = data.duplicate(true) if not data.is_empty() else Campaign.mission(k)


func objective() -> Dictionary:
	return m.get("objective", {})


func optional() -> Dictionary:
	return m.get("optional", {})


func par() -> float:
	return float(m.get("par", 0.0))


# ---------------------------------------------------------------- staging
func begin(s: Sim, mp: Dictionary, player_seat := HUMAN) -> void:
	sim = s
	map = mp
	seat = player_seat
	var stage: Dictionary = m.get("stage", {})
	var extra := float(stage.get("rival_units", 0))
	if extra > 0.0:                                  # shown units, like every number in the data (Rules.shown)
		for rs in _rival_seats():
			if sim.homes.has(rs):
				var h: Dictionary = sim.nodes[int(sim.homes[rs])]
				h["units"] = float(h["units"]) + extra * Rules.SCALE
	pin_settings(mission_pins(m))                    # (main pinned them before sim.setup already; tests pin here)
	sim.abilities_on = Rules.abilities_on
	start_nodes = []
	for n in sim.nodes:
		if n["owner"] == seat:
			start_nodes.append(int(n["id"]))
	_ev_cursor = sim.events.size()
	state = "briefing"
	_bump()


static func mission_pins(mission: Dictionary) -> Dictionary:
	## A mission's own match settings (audit 2026-09-28, a bug fix: SETUP's toggles or a room's used to leak in):
	## ABILITIES on and LAST STAND on unless its stage says otherwise (stage.abilities / stage.last_stand), HIDDEN
	## COUNTS only for a blind mission (stage.hide_counts).
	var stage: Dictionary = mission.get("stage", {})
	return {"abilities_on": bool(stage.get("abilities", true)), "last_stand": bool(stage.get("last_stand", true)),
			"hide_enemy_counts": bool(stage.get("hide_counts", false))}


static func pin_settings(pins: Dictionary) -> void:
	## Set these Rules match settings (PIN_KEYS) for the mission / lesson about to play; the first pin remembers the
	## player's own values for restore_settings().
	for k in pins:
		if not k in PIN_KEYS:
			continue
		if not _pinned_before.has(k):
			_pinned_before[k] = _setting(k)
		_set_setting(k, bool(pins[k]))


static func restore_settings() -> void:
	## main._ready: whatever a mission or a lesson pinned goes back to the player's own setting.
	for k in _pinned_before:
		_set_setting(k, bool(_pinned_before[k]))
	_pinned_before = {}


static func _setting(k: String) -> bool:
	match k:
		"abilities_on":
			return Rules.abilities_on
		"last_stand":
			return Rules.last_stand
	return Rules.hide_enemy_counts


static func _set_setting(k: String, v: bool) -> void:
	match k:
		"abilities_on":
			Rules.abilities_on = v
		"last_stand":
			Rules.last_stand = v
		"hide_enemy_counts":
			Rules.hide_enemy_counts = v


func start() -> void:
	if state == "briefing":
		state = "running"
		_bump()


func _rival_seats() -> Array:
	var out := []
	for s in sim.factions.keys():
		if not sim.allied(str(s), seat):
			out.append(str(s))
	return out


# ---------------------------------------------------------------- the frame
func step(_dt: float) -> void:
	if state != "running" or sim == null:
		return
	if pulse > 0.0:
		pulse = maxf(pulse - _dt, 0.0)
	_scan_events()
	var o := objective()
	if o.has("collapse_at") and not collapse_started and sim.time >= float(o["collapse_at"]):
		collapse_started = true
		sim.start_last_stand_now()
		_bump()
	_resolve()


func _resolve() -> void:
	var o := objective()
	if sim.is_out(seat):
		_complete(false, "out")
		return
	var ours := sim.over and sim.winner != "" and sim.allied(sim.winner, seat)
	if sim.over and not ours:
		_complete(false, "rival_won" if sim.winner != "" else "draw")
		return
	match str(o.get("kind", "conquest")):
		"drops":
			if Rules.shown_f(drops) >= float(o.get("n", 0)):
				_complete(true, "drops")
				return
		"survive":
			if sim.time >= float(o.get("t", 0.0)):
				_complete(true, "survived")
				return
			if ours:
				_complete(true, "conquest")
				return
		"monster_take":
			if monster_took:
				_complete(true, "monster_take")
				return
		"outlast":
			if ours:
				var left := Rules.shown(sim.seat_strength(seat))
				_complete(left >= int(o.get("n", 0)), "outlast" if left >= int(o.get("n", 0)) else "too_few")
				return
		_:
			if ours:
				_complete(true, "conquest")
				return
	if ours:                                         # the match is over and won, but this objective was not met
		_complete(false, "objective")
		return
	if float(o.get("limit", 0.0)) > 0.0 and sim.time >= float(o["limit"]):
		_complete(false, "limit")


func _complete(won: bool, reason: String) -> void:
	state = "complete"
	var t := sim.time
	if reason == "survived":                         # won at the whistle itself (a hold mission's par is its t:
		t = minf(t, float(objective().get("t", t)))  # the frame's overshoot must not cost the second star)
	result = {"key": key, "won": won, "time": t, "stars": Campaign.stars_for(won, t, par(), lost_start),
		"objective": won and optional_ok(), "lost_start": lost_start, "reason": reason}
	_bump()
	completed.emit(result)


func finish_now(won: bool, objective_met := won, lost := false) -> void:
	## Screenshots / tests only: end the mission now with this outcome (the optional objective forced).
	if state == "complete" or sim == null:
		return
	lost_start = lost
	state = "complete"
	var t := sim.time
	result = {"key": key, "won": won, "time": t, "stars": Campaign.stars_for(won, t, par(), lost_start),
		"objective": won and objective_met, "lost_start": lost_start, "reason": "forced"}
	_bump()
	completed.emit(result)


# ---------------------------------------------------------------- events
func _scan_events() -> void:
	var moved := false
	var op := optional()
	while _ev_cursor < sim.events.size():
		var ev: Dictionary = sim.events[_ev_cursor]
		_ev_cursor += 1
		var who := str(ev.get("seat", ""))
		match str(ev.get("type", "")):
			"fall":                                  # a relay's deck went from under a rival line: your drop
				if str(ev.get("why", "")) == "relay" and str(ev.get("by", "")) == seat and who != "" \
						and not sim.allied(who, seat):
					drops += float(ev.get("units", 0.0))
					moved = true
					if drops_fires_at < 0 and str(op.get("kind", "")) == "drops_fires" \
							and Rules.shown_f(drops) >= float(op.get("n", 0)):
						drops_fires_at = fires
			"relay_fired":
				if who == seat:
					fires += 1
					moved = true
			"skill":
				if who == seat:
					skills_cast[str(ev.get("id", ""))] = true
				elif who != "" and not sim.allied(who, seat) and str(ev.get("slot", "")) == "ultimate":
					rival_ult = true
				moved = true
			"monster_kick":
				if who == seat and not sim.allied(str(ev.get("seat_hit", "")), seat):
					kicks += float(ev.get("units", 0.0))
					moved = true
			"monster_take":
				if who == seat and not bool(ev.get("friendly", false)):
					monster_took = true
					moved = true
			"capture", "handover":
				if str(ev.get("from", "")) == seat and who != seat:
					_lost(int(ev.get("node", -1)))
					moved = true
	if moved:
		pulse = PULSE
		_bump()


func on_event(ev: Dictionary) -> void:
	## main: every sim.fx_events entry. The counts come from sim.events (they carry who fired the relay); a fall
	## or fling of rival units only makes the objective line glow as it lands.
	if state != "running" or sim == null:
		return
	if str(ev.get("type", "")) in ["fall", "fling"] and str(ev.get("by", "")) == seat \
			and not sim.allied(str(ev.get("seat", "")), seat):
		pulse = PULSE


func on_captured(node_id: int, new_owner: String, old_owner: String) -> void:
	if sim != null and old_owner == seat and new_owner != seat:
		_lost(node_id)


func _lost(node_id: int) -> void:
	if node_id < 0 or node_id >= sim.nodes.size():
		return
	if node_id in start_nodes:
		lost_start = true
	if Sim.has_vat(sim.nodes[node_id]):              # (a capture keeps the structure, one tier down)
		vat_lost = true
	if sim.homes.has(seat) and int(sim.homes[seat]) == node_id:
		home_lost = true


func _bump() -> void:
	version += 1
	changed.emit()


# ---------------------------------------------------------------- optional objective
func optional_ok() -> bool:
	## Would the optional objective count if the mission were won right now? (The HUD's live ✓ / ✗.)
	var op := optional()
	match str(op.get("kind", "")):
		"no_vat_lost":
			return not vat_lost
		"drops_fires":
			return drops_fires_at >= 0 and drops_fires_at <= int(op.get("fires", 0))
		"machinegoon_t3":
			return _has_machinegoon(3)
		"before_ultimate":
			return not rival_ult
		"no_skill":
			return not skills_cast.has(str(op.get("skill", "")))
		"monster_kicks":
			return Rules.shown_f(kicks) >= float(op.get("n", 0))
		"units_at_end":
			return Rules.shown(sim.seat_strength(seat)) >= int(op.get("n", 0)) if sim else false
		"fires":
			return fires >= int(op.get("n", 0))
		"home_kept":
			return not home_lost
	return false


func optional_locked() -> bool:
	## The optional objective can no longer be met this run (the HUD dims it).
	var op := optional()
	match str(op.get("kind", "")):
		"no_vat_lost":
			return vat_lost
		"drops_fires":
			return drops_fires_at < 0 and fires > int(op.get("fires", 0))
		"before_ultimate":
			return rival_ult
		"no_skill":
			return skills_cast.has(str(op.get("skill", "")))
		"home_kept":
			return home_lost
		"":
			return true
	return not str(op.get("kind", "")) in ["drops_fires", "machinegoon_t3", "monster_kicks", "units_at_end", "fires"]


func _has_machinegoon(tier: int) -> bool:
	if sim == null:
		return false
	for n in sim.nodes:
		if n["owner"] == seat and n["structure"] == "machinegoon" and int(n["tier"]) >= tier:
			return true
	return false


# ---------------------------------------------------------------- readouts (the HUD)
static func clock(t: float) -> String:
	var s := int(ceil(maxf(t, 0.0)))
	return "%d:%02d" % [s / 60, s % 60]


func objective_line() -> String:
	## The objective with its live progress, under the match clock: "DROPS 23 / 60 · 3:12 left".
	if sim == null:
		return Campaign.objective_text(m)
	var o := objective()
	var line := ""
	match str(o.get("kind", "conquest")):
		"drops":
			line = "DROPS %d / %d" % [mini(Rules.shown(drops), int(o.get("n", 0))), int(o.get("n", 0))]
		"survive":
			line = "HOLD UNTIL %s · %s left" % [clock(float(o.get("t", 0.0))), clock(float(o.get("t", 0.0)) - sim.time)]
		"monster_take":
			line = "TAKE A NODE WITH YOUR MONSTER"
		"outlast":
			line = "WIN WITH %d+ UNITS · %d now" % [int(o.get("n", 0)), Rules.shown(sim.seat_strength(seat))]
		_:
			var left := 0
			for n in sim.nodes:
				if n["owner"] != "" and not sim.allied(n["owner"], seat):
					left += 1
			line = "TAKE EVERY RIVAL NODE · %d left" % left
	if o.has("collapse_at") and not collapse_started:
		line += " · collapse in %s" % clock(float(o["collapse_at"]) - sim.time)
	if float(o.get("limit", 0.0)) > 0.0:
		line += " · %s left" % clock(float(o["limit"]) - sim.time)
	return line


func par_line() -> String:
	## "PAR 4:00 · 1:12 left" / "PAR 4:00 · over" (+ "start node lost" once ★★★ is gone).
	if par() <= 0.0:
		return ""
	var t := sim.time if sim else 0.0
	var line := "PAR %s · %s" % [clock(par()), ("%s left" % clock(par() - t)) if t <= par() else "over"]
	if lost_start:
		line += " · start node lost"
	return line


func optional_line() -> String:
	## The optional objective's text with its live count where it has one.
	var op := optional()
	var text := str(op.get("text", ""))
	match str(op.get("kind", "")):
		"drops_fires":
			var used := drops_fires_at if drops_fires_at >= 0 else fires
			text += " (%d / %d · fires %d / %d)" % [mini(Rules.shown(drops), int(op.get("n", 0))), int(op.get("n", 0)),
					used, int(op.get("fires", 0))]
		"monster_kicks":
			text += " (%d / %d)" % [mini(Rules.shown(kicks), int(op.get("n", 0))), int(op.get("n", 0))]
		"units_at_end":
			text += " (%d now)" % (Rules.shown(sim.seat_strength(seat)) if sim else 0)
		"fires":
			text += " (%d / %d)" % [mini(fires, int(op.get("n", 0))), int(op.get("n", 0))]
	return text
