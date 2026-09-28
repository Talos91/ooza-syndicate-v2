class_name PrivacyNotice
extends CanvasLayer
## PROGRESSION (Alpha 21, TELEMETRY-PRIVACY-DESIGN §6): the privacy notice, once, on the first launch - over the
## tutorial's first card or the menu, under the fullscreen gate. Both buttons close it for good (Telemetry.choose).
## Consent (Daniele, 2026-09-28): outside the EU / UK the switch is already ON - OK / TURN OFF; in the EU / UK it is
## OFF until the player turns it on - SHARE / NO THANKS, the same size and weight (no nudging).
## Sizes are in the 1280x720 stretched canvas: buttons 96 tall (>= 44 pt on a 360 pt phone), text >= 26.

signal closed(share: bool)

const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const HEAD_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")

var panel: Control
var _paused_tree := false


func _ready() -> void:
	layer = 95                                      # over the menu / HUD / coach, under the fullscreen gate (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var net := get_node_or_null("/root/Net")        # by path: headless --script runs have no autoloads
	if (net == null or not net.in_room()) and not FullscreenGate.needed():   # the tutorial's first card waits under it (never a room,
														# never over the in-game fullscreen gate, which must stay tappable)
		get_tree().paused = true
		_paused_tree = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0a1216f4")
	sb.border_color = Color("19dce8")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(34)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	var eu := Telemetry.opt_in()
	box.add_child(_label("SHARE PLAY & CRASH DATA?" if eu else "YOUR DATA", 40, HEAD_FONT, Color.WHITE))
	var body := _label(Telemetry.notice_text(), 27, UI_FONT, Color("c5d2da"))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(_width() - 68, 0)
	box.add_child(body)
	box.add_child(_label("Switch starts OFF where you are - it's your choice." if eu
			else "It's ON now - TURN OFF keeps everything on this device.", 26, UI_FONT, Color("ffd15c")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	if eu:
		row.add_child(_button("SHARE", func(): _close(true), false))
		row.add_child(_button("NO THANKS", func(): _close(false), false))
	else:
		row.add_child(_button("OK", func(): _close(true), true))
		row.add_child(_button("TURN OFF", func(): _close(false), false))


func _width() -> float:
	var vp := get_viewport().get_visible_rect().size
	return minf(1120.0, vp.x - 80.0)


func _label(text: String, size_value: int, font: Font, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size_value)
	l.add_theme_color_override("font_color", col)
	return l


func _button(text: String, call: Callable, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 96)
	b.add_theme_font_override("font", UI_FONT)
	b.add_theme_font_size_override("font_size", 34)
	UiSkin.button(b, "vex", primary)
	b.pressed.connect(call)
	return b


func _close(share: bool) -> void:
	Telemetry.choose(share)
	if share:
		Telemetry.flush_soon()
	if _paused_tree:
		get_tree().paused = false
	closed.emit(share)
	queue_free()
