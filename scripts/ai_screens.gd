class_name AiScreens
extends Control
## hud-43 AI SCREENS (Daniele 11-18 screen layout: "AI moods on the AI screens, no top banners"): two screens in the top corners of his
## frame, tilted -12 / +12 deg, each the faction AI's screen (Daniele's 2026-11-17 frame + the ai-clean AI) + its MOOD on a cream plate.
## Who shows: 1v1 = left you (your faction's AI), right the enemy AI. 2v2 = left your team, right the other team (the face = the team
## seat the reaction is about). FFA = left you, right the AI with the biggest reaction (queued, biggest first).
##
## AI REACTIONS (ai-reactions 2026-11-18, Daniele: "ai reactions lets implement more now is too flat"): the screen is drawn from LAYERS
## (assets/art/ui/ai_layers, tools/prep_ai_layers.py: glass, glitch, glow, body, eyes, shut eyes, frame), so a reaction animates the
## face itself: squash / bounce / sag the body inside the glass, squint / widen / tilt / shut / look with the eyes, glitch tears and
## scanlines in the AI colour, a neon flare round the frame in the SEAT colour (neon = seat), a small emote glyph and a short line on
## the plate in the AI's own voice (WORLD-LORE-2026-11 §4 vocabulary). Every reaction is in REACT (table below) and each faction plays
## it with its personality (PERSONA: energy, glitchiness, emotes). Live match events feed it: captures (Hud.ai_event), and sim.events
## (skills cast / hit, armies destroyed, eliminations, Last Stand, the end), plus the share of the map every 0.5 s (swings, near win /
## near loss, idle taunts). THROTTLE: a priority queue per screen, at most one reaction start per screen every GAP s, per-reaction
## cooldowns, stale entries dropped; the match end / out always go through. The screen keeps its footprint (hud43 zones ai_l / ai_r).

const TILT := 12.0
const GAP := 2.0                 # s (match time) between two reaction starts on one screen (brief: "at most 1 per AI every ~2 s")
const STALE := 3.5               # s a queued reaction waits before it is dropped
const IDLE_TAUNT := 10.0         # s without a reaction before the screen taunts
const PLATE_FONT_PT := 12.5     # the plate line (the 12.5 pt floor), in the HUD unit: the screen zone is AI_H_PT tall
const AI_H_PT := 65.0            # hud43 ai_l / ai_r height (min(AI_PT.y, 66 + 2 - AI_Y))
const PLATE_TEXT_X := 0.5        # text start, in plate heights
const PLATE_LAMP := Vector2(0.1, 0.28)   # lamp x, size (plate heights)
const C := 384.0                 # the layer canvas (tools/prep_ai_layers.py SCREEN_PX)
const MID := Vector2(192, 192)
const LAYERS := "res://assets/art/ui/ai_layers/"
const GLITCH := {"vex": Color8(25, 229, 255), "ember": Color8(255, 120, 30), "solar": Color8(255, 190, 25),
		"bloom": Color8(111, 255, 42), "null": Color8(255, 25, 171)}
