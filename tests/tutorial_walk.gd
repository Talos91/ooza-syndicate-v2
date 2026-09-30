extends Node
## Quick-start review walk (TUTORIAL-REWRITE-DESIGN.md §3a): plays the guided QUICK START through the real game (main.tscn,
## orders through main.node_action and the coach's own buttons, following the hand as a new player would) on T-11 and shoots
## every step - the four basics (the Machinegoon card in the inspector), free play, the relay kill (slow motion, the prompt,
## the drop), the Last Stand's explanation cards, the move and the ring falling, LESSON COMPLETE and CONTINUE PLAYING - then
## lays ONE contact sheet. For looking at, not a test suite. Run WINDOWED (phone size):
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


# ------------------------------------------------------------------ the quick start (four chapters, in order)
var _last_follow := -100000


func _follow(force := false) -> void:
	## Do what the hand shows, through the game's own input paths (main.node_action, the inspector).
	var now := Time.get_ticks_msec()
	if now - _last_follow < 700 and not force:                     # at most one order every 0.7 s (real time)
		return
	var g := d.gesture()
	if g.is_empty():
		return
	_last_follow = now
	var cur := d.current_id()
	match str(g[0][0]):
		"drag":
			var f := 0.5 if cur in ["take", "reinforce"] else 1.0
			m.fraction = f
			m.node_action("send", int(g[0][1]), {"to": int(g[0][2]), "fraction": f})
		"double_tap":
			m.node_action("upgrade", int(g[0][1]))
		"tap":
			m.hud.inspect(int(g[0][1]), m.cam)
		"press":
			if str(g[0][1]) == "action:MACHINEGOON":
				m.node_action("build", m.hud.inspector_id, {"kind": "machinegoon"})
				m.hud.close_inspector()


func _step_until(id_not: String, limit: float) -> void:
	## Follow the hand once a second until the step is over.
	var t := 0.0
	var next := 0.0
	Engine.time_scale = FAST
	while t < limit and d.state == "running" and d.current_id() == id_not:
		if t >= next:
			next = t + 1.0
			_follow()
		await get_tree().process_frame
		t += get_process_delta_time()
	Engine.time_scale = 1.0


func _got_it() -> void:
	m._on_coach_button("got_it")
	await _frames(3)


func _quick() -> void:
	var sim: Sim = m.sim
	await _secs(1.0)
	await _shot("1-take-hand")                                      # chapter 1: the card, the hand and the spotlight from the start
	await _until(func(): return d.card()["text"] == TutorialDirector.line("T1.take_send"), 12.0)
	await _shot("1-take-send-panel")
	_follow(true)
	await _until(func(): return d.current_id() != "take", 30.0)
	await _shot("1-take-done")
	await _secs(2.8)
	await _shot("1-reinforce-hand")
	await _step_until("reinforce", 40.0)
	await _secs(2.8)
	await _shot("1-upgrade-hand")
	_follow(true)
	await _secs(1.0)
	await _shot("1-upgrade-building")
	await _until(func(): return d.current_id() != "upgrade", 20.0)
	await _secs(2.8)
	await _shot("1-machinegoon-take-M")
	await _until(func(): return d._phase(d.current_step()) == "main", 40.0, func(_t): _follow())
	await _secs(0.5)
	_follow(true)                                                    # the tap: the inspector opens on M
	await _secs(0.8)
	await _shot("1-machinegoon-inspector-card")                     # the new inspector: the hand on the MACHINEGOON card's centre
	_follow(true)
	await _until(func(): return d._phase(d.current_step()) == "watch" and int(d._mg_probe["line"]) >= 0, 40.0)
	await _secs(1.0)
	await _shot("1-machinegoon-watch")
	await _until(func(): return d.current_id() != "machinegoon", 60.0)
	await _secs(2.8)
	await _shot("2-free-play")                                      # chapter 2: your turn, the countdown on the strip
	await _until(func(): return d.card()["text"] == TutorialDirector.line("T1.free_nudge"), 30.0)
	await _shot("2-free-nudge")
	await _until(func(): return d.current_id() != "free", 60.0)
	await _secs(2.8)
	await _shot("3-relay-take-hand")                                # chapter 3
	await _step_until("relay_take", 60.0)
	await _secs(2.8)
	await _shot("3-relay-wait")
	var st := {"slow": false, "prompt": false}
	Engine.time_scale = FAST
	var t := 0.0
	while d.state == "running" and d.current_id() == "relay" and t < 150.0:
		if d.catch_line() >= 0 and d.time_scale < 1.0 and not d.catch_prompt() and not st["slow"]:
			st["slow"] = true
			await _shot("3-relay-slow-motion")
			Engine.time_scale = FAST
		if d.catch_prompt() and not st["prompt"]:
			st["prompt"] = true
			await _shot("3-relay-prompt")
			m.node_action("switch", _id("R"))
			Engine.time_scale = 0.5
			await _secs(1.4)
			await _shot("3-relay-drop")
			Engine.time_scale = FAST
		await get_tree().process_frame
		t += get_process_delta_time()
	Engine.time_scale = 1.0
	await _secs(0.5)
	await _shot("4-last-stand-announced")                           # chapter 4: the explanation cards
	await _got_it()
	await _secs(0.8)
	await _shot("4-danger-marks")
	await _got_it()
	await _secs(0.8)
	await _shot("4-centre-ring")
	await _got_it()
	await _secs(0.8)
	await _shot("4-move-hand")
	_follow(true)
	await _until(func(): return d.current_id() != "ls_move", 20.0)
	await _secs(1.0)
	await _shot("4-hold-on")
	await _until(func(): return not sim.collapsed.is_empty(), 60.0, func(_t): _follow())
	await _secs(0.6)
	await _shot("4-ring-falling")
	await _until(func(): return d.state != "running", 90.0)
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
