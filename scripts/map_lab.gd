class_name MapLab
extends CanvasLayer
## MAP LAB (branch map-lab only; never merged into main): a separate build of the game for testing maps,
## published at https://talos91.github.io/ooze-syndicate--map-test/. It replaces the title screen with a list
## of lab maps that it downloads at start from the lab site's maps/ folder (maps/index.json + the baked map
## JSONs, written by `python Tools/MapBuilder/mapbuilder.py lab push ...`), so a new test map needs no export.
## Pick a map, a mode and an AI level, then PLAY (you are seat A) or WATCH (every seat AI). In a match the
## LAB button (LabPanel) offers speed, the Last Stand / Very Last Stand now, the rulebook overlay, restart.
## Desktop: --lab-url=http://localhost:8000/ reads another site (the published one otherwise).

const ON := true
const SITE := "https://talos91.github.io/ooze-syndicate--map-test/"
const DIR := "user://lab"
const LEVELS := ["Training", "Casual", "Standard", "Veteran", "Expert"]
const BG := Color(0.043, 0.059, 0.078)
const CARD := Color(0.085, 0.115, 0.15)
const ACCENT := Color(0.18, 0.9, 1.0)
const BAD := Color(1.0, 0.36, 0.36)
const GOOD := Color(0.49, 1.0, 0.35)

static var entries: Array = []          # index.json "maps": {file, code, name, modes, nodes, footprint, pass, hard, soft, findings}
static var index_info := {}
static var picked := ""                 # file of the selected map
static var pick_mode := ""
static var level := "Standard"
static var watch := false               # WATCH: every seat is the AI (main.demo)
static var loaded := false

var main: Node
var http: HTTPRequest
var base := SITE
var queue: Array = []
var status: Label
var list_box: VBoxContainer
var detail: VBoxContainer


static func on() -> bool:
	return ON


static func web_fullscreen() -> bool:
	if not OS.has_feature("web"):
		return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	return JavaScriptBridge.eval("!!(document.fullscreenElement || document.webkitFullscreenElement)", true) == true


static func toggle_fullscreen() -> void:
	## Fullscreen from a Godot button: the tap's user activation is still live when Godot handles it a frame
	## later (Chrome / Android), so the browser grants requestFullscreen; the phone then locks landscape.
	if not OS.has_feature("web"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	JavaScriptBridge.eval("""(() => { const d = document, el = d.documentElement;
		if (d.fullscreenElement || d.webkitFullscreenElement) { (d.exitFullscreen || d.webkitExitFullscreen).call(d); return; }
		const req = el.requestFullscreen || el.webkitRequestFullscreen; if (!req) return;
		const p = req.call(el, {navigationUI: 'hide'});
		const lock = () => { try { screen.orientation.lock('landscape').catch(() => {}); } catch (e) {} };
		if (p && p.then) p.then(lock, () => {}); else lock(); })()""", true)


static func entry_for(code: String) -> Dictionary:
	if entries.is_empty() and FileAccess.file_exists(DIR + "/index.json"):
		var j = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/index.json"))
		if j is Dictionary:
			index_info = j
			entries = j.get("maps", [])
	for e in entries:
		if str(e.get("code", "")) == code:
			return e
	return {}


static func before_match(m: Node) -> void:
	## Called at the top of main._start_map: the lab's WATCH choice (demo = every seat AI).
	m.demo = watch
	if level != "":
		m.ai_level = level
	var j = JSON.parse_string(FileAccess.get_file_as_string(m.map_path))
	var variant: Dictionary = j.get("labVariant", {}) if j is Dictionary and j.get("labVariant") is Dictionary else {}
	big_vat = variant.get("bigVat", false) == true
	Sim.lab_direct = big_vat                            # units leave / enter at the rim (sim._build_path3)


static var big_vat := false                             # this lab map's vats fill the platform (LabPanel scales them)


func _init(m: Node) -> void:
	main = m
	layer = 20


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lab-url="):
			base = arg.substr(10)
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var here = JavaScriptBridge.eval("window.location.href.split('?')[0].split('#')[0].replace(/[^/]*$/, '')", true)
		if here is String and here.begins_with("http"):
			base = here
	if not base.ends_with("/"):
		base += "/"
	DirAccess.make_dir_recursive_absolute(DIR)
	_build_ui()
	http = HTTPRequest.new()
	http.accept_gzip = false                         # web: the browser already unpacks GitHub Pages' gzip; unpacking twice fails
	add_child(http)
	http.request_completed.connect(_on_done)
	if loaded and not entries.is_empty():
		_fill()
	else:
		_reload()


# ---------------------------------------------------------------- download
func _reload() -> void:
	status.text = "Loading maps from %s ..." % base
	queue = ["index"]
	http.request(base + "maps/index.json?t=%d" % Time.get_unix_time_from_system())


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var what: String = queue.pop_front() if not queue.is_empty() else ""
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status.text = "Could not load %s (HTTP %d, result %d). Check the connection, then RELOAD." % [what, code, result]
		return
	if what == "index":
		var j = JSON.parse_string(body.get_string_from_utf8())
		if not j is Dictionary:
			status.text = "maps/index.json is not valid JSON."
			return
		index_info = j
		entries = j.get("maps", [])
		var fi := FileAccess.open(DIR + "/index.json", FileAccess.WRITE)   # kept for restarts and offline
		fi.store_buffer(body)
		fi.close()
		for e in entries:
			queue.append(str(e["file"]))
	else:
		var f := FileAccess.open(DIR + "/" + what, FileAccess.WRITE)
		f.store_buffer(body)
		f.close()
	if queue.is_empty():
		loaded = true
		_fill()
		_maybe_shot()
		return
	status.text = "Loading %s (%d left) ..." % [queue[0], queue.size()]
	http.request(base + "maps/" + str(queue[0]) + "?v=" + str(index_info.get("stamp", "")))


# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	root.add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	margin.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.25
	left.add_theme_constant_override("separation", 12)
	cols.add_child(left)
	var head := HBoxContainer.new()
	left.add_child(head)
	var title := _label("OOZE MAP LAB", 40, ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("FULLSCREEN", MapLab.toggle_fullscreen, 210))
	head.add_child(_button("RELOAD", _reload, 150))
	status = _label("", 22, Color(0.6, 0.7, 0.78))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 10)
	scroll.add_child(list_box)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(right_scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 12)
	right_scroll.add_child(detail)


