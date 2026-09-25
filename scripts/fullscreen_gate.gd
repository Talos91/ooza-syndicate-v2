class_name FullscreenGate
extends CanvasLayer
## Phones must play fullscreen (Daniele, Alpha 14 playtest: "screen size now varies and half the
## interface is shrunk... should mandate full screen - on Android via button, on Apple via convert to
## app"). In a phone browser that is neither fullscreen nor launched from the home screen, this gate
## covers the game: Android gets a PLAY FULLSCREEN button (the browser only allows it from a tap);
## iPhone/iPad Safari can't go fullscreen, so it shows the Add to Home Screen steps - the home-screen
## app opens fullscreen and landscape (PWA manifest). It reappears if the player leaves fullscreen.
## A small "continue in the browser" link stays as an escape hatch in case detection is wrong.

const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const HEAD_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")

var ios := false
var dismissed := false
var panel: Control
var _check_t := 0.0


static func needed() -> bool:
	## Alpha 16: the page's native gate (web/fullscreen-gate.js) does this job; this in-game one is
	## only a fallback if that script is missing.
	if not (OS.has_feature("web") and (OS.has_feature("web_android") or OS.has_feature("web_ios"))):
		return false
	return JavaScriptBridge.eval("!!window.OozeGate", true) != true


func _ready() -> void:
	layer = 100
	ios = OS.has_feature("web_ios")
	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/art/ui-main.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.modulate = Color(0.45, 0.5, 0.55)
	panel.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/ui/Ooze-Syndicate-Logo.svg")
	logo.custom_minimum_size = Vector2(420, 170)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(logo)
	var title := _label("%s  ·  v%s" % [Rules.VERSION_NAME.to_upper(), Rules.VERSION], 26, HEAD_FONT)
	box.add_child(title)
	if ios:
		box.add_child(_label("Ooze Syndicate plays fullscreen. On iPhone and iPad:", 24, UI_FONT))
		box.add_child(_label("Safari  →  Share  →  Add to Home Screen\nthen open the new icon, phone sideways.", 30, HEAD_FONT, Color("7fe9f5")))
	else:
		var b := Button.new()
		b.text = "PLAY FULLSCREEN"
		b.custom_minimum_size = Vector2(520, 96)
		b.add_theme_font_override("font", UI_FONT)
		b.add_theme_font_size_override("font_size", 34)
		UiSkin.button(b, "vex", true)
		b.pressed.connect(_go_fullscreen)
		box.add_child(b)
		box.add_child(_label("Turn your phone sideways.", 22, UI_FONT))
	var skip := Button.new()
	skip.text = "continue in the browser window (not recommended)"
	skip.flat = true
	skip.add_theme_font_override("font", UI_FONT)
	skip.add_theme_font_size_override("font_size", 18)
	skip.add_theme_color_override("font_color", Color("839da9"))
	skip.pressed.connect(func():
		dismissed = true
		panel.visible = false)
	box.add_child(skip)
	panel.visible = not _is_fullscreen()


func _label(t: String, size: int, font: Font, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _go_fullscreen() -> void:
	## Must run inside the tap (browsers only grant fullscreen to a user gesture).
	JavaScriptBridge.eval("""
		(function(){
			var el = document.documentElement;
			var req = el.requestFullscreen || el.webkitRequestFullscreen;
			if (req) { var p = req.call(el, {navigationUI: 'hide'});
				if (p && p.then) p.then(function(){ try { screen.orientation.lock('landscape'); } catch(e){} }); }
		})();""", true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _is_fullscreen() -> bool:
	if not OS.has_feature("web"):
		return true
	var r = JavaScriptBridge.eval("""(document.fullscreenElement != null || document.webkitFullscreenElement != null
		|| window.matchMedia('(display-mode: fullscreen)').matches || window.matchMedia('(display-mode: standalone)').matches
		|| window.navigator.standalone === true)""", true)
	return r == true


func _process(dt: float) -> void:
	_check_t += dt
	if _check_t < 0.5 or dismissed:
		return
	_check_t = 0.0
	panel.visible = not _is_fullscreen()
