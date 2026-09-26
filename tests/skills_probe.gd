extends Node
## Render probe for the SKILLS 2.0 dock (0.18.7; a dev tool, not a suite). Run windowed, as a scene (the Net
## autoload is needed):
##   Godot --path . res://tests/skills_probe.tscn -- state=<state> out=<png> [--mobile --window=1688x780] [--brawl]
##       [map=res://maps4/M-03-drift-belt.json] [faction=null] [active=surge] [mapskill=mire]
## states: ready (every slot ready; the ultimate's READY burst), cooldown (active + map cooling, the ultimate
## charging), armed-line (Surge: your lines lit), armed-deck (the map skill's decks lit), armed-node (Ghost Line:
## the source picked, its destinations lit), toast (rivals' casts on you), rewire (VEX's Rewire running: relays
## lit, fires left). Every cast goes through the dock -> main.node_action("cast", ...): the probe prints the
## toasts it produced ("<Name> cast") and PROBE CAST ok / FAIL from the Sim's own cast events.

const MAIN := "res://main.tscn"
var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--") and "=" in a:
			var kv := a.split("=", true, 1)
			args[kv[0]] = kv[1]
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _run() -> void:
	var state := str(args.get("state", "ready"))
	var f := str(args.get("faction", "vex" if state == "rewire" else "null"))
	var lo := {"active": str(args.get("active", "ghost_line" if state == "armed-node" else "surge")), "map": str(args.get("mapskill", "mire"))}
	var main_script = load("res://scripts/main.gd")
	main_script.relaunch = {"faction": f, "rival": "ember", "mode": "1v1", "map": str(args.get("map", "res://maps4/M-03-drift-belt.json")), "loadout": lo}
	var inst: Node = (load(MAIN) as PackedScene).instantiate()
	get_tree().root.add_child(inst)
	await _frames(12)
	inst.ais.clear()                                     # a still picture: nobody else moves
	var s: Sim = inst.sim
	var dock: SkillDock = inst.hud.dock
	var home: int = s.homes["A"]
	var nb: int = s.adj[home][0][0]
	var casts0 := s.events.filter(func(e): return e["type"] == "skill" and e["seat"] == "A").size()
	match state:
		"ready":
			_line(s, home, nb)
			await _frames(40)
			s.ult_charge["A"] = 0.9995
			s.ult_since["A"] = 100.0
			await _frames(30)
		"cooldown":
			_line(s, home, nb)
			await _frames(50)
			dock.press_slot(0)
			await _frames(2)
			if not dock.cands.is_empty():
				dock.pick(dock.cands[0])
			dock.press_slot(1)
			await _frames(2)
			if not dock.cands.is_empty():
				dock.pick(dock.cands[0])
			s.skill_cd["A"]["active"] = 17.4
			s.skill_cd["A"]["map"] = 9.2
			s.ult_since["A"] = 60.0
			s.ult_charge["A"] = 0.46
			await _frames(6)
		"armed-line":
			_line(s, home, nb)
			var far: int = s.adj[nb][0][0] if s.adj[nb][0][0] != home else s.adj[nb][-1][0]
			await _frames(30)
			_line(s, home, far)
			await _frames(60)
			dock.press_slot(0)
			await _frames(20)
		"armed-deck":
			dock.press_slot(1)
			await _frames(20)
		"armed-node":
			dock.press_slot(0)
			await _frames(4)
			dock.pick(home)
			await _frames(20)
		"toast":
			s.fx_events.append({"type": "skill", "id": "scorch", "seat": "B", "slot": "active", "target": 0, "pos": Vector3.ZERO, "affects": ["A"]})
			await _frames(3)
			s.fx_events.append({"type": "skill", "id": "demolish", "seat": "B", "slot": "map", "target": 0, "pos": Vector3.ZERO, "affects": ["A"]})
			await _frames(20)
		"rewire":
			s.ult_charge["A"] = 1.0
			s.ult_since["A"] = 100.0
			await _frames(3)
			dock.press_slot(2)                              # Rewire: no target, cast at once
			await _frames(10)
			dock.press_slot(2)                              # ... then the slot fires relays
			await _frames(20)
	var casts := s.events.filter(func(e): return e["type"] == "skill" and e["seat"] == "A").size() - casts0
	var toasts := []
	for c in inst.hud.notices.get_children():
		toasts.append(str(c.get_meta("text", "")))
	print("PROBE state=%s armed=%d cands=%d casts=%d toasts=%s" % [state, dock.armed, dock.cands.size(), casts, toasts])
	if state in ["cooldown", "rewire"]:
		print("PROBE CAST %s" % ("ok" if casts >= 1 and toasts.any(func(t): return t.ends_with(" cast")) else "FAIL"))
	await RenderingServer.frame_post_draw
	var out := str(args.get("out", "user://skills_probe.png"))
	get_viewport().get_texture().get_image().save_png(out)
	print("screenshot ", out)
	get_tree().quit()


func _line(s: Sim, a: int, b: int) -> void:
	s.nodes[a]["units"] = maxf(s.nodes[a]["units"], 120.0)
	s.send(a, b, 0.5)
