extends CanvasLayer
## LAB BUILD (Rules.lab; 05 Handoff/handoffs/LAB-BUILD-PLAN 2026-11-23.md): the bare LAB screen a lab build boots into, in front
## of HOME. Two rows of big test cards from one table (lab_cards.gd), paged with < > when they do not fit (never scrolls); a tap
## on a live card starts its vs-AI match through main's relaunch path (main.relaunch + reload, as PLAY AGAIN does) with the card's
## lab_opts merged into Rules.lab_opts; opening this screen again puts Rules.lab_opts back. NORMAL MENU = the real HOME.
## Sizes in pt through UiKit.pt_per_px (text >= 12.5 pt, taps >= 44 pt), inside UiKit.safe_insets; UiKit colours, no new art.
## The header carries Rules.VERSION and the last card, so a screenshot says which build and test it is.

const Cards := preload("res://scripts/lab_cards.gd")
const GAP_PT := 8.0
const CARD_MIN_W_PT := 150.0
const HEAD_PT := 44.0
const TITLE_SLOT_PT := 34.0                    # the card title row: two lines at the smallest size

static var card_id := ""                         # the card being played ("" = none: a normal match)
static var last_card := ""                       # the card played last (the header shows it)
static var normal := false                       # NORMAL MENU was tapped: main shows the real menu from now on
static var _defaults := {}                       # Rules.lab_opts before any card touched it
static var picks := {}                           # CHOICE SHEET (lab4): card id -> {lab_opts key: index into the choice's values}

var main: Node
var page := 0
var _root: Control
var _built_size := Vector2.ZERO


static func apply_card(card: Dictionary) -> void:
	## The card's lab_opts on top of the lab defaults (a fresh copy each time: cards never stack).
	if _defaults.is_empty():
		_defaults = Rules.lab_opts.duplicate(true)
	var opts: Dictionary = _defaults.duplicate(true)
	opts.merge(card.get("lab_opts", {}), true)
	for ch in card.get("choices", []):            # the sheet's picks (values[0] = the default)
		opts[ch["key"]] = ch["values"][pick_index(card, ch)]
	Rules.lab_opts = opts
	card_id = str(card["id"])
	last_card = card_id


static func pick_index(card: Dictionary, ch: Dictionary) -> int:
	return clampi(int((picks.get(str(card["id"]), {}) as Dictionary).get(ch["key"], 0)), 0, (ch["values"] as Array).size() - 1)


static func pick_tag(card: Dictionary) -> String:
	## The card's picked values, short ("x0.9"; "8 m · x1.5 · 1 PER 2"): on the card, in the overlay's folded line. "" = no choices.
	var parts := PackedStringArray()
	for ch in card.get("choices", []):
		parts.append(str(ch["names"][pick_index(card, ch)]))
	return " · ".join(parts)


static func reset_card() -> void:
	## Back on the LAB screen: no card, Rules.lab_opts as the build ships them.
	if not _defaults.is_empty():
		Rules.lab_opts = _defaults.duplicate(true)
	card_id = ""


static func wanted() -> bool:
	## main._ready: the LAB screen instead of HOME.
	return Rules.lab and not normal


func setup(m: Node) -> void:
	main = m
	layer = 5
	reset_card()
	ArmyPresets.load_all()                          # (the card's loadout: your saved preset, as Menu.setup loads them)
	get_viewport().size_changed.connect(_build_deferred)
	_build()


func _build_deferred() -> void:
	_build.call_deferred()


func _u() -> float:
	## Canvas units per pt.
	var vp := get_viewport().get_visible_rect().size
	return 1.0 / maxf(UiKit.pt_per_px(vp), 0.0001)


func _font_px(pt: float) -> int:
	return int(ceil(maxf(pt, UiKit.MIN_FONT_PT) * _u()))


