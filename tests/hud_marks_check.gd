extends Node
## HUD marks check (ui-neon, Daniele 2026-11-02 on 0.23.18: "upgrade badges not appearing, unit count HUD disappearing, some
## of the alert signs disappear"). Windowed only (a scene: the Net autoload exists). For each map it starts the real game on
## the phone HUD, fast-forwards into the Last Stand (the rival AI playing) and checks what a player must always see:
##   count  - every standing node's badge is shown with its count (or the owner's emblem where counts are hidden) - warned
##            nodes included (0.19.0-0.23.18 hid a warned node's whole badge: a falling ring lost every count)
##   signs  - every warned node has its alarm sign on screen, at least SIGN_MIN_PT tall; one RED (the next to fall), at most
##            one YELLOW, the rest GREY; none sits on its own node's badge; a sign just shown is pulsing
##   chip   - one of your vats that can upgrade shows the upgrade chip, at least CHIP_MIN_PT across, clear of its badge
##   Godot --path . --audio-driver Dummy --position -6000,-6000 res://tests/hud_marks_check.tscn -- --mobile --scale3d=0.75
##       [maps=N-08,N-28,M-39] [window=1688x780] [out=<file>] [faction=vex] [active=<skill id>] [shots=<dir>]
## Prints one line per map and HUD MARKS: PASS / FAIL (exit 1).

const MAIN := "res://main.tscn"
const SIGN_MIN_PT := 20.0              # the grey sign's plate + beacon, tall (the red one is ~38 pt)
const CHIP_MIN_PT := 33.0              # the upgrade chip across (the phone's readable / tappable floor in the brief)
const TRIES := 2                       # matches per map to reach the Last Stand (the second without AI)

var _fails := 0
var _lines: PackedStringArray = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("hud_marks_check: windowed only")
		get_tree().quit(2)
		return
	_run.call_deferred()


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.trim_prefix("--").begins_with(name + "="):
			return a.trim_prefix("--").substr(name.length() + 1)
	return def


func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame


func _run() -> void:
	var wh := _arg("window", "1688x780").split("x")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	await _frames(2)
	var main_script = load("res://scripts/main.gd")
	for code in _arg("maps", "N-08,N-28,M-39").split(","):
		var path := ""
		for f in DirAccess.get_files_at("res://maps4"):
			if f.begins_with(code) and f.ends_with(".json"):
				path = "res://maps4/" + f
		if path == "":
			_lines.append("%s FAIL map not found" % code)
			_fails += 1
			continue
		var m := MapBuilder.load_map(path)
		for attempt in range(TRIES):                       # an AI-vs-AI match on a small map can end before 4:00: again, no AI
			main_script.relaunch = {"faction": _arg("faction", "vex"), "mode": str(m["modes"][0]), "map": path}
			if _arg("active", "") != "":                   # Neon Noir shots: a loadout's active skill (EMERGENCY EVAC's two lines)
				main_script.relaunch["loadout"] = {"active": _arg("active", "")}
			var inst: Node = (load(MAIN) as PackedScene).instantiate()
			inst.mobile = true
			get_tree().root.add_child(inst)
			var t0 := Time.get_ticks_msec()
			while not bool(inst.get("started")) and Time.get_ticks_msec() - t0 < 20000:
				await get_tree().process_frame
			await _frames(10)
			var reached: bool = await _check(code, inst, attempt)
			inst.queue_free()
			await _frames(3)
			if reached:
				break
	var verdict := "PASS" if _fails == 0 else "FAIL (%d map(s))" % _fails
	_lines.append("HUD MARKS: %s" % verdict)
	print(_lines[-1])
	var out := _arg("out", "")
	if out != "":
		var fa := FileAccess.open(out, FileAccess.WRITE)
		fa.store_string("\n".join(_lines) + "\n")
		fa.close()
	get_tree().quit(0 if _fails == 0 else 1)


func _ff(inst: Node, sim, until_warned: bool, limit: float, with_ai: bool) -> void:
	## main's own --ff loop: the AIs think - one plays your seat too, so you are still in the match at the Last Stand - and the
	## sim steps (only the end state renders). Without AI (a retry) nobody attacks: the Last Stand always comes.
	var ais: Array = (inst.get("ais") as Array).duplicate() if with_ai else []
	if with_ai:
		ais.append(SeatAI.new(str(inst.get("HUMAN")), 2.5, str(inst.get("ai_level"))))
	while sim.time < limit and not sim.over:
		for ai in ais:
			ai.think(sim, 0.1)
		sim.step(0.1)
		if until_warned and not sim.last_stand_warn.is_empty() and sim.last_stand_warn_t < 9.5:
			break
	sim.fx_events.clear()


