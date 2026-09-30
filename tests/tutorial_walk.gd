extends Node
## Quick-start review walk (TUTORIAL-REWRITE-DESIGN.md): plays the QUICK START through the real game (main.tscn, orders
## through main.node_action and the coach's own buttons, as a player's input would) on T-11 and shoots each state - the
## opening, the idle hint (hand + spotlight), a goal ticking, a short-send assist, the Machinegoon watch, the relay moment
## (slow motion, the prompt, the drop), the Last Stand (announcement, evacuation hand, the ring falling), LESSON COMPLETE and
## CONTINUE PLAYING - then lays ONE contact sheet. For looking at, not a test suite. Run WINDOWED (phone size):
##
##   Godot --path <wt> --resolution 1266x585 res://tests/tutorial_walk.tscn -- --mobile --no-notice out=<dir>
##
## Waits run the game 3x faster (Engine.time_scale); every shot is taken at 1x. Progress goes to a scratch file
## (user://tutorial_walk.cfg), never the real one.

const PROGRESS := "user://tutorial_walk.cfg"
const FAST := 3.0
var out_dir := ""
var m: Node
var d: TutorialDirector
var shots: Array = []                # [label, path]


func _ready() -> void:
	_run.call_deferred()


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--") and "=" in a:
			var kv := a.split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()


func _run() -> void:
	var args := _args()
	out_dir = str(args.get("out", "user://tutorial_walk"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	TutorialDirector.path = PROGRESS
	Progression.path = "user://coach_preview_progression.cfg"   # TUTORIAL + PROGRESSION: never the real wallet
	TutorialDirector.completed_ids = []
	TutorialDirector.skipped_ids = []
	TutorialDirector.offered = true
	TutorialDirector._loaded = true
	await _start()
	await _quick()
	await _sheet()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS))
	Engine.time_scale = 1.0
	print("WALK done ", out_dir)
	get_tree().quit()


