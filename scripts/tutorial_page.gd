class_name TutorialPage
extends Control
## The TUTORIAL menu page (TUTORIAL-DESIGN.md §7, `Menu.show_tutorial`): a self-contained Control built in
## menu.gd's own skin (NeonPanel frames, UiSkin/faction buttons, Rajdhani / Russo One, the same phone tap() /
## fsz() >= 44 pt / >= 14 pt minimums as menu.gd) with no dependency on a live Menu instance -
## `Menu.show_tutorial()` instances it, feeds it TutorialDirector.lesson_rows() and forwards its signals. Its
## words are the handler script's (TutorialDirector.line). Laid out on its own 1280x720 canvas (no Alpha-11 legacy coordinates to
## port for a brand-new page, so no extra K factor is needed - see menu.gd's own K comment), scaled and
## centred to any screen exactly like menu.gd's `_fit()`.
##
## Public API
##   set_faction(key: String)              button / accent skin (UiSkin.faction keys); default "null"
##   set_mobile(is_mobile: bool)           phone tap (>= 44 pt) / text (>= 14 pt) minimums
##   set_lessons(lessons: Array)           each {id: int, title: String, goal: String, done: bool}; the
##                                         9 rows, already in the order they should show
##   set_progress_note(text: String)       e.g. "Progress isn't saved on this browser" (no user:// - the
##                                         ARMIES pattern, §7); "" (default) shows nothing
##   host_in(menu, area: Rect2)            Alpha 21 UI pass: build inside the Menu's shell page (menu.content, its
##                                         top / tab bars, title and BACK) with UiKit, in `area`; call before
##                                         adding the page to menu.content. Without it: its own canvas, as before
##   show_list()                           the normal TRAINING page: title, rows, CONTINUE, BACK (hosted: the
##                                         rows in two columns and CONTINUE / START TRAINING; the Menu has BACK)
## Signals
##   continue_pressed, back_pressed        the list page's footer
##   lesson_pressed(id: int)               a row tapped directly (replay out of order, §7)

signal continue_pressed
signal back_pressed
signal lesson_pressed(id: int)

const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const HEAD_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")
const CANVAS := Vector2(1280.0, 720.0)

# Phone sizing - the same numbers and shape as menu.gd's (§ "Phone sizing" there); K is 1.0 here since
# this page has no Alpha-11 layout to match, so a raw unit already is a canvas unit.
const MIN_TAP_PT := 44.0
const MIN_FONT_PT := 12.5
const PHONE_PT_H := 390.0

var faction := "null"
var mobile := false
var standalone_backdrop := true          # false once Menu hosts this page and supplies its own backdrop

var content: Control
var host = null                          # the Menu hosting this page in its shell (host_in); null = own canvas
var area := Rect2()                      # hosted: the free area to lay out in (the host's canvas units)
var _backdrop: ColorRect
var _lessons: Array = []
var _progress_note := ""


func _ready() -> void:
	if host != null:                     # in the shell: the host's canvas, no backdrop, the host rebuilds on resize
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = host.content.size
		content = Control.new()
		add_child(content)
		_fit()
		show_list()
		return
	if standalone_backdrop:
		_backdrop = ColorRect.new()
		_backdrop.color = Color("030c12")
		_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE     # sized explicitly in _fit(), not by anchors
		add_child(_backdrop)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	content = Control.new()
	add_child(content)
	_fit()
	var vp := get_viewport()
	if vp:
		vp.size_changed.connect(_fit)
	show_list()


func _fit() -> void:
	## Same recipe as menu.gd's _fit(): the page is laid out on a 1280x720 canvas, scaled to fit any
	## screen shape and centred.
	if not is_instance_valid(content):
		return
	if host != null:                     # hosted: the host's canvas units already
		content.position = Vector2.ZERO
		content.size = size
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	if is_instance_valid(_backdrop):
		# explicit, not just anchors: a Control added straight under the root Window only gets its
		# anchor-driven full-rect size once the engine's own resize notification reaches it, which can
		# lag a frame behind _ready() - the backdrop must be right the instant the page first shows.
		_backdrop.position = Vector2.ZERO
		_backdrop.size = vp
	var s := minf(vp.x / CANVAS.x, vp.y / CANVAS.y)
	content.size = CANVAS
	content.scale = Vector2(s, s)
	content.position = (vp - CANVAS * s) / 2.0