func _fill() -> void:
	status.text = "%d maps · game %s · maps pushed %s" % [entries.size(), Rules.VERSION, str(index_info.get("built", "?"))]
	for c in list_box.get_children():
		c.queue_free()
	if picked == "" and not entries.is_empty():
		picked = str(entries[0]["file"])
	for e in entries:
		var f: String = str(e["file"])
		var fp: Array = e.get("footprint", [0, 0])
		var txt := "%s  %s\n%d x %d m · %d nodes · %s" % [e.get("code", ""), e.get("name", ""), int(fp[0]), int(fp[1]),
				int(e.get("nodes", 0)), " ".join(e.get("modes", []))]
		var b := _button(txt, func(): _select(f), 0, 24)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 96
		var ok: bool = e.get("pass", false)
		var tag := " PASS" if ok else " %d HARD" % int(e.get("hard", 0))
		b.text = txt.replace("\n", "   " + tag + "\n")
		if f == picked:
			b.add_theme_color_override("font_color", GOOD if ok else BAD)
		_style(b, CARD.lightened(0.12) if f == picked else CARD)
		list_box.add_child(b)
	_detail()


func _maybe_shot() -> void:
	## --lab-shot=<png>: screenshot the lab screen once the maps are in, then quit (testing).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lab-shot="):
			for i in range(10):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.substr(11))
			get_tree().quit()


func _select(f: String) -> void:
	picked = f
	pick_mode = ""
	_fill()


func _detail() -> void:
	for c in detail.get_children():
		c.queue_free()
	var e: Dictionary = {}
	for x in entries:
		if str(x["file"]) == picked:
			e = x
	if e.is_empty():
		return
	var modes: Array = e.get("modes", ["1v1"])
	if pick_mode == "" or not pick_mode in modes:
		pick_mode = str(modes[0])
	detail.add_child(_label("%s %s" % [e.get("code", ""), e.get("name", "")], 32, Color.WHITE))
	if e.get("note") is String and str(e["note"]) != "":
		var n := _label(str(e["note"]), 20, Color(0.65, 0.74, 0.8))
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_child(n)
	detail.add_child(_label("MODE", 20, Color(0.55, 0.65, 0.72)))
	detail.add_child(_chips(modes, pick_mode, _set_mode))
	detail.add_child(_label("AI LEVEL", 20, Color(0.55, 0.65, 0.72)))
	detail.add_child(_chips(LEVELS, level, _set_level))
	var go := HBoxContainer.new()
	go.add_theme_constant_override("separation", 12)
	var play := _button("PLAY", func(): _launch(false), 0, 30)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style(play, ACCENT.darkened(0.55))
	var watch_b := _button("WATCH AI", func(): _launch(true), 0, 30)
	watch_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.add_child(play)
	go.add_child(watch_b)
	detail.add_child(go)
	var fnd: Array = e.get("findings", [])
	detail.add_child(_label("RULEBOOK: %s · %d hard · %d soft" % ["PASS" if e.get("pass", false) else "FAIL", int(e.get("hard", 0)), int(e.get("soft", 0))],
			22, GOOD if e.get("pass", false) else BAD))
	for f in fnd:
		var l := _label("%s %s  %s" % [f.get("rule", ""), str(f.get("sev", "")).to_upper(), f.get("msg", "")], 19,
				BAD if f.get("sev") == "hard" else Color(1.0, 0.8, 0.35))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_child(l)


func _set_mode(v: String) -> void:
	pick_mode = v
	_detail()


func _set_level(v: String) -> void:
	level = v
	_detail()


func _launch(ai_only: bool) -> void:
	watch = ai_only
	var path := DIR + "/" + picked
	if not FileAccess.file_exists(path):
		status.text = "%s is not downloaded yet - RELOAD." % picked
		return
	queue_free()
	main.start_match(path, main.SEAT_FACTIONS[main.HUMAN], {}, level, pick_mode, main.color_choice)


# ---------------------------------------------------------------- widgets
func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _button(t: String, cb: Callable, min_w := 0, size := 26) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(min_w, 84)
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(cb)
	_style(b, CARD)
	return b


func _style(b: Button, col: Color) -> void:
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.08) if st == "hover" else (col.darkened(0.2) if st == "pressed" else col)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		if st == "focus":
			sb.draw_center = false
		b.add_theme_stylebox_override(st, sb)


func _chips(values: Array, current: String, cb: Callable) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	for v in values:
		var val := str(v)
		var b := _button(val, func(): cb.call(val), 120, 24)
		_style(b, ACCENT.darkened(0.55) if val == current else CARD)
		row.add_child(b)
	return row
