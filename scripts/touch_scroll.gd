class_name TouchScroll
extends ScrollContainer
## PAGES, NOT SCROLLING (Daniele 2026-11-04, ui-menus: "NO scrolling only pagination, no more scrolling anywhere").
## Every list that used to scroll (map grid, lobby columns, profile rows, skills, history, campaign cards...) is cut into
## pages instead: the breaks snap to whole items (a row never shows half), a pager - ‹  2 / 5  › - sits under the list
## (>= 44 pt taps), the wheel and the finger never move the list by pixels; a quick swipe (> 40 px) flips a page. Items
## of the next page that would peek under the page's end are hidden. A list that fits shows no pager.
## `horizontal` (the campaign's card rows) pages sideways. was_drag() still tells a swipe from a tap: buttons inside
## check it before acting (a swipe flips the page and never presses).

var finger := -1
var origin := Vector2.ZERO
var dragged := false
var released_at := -1000
var page := 0
var pages: Array = [0.0]                            # each page's start along the axis (content units)
var _full := -1.0                                  # the list's own length along the axis
var _full_w := -1.0                                # (vertical lists) its width before the pager took its column
var _side := false                                 # the pager is a column at the right (wide lists) or a strip under (narrow)
var _pager: Control = null
var pager_dock := Rect2()                          # ROUND 4 (Daniele: "navigation can be next to done button"): when set (parent
                                                   # coords), the ‹ n / N › strip sits there, right-aligned, its height; the list keeps its length
var _label: Label = null
var _queued := false
var horizontal := false:
	set(v):
		horizontal = v
		horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if v else ScrollContainer.SCROLL_MODE_DISABLED
		vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if v else ScrollContainer.SCROLL_MODE_SHOW_NEVER


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER


func _ready() -> void:
	child_entered_tree.connect(func(c):
		_watch(c)
		_queue_layout())
	for c in get_children():
		_watch(c)
	_queue_layout()


func _watch(c: Node) -> void:
	## The list's box: re-page when it resizes, and when a container (the map grid) places its items.
	if c is Control:
		(c as Control).resized.connect(_queue_layout)
	if c is Container:
		(c as Container).sort_children.connect(_queue_layout)


func was_drag() -> bool:
	return dragged or Time.get_ticks_msec() - released_at < 250


# ------------------------------------------------------------------ pages
func _queue_layout() -> void:
	if _queued:
		return
	_queued = true
	(func():
		_queued = false
		if is_inside_tree():
			_layout()).call_deferred()


func _len(c: Control) -> float:
	return c.size.x if horizontal else c.size.y


func _start(c: Control) -> float:
	return c.position.x if horizontal else c.position.y


func _items() -> Array:
	## The list's items: the content's own children (a GridContainer's cards, a stack's rows), with where they start / end.
	var out := []
	if get_child_count() == 0:
		return out
	var box := get_child(0) as Control
	if box == null:
		return out
	for c in box.get_children():
		if c is Control and (c as Control).visible:
			var cc := c as Control
			out.append([_start(cc), _start(cc) + _len(cc), cc])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


func _menu():
	## The page this list lives on (Menu / MatchScreens / CampaignPage...): its tap and font sizes, its faction.
	var n: Node = get_parent()
	while n != null:
		if n.has_method("_pt_factor") and "content" in n:
			return n
		n = n.get_parent()
	return null


func _layout() -> void:
	if get_child_count() == 0:
		return
	var box := get_child(0) as Control
	if _full < 0.0:
		_full = size.x if horizontal else size.y
		_full_w = size.x
	var total := maxf(_len(box), box.get_combined_minimum_size().x if horizontal else box.get_combined_minimum_size().y)
	var m = _menu()
	var ph := UiKit.tap_h(m, 40.0) if m != null else 40.0
	if m is CampaignPage:                          # its _pt_factor is in canvas units (no K): its own 44 pt minimum (0.23.25)
		ph = m.rh(40.0)
	if total <= _full + 2.0:                       # it fits: no pager, the whole length
		_set_len(_full)
		if not horizontal:
			size.x = _full_w
		if is_instance_valid(_pager):
			_pager.queue_free()
			_pager = null
		pages = [0.0]
		page = 0
		_show()
		return
	_side = false                                  # ROUND 2b (Daniele 2026-11-04: "up and down arrows should be gone"): the pager is
	                                               # always ‹ n / N › under the list, never a ▲ / ▼ column
	if pager_dock.size.y > 0.0:
		ph = pager_dock.size.y
	var view := _full if (_side or horizontal or pager_dock.size.y > 0.0) else _full - ph - 6.0   # a narrow rail: the pager under it
	_set_len(view)
	size.x = _full_w - ph - 8.0 if _side else (_full_w if not horizontal else size.x)
	pages = [0.0]
	var at := 0.0
	for it in _items():
		if it[1] - it[0] > view * 0.9:                 # a backdrop / frame as tall as a page decides no break
			continue
		if it[1] > at + view + 1.0 and it[0] > at + 1.0:
			at = it[0]
			pages.append(at)
	var cur := scroll_horizontal if horizontal else scroll_vertical
	page = 0
	for i in range(pages.size()):
		if pages[i] <= cur + 1.0:
			page = i
	_make_pager(m, ph)
	_show()


func _set_len(v: float) -> void:
	if horizontal:
		size.x = v
	else:
		size.y = v