func _pt_factor() -> float:
	if host != null:                     # hosted: the Menu's (UiKit's unit)
		return host._pt_factor()
	if not mobile:
		return 0.0
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return 0.0
	var s := minf(vp.x / CANVAS.x, vp.y / CANVAS.y)
	if s <= 0.0:
		return 0.0
	return s * (PHONE_PT_H / vp.y)


func tap(dims: Vector2) -> Vector2:
	var f := _pt_factor()
	var min_h := (MIN_TAP_PT / f) if f > 0.0 else 0.0
	return Vector2(dims.x, maxf(dims.y, min_h))


func rh(base: float) -> float:
	var f := _pt_factor()
	return maxf(base, (MIN_TAP_PT / f) if f > 0.0 else 0.0)


func fsz(size_value: int) -> int:
	var f := _pt_factor()
	return maxi(size_value, int(ceil(MIN_FONT_PT / f))) if f > 0.0 else size_value


func _color() -> Color:
	## Rules.FACTIONS keys are the raw faction ids ("bloom" included) - UiSkin.faction() only renames
	## the ui-kit texture folder ("viridian"), it is not a Rules key.
	return Rules.FACTIONS[faction][1] if Rules.FACTIONS.has(faction) else Color("18dae8")


# ------------------------------------------------------------------ public API
func set_faction(key: String) -> void:
	faction = key


func set_mobile(is_mobile: bool) -> void:
	mobile = is_mobile


func set_lessons(lessons: Array) -> void:
	_lessons = lessons


func set_progress_note(text: String) -> void:
	_progress_note = text


func host_in(m, free_area: Rect2) -> void:
	host = m
	area = free_area
	standalone_backdrop = false


# ------------------------------------------------------------------ building blocks (menu.gd's shapes)
func _clear_content() -> void:
	if is_instance_valid(content):
		remove_child(content)
		content.queue_free()
	content = Control.new()
	add_child(content)
	_fit()


