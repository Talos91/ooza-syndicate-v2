class_name AiScreens
extends Control
## hud-43 AI SCREENS (Daniele 11-18 screen layout: "AI moods on the AI screens, no top banners"): two screens in the top corners of his
## frame, tilted -12 / +12 deg, each the faction AI's HD screen (UiKit.ai_screen_path, the VERSUS art) + its MOOD on a cream plate.
## Who shows: 1v1 = left you (your faction's AI), right the enemy AI. 2v2 = left your team, right the other team (the face = the team
## seat the latest event was about). FFA = left you, right the AI with the BIGGEST event (an elimination > a capture from you > a capture,
## queued, biggest first, each held MOOD_HOLD s). Moods come from events (node captured / lost, a seat out) and fall back to the
## share of the map each 0.5 s: SMUG (>= 45 % in 1v1-scaled share), PANIC (<= 15 %), else CALM.
## Animation per mood: GLEE bounce, RAGE shake + red flash, PANIC flicker, SMUG slow sway, OUT grey; the face blinks every few s.

const TILT := 12.0
const MOOD_HOLD := 2.6
const MOODS := {
	"CALM": [Color("e7b68b"), "CALM"],
	"SMUG": [Color("f3c969"), "SMUG"],
	"GLEE": [Color("8be38b"), "GLEE!"],
	"RAGE": [Color("ff5b5b"), "RAGE!"],
	"PANIC": [Color("ff9a3c"), "PANIC"],
	"OUT": [Color("8a7f86"), "OFFLINE"],
}

var hud
var sides: Array = []                       # [[seats...], [seats...]]: left, right
var ffa := false
var shown := ["", ""]                       # the seat each screen shows now
var mood := ["CALM", "CALM"]
var hold := [0.0, 0.0]                      # an event mood's time left
var flash := [0.0, 0.0]
var queue: Array = []                       # FFA right screen: [weight, seat, mood]
var _t := 0.0
var _acc := 0.0
var rects := [Rect2(), Rect2()]


func setup(h) -> void:
	hud = h
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	for a in OS.get_cmdline_user_args():      # dev shots: --ai-mood=RAGE,GLEE (left, right)
		if a.begins_with("--ai-mood="):
			var v := a.substr(10).split(",")
			for i in range(mini(2, v.size())):
				mood[i] = v[i]
				hold[i] = 9999.0


func lay(l: Rect2, r: Rect2) -> void:
	rects = [l, r]
	queue_redraw()


func _side_of(seat: String) -> int:
	if seat in sides[0]:
		return 0
	if seat in sides[1]:
		return 1
	return -1


func event(seat: String, m: String, weight: float) -> void:
	## A mood for a seat's AI from a match event (Hud.ai_event).
	var i := _side_of(seat)
	if i < 0:
		return
	if i == 1 and ffa:
		queue.append([weight, seat, m])
		queue.sort_custom(func(a, b): return a[0] > b[0])
		if queue.size() > 6:
			queue.resize(6)
		if hold[1] <= 0.0 or weight > 2.5:
			_next_ffa()
		return
	shown[i] = seat
	mood[i] = m
	hold[i] = MOOD_HOLD
	if m == "RAGE":
		flash[i] = 0.5


func _next_ffa() -> void:
	if queue.is_empty():
		return
	var e: Array = queue.pop_front()
	shown[1] = e[1]
	mood[1] = e[2]
	hold[1] = MOOD_HOLD
	if e[2] == "RAGE":
		flash[1] = 0.5


func on_capture(new_owner: String, old_owner: String, units: float) -> void:
	## A node changed hands: the taker gloats, the loser rages (an AI that took it from YOU: the biggest).
	var me := str(hud.human)
	var w := 1.0 + clampf(units / 60.0, 0.0, 1.0)
	if new_owner != "":
		event(new_owner, "GLEE", w + (1.0 if old_owner == me else 0.0))
	if old_owner != "":
		event(old_owner, "RAGE", w)


func on_out(seat: String) -> void:
	event(seat, "OUT", 3.0)