func _show() -> void:
	page = clampi(page, 0, pages.size() - 1)
	var a: float = pages[page]
	var b: float = pages[page + 1] if page + 1 < pages.size() else INF
	if horizontal:
		scroll_horizontal = int(a)
	else:
		scroll_vertical = int(a)
	for it in _items():                            # the next page's items never peek under this one's end
		var c: Control = it[2]
		var on: bool = it[0] < b - 0.5
		c.modulate.a = 1.0 if on else 0.0
		if not c.has_meta("mf"):
			c.set_meta("mf", c.mouse_filter)
		c.mouse_filter = int(c.get_meta("mf")) if on else Control.MOUSE_FILTER_IGNORE
	if _label:
		_label.text = "%d / %d" % [page + 1, pages.size()]
	if is_instance_valid(_pager):
		for b2 in _pager.get_children():
			if b2 is Button:
				(b2 as Button).disabled = (b2.get_meta("d") < 0 and page == 0) or (b2.get_meta("d") > 0 and page == pages.size() - 1)


func flip(d: int) -> void:
	if pages.size() < 2:
		return
	page = clampi(page + d, 0, pages.size() - 1)
	Sfx.play_ui("tap")
	_show()


func _make_pager(m, ph: float) -> void:
	if is_instance_valid(_pager):
		_pager.queue_free()
	var f := str(m.get("shell_f")) if m != null and m.get("shell_f") != null else "vex"
	_pager = Control.new()
	_pager.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bw := ph * 1.3
	var lw := UiKit.text_w(m, "88 / 88", 14, true) + 20.0 if m != null else 70.0
	if m is CampaignPage:
		lw = maxf(lw, m.fsz(13) * 4.5 + 20.0)
	var prev: Button
	var next: Button
	if m != null:
		prev = UiKit.make_btn(m, "‹", Vector2(bw, ph), func(): flip(-1), "secondary", f, 22)
		next = UiKit.make_btn(m, "›", Vector2(bw, ph), func(): flip(1), "secondary", f, 22)
	else:                                          # a list outside a menu page: plain buttons
		prev = Button.new()
		prev.text = "‹"
		prev.size = Vector2(bw, ph)
		prev.pressed.connect(func(): flip(-1))
		next = Button.new()
		next.text = "›"
		next.size = Vector2(bw, ph)
		next.pressed.connect(func(): flip(1))
	prev.set_meta("d", -1)
	next.set_meta("d", 1)
	_label = UiKit.label(m, "", 13, UiKit.INK, true) if m != null else Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if m is CampaignPage:                          # 12.5 pt text on its page (UiKit.px assumes the Menu's raw units)
		_label.add_theme_font_size_override("font_size", m.fsz(13))
	_label.size = Vector2(lw, ph)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var w := bw * 2.0 + lw
	if _side:                                      # a column at the list's right edge: ▲ on top, the count, ▼ at the foot
		bw = ph
		prev.text = "▲"
		next.text = "▼"
		prev.size = Vector2(bw, ph)
		next.size = Vector2(bw, ph)
		_label.size = Vector2(bw, ph)
		w = bw
		prev.position = Vector2.ZERO
		_label.position = Vector2(0, (_full - ph) / 2.0)
		next.position = Vector2(0, _full - ph)
	else:
		prev.position = Vector2.ZERO
		_label.position = Vector2(bw, 0)
		next.position = Vector2(bw + lw, 0)
	_pager.add_child(prev)
	_pager.add_child(_label)
	_pager.add_child(next)
	if not _side:                                  # sideways rows / a narrow rail: the pager under it, at its right end
		w = minf(w, _full_w)
		if w < bw * 2.0 + lw:                      # a rail narrower than the strip: the count goes, the arrows stay
			_label.visible = false
			next.position = Vector2(w - bw, 0)
		_pager.size = Vector2(w, ph)
		_pager.position = position + Vector2(_full_w - w, size.y + 6.0)
		if pager_dock.size.y > 0.0:                # ROUND 4: docked beside the page's DONE
			_pager.position = pager_dock.position + Vector2(pager_dock.size.x - w, 0)
	else:
		_pager.size = Vector2(w, _full)
		_pager.position = position + Vector2(_full_w - w, 0)
	get_parent().add_child(_pager)
	tree_exiting.connect(func():
		if is_instance_valid(_pager):
			_pager.queue_free())


# ------------------------------------------------------------------ input: no pixel scrolling
func _inside(p: Vector2) -> bool:
	var local := get_global_transform_with_canvas().affine_inverse() * p
	return Rect2(Vector2.ZERO, size).has_point(local)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and _inside((event as InputEventMouseButton).position):
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			get_viewport().set_input_as_handled()     # the wheel never slides the list by pixels (a notch = a page)
			if pages.size() > 1:
				flip(1 if mb.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT] else -1)
			return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and _inside(st.position):
			finger = st.index
			origin = st.position
			dragged = false
		elif not st.pressed and st.index == finger:
			if dragged:
				released_at = Time.get_ticks_msec()
				var d := (origin.x - st.position.x) if horizontal else (origin.y - st.position.y)
				if absf(d) > 40.0:
					flip(1 if d > 0.0 else -1)
				get_viewport().set_input_as_handled()
			finger = -1
			dragged = false
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == finger:
		var sd := event as InputEventScreenDrag
		if sd.position.distance_to(origin) > 12.0:
			dragged = true
		if dragged:
			get_viewport().set_input_as_handled()
