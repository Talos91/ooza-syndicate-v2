extends Node
## Screenshot helper (ui-a24): a staged lobby (two players, host) under the real menu, for the contact sheet.
## Godot --path . res://tests/lobby_ui_shot.tscn -- --window=... --mobile --pt-height=390 --theme=dark --menu-page=lobby --menu-shot=<png>
class FakeBridge extends Node:
	func close(): pass
	func poll(): pass
	func poll_events(): return []
	func send(_a = null, _b = null, _c = null): pass
	func send_bin(_a = null, _b = null, _c = null): pass
	func start(_a = null, _b = null, _c = null): return true
	func start_with(_a = null, _b = null, _c = null): return true
func _ready() -> void:
	Net.bridge = FakeBridge.new()
	Net.hosting = true
	Net.connected = true
	Net.room_code = "K7QX"
	Net.mode = "1v1"
	Net.map_path = "res://maps4/N-01-knot.json"
	Net.roster = {1: {"faction": "vex", "slot": 0, "colour": 0, "name": "DANIELE"}, 2: {"faction": "ember", "slot": 1, "colour": 1, "name": "RIVAL"}}
	get_tree().change_scene_to_file.call_deferred("res://main.tscn")