func _process(dt: float) -> void:
	if hud == null or hud.sim == null:
		return
	_t += dt
	for i in range(2):
		if hold[i] > 0.0:
			hold[i] -= dt
			if hold[i] <= 0.0 and i == 1 and ffa:
				_next_ffa()
		flash[i] = maxf(0.0, flash[i] - dt)
	_acc += dt
	if _acc >= 0.5:
		_acc = 0.0
		_baseline()
	queue_redraw()


func _baseline() -> void:
	## No event mood: from the share of units on the map (Sim.seat_strength), OUT when the seat is out.
	var tot := 0.0
	var all: Array = sides[0] + sides[1]
	for s in all:
		if hud.sim.factions.has(s) and not hud._seat_out(s):
			tot += maxf(float(hud.sim.seat_strength(s)), 0.0)
	var fair := 1.0 / maxf(float(all.size()), 1.0)
	for i in range(2):
		if hold[i] > 0.0:
			continue
		var s: String = shown[i]
		if hud.sim.factions.has(s) and hud._seat_out(s):
			mood[i] = "OUT"
			continue
		var share := (maxf(float(hud.sim.seat_strength(s)), 0.0) / tot) if tot > 0.0 else fair
		mood[i] = "SMUG" if share >= fair * 1.8 else ("PANIC" if share <= fair * 0.6 else "CALM")


func _draw() -> void:
	if hud == null:
		return
	for i in range(2):
		var r: Rect2 = rects[i]
		if r.size.x <= 0.0:
			continue
		_draw_screen(i, r)


func _draw_screen(i: int, r: Rect2) -> void:
	var m: String = mood[i] if MOODS.has(mood[i]) else "CALM"
	var seat: String = shown[i]
	var f: String = str(hud.sim.factions.get(seat, "vex"))
	var side := r.size.y
	var ang := deg_to_rad(-TILT if i == 0 else TILT)
	var off := Vector2.ZERO
	match m:                                      # the mood's motion
		"GLEE": off.y = -absf(sin(_t * 9.0)) * side * 0.06
		"RAGE": off = Vector2(sin(_t * 47.0), cos(_t * 39.0)) * side * 0.025
		"SMUG": ang += sin(_t * 1.6) * 0.05
	# the screen sits on the outer side of the zone, the mood plate on the inner side
	var sc := Vector2(r.position.x + side * 0.5 if i == 0 else r.end.x - side * 0.5, r.get_center().y) + off
	draw_set_transform(sc, ang, Vector2.ONE)
	var blink := fmod(_t + i * 1.7, 4.2) < 0.14
	var t := UiKit.tex(UiKit.ai_screen_path(f, blink))
	var mod := Color.WHITE
	if m == "OUT":
		mod = Color(0.45, 0.43, 0.45)
	elif m == "PANIC" and fmod(_t * 7.0, 1.0) < 0.25:
		mod = Color(1.0, 0.85, 0.7)
	if flash[i] > 0.0:
		mod = mod.lerp(Color(1.0, 0.45, 0.45), flash[i] / 0.5)
	if t:
		draw_texture_rect(t, Rect2(-Vector2(side, side) * 0.5, Vector2(side, side)), false, mod)
	# (Daniele 11-18: "the cyan / red square around the AI shouldn't be there": no seat square on the glass)
	# the mood plate
	var col: Color = MOODS[m][0]
	var word: String = MOODS[m][1]
	var pw := r.size.x - side + side * 0.12
	var ph := side * 0.3
	var px := (side * 0.5 - side * 0.06) if i == 0 else (-side * 0.5 + side * 0.06 - pw)
	var pr := Rect2(Vector2(px, -ph * 0.5 + side * 0.12), Vector2(pw, ph))
	draw_rect(pr, Color("f4e7d4"))
	draw_rect(pr, Color("8a5a3c"), false, maxf(1.0, side * 0.02))
	draw_rect(Rect2(pr.position + Vector2(pw * 0.06, ph * 0.28), Vector2(ph * 0.44, ph * 0.44)), col)   # the mood lamp
	var fs := int(round(ph * 0.58))
	var font := HudLab.bold()
	var tw := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var room := pw - ph * 0.8
	while tw > room and fs > 6:
		fs -= 1
		tw = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(pr.position.x + ph * 0.7 + (room - tw) * 0.5, pr.get_center().y + font.get_ascent(fs) * 0.36), word,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("30202a"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