func _label(text: String, pt: float, col: Color, head := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiKit.HEAD if head else UiKit.BODY)
	l.add_theme_font_size_override("font_size", _font_px(pt))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, dims: Vector2, call: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UiKit.HEAD)
	b.add_theme_font_size_override("font_size", _font_px(14.0))
	UiKit.style_button(b, "tertiary")
	b.add_theme_stylebox_override("normal", UiKit.sb(Color(UiKit.PANEL, 0.94), UiKit.FRAME, 1))
	b.size = dims
	b.pressed.connect(call)
	return b


func _build() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	_built_size = vp
	if is_instance_valid(_root):
		_root.queue_free()
	var u := _u()
	_root = Control.new()
	_root.size = vp
	add_child(_root)
	var bg := ColorRect.new()                      # the plain lab ground (no art)
	bg.color = UiKit.BASE
	bg.size = vp
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bg)
	var ins := UiKit.safe_insets(vp)
	var area := Rect2(ins.x + 12.0 * u, ins.y + 8.0 * u, vp.x - ins.x - ins.z - 24.0 * u, vp.y - ins.y - ins.w - 16.0 * u)
	var gap := GAP_PT * u
	var cols := clampi(int(floor((area.size.x + gap) / (CARD_MIN_W_PT * u + gap))), 2, 5)
	var per_page := cols * 2
	var pages := int(ceil(float(Cards.CARDS.size()) / per_page))
	page = clampi(page, 0, pages - 1)
	# header: title + build + last card (left); < n/N > and NORMAL MENU (right)
	var head_h := HEAD_PT * u
	var right := area.end.x
	var nb := _button("NORMAL MENU", Vector2(132.0 * u, head_h), _normal_menu)
	nb.position = Vector2(right - nb.size.x, area.position.y)
	_root.add_child(nb)
	right = nb.position.x - gap
	if pages > 1:
		var nx := _button(">", Vector2(head_h, head_h), func(): _page(1))
		nx.position = Vector2(right - head_h, area.position.y)
		nx.disabled = page >= pages - 1
		_root.add_child(nx)
		var pl := _label("%d / %d" % [page + 1, pages], 14.0, UiKit.MUTED, true)
		pl.size = Vector2(56.0 * u, head_h)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pl.position = Vector2(nx.position.x - pl.size.x, area.position.y)
		_root.add_child(pl)
		var pv := _button("<", Vector2(head_h, head_h), func(): _page(-1))
		pv.position = Vector2(pl.position.x - head_h, area.position.y)
		pv.disabled = page <= 0
		_root.add_child(pv)
		right = pv.position.x - gap
	var title := _label("OOZE LAB", 20.0, UiKit.CYAN, true)
	title.position = Vector2(area.position.x, area.position.y)
	title.size = Vector2(maxf(right - area.position.x, 10.0), head_h * 0.55)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(title)
	var sub := _label("BUILD %s  ·  LAST CARD %s" % [Rules.VERSION, last_card if last_card != "" else "-"], 12.5, UiKit.MUTED)
	sub.position = Vector2(area.position.x, area.position.y + head_h * 0.52)
	sub.size = Vector2(maxf(right - area.position.x, 10.0), head_h * 0.48)
	sub.clip_text = true
	_root.add_child(sub)
	# the cards: two rows, `cols` across
	var top := area.position.y + head_h + gap
	var card_h := (area.end.y - top - gap) / 2.0
	var card_w := (area.size.x - gap * (cols - 1)) / cols
	for i in range(per_page):
		var k := page * per_page + i
		if k >= Cards.CARDS.size():
			break
		var pos := Vector2(area.position.x + (i % cols) * (card_w + gap), top + int(i / cols) * (card_h + gap))
		_root.add_child(_card(Cards.CARDS[k], pos, Vector2(card_w, card_h), u))


func fit_title_pt(title: String, width_pt: float) -> float:
	## Largest title size (pt, 17 down to UiKit.MIN_FONT_PT = 12.5) at which the title is one line in width_pt.
	var pt := 17.0
	while pt > UiKit.MIN_FONT_PT:
		if UiKit.HEAD.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_px(pt)).x <= width_pt * _u():
			return pt
		pt -= 0.5
	return UiKit.MIN_FONT_PT


