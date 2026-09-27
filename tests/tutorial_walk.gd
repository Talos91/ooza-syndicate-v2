extends Node
## Tutorial review walk (0.19.3, Daniele: "tutorial feels veeeeery unpolished and messy"): plays every lesson
## through the real game (main.tscn, orders through main.node_action and the coach's own buttons, as a player's
## input would) and shoots EVERY step once its line has typed in, plus the relay prompts and each completion
## screen, then lays one contact sheet per lesson. For looking at, not a test suite. Run WINDOWED:
##
##   Godot --path <wt> --resolution 1266x585 res://tests/tutorial_walk.tscn -- --mobile out=<dir> [lessons=0,4]
##
## Waits run the game 3x faster (Engine.time_scale); every shot is taken at 1x. Progress goes to a scratch file
## (user://tutorial_walk.cfg), never the real one.

const PROGRESS := "user://tutorial_walk.cfg"
const FAST := 3.0
var out_dir := ""
var m: Node
var d: TutorialDirector
var shots: Array = []                # this lesson's [label, path]


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
	TutorialDirector.offered = true
	TutorialDirector._loaded = true
	var only := []
	for v in str(args.get("lessons", "0,1,2,3,4,5,6,7,8,9")).split(","):
		only.append(int(v))
	for id in only:
		shots = []
		await _lesson(id)
		await _sheet(id)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS))
	Engine.time_scale = 1.0
	print("WALK done ", out_dir)
	get_tree().quit()