const MOODS := {
	"CALM": [Color("e7b68b"), "CALM"],
	"SMUG": [Color("f3c969"), "SMUG"],
	"GLEE": [Color("8be38b"), "GLEE!"],
	"RAGE": [Color("ff5b5b"), "RAGE!"],
	"PANIC": [Color("ff9a3c"), "PANIC"],
	"SHOCK": [Color("f4f0ff"), "HIT!"],
	"OUT": [Color("8a7f86"), "OFFLINE"],
}
## REACTION TABLE: id -> mood (plate lamp), dur s, prio (higher wins the queue), cd s (same reaction on that screen), body motion,
## eyes, glitch 0..1, flare 0..1 (seat neon), emote kind, flash colour. Personas scale and swap these per faction.
const REACT := {
	"BOOT":      {"mood": "CALM",  "dur": 2.2, "prio": 5, "cd": 99.0, "body": "pop",    "eyes": "wake",   "glitch": 1.0, "flare": 0.8, "emote": ""},
	"TAKE":      {"mood": "GLEE",  "dur": 1.6, "prio": 2, "cd": 4.0,  "body": "bounce", "eyes": "happy",  "glitch": 0.0, "flare": 0.6, "emote": "happy"},
	"LOST":      {"mood": "RAGE",  "dur": 1.8, "prio": 3, "cd": 4.0,  "body": "shake",  "eyes": "angry",  "glitch": 0.5, "flare": 0.3, "emote": "anger", "flash": Color(1, 0.35, 0.35)},
	"ARMY_WON":  {"mood": "GLEE",  "dur": 1.8, "prio": 3, "cd": 6.0,  "body": "hop",    "eyes": "happy",  "glitch": 0.0, "flare": 0.9, "emote": "happy"},
	"ARMY_LOST": {"mood": "PANIC", "dur": 2.0, "prio": 3, "cd": 6.0,  "body": "squash", "eyes": "wide",   "glitch": 0.8, "flare": 0.0, "emote": "sweat"},
	"CAST":      {"mood": "SMUG",  "dur": 1.6, "prio": 2, "cd": 6.0,  "body": "lean",   "eyes": "squint", "glitch": 0.2, "flare": 1.0, "emote": "bang"},
	"HIT":       {"mood": "SHOCK", "dur": 1.8, "prio": 4, "cd": 4.0,  "body": "squash", "eyes": "shock",  "glitch": 1.0, "flare": 0.2, "emote": "bang", "flash": Color(1, 1, 1), "shake": 1.0},
	"SURGE":     {"mood": "SMUG",  "dur": 1.8, "prio": 2, "cd": 10.0, "body": "sway",   "eyes": "lid",    "glitch": 0.0, "flare": 0.5, "emote": "taunt"},
	"SLUMP":     {"mood": "PANIC", "dur": 2.0, "prio": 3, "cd": 10.0, "body": "sag",    "eyes": "sad",    "glitch": 0.3, "flare": 0.0, "emote": "sweat"},
	"NEARWIN":   {"mood": "SMUG",  "dur": 2.4, "prio": 3, "cd": 25.0, "body": "sway",   "eyes": "lid",    "glitch": 0.0, "flare": 0.8, "emote": "happy"},
	"NEARLOSS":  {"mood": "PANIC", "dur": 2.4, "prio": 3, "cd": 20.0, "body": "jitter", "eyes": "darting", "glitch": 0.6, "flare": 0.0, "emote": "sweat", "flash": Color(1, 0.6, 0.25)},
	"TAUNT":     {"mood": "SMUG",  "dur": 2.0, "prio": 1, "cd": 12.0, "body": "hop",    "eyes": "look",   "glitch": 0.0, "flare": 0.3, "emote": "taunt"},
	"ALARM":     {"mood": "PANIC", "dur": 2.2, "prio": 3, "cd": 30.0, "body": "jitter", "eyes": "wide",   "glitch": 0.7, "flare": 0.0, "emote": "bang", "flash": Color(1, 0.3, 0.3)},
	"KO":        {"mood": "GLEE",  "dur": 2.0, "prio": 4, "cd": 3.0,  "body": "hop",    "eyes": "happy",  "glitch": 0.0, "flare": 1.0, "emote": "happy"},
	"WIN":       {"mood": "GLEE",  "dur": 9999.0, "prio": 7, "cd": 9999.0, "body": "bounce", "eyes": "happy", "glitch": 0.0, "flare": 0.7, "emote": "happy"},
	"LOSE":      {"mood": "OUT",   "dur": 9999.0, "prio": 6, "cd": 9999.0, "body": "sag",    "eyes": "shut",  "glitch": 0.6, "flare": 0.0, "emote": "sweat"},
	"OUT":       {"mood": "OUT",   "dur": 3.0, "prio": 6, "cd": 9999.0, "body": "sag",    "eyes": "shut",  "glitch": 0.5, "flare": 0.0, "emote": ""},
}
## PERSONA per faction (WORLD-LORE-2026-11 §4 voices): energy (body motion), glitch (tears), eyes (how far the eyes move), split (two eyes
## that tilt apart for anger / sadness), emotes (kind -> glyph), and the plate lines in its own voice (no new names).
const PERSONA := {
	"vex": {"energy": 1.35, "glitch": 1.0, "eyes": 1.0, "split": false,
		"emotes": {"happy": "spark", "anger": "anger", "sweat": "sweat", "bang": "bang", "taunt": "ask"},
		"lines": {"BOOT": "BETA!", "TAKE": "SHIPPED", "LOST": "OOPS.", "ARMY_WON": "SCALE!", "ARMY_LOST": "PIVOT!", "CAST": "HYPE!", "HIT": "BUG?!", "SURGE": "GROWTH", "SLUMP": "PIVOT?", "NEARWIN": "DISRUPT", "NEARLOSS": "v0.9!", "TAUNT": "SHIP IT", "ALARM": "HOTFIX", "KO": "LEGACY", "WIN": "LAUNCH!", "LOSE": "SUNSET.", "OUT": "OFFLINE"}},
	"ember": {"energy": 0.6, "glitch": 0.7, "eyes": 0.6, "split": false,
		"emotes": {"happy": "spark", "anger": "anger", "sweat": "sweat", "bang": "bang", "taunt": "bang"},
		"lines": {"BOOT": "SHIFT!", "TAKE": "OUTPUT", "LOST": "DELAY.", "ARMY_WON": "100 %", "ARMY_LOST": "FUEL.", "CAST": "FIRE!", "HIT": "FAULT.", "SURGE": "ON TIME", "SLUMP": "BEHIND", "NEARWIN": "MAX OUT", "NEARLOSS": "HOT!", "TAUNT": "IDLE?", "ALARM": "HALT!", "KO": "BURNED", "WIN": "QUOTA!", "LOSE": "CLOSED.", "OUT": "OFFLINE"}},
	"solar": {"energy": 0.35, "glitch": 0.5, "eyes": 0.7, "split": false,
		"emotes": {"happy": "check", "anger": "cross", "sweat": "sweat", "bang": "bang", "taunt": "check"},
		"lines": {"BOOT": "POLICY", "TAKE": "FILED.", "LOST": "DENIED", "ARMY_WON": "AUDITED.", "ARMY_LOST": "INQUIRY.", "CAST": "FORM 4.7", "HIT": "OBJECT!", "SURGE": "IN ORDER", "SLUMP": "REVIEW", "NEARWIN": "FINAL.", "NEARLOSS": "APPEAL!", "TAUNT": "FORMS?", "ALARM": "POLICY!", "KO": "CLASSED", "WIN": "PASSED.", "LOSE": "VOID.", "OUT": "OFFLINE"}},
	"bloom": {"energy": 1.2, "glitch": 0.6, "eyes": 1.0, "split": true,
		"emotes": {"happy": "heart", "anger": "anger", "sweat": "sweat", "bang": "bang", "taunt": "heart"},
		"lines": {"BOOT": "THRIVE!", "TAKE": "HELLO!", "LOST": "OUCH...", "ARMY_WON": "GROWTH!", "ARMY_LOST": "BREATHE", "CAST": "HUGS!", "HIT": "RUDE!", "SURGE": "ENGAGED", "SLUMP": "SURVEY?", "NEARWIN": "SO WELL", "NEARLOSS": "BURNOUT", "TAUNT": "HUG?", "ALARM": "CALM!", "KO": "REHOMED", "WIN": "WE WIN!", "LOSE": "SAD.", "OUT": "OFFLINE"}},
	"null": {"energy": 0.75, "glitch": 1.7, "eyes": 0.8, "split": true,
		"emotes": {"happy": "coin", "anger": "anger", "sweat": "ask", "bang": "bang", "taunt": "coin"},
		"lines": {"BOOT": "N/A", "TAKE": "MARGIN.", "LOST": "LOSS.", "ARMY_WON": "PROFIT.", "ARMY_LOST": "EXPOSED", "CAST": "DENY.", "HIT": "DENIED.", "SURGE": "MARGIN+", "SLUMP": "...", "NEARWIN": "BOUGHT.", "NEARLOSS": "LIQUID?", "TAUNT": "PAY UP.", "ALARM": "SELL!", "KO": "ACQUIRE", "WIN": "OWNED.", "LOSE": "BUST.", "OUT": "N/A"}},
}
## the old dev moods (--ai-mood=RAGE,GLEE) -> reactions
const OLD_MOOD := {"GLEE": "TAKE", "RAGE": "LOST", "PANIC": "NEARLOSS", "SMUG": "NEARWIN", "OUT": "OUT"}