func _card(c: Dictionary, pos: Vector2, dims: Vector2, u: float) -> Control:
	var live: bool = bool(c.get("live", false)) and Cards.map_path(str(c.get("map", ""))) != ""
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.position = pos
	b.size = dims
	b.clip_contents = true
	b.disabled = not live
	var a := UiKit.CYAN
	b.add_theme_stylebox_override("normal", UiKit.sb(Color(UiKit.PANEL, 0.96), a, 2))
	b.add_theme_stylebox_override("hover", UiKit.sb(Color(UiKit.PANEL.lightened(0.06), 0.98), a.lightened(0.2), 2))
	b.add_theme_stylebox_override("pressed", UiKit.sb(Color(a.darkened(0.7), 0.98), a, 2))
	b.add_theme_stylebox_override("hover_pressed", UiKit.sb(Color(a.darkened(0.7), 0.98), a, 2))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", UiKit.sb(Color(UiKit.PANEL, 0.55), Color(UiKit.FRAME, 0.5), 1))
	if live:
		b.pressed.connect(func(): _tap(c))
	# Fixed rows, placed by hand so every card lines up: title slot (one line, shrunk to fit down to 12.5 pt, else two
	# lines at 12.5 pt; never clipped), meta, question (takes the rest), CARD line pinned to the card's foot.
	var pad := 10.0 * u
	var w := dims.x - pad * 2.0
	var y := pad * 0.8
	var ink := UiKit.INK if live else UiKit.DIM
	var tcol := UiKit.CYAN if live else UiKit.DIM
	var title_txt := str(c["title"])
	var tpt := fit_title_pt(title_txt, w / u)
	var t := _label(title_txt, tpt, tcol, true)
	t.position = Vector2(pad, y)
	t.size = Vector2(w, 0.0)
	if tpt <= UiKit.MIN_FONT_PT + 0.01 and UiKit.HEAD.get_string_size(title_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_px(tpt)).x > w:
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # still too wide at the smallest size: two lines
	b.add_child(t)
	y += TITLE_SLOT_PT * u
	var meta := "%s  ·  %s  ·  AI %s" % [str(c["map"]), str(c.get("mode", "1v1")).to_upper(), str(c.get("ai", ""))] if live 			else "COMING IN %s" % str(c.get("coming", "a later lab")).to_upper()
	var ml := _label(meta, 13.0, UiKit.MUTED if live else UiKit.COPPER)
	ml.clip_text = true
	ml.position = Vector2(pad, y)
	ml.size = Vector2(w, ml.get_combined_minimum_size().y)
	b.add_child(ml)
	y += ml.size.y + 4.0 * u
	var tag := pick_tag(c)
	if tag != "" and live:                         # CHOICE SHEET: the values the next PLAY uses (tap the card to change them)
		var pk := _label(tag + "  ›", 14.0, UiKit.CYAN, true)
		pk.clip_text = true
		pk.position = Vector2(pad, y)
		pk.size = Vector2(w, pk.get_combined_minimum_size().y)
		b.add_child(pk)
		y += pk.size.y + 4.0 * u
	var idl := _label("CARD %s" % str(c["id"]), 12.5, UiKit.DIM)
	var ih := idl.get_combined_minimum_size().y
	idl.position = Vector2(pad, dims.y - pad * 0.8 - ih)
	idl.size = Vector2(w, ih)
	b.add_child(idl)
	var q := _label(str(c["question"]), 14.0, ink)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.clip_text = true
	q.position = Vector2(pad, y)
	q.size = Vector2(w, maxf(idl.position.y - 2.0 * u - y, 10.0))
	b.add_child(q)
	return b


func _tap(c: Dictionary) -> void:
	## A card with choices opens its sheet; any other card plays at once.
	if (c.get("choices", []) as Array).is_empty():
		_play(c)
	else:
		_sheet(c)