func _start(id: int) -> void:
	var ms: GDScript = load("res://scripts/main.gd")
	ms.relaunch = {"tutorial": id, "faction": "null", "colour": "A"}
	m = (load("res://main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(m)
	await _frames(20)
	d = m.director


func _shot(label: String) -> void:
	## At 1x, once the card's line has typed in.
	Engine.time_scale = 1.0
	var t := 0.0
	while m.coach and m.coach._typing and t < 4.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	await _frames(8)
	await RenderingServer.frame_post_draw
	var path := "%s/L%d-%02d-%s.png" % [out_dir, d.lesson_id, shots.size(), label]
	get_viewport().get_texture().get_image().save_png(path)
	shots.append([label, path])
	print("shot ", path)


func _got_it() -> void:
	m._on_coach_button("got_it")


func _step_key() -> String:
	return str(d.L["steps"][d.step_i]["key"]) if d.state != "complete" else ""


func _play(act: Callable, limit := 90.0) -> void:
	## Run the current step (act.call(t) every frame, at FAST) until the next step starts or the lesson ends.
	var k := d.step_i
	var t := 0.0
	Engine.time_scale = FAST
	while d.step_i == k and d.state in ["running", "interlude", "failed"] and t < limit:
		if d.state == "failed":
			break
		act.call(t)
		await get_tree().process_frame
		t += get_process_delta_time()
	Engine.time_scale = 1.0


func _id(nm: String) -> int:
	return int(d.names[nm])


func _send(a: String, b: String, f: float) -> void:
	m.fraction = f
	m.node_action("send", _id(a), {"to": _id(b), "fraction": f})


func _deck_m(hid: int, relay: int) -> float:
	var h: Dictionary = m.sim._horde(hid)
	if h.is_empty():
		return 0.0
	var head: float = h["s"]
	var tail: float = head - Sim.chain_length(h)
	var out := 0.0
	for sp in h["spans"]:
		if sp["edge"] in m.sim.controlled_edges(relay) and m.sim.is_edge_open(sp["edge"]):
			out += maxf(0.0, minf(head, sp["s1"]) - maxf(tail, sp["s0"]))
	return out


# ------------------------------------------------------------------ per lesson
func _lesson(id: int) -> void:
	await _start(id)
	var once := {}
	var fired := {}
	while d.state != "complete" and d.state != "failed":
		var key := _step_key()
		await _shot(key)
		if id == 0 and key == "go":                     # (the tour's last NEXT reloads the scene into L1)
			break
		var sim: Sim = m.sim
		match "L%d.%s" % [id, key]:
			"L1.drag":
				await _play(func(t): if not once.has(key): once[key] = true; _send("H", "N1", m.fraction))
			"L1.percent":
				await _play(func(t): m.fraction = 0.25)
			"L1.send25":                                     # a deliberately short send first: the assist
				m.sim.nodes[_id("H")]["units"] = 20.0 * Rules.SCALE
				_send("H", "N2", 0.1)
				Engine.time_scale = FAST
				var ta := 0.0
				while d.assist_retry().is_empty() and ta < 20.0:
					await get_tree().process_frame
					ta += get_process_delta_time()
				await _shot("short-assist")
				var rt := d.assist_retry()
				await _play(func(t): if not once.has(key) and not rt.is_empty(): once[key] = true; m.node_action("send", int(rt[0]), {"to": int(rt[1]), "fraction": 1.0}))
			"L1.reinforce":
				await _play(func(t): if not once.has(key): once[key] = true; _send("N1", "H", 0.5))
			"L2.inspect":
				await _play(func(t): if m.hud.inspector_id != _id("H"): m.hud.inspect(_id("H"), m.cam))
			"L2.upgrade":
				await _play(func(t): if not once.has(key): once[key] = true; m.node_action("upgrade", _id("H")))
			"L2.t3":
				await _play(func(t): if sim.can_upgrade(_id("H"), "A") == "": m.node_action("upgrade", _id("H")))
			"L2.machinegoon":
				m.hud.inspect(_id("N1"), m.cam)
				await _shot("machinegoon-inspector")
				await _play(func(t): if not once.has(key): once[key] = true; m.node_action("build", _id("N1"), {"kind": "machinegoon"}))
			"L2.mg_upgrade":
				await _play(func(t): if not once.has(key): once[key] = true; m.node_action("upgrade", _id("N1")))
			"L3.neutral":
				await _play(func(t): if not once.has(key): once[key] = true; _send("H", "N2", 0.75))
			"L3.defend":
				await _secs(1.0)
				await _shot("defend-incoming")
				await _play(func(t): if not once.has(key): once[key] = true; _send("H", "N1", 1.0))
			"L3.attack":
				await _play(func(t):
					var mine: float = sim.nodes[_id("N1")]["units"] + sim.nodes[_id("H")]["units"]
					if not sim.hordes.any(func(h): return h["owner"] == "A") and mine > sim.nodes[_id("B1")]["units"] + 60.0:
						_send("N1", "B1", 1.0)
						_send("H", "B1", 1.0))
			"L4.inspect":
				await _play(func(t): if m.hud.inspector_id != _id("R"): m.hud.inspect(_id("R"), m.cam))
			"L4.fire":
				await _play(func(t): if not once.has(key): once[key] = true; m.node_action("switch", _id("R")))
			"L4.prompt", "L5.retract", "L5.switch", "L5.remote":
				var relay := _id({"prompt": "R", "retract": "RT", "switch": "SW", "remote": "RC"}[key])
				var st := {"shot": false}
				var k := d.step_i
				Engine.time_scale = FAST
				var t := 0.0
				while d.step_i == k and d.state == "running" and t < 120.0:
					var hid := d.catch_line()
					if hid >= 0 and d.catch_prompt() and not st["shot"]:
						st["shot"] = true
						await _shot(key + "-prompt")
						Engine.time_scale = FAST
					if hid >= 0 and not st.get("slow_shot", false) and d.time_scale < 1.0 and not d.catch_prompt():
						st["slow_shot"] = true
						await _shot(key + "-slow")
						Engine.time_scale = FAST
					if hid >= 0 and d.catch_prompt() and st["shot"] and not fired.has(hid):   # fire when the hand says
						fired[hid] = true
						m.node_action("switch", relay)
					await get_tree().process_frame
					t += get_process_delta_time()
				Engine.time_scale = 1.0
			"L6.inspect":
				await _play(func(t): if m.hud.inspector_id != _id("R1"): m.hud.inspect(_id("R1"), m.cam))
			"L6.laser":
				if m.hud.inspector_id != _id("R1"):
					m.hud.inspect(_id("R1"), m.cam)
				await _play(func(t): if not once.has(key): once[key] = true; m.node_action("build", _id("R1"), {"kind": "laser"}))
			"L6.forge":
				m.hud.inspect(_id("R2"), m.cam)
				await _shot("forge-inspector")
				await _play(func(t): if not once.has(key): once[key] = true; m.node_action("build", _id("R2"), {"kind": "forge"}))
			"L6.hub":
				m.hud.inspect(_id("R3"), m.cam)
				await _shot("hub-inspector")
				await _play(func(t): if not once.has(key): once[key] = true; m.node_action("build", _id("R3"), {"kind": "monster_hub"}))
			"L6.send":                                       # 0.19.2: tap the monster over the hub, then the end node
				await _secs(0.5)
				if m.hud.monster_icon.visible:
					m.hud.monster_icon.pressed.emit()
				await _secs(0.4)
				await _shot("monster-armed")
				await _play(func(t): if not once.has(key): once[key] = true; m.node_action("launch_monster", _id("R3"), {"to": _id("M2")}); m.monster_from = -1)
			"L6.take":
				await _secs(2.0)
				await _shot("monster-walking")
				await _play(func(t): pass)
			"L7.evacuate":
				await _play(func(t):
					if not once.has(key):
						once[key] = true
						_send("H", "I1", 1.0)
						_send("A1", "I2", 1.0)
						_send("A2", "I2", 1.0)
					if sim.last_stand_active and not once.has("ls"):
						once["ls"] = true
						for nm in ["H", "A1", "A2"]:
							if sim.nodes[_id(nm)]["owner"] == "A":
								_send(nm, "I1", 1.0)
					if sim.last_stand_active and not once.has("ls_shot") and not sim.last_stand_warn.is_empty():
						once["ls_shot"] = true)
			"L7.vls":
				await _secs(1.0)
				await _shot("vls-running")
				_got_it()
				await _frames(4)
			"L7.hold":
				await _play(func(t):                      # the player follows the hand: off the warned node
					var mv := d._vls_move()
					if not mv.is_empty() and not sim.hordes.any(func(h): return h["owner"] == "A" and int(h["route"][0]) == int(mv[0])):
						m.node_action("send", int(mv[0]), {"to": int(mv[1]), "fraction": 1.0}))
			"L8.surge":
				await _secs(1.0)
				m.hud.dock.press_slot(0)
				await _shot("surge-armed")
				await _play(func(t):
					for h in sim.hordes:
						if h["owner"] == "A" and sim.cast_check("A", "active", h["id"]) == "":
							m.node_action("cast", 0, {"target": h["id"]})
							break)
			"L8.demolish":
				await _play(func(t):
					for h in sim.hordes:
						if h["owner"] != "B":
							continue
						for sp in h["spans"]:
							if h["s"] >= sp["s0"] + 2.0 and h["s"] <= sp["s1"] and sim.cast_check("A", "map", sp["edge"]) == "":
								m.node_action("cast", 1, {"target": sp["edge"]})
								return)
			"L8.ultimate":
				await _play(func(t):
					var ts := sim.targets_for("A", "ultimate")
					if not ts.is_empty():
						m.node_action("cast", 2, {"target": ts[0]}))
			"L9.start":
				_got_it()
				await _secs(0.5)
				await _shot("match-running")
				_stage_l9()
				var st9 := {"shot": false, "fired": false}
				var t := 0.0
				Engine.time_scale = FAST
				while d.state != "complete" and t < 150.0:
					var hid := d.catch_line()
					if d.catch_prompt() and not st9["shot"]:
						st9["shot"] = true
						await _shot("push-prompt")
						Engine.time_scale = FAST
					if d.catch_prompt() and hid >= 0 and not st9["fired"]:
						st9["fired"] = true
						m.node_action("switch", _id("R"))
					await get_tree().process_frame
					t += get_process_delta_time()
				Engine.time_scale = 1.0
			_:
				if d.L["steps"][d.step_i].get("read_only", false):
					await _secs(0.4)
					_got_it()
					await _frames(4)
				else:
					await _play(func(t): pass)
		await _frames(2)
	await _secs(0.6)
	if id != 0:
		await _shot("complete" if d.state == "complete" else "FAILED")
	m.queue_free()
	await _frames(6)


func _stage_l9() -> void:
	var sim: Sim = m.sim
	var R := _id("R")
	for x in sim.nodes:
		if x["id"] in [_id("H"), 1, 2, 3, R]:
			x["owner"] = "A"
			x["units"] = 30.0 * Rules.SCALE
		elif x["id"] in [_id("BH"), 8, 9, 10]:
			x["owner"] = "B"
			x["units"] = 25.0 * Rules.SCALE
		MapBuilder.apply_owner(m.vis[x["id"]]["parts"], x["owner"])


# ------------------------------------------------------------------ one contact sheet per lesson
func _sheet(id: int) -> void:
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
		l.text = "L%d · %02d · %s" % [id, i, str(shots[i][0]).to_upper()]
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
	var path := "%s/L%d-sheet.png" % [out_dir, id]
	sub.get_texture().get_image().save_png(path)
	sub.queue_free()
	print("SHEET ", path)