static var _boxes := {}
static var _tex := {}

var hud
var sides: Array = []                       # [[seats...], [seats...]]: left, right
var ffa := false
var shown := ["", ""]                       # the seat each screen shows now
var mood := ["CALM", "CALM"]                # the baseline mood (share of the map) when no reaction plays
var cur := ["", ""]                         # the reaction playing on each screen ("" = none)
var cur_t := [0.0, 0.0]                     # its age (s, real time: the animation clock)
var started := [-99.0, -99.0]               # match time of the last start (the throttle)
var queue := [[], []]                       # per screen: [{id, seat, prio, at}]
var cds := [{}, {}]                         # per screen: reaction id -> match time it may play again
var log_: Array = []                        # [match t, screen, id, seat] every start (tests / the spam check)
var loop_dev := ["", ""]                    # dev shots: --ai-react=ID,ID plays forever (restarts)
var dev_phase: Array = []                   # dev shots: --ai-react-t=0.15,0.6,1.2 --ai-react-from=6: the pose frozen at that age, one per s
var dev_from := 6.0
var dev_face: Array = []
var _t := 0.0
var _acc := 0.0
var _ev_i := 0
var _hist := {}                             # seat -> [ratio samples, every 0.5 s] (share swings)
var _booted := false
var _ended := false
var rects := [Rect2(), Rect2()]
var rigs: Array = []                        # per screen: {rig, flare, glass, face, front, plate}
var rng := RandomNumberGenerator.new()


func setup(h) -> void:
	hud = h
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rng.seed = 7
	var groups: Array = hud._seat_groups()
	var me := str(hud.human)
	ffa = groups.size() > 2
	if ffa:
		var others := []
		for g in groups:
			for s in g:
				if str(s) != me:
					others.append(str(s))
		sides = [[me], others]
	else:
		sides = [groups[0].map(func(s): return str(s)), (groups[1] if groups.size() > 1 else groups[0]).map(func(s): return str(s))]
	shown = [str(sides[0][0]), str(sides[1][0])]
	_build_rigs()
	if hud.sim != null:
		_ev_i = hud.sim.events.size()
	for a in OS.get_cmdline_user_args():      # dev shots: --ai-mood=RAGE,GLEE (left, right) / --ai-react=HIT,TAKE (loops)
		if a.begins_with("--ai-mood=") or a.begins_with("--ai-react="):
			var v := a.substr(a.find("=") + 1).split(",")
			for i in range(mini(2, v.size())):
				var id: String = OLD_MOOD.get(v[i], v[i])
				if REACT.has(id):
					loop_dev[i] = id
		elif a.begins_with("--ai-react-t="):
			for v in a.substr(13).split(","):
				dev_phase.append(float(v))
		elif a.begins_with("--ai-react-from="):
			dev_from = float(a.substr(16))
		elif a.begins_with("--ai-face="):            # dev shots: --ai-face=bloom,ember (left, right faction faces)
			dev_face = Array(a.substr(10).split(","))