func _check(code: String, inst: Node, attempt: int) -> bool:
	## The checks on one match; false (nothing recorded) when it ended before the Last Stand and another try is left.
	var sim = inst.get("sim")
	var hud = inst.get("hud")
	var overlay = hud.get("overlay")
	var human: String = inst.get("HUMAN")
	var vp: Vector2 = inst.get_viewport().get_visible_rect().size
	var ppt: float = UiKit.pt_per_px(vp)
	var api: bool = overlay.has_method("danger_tiers")
	var bad: PackedStringArray = []
	# ---- the upgrade chip: one of your vats topped up to its cap (early: nothing attacks it yet)
	var chip := "n/a"
	var vat := -1
	for n in sim.nodes:
		if n["owner"] == human and n["structure"] == "vat" and n["tier"] < Rules.VAT_MAX_UPGRADE:
			vat = n["id"]
			break
	if vat >= 0:
		sim.nodes[vat]["units"] = maxf(sim.nodes[vat]["units"], float(sim.upgrade_cost(sim.nodes[vat])))
		await _frames(8)
		if sim.can_upgrade(vat, human) == "" and not sim.node_under_attack(vat, human):
			if not api:
				chip = "no chip api"
				bad.append("chip")
			else:
				var cr: Rect2 = overlay.upgrade_chip_rect(vat)
				var badge: Control = hud.badges[vat]["panel"]
				var across := cr.size.x * ppt
				chip = "%.1f pt" % across
				if cr.size == Vector2.ZERO or across < CHIP_MIN_PT or not Rect2(Vector2.ZERO, vp).encloses(cr) \
						or (badge.visible and cr.intersects(Rect2(badge.position, badge.size))):
					bad.append("chip")
		else:
			chip = "vat busy (%s)" % sim.can_upgrade(vat, human)
	# ---- into the Last Stand
	_ff(inst, sim, true, Rules.LAST_STAND_TIME + 120.0, attempt == 0)
	await _frames(12)
	var warned := []
	for n in sim.nodes:
		if not sim.collapsed.get(n["id"], false) and sim.is_warned(n["id"]):
			warned.append(n["id"])
	# ---- every standing node shows its count (or the owner's emblem where counts are hidden)
	var nocount := 0
	for n in sim.nodes:
		var id: int = n["id"]
		if sim.collapsed.get(id, false) or n.get("node_kind", "") == "junction":
			continue
		var b: Dictionary = hud.badges[id]
		var shown: bool = (b["panel"] as Control).visible and (((b["label"] as Label).visible and (b["label"] as Label).text != "") 				or (b["emblem"] as TextureRect).visible)
		if not shown:
			nocount += 1
	if nocount > 0:
		bad.append("count")
	# ---- the alarm signs
	var reds := 0
	var yellows := 0
	var greys := 0
	var small := 0
	var off := 0
	var on_badge := 0
	var unpulsed := 0
	if not api:
		if not warned.is_empty():
			bad.append("signs (no tiers api)")
	else:
		var tiers: Dictionary = overlay.danger_tiers()
		for id in warned:
			var t: int = int(tiers.get(id, -1))
			reds += 1 if t == 0 else 0
			yellows += 1 if t == 1 else 0
			greys += 1 if t == 2 else 0
			var sr: Rect2 = overlay.sign_rect(id)
			if sr.size.y * ppt < SIGN_MIN_PT:
				small += 1
			if not Rect2(Vector2.ZERO, vp).encloses(sr):
				off += 1
			var badge: Control = hud.badges[id]["panel"]
			if badge.visible and sr.intersects(Rect2(badge.position, badge.size)):
				on_badge += 1
			if float(overlay.get("_sign_pulse").get(id, 0.0)) <= 0.0:
				unpulsed += 1
		if not warned.is_empty() and (reds != 1 or yellows > 1 or reds + yellows + greys != warned.size()):
			bad.append("tiers")
		if small > 0 or off > 0 or on_badge > 0:
			bad.append("signs")
		if unpulsed > 0:
			bad.append("pulse")
	if warned.is_empty():
		if attempt < TRIES - 1:
			print("%s: match over at t=%.1f before the Last Stand - again" % [code, sim.time])
			return false
		bad.append("no Last Stand reached")
	var ok := bad.is_empty()
	if not ok:
		_fails += 1
	var line := "%s %-4s t=%5.1f nodes %2d  count-missing %d  warned %d (red %d yellow %d grey %d; small %d off %d on-badge %d unpulsed %d)  chip %s%s" % [
			code, "ok" if ok else "FAIL", sim.time, sim.nodes.size(), nocount, warned.size(), reds, yellows, greys, small, off, on_badge,
			unpulsed, chip, "" if ok else "  <- " + ", ".join(bad)]
	_lines.append(line)
	print(line)
	var shots := _arg("shots", "")
	if shots != "" and api and not warned.is_empty():
		await _pulse_shots(code, inst, shots)
	return true


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("screenshot ", path)


func _pulse_shots(code: String, inst: Node, dir: String) -> void:
	## shots=<dir>: the Last Stand as it stands, then the next drop - the signs move up a tier and pulse - at +0.15 / +0.5 /
	## +0.9 s (the pulse's beats) and +2.2 s (settled).
	var sim = inst.get("sim")
	DirAccess.make_dir_recursive_absolute(dir)
	await _frames(30)
	await _grab("%s/%s_ls.png" % [dir, code])
	var left: int = sim.last_stand_queue.size()
	var t0 := Time.get_ticks_msec()
	while sim.last_stand_queue.size() == left and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	var t1 := Time.get_ticks_msec()
	for at in [0.15, 0.5, 0.9, 2.2]:
		while Time.get_ticks_msec() - t1 < int(at * 1000.0):
			await get_tree().process_frame
		await _grab("%s/%s_pulse_%.2f.png" % [dir, code, at])
