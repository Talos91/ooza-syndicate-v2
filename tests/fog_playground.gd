extends Node
## FOG PLAYGROUND (Daniele 2026-11-11): R-01 STRAIT running for real, with switches for the two background layers.
##   cloud / fog         the side-band backdrop layers (0 = absent, 1 = fully opaque where present)
##   centre cloud / fog  the same layers on a plane between the decks and the floor, so the CENTRE gets them too (x factor)
##   fog colour          what the fog layer turns into when a seat leads (the clouds never change)
##   tubes: v3 / ortho   switches the transport tubes between the free routing and the cardinal-axis grid routing
##   ENDGAME             every column built and every tube filled;  HUD  hides the game's HUD to see the picture
## Run (desktop):  Godot_v4.6.1-stable_win64.exe --path <Game/2.0 clone> res://tests/fog_playground.tscn -- --test
## Same layers in the game: --backdrop-fog=<low|mid|high|none>  --centre-fog=<0..1>

var inst: Node
var sky_mat: ShaderMaterial
var wl: WorldLayer
var amt := {"cloud": 0.9, "fog": 0.6, "ccloud": 0.9, "cfog": 0.6}
var _panel: PanelContainer
var _share := {"A": 0.0, "B": 0.0}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var f := ""
	for g in DirAccess.get_files_at("res://maps4"):
		if g.begins_with("R-01") and g.ends_with(".json"):
			f = g
	load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "ember", "mode": "1v1", "map": "res://maps4/" + f}
	inst = (load("res://main.tscn") as PackedScene).instantiate()
	inst.demo = false
	add_child(inst)
	for i in range(8):
		await get_tree().process_frame
	inst.ais.clear()
	wl = inst.world_layer
	var tries := 0
	while (wl.pipes == null or not wl.pipes.built or wl.center_fog_mat == null) and tries < 600:
		await get_tree().process_frame
		tries += 1
	sky_mat = inst.scenery.backdrop.get_child(0).material
	_build_panel()
	_apply()


func _build_panel() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	_panel = PanelContainer.new()
	_panel.position = Vector2(110, 60)
	cl.add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	for k in [["cloud", "cloud (sides)"], ["fog", "fog (sides)"], ["ccloud", "cloud (centre)"], ["cfog", "fog (centre)"]]:
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = k[1]
		l.custom_minimum_size.x = 110
		h.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.01
		s.value = amt[k[0]]
		s.custom_minimum_size.x = 180
		s.value_changed.connect(func(x): amt[k[0]] = x; _apply())
		h.add_child(s)
		v.add_child(h)
	var lbl := Label.new()
	lbl.text = "FOG COLOUR TEST: share of the nodes held (the rest is gray)"
	v.add_child(lbl)
	for k in [["A", "A (cyan) share"], ["B", "B (red) share"]]:
		var h2 := HBoxContainer.new()
		var l2 := Label.new()
		l2.text = k[1]
		l2.custom_minimum_size.x = 110
		h2.add_child(l2)
		var s2 := HSlider.new()
		s2.min_value = 0.0
		s2.max_value = 1.0
		s2.step = 0.01
		s2.value = 0.0
		s2.custom_minimum_size.x = 180
		s2.value_changed.connect(func(x): _share[k[0]] = x; _fog_test())
		h2.add_child(s2)
		v.add_child(h2)
	var br := Button.new()
	br.text = "fog: follow the real nodes again"
	br.pressed.connect(func(): inst.fog_lead.fog_force = {})
	v.add_child(br)
	var row := HBoxContainer.new()
	v.add_child(row)
	var row2 := HBoxContainer.new()
	v.add_child(row2)
	var be := Button.new()
	be.text = "ENDGAME"
	be.pressed.connect(_endgame)
	row2.add_child(be)
	var bt := Button.new()
	bt.text = "tubes: v3 / bundle / ortho"
	bt.pressed.connect(func():
		var pp: WorldTubes = wl.pipes
		if not pp.ortho and not pp.bundle:
			pp.rebuild(false, true)
		elif pp.bundle:
			pp.rebuild(true)
		else:
			pp.rebuild(false)
		print("tubes ortho=", pp.ortho, " bundle=", pp.bundle, " ribbons ", pp.bundle_stats))
	row2.add_child(bt)
	var bh := Button.new()
	bh.text = "hide panel (H)"
	bh.pressed.connect(func(): _panel.visible = false)
	row2.add_child(bh)


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_H and _panel != null:
		_panel.visible = not _panel.visible


func _apply() -> void:
	if sky_mat == null:
		return
	sky_mat.set_shader_parameter("cloud_amt", amt["cloud"])
	sky_mat.set_shader_parameter("fog_amt", amt["fog"])
	wl.center_fog_mat.set_shader_parameter("cloud_amt", amt["ccloud"])
	wl.center_fog_mat.set_shader_parameter("fog_amt", amt["cfog"])


func _fog_test() -> void:
	## forces the fog mix: A and B hold these shares of the nodes, the rest is gray (the fog eases to it like in a match)
	inst.fog_lead.fog_force = {"A": _share["A"], "B": _share["B"]}


func _fog_col(c: Color) -> void:
	sky_mat.set_shader_parameter("fog_col", c)
	wl.center_fog_mat.set_shader_parameter("fog_col", c)


func _endgame() -> void:
	for i in wl.pipes.cols:
		var n: Dictionary = inst.sim.nodes[wl._tubes[i]["id"]]
		n["owner"] = "A" if float(wl._tubes[i]["x"]) < 0.0 else "B"
		n["structure"] = "vat"
		n["tier"] = 3