static func _layer(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(LAYERS + name + ".png") if ResourceLoader.exists(LAYERS + name + ".png") else null
	return _tex[name]


static func _box(name: String) -> Rect2:
	if _boxes.is_empty():
		var f := FileAccess.open(LAYERS + "layers.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				for k in d["boxes"]:
					var b: Array = d["boxes"][k]
					_boxes[k] = Rect2(b[0], b[1], b[2], b[3])
	return _boxes.get(name, Rect2())


func _build_rigs() -> void:
	## Per screen: rig (position + tilt) > flare (seat neon behind the frame, additive) > glass (clips the face to the glass) > face >
	## front (the frame + emote) > plate (the mood plate, in screen units).
	for i in range(2):
		var rig := Node2D.new()
		add_child(rig)
		var flare := Node2D.new()
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		flare.material = add
		var glass := Node2D.new()
		glass.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		var face := Node2D.new()
		var front := Node2D.new()
		var shine := Node2D.new()
		shine.material = add
		var plate := Node2D.new()
		for n in [flare, glass, front, shine, plate]:
			rig.add_child(n)
		glass.add_child(face)
		flare.draw.connect(_draw_flare.bind(i, flare))
		glass.draw.connect(_draw_glass.bind(glass))
		face.draw.connect(_draw_face.bind(i, face))
		front.draw.connect(_draw_front.bind(i, front))
		shine.draw.connect(_draw_flare.bind(i, shine))
		plate.draw.connect(_draw_plate.bind(i, plate))
		rigs.append({"rig": rig, "flare": flare, "glass": glass, "face": face, "front": front, "shine": shine, "plate": plate})


func lay(l: Rect2, r: Rect2) -> void:
	rects = [l, r]
	queue_redraw()


func _side_of(seat: String) -> int:
	if seat in sides[0]:
		return 0
	if seat in sides[1]:
		return 1
	return -1


func _faction(seat: String) -> String:
	if not dev_face.is_empty():
		var k := _side_of(seat)
		if k >= 0 and k < dev_face.size() and PERSONA.has(dev_face[k]):
			return dev_face[k]
	var f := str(hud.sim.factions.get(seat, "vex")) if hud and hud.sim else "vex"
	return f if PERSONA.has(f) else "vex"


func _now() -> float:
	return float(hud.sim.time) if hud and hud.sim else _t


# ------------------------------------------------------------------ the queue (THROTTLE)
func react(seat: String, id: String, bonus := 0) -> void:
	## Ask for a reaction on the seat's screen. It waits in that screen's queue; _pump starts the best one when the screen may.
	var i := _side_of(seat)
	if i < 0 or not REACT.has(id) or (_ended and int(REACT[id]["prio"]) < 6):
		return
	if hud.sim != null and hud._seat_out(seat) and id != "OUT" and id != "LOSE":
		return
	var q: Array = queue[i]
	for e in q:                                      # one entry per seat + reaction: the newest wins
		if e["id"] == id and e["seat"] == seat:
			e["at"] = _now()
			return
	q.append({"id": id, "seat": seat, "prio": int(REACT[id]["prio"]) + bonus, "at": _now()})
	if q.size() > 6:
		q.sort_custom(func(a, b): return a["prio"] > b["prio"])
		q.resize(6)


func _pump(i: int) -> void:
	var now := _now()
	var q: Array = queue[i]
	for k in range(q.size() - 1, -1, -1):            # stale / cooling entries go
		var e: Dictionary = q[k]
		if (int(e["prio"]) < 6 and now - float(e["at"]) > STALE) or now < float(cds[i].get(e["id"] + "|" + e["seat"], -1.0)):
			q.remove_at(k)
	if q.is_empty():
		return
	q.sort_custom(func(a, b): return a["prio"] > b["prio"] or (a["prio"] == b["prio"] and a["at"] > b["at"]))
	var best: Dictionary = q[0]
	var playing: bool = cur[i] != "" and cur_t[i] < float(REACT[cur[i]]["dur"])
	var cur_p: int = int(REACT[cur[i]]["prio"]) if cur[i] != "" else -1
	if playing and cur_p >= 6 and (int(best["prio"]) < cur_p or (best["id"] == cur[i] and best["seat"] == shown[i])):   # nothing replaces the end / an out (but LOSE follows an OUT)
		q.pop_front()
		return
	if int(best["prio"]) < 6:
		if now - float(started[i]) < GAP:
			return
		if playing and int(best["prio"]) <= cur_p:
			return
	q.pop_front()
	_start(i, best["id"], best["seat"])


func _start(i: int, id: String, seat: String) -> void:
	cur[i] = id
	cur_t[i] = 0.0
	shown[i] = seat
	started[i] = _now()
	cds[i][id + "|" + seat] = _now() + float(REACT[id]["cd"])
	log_.append([snappedf(_now(), 0.01), i, id, seat])
	if log_.size() > 4000:
		log_.pop_front()


# ------------------------------------------------------------------ the events
func on_capture(new_owner: String, old_owner: String, units: float) -> void:
	## A node changed hands (Hud.ai_event): the taker gloats, the loser rages (an AI that took it from YOU: the biggest).
	var me := str(hud.human)
	var big := 1 if units >= 30.0 else 0
	if new_owner != "":
		react(new_owner, "TAKE", big + (1 if old_owner == me else 0))
	if old_owner != "":
		react(old_owner, "LOST", big)


func on_out(seat: String) -> void:
	react(seat, "OUT")


func event(seat: String, m: String, _weight := 1.0) -> void:
	## (old API) a mood for a seat: mapped to its reaction.
	react(seat, OLD_MOOD.get(m, m))


func _rivals_of(seat: String) -> Array:
	var out := []
	for s in hud.sim.factions.keys():
		if str(s) == seat:
			continue
		if hud.sim.teams.has(seat) and hud.sim.teams.get(s, -1) == hud.sim.teams.get(seat, -2):
			continue
		out.append(str(s))
	return out


func _read_events() -> void:
	var ev: Array = hud.sim.events
	if _ev_i > ev.size():
		_ev_i = 0
	while _ev_i < ev.size():
		var e: Dictionary = ev[_ev_i]
		_ev_i += 1
		match str(e.get("type", "")):
			"skill":                                     # cast: the caster schemes, every seat it hits is shocked
				var by := str(e.get("seat", ""))
				react(by, "CAST")
				for s in e.get("affects", []):
					if str(s) != by:
						react(str(s), "HIT", 1 if by == str(hud.human) else 0)
			"horde_destroyed":                          # a big army lost (>= 20 % of what the seat holds): it panics, the rivals cheer
				var s := str(e.get("seat", ""))
				var u := float(e.get("units", 0.0))
				if s != "" and u >= 8.0 and u >= 0.2 * (maxf(float(hud.sim.seat_strength(s)), 0.0) + u):
					react(s, "ARMY_LOST")
					var rv := _rivals_of(s)
					if rv.size() <= 2:                     # 1v1 / 2v2: the other side won that fight (FFA: nobody can tell)
						for r in rv:
							react(r, "ARMY_WON")
			"collapse":
				var s := str(e.get("from", ""))
				if s != "":
					react(s, "LOST")
			"hub_destroyed", "forge_lost":
				react(str(e.get("seat", "")), "ARMY_LOST")
			"last_stand":
				for s in hud.sim.factions.keys():
					react(str(s), "ALARM")
			"eliminated":
				var s := str(e.get("seat", ""))
				react(s, "OUT")
				for r in _rivals_of(s):
					react(r, "KO")
			"end":
				_end(str(e.get("winner", "")))


func _end(winner: String) -> void:
	if _ended:
		return
	for s in hud.sim.factions.keys():
		var seat := str(s)
		var won: bool = seat == winner or (winner != "" and hud.sim.teams.has(seat) and hud.sim.teams.get(seat) == hud.sim.teams.get(winner, -9))
		react(seat, "WIN" if won else ("LOSE" if winner != "" else "SLUMP"))
	_ended = true


func _sample() -> void:
	## Every 0.5 s: the baseline mood, share swings, near win / near loss, idle taunts (match time).
	var sim = hud.sim
	var now := _now()
	var all: Array = sides[0] + sides[1]
	var tot := 0.0
	for s in all:
		if sim.factions.has(s) and not hud._seat_out(s):
			tot += maxf(float(sim.seat_strength(s)), 0.0)
	var fair := 1.0 / maxf(float(all.size()), 1.0)
	for s in all:
		if not sim.factions.has(s):
			continue
		if hud._seat_out(s):
			react(s, "OUT")
			continue
		var ratio := ((maxf(float(sim.seat_strength(s)), 0.0) / tot) if tot > 0.0 else fair) / fair
		var h: Array = _hist.get(s, [])
		h.append(ratio)
		if h.size() > 13:
			h.pop_front()
		_hist[s] = h
		if now < 20.0 or h.size() < 13:
			continue
		var d := ratio - float(h[0])
		if d >= 0.4:
			react(s, "SURGE")
		elif d <= -0.4:
			react(s, "SLUMP")
		if ratio >= 1.6:
			react(s, "NEARWIN")
		elif ratio <= 0.4:
			react(s, "NEARLOSS")
	for i in range(2):                               # the baseline mood of the seat on screen (a live teammate replaces an out seat)
		if cur[i] == "" and hud._seat_out(shown[i]):
			for x in sides[i]:
				if sim.factions.has(x) and not hud._seat_out(x):
					shown[i] = str(x)
					break
		var s: String = shown[i]
		if sim.factions.has(s) and hud._seat_out(s):
			mood[i] = "OUT"
		else:
			var r: float = float(_hist.get(s, [1.0]).back())
			mood[i] = "SMUG" if r >= 1.8 else ("PANIC" if r <= 0.6 else "CALM")
		if now - float(started[i]) >= IDLE_TAUNT and queue[i].is_empty() and now > 6.0:
			var alive := (sides[i] as Array).filter(func(x): return sim.factions.has(x) and not hud._seat_out(x))
			if not alive.is_empty():
				react(alive[rng.randi() % alive.size()], "TAUNT")


func _process(dt: float) -> void:
	if hud == null or hud.sim == null:
		return
	var covered: bool = hud.pause_panel != null and hud.pause_panel.visible   # designer 11 FIX 9: PAUSE hides the AI screens it would cut
	visible = not covered
	_t += dt
	if not _booted:
		_booted = true
		if hud.sim.time < 3.0:
			for i in range(2):
				for s in sides[i]:
					if hud.sim.factions.has(s):
						react(str(s), "BOOT")
						break
	_read_events()
	if hud.sim.over:
		_end(str(hud.sim.winner))
	_acc += dt
	if _acc >= 0.5:
		_acc = 0.0
		_sample()
	for i in range(2):
		cur_t[i] += dt
		if loop_dev[i] != "":
			if cur[i] != loop_dev[i] or cur_t[i] > minf(float(REACT[loop_dev[i]]["dur"]), 2.4) + 0.6:
				cur[i] = loop_dev[i]
				cur_t[i] = 0.0
			if not dev_phase.is_empty():
				cur_t[i] = dev_phase[clampi(int(floor(_now() - dev_from)), 0, dev_phase.size() - 1)]
			continue
		if cur[i] != "" and cur_t[i] >= float(REACT[cur[i]]["dur"]):
			cur[i] = ""
		_pump(i)
	_place()


# ------------------------------------------------------------------ the animation
func _env(i: int) -> float:
	## 0..1: the reaction's strength (eases in 0.12 s, out over its last 0.3 s).
	if cur[i] == "":
		return 0.0
	var d: float = REACT[cur[i]]["dur"]
	var t: float = cur_t[i]
	return clampf(t / 0.12, 0.0, 1.0) * clampf((d - t) / 0.3, 0.0, 1.0)


func _pose(i: int) -> Dictionary:
	## The face's pose now: body offset / squash / tilt, eyes, glitch, flare, flash, emote, rig shake.
	var f := _faction(shown[i])
	var P: Dictionary = PERSONA[f]
	var en: float = P["energy"]
	var t: float = cur_t[i]
	var id: String = cur[i]
	var R: Dictionary = REACT.get(id, {})
	var e := _env(i)
	var p := {"off": Vector2.ZERO, "sq": 0.0, "rot": 0.0, "eye_sy": 1.0, "eye_s": 1.0, "eye_off": Vector2.ZERO, "eye_tilt": 0.0,
			"lid": 0.0, "shut": false, "glitch": 0.0, "flare": 0.0, "flash": Color(0, 0, 0, 0), "shake": Vector2.ZERO,
			"glow": 0.85 + 0.15 * sin(_t * 2.2 + i), "grey": false, "emote": ""}
	# idle life: breathing, a blink every ~4 s, a slow glance
	p["sq"] = sin(_t * 2.4 + i * 1.3) * 0.012
	p["shut"] = fmod(_t + i * 1.7, 4.2) < 0.14
	p["eye_off"] = Vector2(sin(_t * 0.7 + i * 2.0) * 3.0, 0.0) * float(P["eyes"])
	match mood[i]:                                    # the baseline mood leans the idle face
		"SMUG": p["lid"] = 0.25; p["rot"] = sin(_t * 1.6) * 0.03
		"PANIC": p["eye_s"] = 1.1; p["off"].x = sin(_t * 31.0) * 1.2 * en
		"OUT": p["grey"] = true; p["shut"] = true; p["glow"] = 0.2; p["glitch"] = 0.25
	if id == "":
		return p
	var body: String = R["body"]
	var w := TAU * t
	match body:
		"pop":                                         # boot: grows in with an overshoot
			var k := clampf(t / 0.55, 0.0, 1.0)
			p["sq"] = (1.0 - k) * -0.5 + sin(k * PI) * 0.12 * en
			p["off"].y = (1.0 - k) * 30.0
		"bounce":
			p["off"].y = -absf(sin(w * 1.6)) * 22.0 * en * e
			p["sq"] = -cos(w * 3.2) * 0.06 * en * e
		"hop":                                         # one big jump, squash on the landing
			var k := clampf(t / 0.7, 0.0, 1.0)
			p["off"].y = -sin(k * PI) * 34.0 * en * e
			p["sq"] = (0.12 * sin(k * PI) - (0.14 * exp(-(t - 0.7) * 9.0) if t > 0.7 else 0.0)) * en * e
		"shake":
			p["off"] = Vector2(sin(_t * 47.0), cos(_t * 39.0)) * 6.0 * en * e
			p["rot"] = sin(_t * 33.0) * 0.05 * en * e
		"squash":                                      # an impact: flattened, then a wobble back
			p["sq"] = -0.22 * exp(-t * 5.0) * cos(t * 18.0) * maxf(en, 0.6) * e
			p["off"].y = 10.0 * exp(-t * 5.0) * e
		"sag":
			p["sq"] = -0.08 * e
			p["off"].y = 12.0 * e
			p["rot"] = (0.06 if i == 0 else -0.06) * e
		"sway":
			p["rot"] = sin(_t * 2.6) * 0.09 * en * e
			p["off"].x = sin(_t * 2.6) * 6.0 * en * e
		"lean":                                        # casting: leans in toward the board
			p["rot"] = (0.12 if i == 0 else -0.12) * e * en
			p["sq"] = 0.05 * e
			p["off"].x = (8.0 if i == 0 else -8.0) * e
		"jitter":
			p["off"] = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 4.0 * en * e
	var ey: float = P["eyes"]
	match R["eyes"]:
		"wake": p["shut"] = t < 0.7; p["eye_s"] = 1.0 + 0.15 * clampf((t - 0.7) / 0.2, 0.0, 1.0) * clampf((1.3 - t) / 0.3, 0.0, 1.0)
		"happy": p["eye_sy"] = lerpf(1.0, 0.45, e); p["eye_off"] = Vector2(0, -5.0 * e)
		"angry": p["eye_sy"] = lerpf(1.0, 0.72, e); p["eye_tilt"] = 0.42 * e * ey; p["lid"] = 0.22 * e; p["eye_off"] = Vector2(0, 4.0 * e)
		"wide": p["eye_s"] = 1.0 + 0.28 * e * ey
		"shock": p["eye_s"] = 1.0 + 0.35 * e; p["shut"] = t > 0.35 and t < 0.5
		"squint": p["eye_sy"] = lerpf(1.0, 0.55, e); p["eye_off"] = Vector2((10.0 if i == 0 else -10.0) * e * ey, 0)
		"lid": p["lid"] = 0.42 * e
		"sad": p["eye_tilt"] = -0.3 * e * ey; p["eye_off"] = Vector2(0, 7.0 * e); p["lid"] = 0.2 * e
		"look": p["eye_off"] = Vector2(sin(t * 5.0) * 14.0 * ey * e, 0)
		"darting": p["eye_off"] = Vector2(sin(_t * 17.0) * 12.0 * ey * e, cos(_t * 11.0) * 3.0 * e); p["eye_s"] = 1.15
		"shut": p["shut"] = true
	p["glitch"] = maxf(p["glitch"], float(R["glitch"]) * float(P["glitch"]) * (e if t < 0.9 or id in ["OUT", "LOSE"] else e * 0.35))
	p["flare"] = float(R["flare"]) * e * (0.75 + 0.25 * sin(_t * 9.0))
	if f == "ember":                                  # the furnace: its flares burn hotter in the glow
		p["glow"] = minf(1.0, p["glow"] + p["flare"] * 0.5)
	if R.has("flash"):
		var fl: Color = R["flash"]
		p["flash"] = Color(fl, 0.55 * clampf(1.0 - t / 0.45, 0.0, 1.0) + (0.25 * (0.5 + 0.5 * sin(_t * 14.0)) * e if id in ["ALARM", "NEARLOSS"] else 0.0))
	if R.has("shake"):
		p["shake"] = Vector2(sin(_t * 61.0), cos(_t * 53.0)) * 3.0 * clampf(1.0 - t / 0.5, 0.0, 1.0)
	if id in ["OUT", "LOSE"]:
		p["grey"] = t > 0.6
		p["glow"] = lerpf(p["glow"], 0.2, clampf(t / 0.6, 0.0, 1.0))
	var ek: String = R["emote"]
	if ek != "":
		p["emote"] = P["emotes"].get(ek, ek)
	return p


func _place() -> void:
	for i in range(2):
		var r: Rect2 = rects[i]
		var R: Dictionary = rigs[i]
		var rig: Node2D = R["rig"]
		rig.visible = r.size.x > 0.0
		if not rig.visible:
			continue
		var side := r.size.y
		var p := _pose(i)
		R["pose"] = p
		rig.position = Vector2(r.position.x + side * 0.5 if i == 0 else r.end.x - side * 0.5, r.get_center().y) + p["shake"] * side / 80.0
		rig.rotation = deg_to_rad(-TILT if i == 0 else TILT)
		var k := side / C
		for n in ["flare", "glass", "front", "shine"]:
			var nd: Node2D = R[n]
			nd.scale = Vector2(k, k)
			nd.position = -MID * k
			nd.queue_redraw()
		R["face"].queue_redraw()
		R["plate"].queue_redraw()


func _draw_layer(ci: CanvasItem, name: String, mod := Color.WHITE, box_name := "") -> void:
	var t := _layer(name)
	if t:
		ci.draw_texture_rect(t, _box(box_name if box_name != "" else name), false, mod)


func _draw_flare(i: int, ci: Node2D) -> void:
	## The seat neon (neon = seat colour): the frame's silhouette, a touch larger, additive, behind the frame.
	var p: Dictionary = rigs[i].get("pose", {})
	var a: float = p.get("flare", 0.0)
	if a <= 0.01:
		return
	var col := Color(Rules.seat_color(shown[i]), a * 0.9)
	var t := _layer("frame")
	if t == null:
		return
	var b := _box("frame")
	var c := b.get_center()
	if ci == rigs[i]["shine"]:                        # the neon running over the metal itself
		ci.draw_texture_rect(t, b, false, Color(col, a * 0.45))
		return
	for s in [1.13, 1.09, 1.05]:
		ci.draw_texture_rect(t, Rect2(c + (b.position - c) * s, b.size * s), false, Color(col, a * (0.5 if s > 1.1 else 0.8)))


func _draw_glass(ci: Node2D) -> void:
	_draw_layer(ci, "glass")                          # the clip mask for the face (clip_children)


func _draw_face(i: int, ci: Node2D) -> void:
	var p: Dictionary = rigs[i].get("pose", {})
	if p.is_empty():
		return
	var seat: String = shown[i]
	var f := _faction(seat)
	var grey: bool = p["grey"]
	var g: float = p["glitch"]
	var gm := Color(GLITCH[f], 1.0) if not grey else Color(0.5, 0.5, 0.5)
	# the glitch bars: always faint (as the flat screen had them), strong and torn in a glitch burst
	var gb := _box("glitch@" + f)
	if g > 0.05:
		gb.position.x += rng.randf_range(-1, 1) * 10.0 * g
	_draw_layer(ci, "glitch", Color(gm, 1.0), "glitch@" + f)
	if g > 0.05 and _layer("glitch"):
		ci.draw_texture_rect(_layer("glitch"), gb, false, Color(gm, 0.9 * g))
	# the body transform: squash about the body's foot, offset, tilt
	var bb := _box(f + "_body")
	var foot := Vector2(bb.get_center().x, bb.end.y)
	var sq: float = p["sq"]
	var xf := Transform2D(p["rot"], Vector2(1.0 - sq * 0.6, 1.0 + sq), 0.0, foot + p["off"]) * Transform2D(0.0, -foot)
	ci.draw_set_transform_matrix(xf)
	var mod := Color(0.45, 0.43, 0.45) if grey else Color.WHITE
	_draw_layer(ci, f + "_glow", Color(mod, clampf(p["glow"], 0.0, 1.0)))
	var tb := _layer(f + "_body")
	if tb:
		if g > 0.3:                                    # a tear: the body in bands, each shoved sideways
			var n := 7
			var seed_ := int(_t * 18.0)
			for b in range(n):
				var h := bb.size.y / n
				var src := Rect2(0, b * h, bb.size.x, h)
				var sh := sin(float(seed_ * 13 + b * 7)) * 14.0 * g * (1.0 if (seed_ + b) % 3 == 0 else 0.25)
				ci.draw_texture_rect_region(tb, Rect2(bb.position + Vector2(sh, b * h), src.size), src, mod)
		else:
			ci.draw_texture_rect(tb, bb, false, mod)
	_draw_eyes(ci, f, p, mod, xf)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	var gl := _box("glass")
	if g > 0.05:                                       # scanlines + a bright scan bar in the AI colour
		var y := gl.position.y
		while y < gl.end.y:
			ci.draw_rect(Rect2(gl.position.x, y, gl.size.x, 2.0), Color(0, 0, 0, 0.28 * g))
			y += 6.0
		var by := gl.position.y + fmod(_t * 260.0, gl.size.y)
		ci.draw_rect(Rect2(gl.position.x, by, gl.size.x, 7.0), Color(gm, 0.35 * g))
	var fl: Color = p["flash"]
	if fl.a > 0.01:
		ci.draw_rect(gl, fl)


func _draw_eyes(ci: CanvasItem, f: String, p: Dictionary, mod: Color, xf: Transform2D) -> void:
	var shut: bool = p["shut"]
	var name := f + ("_shut" if shut else "_eyes")
	var t := _layer(name)
	if t == null:
		return
	var eb := _box(f + "_eyes")                       # open eyes' box = the pivot (shut eyes sit inside it)
	var b := _box(name)
	var c: Vector2 = eb.get_center() + p["eye_off"]
	var s: float = p["eye_s"]
	var sy: float = p["eye_sy"] * s
	var lid: float = 0.0 if shut else clampf(p["lid"], 0.0, 0.8)
	var tilt: float = p["eye_tilt"]
	var split: bool = PERSONA[f]["split"] and absf(tilt) > 0.01 and not shut
	if not split:
		var src := Rect2(0, b.size.y * lid, b.size.x, b.size.y * (1.0 - lid))
		var rel := b.position - eb.get_center()
		var dst := Rect2(c + Vector2(rel.x * s, (rel.y + b.size.y * lid) * sy), Vector2(b.size.x * s, src.size.y * sy))
		ci.draw_texture_rect_region(t, dst, src, mod)
		return
	for half in range(2):                              # two eyes, tilted apart (anger: inner corners down; sadness: up)
		var hw := b.size.x * 0.5
		var src := Rect2(half * hw, b.size.y * lid, hw, b.size.y * (1.0 - lid))
		var hc := Vector2(b.position.x + hw * (half + 0.5), b.position.y + b.size.y * 0.5) - eb.get_center()
		var pc: Vector2 = c + Vector2(hc.x * s, hc.y * sy)
		var rot := tilt if half == 0 else -tilt
		ci.draw_set_transform_matrix(xf * Transform2D(rot, pc))
		var size := Vector2(hw * s, src.size.y * sy)
		ci.draw_texture_rect_region(t, Rect2(Vector2(-size.x * 0.5, -b.size.y * 0.5 * sy + b.size.y * lid * sy), size), src, mod)
	ci.draw_set_transform_matrix(xf)


func _draw_front(i: int, ci: Node2D) -> void:
	var p: Dictionary = rigs[i].get("pose", {})
	_draw_layer(ci, "frame")
	var em: String = p.get("emote", "")
	if em == "" or cur[i] == "":
		return
	# the emote: pops in at the glass's outer top corner, bobs, fades with the reaction
	var e := _env(i)
	var t: float = cur_t[i]
	var gl := _box("glass")
	var pos := Vector2(gl.position.x + gl.size.x * (0.17 if i == 0 else 0.83), gl.position.y + gl.size.y * 0.2)
	pos.y += sin(_t * 6.0) * 4.0
	var sc := (0.4 + 0.6 * clampf(t / 0.18, 0.0, 1.0) + 0.15 * sin(clampf(t / 0.3, 0.0, 1.0) * PI)) * 84.0
	_emote(ci, em, pos, sc, e, Color(GLITCH[_faction(shown[i])]))


func _emote(ci: CanvasItem, kind: String, c: Vector2, s: float, a: float, acc: Color) -> void:
	## Small vector emotes (no painted art): spark, heart, coin, check, cross, anger, sweat, bang, ask.
	var ink := Color(0.12, 0.06, 0.1, a)
	var lw := maxf(2.0, s * 0.1)
	match kind:
		"spark":
			for k in range(4):
				var d := Vector2.from_angle(k * PI / 2.0 + _t * 1.5)
				var pts := PackedVector2Array([c + d * s * 0.62, c + d.rotated(PI / 2) * s * 0.14, c - d * s * 0.05, c + d.rotated(-PI / 2) * s * 0.14])
				ci.draw_colored_polygon(pts, Color(1.0, 0.95, 0.6, a))
			ci.draw_circle(c, s * 0.12, Color(1, 1, 1, a))
		"heart":
			var pts := PackedVector2Array()
			for k in range(28):
				var u := TAU * k / 28.0
				pts.append(c + Vector2(16.0 * pow(sin(u), 3), -(13.0 * cos(u) - 5.0 * cos(2 * u) - 2.0 * cos(3 * u) - cos(4 * u))) * s / 34.0)
			ci.draw_colored_polygon(pts, Color(1.0, 0.36, 0.55, a))
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, lw * 0.6, true)
		"coin":
			ci.draw_circle(c, s * 0.42, Color(1.0, 0.82, 0.3, a))
			ci.draw_arc(c, s * 0.42, 0, TAU, 32, ink, lw * 0.6, true)
			_glyph(ci, "$", c, s * 0.62, ink)
		"check":
			ci.draw_rect(Rect2(c - Vector2(s, s) * 0.42, Vector2(s, s) * 0.84), Color(0.55, 0.9, 0.5, a))
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.24, 0.0) * s, c + Vector2(-0.06, 0.2) * s, c + Vector2(0.26, -0.2) * s]), ink, lw * 1.3, true)
		"cross":
			ci.draw_rect(Rect2(c - Vector2(s, s) * 0.42, Vector2(s, s) * 0.84), Color(1.0, 0.4, 0.38, a))
			ci.draw_line(c + Vector2(-0.22, -0.22) * s, c + Vector2(0.22, 0.22) * s, ink, lw * 1.3, true)
			ci.draw_line(c + Vector2(0.22, -0.22) * s, c + Vector2(-0.22, 0.22) * s, ink, lw * 1.3, true)
		"anger":                                      # the cartoon vein: four curved strokes
			for k in range(4):
				var d := Vector2.from_angle(k * PI / 2.0 + PI / 4.0)
				ci.draw_arc(c + d * s * 0.34, s * 0.22, d.angle() + PI * 0.55, d.angle() + PI * 1.45, 10, Color(1.0, 0.25, 0.25, a), lw * 1.2, true)
		"sweat":
			var pts := PackedVector2Array([c + Vector2(0, -0.5) * s])
			for k in range(17):
				var u := PI * k / 16.0
				pts.append(c + Vector2(cos(u) * 0.26, 0.12 + sin(u) * 0.26) * s)
			ci.draw_colored_polygon(pts, Color(0.6, 0.85, 1.0, a))
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), ink, lw * 0.6, true)
		"bang":
			ci.draw_circle(c, s * 0.42, Color(acc, a))
			ci.draw_arc(c, s * 0.42, 0, TAU, 32, ink, lw * 0.6, true)
			_glyph(ci, "!", c, s * 0.7, ink)
		"ask":
			ci.draw_circle(c, s * 0.42, Color(acc, a))
			ci.draw_arc(c, s * 0.42, 0, TAU, 32, ink, lw * 0.6, true)
			_glyph(ci, "?", c, s * 0.7, ink)