func _start() -> void:
	var ms: GDScript = load("res://scripts/main.gd")
	ms.relaunch = {"tutorial": 1, "faction": "null", "colour": "A"}
	m = (load("res://main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(m)
	await _frames(20)
	d = m.director


func _shot(label: String) -> void:
	## At 1x, once the card's line has typed in.
	var was := Engine.time_scale
	Engine.time_scale = 1.0
	var t := 0.0
	while m.coach and m.coach._typing and t < 4.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	await _frames(8)
	await RenderingServer.frame_post_draw
	var path := "%s/Q-%02d-%s.png" % [out_dir, shots.size(), label]
	get_viewport().get_texture().get_image().save_png(path)
	shots.append([label, path])
	print("shot ", path, "  [", d.current_id(), " | ", d.card()["text"], "]")
	Engine.time_scale = was


func _until(cond: Callable, limit: float, act := Callable()) -> bool:
	## Run the game (FAST) until cond, acting every frame; false on the limit.
	var t := 0.0
	Engine.time_scale = FAST
	while t < limit and d.state == "running" and not cond.call():
		if act.is_valid():
			act.call(t)
		await get_tree().process_frame
		t += get_process_delta_time()
	Engine.time_scale = 1.0
	return cond.call()


func _id(nm: String) -> int:
	return int(d.names[nm])


func _send(a: String, b: String, f: float) -> void:
	m.fraction = f
	m.node_action("send", _id(a), {"to": _id(b), "fraction": f})


func _units(nm: String, shown: float) -> void:
	m.sim.nodes[_id(nm)]["units"] = shown * Rules.SCALE


# ------------------------------------------------------------------ the quick start
func _quick() -> void:
	var sim: Sim = m.sim
	await _secs(1.2)
	await _shot("opening")                                          # the welcome line, the strip, no hand yet
	await _until(func(): return sim.time > 7.0, 20.0)
	await _shot("hint-upgrade")                                     # the current hint, nothing pointed yet (the player is "active")
	await _until(func(): return sim.time - d._last_order_t >= 8.5, 30.0)
	await _shot("idle-hand-upgrade")                                # 8 s idle: the hand double-taps the home, one ring
	m.node_action("upgrade", _id("H"))
	await _until(func(): return d.goals.goal_done("upgrade"), 30.0)
	await _shot("goal-upgrade")                                     # a goal ticked: Dr. Vesk's one line, the chip ticked
	# TAKE, with a deliberately short send first (the assist)
	_units("H", 30.0)
	_send("H", "N2", 0.1)
	await _until(func(): return not d.assist_retry().is_empty(), 25.0)
	await _shot("short-send-assist")
	var rt := d.assist_retry()
	if not rt.is_empty():
		m.node_action("send", int(rt[0]), {"to": int(rt[1]), "fraction": 1.0})
	await _until(func(): return d.goals.goal_done("take"), 60.0)
	await _shot("goal-take")
	# REINFORCE
	await _until(func(): return sim.time - d._last_order_t >= 8.5, 30.0)
	await _shot("idle-hand-reinforce")                              # a drag between two of your nodes
	_send("N2", "H", 1.0)
	await _until(func(): return d.goals.goal_done("reinforce"), 60.0)
	await _shot("goal-reinforce")
	# MACHINEGOON: take M, build, watch the probe
	_units("H", 60.0)
	_send("H", "M", 1.0)
	await _until(func(): return sim.nodes[_id("M")]["owner"] == "A", 60.0)
	_units("M", 30.0)
	m.hud.inspect(_id("M"), m.cam)
	await _secs(0.5)
	await _shot("machinegoon-inspector")
	m.node_action("build", _id("M"), {"kind": "machinegoon"})
	m.hud.close_inspector()
	await _until(func(): return int(d._mg_probe["line"]) >= 0, 60.0)
	await _secs(1.5)
	await _shot("machinegoon-probe")                                # the watch moment: undimmed, one subtle ring
	await _until(func(): return d.goals.goal_done("machinegoon"), 60.0)
	await _shot("goal-machinegoon")
	# RELAY: take it (stage B), wait for the push
	await _until(func(): return d.stage >= 1, 70.0)
	await _secs(0.5)
	await _shot("stage-b-relay")                                    # the relay parts appear
	_units("M", 60.0)
	_send("M", "R", 1.0)
	await _until(func(): return sim.nodes[_id("R")]["owner"] == "A", 60.0)
	var st := {"slow": false, "prompt": false, "fired": false}
	Engine.time_scale = FAST
	var t := 0.0
	while d.state == "running" and not d.goals.goal_done("relay") and t < 150.0:
		if d.catch_line() >= 0 and d.time_scale < 1.0 and not d.catch_prompt() and not st["slow"]:
			st["slow"] = true
			await _shot("relay-slow-motion")
			Engine.time_scale = FAST
		if d.catch_prompt() and not st["prompt"]:
			st["prompt"] = true
			await _shot("relay-prompt")                             # the line is on the deck: hand on the relay, no dim
			Engine.time_scale = 1.0
			await _secs(0.4)
			await _shot("relay-prompt-2")
			m.node_action("switch", _id("R"))
			st["fired"] = true
			Engine.time_scale = 0.5
			await _secs(1.4)
			await _shot("relay-drop")
			Engine.time_scale = FAST
		await get_tree().process_frame
		t += get_process_delta_time()
	Engine.time_scale = 1.0
	await _shot("goal-relay")
	# LAST STAND
	await _until(func(): return d._ls_started, 90.0)
	await _secs(1.0)
	await _shot("last-stand-announced")
	await _until(func(): return sim.time - d._last_order_t >= 8.5, 30.0)
	await _shot("last-stand-hand")                                  # the hand drags off the falling ring
	var mv := d._evac_move()
	for id in d._mine():
		if d._doomed(id) and float(sim.nodes[id]["units"]) >= Rules.SCALE and not mv.is_empty():
			m.node_action("send", id, {"to": int(mv[1]), "fraction": 1.0})
	await _until(func(): return not sim.last_stand_warn.is_empty() and sim.last_stand_warn_t < 6.0, 40.0)
	await _shot("last-stand-warning")
	await _until(func(): return d.state != "running", 90.0, func(_t):
		for id in d._mine():
			if d._doomed(id) and float(sim.nodes[id]["units"]) >= Rules.SCALE and sim.nodes[id]["streaming"].is_empty():
				var mv2 := d._evac_move()
				if not mv2.is_empty() and int(mv2[0]) == id:
					m.node_action("send", id, {"to": int(mv2[1]), "fraction": 1.0}))
	await _secs(0.8)
	await _shot("complete" if d.state == "complete" else "NOT-COMPLETE-" + d.state)
	if d.state == "complete":
		m._on_coach_button("primary")                               # CONTINUE PLAYING
		await _secs(1.5)
		await _shot("continue-playing")
	m.queue_free()
	await _frames(6)


# ------------------------------------------------------------------ one contact sheet
func _sheet() -> void:
	if shots.is_empty():
		return
	const COLS := 4
	const TW := 420.0
	const PAD := 12.0
	const LH := 24.0
	var tex := []
	var th := 0.0
	for s in shots:
		var img := Image.load_from_file(s[1])
		tex.append(ImageTexture.create_from_image(img))
		th = maxf(th, TW * float(img.get_height()) / float(img.get_width()))
	var rows := ceili(float(shots.size()) / COLS)
	var sub := SubViewport.new()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(sub)
	var ui := Control.new()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.045)
	ui.add_child(bg)
	sub.add_child(ui)
	var font := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
	for i in range(shots.size()):
		var x := PAD + (i % COLS) * (TW + PAD)
		var y := PAD + (i / COLS) * (th + LH + PAD)
		var l := Label.new()
		l.text = "%02d · %s" % [i, str(shots[i][0]).to_upper()]
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", 16)
		l.position = Vector2(x, y)
		ui.add_child(l)
		var tr := TextureRect.new()
		tr.texture = tex[i]
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		tr.position = Vector2(x, y + LH)
		tr.size = Vector2(TW, th)
		ui.add_child(tr)
	var W := COLS * (TW + PAD) + PAD
	var H := rows * (th + LH + PAD) + PAD
	ui.size = Vector2(W, H)
	bg.size = ui.size
	sub.size = Vector2i(int(W), int(H))
	await _frames(6)
	var path := "%s/quick-start-sheet.png" % out_dir
	sub.get_texture().get_image().save_png(path)
	sub.queue_free()
	print("SHEET ", path)
