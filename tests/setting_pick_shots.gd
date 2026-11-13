extends Node
## SETTING PICK shots (2026-11-13): PLAY VS AI and the online room (host + guest) with the SETTING button and its sheet.
## Built on menu_flow_shots.gd (same stub room). Windowed only.
##   Godot --path . --resolution 1624x750 --audio-driver Dummy --position -6000,-6000 res://tests/setting_pick_shots.tscn -- \
##     --mobile --pt-height=375 --no-notice --no-account --no-telemetry --ui-cfg=<scratch cfg> --out=<dir>
## Rooms are faked locally (a stub bridge, as the 2026-11-02 UI capture did): the layout only, no network.
var main: Node
var out := "user://"
var m


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	main = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func shot(name: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("screenshot ", path)


func _fake_room(mode: String, guest: bool, ready_all := false) -> void:
	var stub := GDScript.new()
	stub.source_code = "extends Node\nfunc poll(): pass\nfunc _get(_p): return null\n"
	stub.reload()
	Net.bridge = stub.new()
	Net.connected = true
	Net.hosting = not guest
	Net.room_code = "K7QD"
	Net.room_owner = 1
	Net.assigned_id = 2 if guest else 1
	Net.mode = mode
	var pool: Array = Net.maps_for(mode)
	Net.map_path = str(pool[0]) if not pool.is_empty() else ""
	var facs := ["vex", "null", "ember", "solar", "bloom"]
	Net.roster = {}
	var n := Net.slots() - (1 if not guest else 0)
	for i in range(n):
		Net.roster[i + 1] = {"faction": facs[i], "slot": i, "colour": "", "name": ["DANIELE", "MIRA", "LUCA", "GOOGIRL", "VEX-99"][i],
				"ready": ready_all and i > 0}
	Net.chat_history = [{"id": 1, "pid": 2, "who": "MIRA", "seat": "B", "text": "gl hf"},
			{"id": 2, "pid": 1, "who": "DANIELE", "seat": "A", "text": "ready when you are"},
			{"id": 3, "pid": 3, "who": "LUCA", "seat": "C", "text": "give me a sec, picking my army"}]


func _run() -> void:
	await _frames(40)
	m = main.menu_layer
	UiKit.save_setting_choice("golden_hour")
	m.show_setup()
	await shot("01-vs-ai-setup")
	m._bg_sheet = true
	m.show_setup()
	await shot("02-vs-ai-setting-sheet")
	m._bg_sheet = false
	_fake_room("2v2", false)
	m._setting_room = Net.room_code                  # (the stub room can't publish: the remembered pick is set by hand)
	Net.room_backdrop = "3"
	m.show_lobby()
	await shot("03-room-host")
	m._lobby_sheet = "setting"
	m.show_lobby()
	await shot("04-room-host-setting-sheet")
	m._lobby_sheet = ""
	_fake_room("2v2", true)
	Net.room_backdrop = "3"
	m.show_lobby()
	await shot("05-room-guest")
	m._lobby_sheet = "setting"
	m.show_lobby()
	await shot("06-room-guest-setting-sheet")
	get_tree().quit()
