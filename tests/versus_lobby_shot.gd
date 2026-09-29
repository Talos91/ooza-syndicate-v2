extends Node
## 0.23.2 probe (windowed): the VERSUS card raised from a lobby's data, as a player sees it right after DEPLOY.
##   Godot --path . --resolution 1266x585 res://tests/versus_lobby_shot.tscn
func _ready() -> void:
	Net.hosting = true
	Net.mode = "1v1"
	Net.map_path = "res://maps4/N-01-knot.json"
	Net.roster = {1: {"faction": "vex", "slot": 0, "colour": 0, "name": "DANIELE"}, 2: {"faction": "ember", "slot": 1, "colour": 1, "name": "RIVAL"}}
	VersusScreen.hold_lobby(get_tree().root)
	for i in range(40):
		await get_tree().process_frame
	var card := get_tree().root.get_node_or_null(LaunchCard.NAME)
	print("LOBBY CARD: ", card != null and card is VersusScreen, " lobby=", card.get("lobby") if card else null)
	get_viewport().get_texture().get_image().save_png("user://versus_lobby.png")
	print("screenshot user://versus_lobby.png")
	get_tree().quit(0 if card != null else 1)
