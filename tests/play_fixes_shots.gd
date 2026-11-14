extends Node
## play-fixes shots (2026-11-14): windowed, R-01 on the phone HUD at 812x375 emulation.
##   chevron: your first vat below / at its upgrade cost; gat: a Googatling's stock filling from low.
##   Godot --path . --audio-driver Dummy --position -6000,-6000 res://tests/play_fixes_shots.tscn -- --mobile out=<dir> [window=812x375]
const MAIN := "res://main.tscn"

func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.trim_prefix("--").begins_with(name + "="):
			return a.trim_prefix("--").substr(name.length() + 1)
	return def

func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame

func _snap(inst: Node, name: String) -> void:
	await _frames(6)
	var img := get_viewport().get_texture().get_image()
	img.save_png(_arg("out", "C:/Users/itisf/work/shots/pf") + "/" + name + ".png")

func _dtap(c: Vector2) -> void:
	for k in range(2):
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.position = c
			ev.global_position = c
			get_viewport().push_input(ev, true)
			await _frames(1)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := _arg("out", "C:/Users/itisf/work/shots/pf")
	DirAccess.make_dir_recursive_absolute(out)
	var wh := _arg("window", "812x375").split("x")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	await _frames(2)
	var main_script = load("res://scripts/main.gd")
	var path := "res://maps4/" + _arg("map", "R-01-strait") + ".json"
	var m := MapBuilder.load_map(path)
	main_script.relaunch = {"faction": "vex", "mode": str(m["modes"][0]), "map": path}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	inst.mobile = true
	get_tree().root.add_child(inst)
	var t0 := Time.get_ticks_msec()
	while not bool(inst.get("started")) and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	await _frames(20)
	var sim = inst.get("sim")
	var human: String = inst.get("HUMAN")
	var vat := -1
	for n in sim.nodes:
		if n["owner"] == human and n["structure"] == "vat" and n["tier"] < Rules.VAT_MAX_UPGRADE:
			vat = n["id"]
			break
	var cost: float = float(sim.upgrade_cost(sim.nodes[vat]))
	print("vat ", vat, " tier ", sim.nodes[vat]["tier"], " cost ", cost, " units ", sim.nodes[vat]["units"])
	sim.nodes[vat]["units"] = cost * 0.5
	await _snap(inst, "chev-1-below")
	sim.nodes[vat]["units"] = cost
	await _snap(inst, "chev-2-at-cost")
	var hud = inst.get("hud")
	var cr: Rect2 = hud.overlay.upgrade_chip_rect(vat)
	print("chip rect ", cr, " can_upgrade '", sim.can_upgrade(vat, human), "' under_attack ", sim.node_under_attack(vat, human))
	# double-tap the node while the chevron shows: upgrades
	var cam = inst.get("cam")
	var nc: Vector2 = hud.overlay._node_screen(vat, cam)[0]
	await _dtap(nc)
	print("DOUBLE-TAP vat: build_kind '", sim.nodes[vat]["build_kind"], "'")
	await _snap(inst, "chev-3-after-double-tap")
	# a relay of yours: ready symbol, then a double-tap fires it
	var rid := -1
	for n in sim.nodes:
		if n["relay"] != "" and not sim.relay_fixed(n["id"]):
			rid = n["id"]
			break
	if rid >= 0:
		sim.nodes[rid]["owner"] = human
		await _snap(inst, "relay-1-ready")
		print("relay ", rid, " kind ", sim.nodes[rid]["relay"], " ready chip ", hud.overlay.relay_chip_rect(rid))
		var rs: Array = hud.overlay._node_screen(rid, cam)
		var bs: Array = RelayView.button_screen(cam, inst.get("vis"), rid)
		await _dtap((bs[0] if not bs.is_empty() else rs[0]) as Vector2)
		print("DOUBLE-TAP relay: phase '", sim.nodes[rid]["relay_phase"], "' ready ", hud.overlay.relay_ready(rid))
		await _snap(inst, "relay-2-fired")
	else:
		print("NO RELAY on R-01")
	# GOOGATLING: a second owned common node becomes a Googatling, stock low, then filling
	var gid := -1
	for n in sim.nodes:
		if n["owner"] == "" and n["id"] != vat and n["structure"] == "vat" and n["node_kind"] == "common":
			gid = n["id"]
			sim.nodes[gid]["owner"] = human
			break
	if gid >= 0:
		sim.nodes[gid]["units"] = 100.0
		sim.build(gid, human, "machinegoon")
		while sim.nodes[gid]["build_kind"] != "":
			sim.step(0.5)
		sim.nodes[gid]["units"] = 3.0
		await _snap(inst, "gat-1-low")
		for i in range(5):
			sim.step(1.0)
			sim.nodes[gid]["units"] += 0.0
		print("GAT stock ", sim.nodes[gid]["units"], " rate ", sim.gat_rate(sim.nodes[gid]))
		await _snap(inst, "gat-2-filling")
		for i in range(40):
			sim.step(1.0)
		await _snap(inst, "gat-3-later")
		print("GAT stock later ", sim.nodes[gid]["units"], " cap ", Sim.gat_cap(sim.nodes[gid]))
	get_tree().quit(0)
