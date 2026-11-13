extends Node
## MENU FLOWS (Alpha 24 step 3, UX pass): boots main.tscn and saves every new menu screen at phone size. Windowed only.
##   Godot --path . --resolution 1624x750 --audio-driver Dummy --position -6000,-6000 res://tests/menu_flow_shots.tscn -- \
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
	m.show_main()
	await shot("01-home")
	m._join_open = true
	Net.status = "Room not found - check the code"
	m.show_main()
	await shot("02-home-join-code-error")
	Net.status = ""
	m._join_open = false
	m.show_setup()
	await shot("03-match-setup")
	for sh in [["seat:B", "03b-setup-seat-sheet"], ["mode", "03c-setup-mode-sheet"]]:   # ROUND 4
		m._lobby_sheet = sh[0]
		m.show_setup()
		await shot(sh[1])
	m._lobby_sheet = ""
	m._bg_sheet = true
	m.show_setup()
	await shot("04-setup-setting-sheet")
	m._bg_sheet = false
	m._open_maps()
	await shot("05-map-picker")
	m._map_list = "favourites"
	m.show_maps()
	await shot("06-map-picker-favourites-empty")
	m._map_list = ""
	Menu.map_filter_mode = "1v1"
	Menu.map_filter_type = "all"
	m.show_maps()
	await shot("06b-map-picker-1v1-size-tabs")
	m._cancel_pick()
	m._pick(m.show_factions)
	await shot("07-faction-picker")
	m._cancel_pick()
	m.mode = "FFA4" if "FFA4" in m._modes_of(m._selected_map()) else m.mode
	m._pick(m.show_seats)
	await shot("08-rivals-sheet")
	m._cancel_pick()
	m._pick(m.show_setup_advanced)
	await shot("09-rules-sheet")
	m._cancel_pick()
	m._pick(m.show_colours)
	await shot("10-colour-sheet")
	m._cancel_pick()
	_fake_room("2v2", false)
	m.show_lobby()
	await shot("11-room-host-2v2")
	m._open_maps()
	await shot("12-room-host-map-picker")
	m._cancel_pick()
	for sh in [["rules", "14-room-sheet-rules"], ["mode", "15-room-sheet-mode"], ["seat:1", "16-room-sheet-seat"],
			["setting", "17-room-sheet-setting"], ["colour", "18-room-sheet-colour"]]:
		m._lobby_sheet = sh[0]
		m.show_lobby()
		await shot(sh[1])
	m._lobby_sheet = ""
	for md in [["3v3", "19-room-host-3v3"], ["2v2v2", "20-room-host-2v2v2"], ["FFA5", "21-room-host-ffa5"]]:
		_fake_room(md[0], false, true)
		m.show_lobby()
		await shot(md[1])
	_fake_room("1v1", true)
	m.show_lobby()
	await shot("13-room-guest-1v1")
	_fake_room("2v2", true)
	m._lobby_sheet = "seat:0"
	m.show_lobby()
	await shot("22-room-guest-2v2-seat-sheet")
	m._lobby_sheet = ""
	m._pick(m.show_factions)                          # ROUND 4: ARMY from the room, then EDIT LOADOUT
	await shot("23-room-army")
	m.show_armies(m.faction, m.show_factions)
	await shot("24-loadout-from-lobby")
	m._save_armies()
	await shot("24b-after-save")
	_fake_room("2v2", false)
	m._lobby_sheet = "seat:3"
	m.show_lobby()
	await shot("16b-room-host-open-seat-sheet")
	m._lobby_sheet = ""
	m.show_options()
	await shot("25-settings")
	get_tree().quit()
