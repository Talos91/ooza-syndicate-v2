class_name LaunchCard
extends CanvasLayer
## 0.23.1 (Daniele: "the game freezes on the deploy page, shows the vs screen for half a sec and then starts"): a room's launch
## reloads the whole scene, and nothing draws during that reload - so the VERSUS card could only appear after the freeze.
## This card goes up on the window's root (it survives reload_current_scene) the moment the launch arrives, is drawn before the
## reload starts (Net._reload_after_card), and stays until the match scene's own VERSUS card is up (VersusScreen removes it) -
## the player sees one loading screen from DEPLOY to the battlefield. Never on the room server or a headless run.

const NAME := "LaunchCard"
const MAX_SECONDS := 30.0                            # safety: gone by itself if nothing takes over (a failed launch)

var _t := 0.0


static func raise(root: Node, info: Dictionary, map_name: String) -> void:
	drop(root)
	var c := LaunchCard.new()
	c.name = NAME
	c.layer = 120
	c.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(c)
	c._build(info, map_name)


static func drop(root: Node) -> void:
	var old := root.get_node_or_null(NAME)
	if old != null:
		old.queue_free()


func _build(info: Dictionary, map_name: String) -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.BASE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP      # no tap reaches the lobby underneath while it reloads
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	bg.add_child(box)
	var sides := []
	var players: Dictionary = info.get("players", {})
	var seats := players.keys()
	seats.sort()
	for s in seats:
		var f := str(players[s])
		sides.append([str((Rules.FACTION_NAMES.get(f, [f.to_upper()]) as Array)[0]), Rules.seat_color(str(s))])
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	for i in range(sides.size()):
		if i > 0:
			row.add_child(_text("VS", 30, UiKit.MUTED))
		row.add_child(_text(str(sides[i][0]), 40, sides[i][1]))
	box.add_child(row)
	box.add_child(_text(map_name.to_upper(), 22, UiKit.INK))
	box.add_child(_text("LOADING THE BATTLEFIELD…", 16, UiKit.CYAN))
	await get_tree().process_frame                    # centre once the sizes are known
	box.position = (get_viewport().get_visible_rect().size - box.size) * 0.5


func _text(s: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _process(dt: float) -> void:
	_t += dt
	if _t > MAX_SECONDS:
		queue_free()