func _sheet(c: Dictionary) -> void:
	## CHOICE SHEET (lab4 jobs 2 + 5): over the LAB screen, the card's title, one row per choice (label + one chip per value,
	## the picked one lit), BACK and PLAY. Never scrolls: at most three rows of 44 pt chips on a 375 pt-tall phone.
	_build()
	var vp := get_viewport().get_visible_rect().size
	var u := _u()
	var ins := UiKit.safe_insets(vp)
	var area := Rect2(ins.x + 12.0 * u, ins.y + 8.0 * u, vp.x - ins.x - ins.z - 24.0 * u, vp.y - ins.y - ins.w - 16.0 * u)
	var sh := ColorRect.new()
	sh.color = UiKit.BASE
	sh.size = vp
	sh.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(sh)
	var gap := GAP_PT * u
	var row_h := 44.0 * u
	var t := _label(str(c["title"]), 20.0, UiKit.CYAN, true)
	t.position = area.position
	t.size = Vector2(area.size.x, row_h * 0.6)
	sh.add_child(t)
	var q := _label(str(c["question"]), 14.0, UiKit.INK)
	q.clip_text = true
	q.position = Vector2(area.position.x, area.position.y + row_h * 0.6)
	q.size = Vector2(area.size.x, row_h * 0.5)
	sh.add_child(q)
	var y := area.position.y + row_h * 1.2 + gap
	var label_w := 120.0 * u
	for ch in c["choices"]:
		var l := _label(str(ch["label"]), 15.0, UiKit.MUTED, true)
		l.position = Vector2(area.position.x, y)
		l.size = Vector2(label_w, row_h)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sh.add_child(l)
		var names: Array = ch["names"]
		var cw := minf((area.size.x - label_w - gap * names.size()) / names.size(), 170.0 * u)
		for k in range(names.size()):
			var on := pick_index(c, ch) == k
			var chip := _button(str(names[k]), Vector2(cw, row_h), func(): _pick(c, ch, k))
			chip.position = Vector2(area.position.x + label_w + k * (cw + gap), y)
			if on:
				chip.add_theme_stylebox_override("normal", UiKit.sb(Color(UiKit.CYAN.darkened(0.6), 0.98), UiKit.CYAN, 2))
				chip.add_theme_stylebox_override("hover", UiKit.sb(Color(UiKit.CYAN.darkened(0.55), 0.98), UiKit.CYAN, 2))
				chip.add_theme_color_override("font_color", UiKit.INK)
			sh.add_child(chip)
		y += row_h + gap
	var by := maxf(y + gap, area.end.y - row_h)
	var back := _button("BACK", Vector2(132.0 * u, row_h), _build)
	back.position = Vector2(area.position.x, by)
	sh.add_child(back)
	var play := _button("PLAY  " + pick_tag(c), Vector2(minf(area.size.x - 140.0 * u, 320.0 * u), row_h), func(): _play(c))
	play.add_theme_stylebox_override("normal", UiKit.sb(Color(UiKit.CYAN.darkened(0.6), 0.98), UiKit.CYAN, 2))
	play.position = Vector2(area.end.x - play.size.x, by)
	sh.add_child(play)


func _pick(c: Dictionary, ch: Dictionary, k: int) -> void:
	var p: Dictionary = picks.get(str(c["id"]), {})
	p[ch["key"]] = k
	picks[str(c["id"])] = p
	_sheet(c)


func _page(d: int) -> void:
	page += d
	_build()


func _normal_menu() -> void:
	normal = true
	reset_card()
	main.get_script().relaunch = {}
	get_tree().reload_current_scene()


func _play(c: Dictionary) -> void:
	## The card's match: main's relaunch path (as PLAY AGAIN), straight in (no VERSUS card on a relaunch).
	apply_card(c)
	var f := str(c.get("faction", "vex"))
	main.get_script().relaunch = {"map": Cards.map_path(str(c["map"])), "faction": f, "rival": str(c.get("rival", "null")),
			"ai": str(c.get("ai", "Standard")), "mode": str(c.get("mode", "1v1")), "colour": "A",
			"loadout": ArmyPresets.loadout_for(f)}
	get_tree().reload_current_scene()