func _label(text: String, size_value: int, col: Color, grow := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", HEAD_FONT if size_value >= 24 else UI_FONT)
	l.add_theme_font_size_override("font_size", fsz(size_value) if grow else size_value)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _label_at(text: String, pos: Vector2, size_value: int = 20, col: Color = Color.WHITE, grow := true) -> Label:
	var l := _label(text, size_value, col, grow)
	l.position = pos
	content.add_child(l)
	return l


func _frame(pos: Vector2, dims: Vector2) -> NeonPanel:
	var p := NeonPanel.new()
	p.accent = _color()
	p.position = pos
	p.custom_minimum_size = dims
	p.size = dims
	content.add_child(p)
	return p


func _button(text: String, cb: Callable, dims: Vector2, primary := false, font_size := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", UI_FONT)
	b.custom_minimum_size = dims
	b.size = dims
	b.add_theme_stylebox_override("normal", Hud.panel_style())
	b.add_theme_stylebox_override("hover", Hud.panel_style(_color()))
	var pressed := Hud.panel_style(Color("00ddf2"))
	pressed.bg_color = Color("147185")
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_font_size_override("font_size", fsz(font_size))
	b.pressed.connect(func(): cb.call_deferred())
	UiSkin.button(b, faction, primary)
	return b


func _nav_button(text: String, pos: Vector2, dims: Vector2, cb: Callable, primary := false) -> Button:
	dims = tap(dims)
	var b := _button(text, cb, dims, primary)
	b.position = pos
	content.add_child(b)
	return b


func _stack_open(pos: Vector2, dims: Vector2) -> Dictionary:
	## A scrollable, phone-safe row stack (TouchScroll, menu.gd's stack_open()): rows grown to the phone
	## tap minimum can outgrow a fixed frame before the frame itself would need hand-tuning.
	var scroll := TouchScroll.new()
	scroll.position = pos
	scroll.size = dims
	content.add_child(scroll)
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(inner)
	return {"scroll": scroll, "inner": inner}


func _stack_close(stack: Dictionary, content_h: float) -> void:
	var inner: Control = stack["inner"]
	var w: float = (stack["scroll"] as Control).size.x
	inner.custom_minimum_size = Vector2(w, content_h)
	inner.size = inner.custom_minimum_size


# ------------------------------------------------------------------ pages
func _first_unfinished_id() -> int:
	## The lit row / CONTINUE's lesson: the first neither done nor skipped, then the first skipped (-1: all done).
	for l in _lessons:
		if not bool(l.get("done", false)) and not bool(l.get("skipped", false)):
			return int(l.get("id", -1))
	for l in _lessons:
		if not bool(l.get("done", false)):
			return int(l.get("id", -1))
	return -1


func _lesson_row(stack: Dictionary, lesson: Dictionary, y: float, w: float, h: float) -> void:
	var row := Panel.new()
	var done := bool(lesson.get("done", false))
	row.add_theme_stylebox_override("panel", Hud.panel_style(_color() if done else Color("276578")))
	row.position = Vector2(0, y)
	row.size = Vector2(w, h)
	(stack["inner"] as Control).add_child(row)
	var pad := 18.0
	var idx := int(lesson.get("id", 0))
	var title := _label("%d.  %s" % [idx, str(lesson.get("title", ""))], 19, Color("edf7fa"))
	title.position = Vector2(pad, h * 0.14)
	row.add_child(title)
	var goal := _label(str(lesson.get("goal", "")), 14, Color("9fb6c0"))
	goal.position = Vector2(pad, h * 0.56)
	row.add_child(goal)
	var tick := _label("DONE" if done else "-", fsz(16), Color("6dff8a") if done else Color("445a66"))
	tick.position = Vector2(w - 96, h / 2.0 - 12)
	row.add_child(tick)
	var hit := Button.new()                # a flat, invisible full-row tap target
	hit.flat = true
	hit.size = row.size
	hit.modulate = Color(1, 1, 1, 0)
	var scroll: TouchScroll = stack["scroll"]
	hit.pressed.connect(func():
		if not scroll.was_drag():
			lesson_pressed.emit(idx))
	row.add_child(hit)


func show_list() -> void:
	if host != null:
		_show_shell_list()
		return
	_clear_content()
	var frame_dims := Vector2(1160, 640)
	var frame_pos := Vector2(60, 40)
	_frame(frame_pos, frame_dims)
	_label_at(TutorialDirector.line("page_title"), frame_pos + Vector2(40, 18), 40, Color("edf7fa"))
	_label_at(TutorialDirector.line("page_sub"), frame_pos + Vector2(40, 68), 16, Color("9fb6c0"))
	var y := 122.0
	if _progress_note != "":
		_label_at(_progress_note, frame_pos + Vector2(40, y), 13, Color("7795a4"))
		y += 26.0
	var list_pos := frame_pos + Vector2(40, y)
	var list_h := frame_dims.y - y - 100.0
	var st := _stack_open(list_pos, Vector2(frame_dims.x - 80, list_h))
	var row_h := rh(58.0)
	var yy := 0.0
	for lesson in _lessons:
		_lesson_row(st, lesson, yy, frame_dims.x - 80, row_h)
		yy += row_h + 10.0
	_stack_close(st, maxf(yy - 10.0, 0.0))
	var foot_y := frame_pos.y + frame_dims.y - rh(56.0) - 24.0
	_nav_button(TutorialDirector.line("back"), Vector2(frame_pos.x + 40, foot_y), Vector2(200, 56), func(): back_pressed.emit())
	var next_id := _first_unfinished_id()
	var label := TutorialDirector.line("continue") if next_id >= 0 else TutorialDirector.line("replay")
	_nav_button(label, Vector2(frame_pos.x + frame_dims.x - 300, foot_y), Vector2(260, 56),
			func(): continue_pressed.emit(), true)


func _show_shell_list() -> void:
	## The shell's TRAINING list (screen system 11) in `area`: the lessons as numbered rows in two columns (UiKit.row:
	## "00", title, goal, a tick when done; the first one not done lit), swiped when they outgrow the area; the
	## progress note and CONTINUE / START TRAINING (the first lesson not done; REPLAY when all are) at the foot.
	_clear_content()
	var x: float = host.shell_x()
	var w := content.size.x - x * 2.0
	var bh := UiKit.tap_h(self, 50.0)
	var fy := area.end.y - bh - 14.0
	var next_id := _first_unfinished_id()
	var done := _lessons.filter(func(l): return bool(l.get("done", false))).size()
	var label := TutorialDirector.line("replay") if next_id < 0 else 			(TutorialDirector.line("continue") if done > 0 else "START TRAINING")
	label += "  →"
	var bw := UiKit.text_w(self, label, 17, true) + 64.0
	UiKit.btn(self, label, Vector2(content.size.x - x - bw, fy), Vector2(bw, 50), func(): continue_pressed.emit(),
			"primary", faction, 17)
	var note := "%d / %d lessons done" % [done, _lessons.size()]
	if _progress_note != "":
		note += "  ·  " + _progress_note
	var nl := UiKit.label(self, note, 15, UiKit.MUTED)
	UiKit.add(self, nl, Vector2(x, fy + (bh - nl.get_minimum_size().y) / 2.0))
	# the rows, left to right then down
	var scroll := TouchScroll.new()
	scroll.position = Vector2(x, area.position.y)
	scroll.size = Vector2(w + 20.0, fy - 14.0 - area.position.y)
	var grab := UiKit.sb(Color(UiKit.accent(faction), 0.7), Color(0, 0, 0, 0), 0, 2)
	grab.set_content_margin_all(3)
	for st in ["grabber", "grabber_highlight", "grabber_pressed"]:
		scroll.get_v_scroll_bar().add_theme_stylebox_override(st, grab)
	scroll.get_v_scroll_bar().add_theme_stylebox_override("scroll", UiKit.sb(Color(UiKit.FRAME, 0.35), Color(0, 0, 0, 0), 0, 2))
	content.add_child(scroll)
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(inner)
	var gap := 12.0
	var rw := (w - gap) / 2.0
	var rows := ceili(_lessons.size() / 2.0)
	var rh_ := maxf(UiKit.tap_h(self, 64.0), minf(84.0, (scroll.size.y - gap * (rows - 1)) / maxf(rows, 1)))
	for i in range(_lessons.size()):
		var lesson: Dictionary = _lessons[i]
		var idx := int(lesson.get("id", 0))
		var is_done := bool(lesson.get("done", false))
		var go := func():
			if not scroll.was_drag():
				lesson_pressed.emit(idx)
		var goal := str(lesson.get("goal", ""))
		if bool(lesson.get("skipped", false)) and not is_done:   # (Daniele, 2026-09-28: a skipped lesson says so)
			goal = TutorialDirector.line("skipped")
		var b := UiKit.row(self, Vector2.ZERO, Vector2(rw, rh_), "%02d" % idx, str(lesson.get("title", "")),
				goal, go, faction, idx == next_id)
		content.remove_child(b)                  # UiKit places it on the page; it belongs in the list
		b.position = Vector2((i % 2) * (rw + gap), (i / 2) * (rh_ + gap))
		inner.add_child(b)
		if is_done:                              # the done tick, left of the chevron
			var t := Tick.new()
			t.color = UiKit.accent(faction)
			t.size = Vector2(22, 22)
			t.position = Vector2(rw - 62.0, (rh_ - 22.0) / 2.0)
			b.add_child(t)
	inner.custom_minimum_size = Vector2(w, rows * (rh_ + gap) - gap)


class Tick extends Control:
	## A drawn tick (the web build has no symbol fallback for a font glyph).
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := minf(size.x, size.y) / 2.0
		var c := size / 2.0
		draw_polyline(PackedVector2Array([c + Vector2(-0.8, 0.0) * r, c + Vector2(-0.25, 0.6) * r,
				c + Vector2(0.85, -0.65) * r]), color, maxf(2.0, r * 0.3), true)