func _glyph(ci: CanvasItem, ch: String, c: Vector2, size: float, col: Color) -> void:
	var font := HudLab.bold()
	var fs := int(round(size))
	var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, Vector2(c.x - w * 0.5, c.y + font.get_ascent(fs) * 0.36), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func plate_room_pt() -> float:
	## The width a plate line may take at PLATE_FONT_PT (pt): the plate minus the text start and a right pad.
	var side := AI_H_PT
	var pw := 133.0 - side + side * 0.12
	var ph := side * 0.3
	return pw - ph * PLATE_TEXT_X - ph * 0.12


func _draw_plate(i: int, ci: Node2D) -> void:
	## The mood plate on the screen's inner side (screen units): a lamp in the mood colour + the reaction's line in the AI's voice
	## (the baseline mood word when no reaction plays). It pops a little when a reaction starts.
	var r: Rect2 = rects[i]
	var side := r.size.y
	var id: String = cur[i]
	var m: String = REACT[id]["mood"] if id != "" else mood[i]
	if not MOODS.has(m):
		m = "CALM"
	var col: Color = MOODS[m][0]
	var word: String = PERSONA[_faction(shown[i])]["lines"].get(id, MOODS[m][1]) if id != "" else MOODS[m][1]
	var pw := r.size.x - side + side * 0.12
	var ph := side * 0.3
	var px := (side * 0.5 - side * 0.06) if i == 0 else (-side * 0.5 + side * 0.06 - pw)
	var pr := Rect2(Vector2(px, -ph * 0.5 + side * 0.12), Vector2(pw, ph))
	var pop := 1.0 + (0.1 * sin(clampf(cur_t[i] / 0.25, 0.0, 1.0) * PI) if id != "" else 0.0)
	if pop != 1.0:
		var anchor := Vector2(pr.position.x if i == 0 else pr.end.x, pr.get_center().y)
		ci.draw_set_transform(anchor * (1.0 - pop), 0.0, Vector2(pop, pop))
	var p: Dictionary = rigs[i].get("pose", {})
	if float(p.get("flare", 0.0)) > 0.05:             # the seat neon on the plate's edge while the AI flares
		ci.draw_rect(pr.grow(side * 0.025), Color(Rules.seat_color(shown[i]), 0.8 * float(p["flare"])), false, maxf(1.0, side * 0.03))
	ci.draw_rect(pr, Color("f4e7d4"))
	ci.draw_rect(pr, Color("8a5a3c"), false, maxf(1.0, side * 0.02))
	var lamp := col
	if id != "" and fmod(_t * 6.0, 1.0) < 0.5 and _env(i) > 0.5:
		lamp = col.lightened(0.35)
	ci.draw_rect(Rect2(pr.position + Vector2(ph * PLATE_LAMP.x, ph * (0.5 - PLATE_LAMP.y * 0.5)), Vector2(ph, ph) * PLATE_LAMP.y), lamp)   # the mood lamp
	# designer 12 FIX: every line at 12.5 pt (never shrunk), one left padding for all; lines are written to fit (test_ai_reactions audits)
	var fs := int(round(PLATE_FONT_PT * side / AI_H_PT))
	var font := HudLab.bold()
	ci.draw_string(font, Vector2(pr.position.x + ph * PLATE_TEXT_X, pr.get_center().y + font.get_ascent(fs) * 0.36), word,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("30202a"))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
