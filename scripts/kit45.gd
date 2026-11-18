class_name Kit45
extends RefCounted
## The remake's menu kit (Daniele 11-18: "apply them and improve the menus look to what was the mock up direction"):
## round 45A2 geometry (PASS + locked) painted in 45B, imported by tools/prep_menu45.py into assets/ui/menu45 (2x PNG,
## parts.json in points). Every screen is laid out on the remake's 812 x 375 pt canvas (sizes.json of the delivery):
## a Stage maps those points into the menu's content (one even scale, centred), fixed parts are drawn at their native
## size, the seven stretch families are 9-sliced, WHITE masks are tinted at run time (seat = the viewer's seat colour,
## fill = a progress colour). Text is runtime text, never below the 12.5 pt floor (UiKit.px), shrunk or wrapped to fit.

const DIR := "res://assets/ui/menu45/"
const DW := 812.0
const DH := 375.0
const INK_DARK := Color("2a1620")                    # lettering on cream (burgundy-black)
const INK_OFF := Color("cbb7a6")                     # lettering on a DISABLED key (plum)
const KICK := Color("e3a56d")                        # bronze small caps (section titles, kickers)
const CYAN_KICK := Color("29d3e0")                   # HOME's tagline
const MIN_HIT := 33.0                                # pt: the smallest tap box (45A2: every target >= 33 pt)

static var _parts: Dictionary = {}
static var audit_on := false                         # dev --font-audit: every label drawn through the kit, in pt
static var audit: Array = []                         # [text, size_pt, cut]


static func audit_note(m, t: String, size_cu: float, cut := false) -> void:
	## Dev (--font-audit): one label as drawn - its size in pt and whether it lost letters to an ellipsis.
	if audit_on and t != "":
		audit.append([t, size_cu * UiKit.pt(m), cut])


static func parts() -> Dictionary:
	if _parts.is_empty():
		var f := FileAccess.open(DIR + "parts.json", FileAccess.READ)
		if f != null:
			_parts = JSON.parse_string(f.get_as_text()).get("parts", {})
	return _parts


static func variant(fam: String, key := "") -> Dictionary:
	var vs: Dictionary = parts().get(fam, {}).get("variants", {})
	if vs.is_empty():
		return {}
	if key != "" and vs.has(key):
		return vs[key]
	return vs[vs.keys()[0]]


static func nearest(fam: String, w: float, h: float) -> String:
	## The family's variant closest to w x h pt (the delivery's merge rule: within 2 pt -> the native file).
	var best := ""
	var bd := INF
	for k in parts().get(fam, {}).get("variants", {}):
		var s: Array = parts()[fam]["variants"][k]["size"]
		var d := absf(float(s[0]) - w) + absf(float(s[1]) - h)
		if d < bd:
			bd = d
			best = k
	return best


static func tex(file: String) -> Texture2D:
	return UiKit.tex(DIR + "parts/" + file)


static func art(n: String) -> Texture2D:
	return UiKit.tex(DIR + "art/" + n + ".png")


static func seat() -> Color:
	return Rules.seat_color("A")                     # the local player in the menus: seat A


static func state_of(v: Dictionary, st: String) -> Dictionary:
	var sts: Dictionary = v.get("states", {})
	if sts.has(st):
		return sts[st]
	for k in ["NORMAL", "STATIC", "FILLED"]:
		if sts.has(k):
			return sts[k]
	return sts[sts.keys()[0]] if not sts.is_empty() else {}


static func draw_part(ci: CanvasItem, fam: String, key: String, st: String, r: Rect2, u: float, tints := {}, fill := -1.0) -> void:
	## One part into r (canvas units; u = canvas units per pt). tints: mask channel -> colour (seat defaults to the
	## viewer's seat colour, edge / letter to the seat too); fill: 0..1 of the "fill" mask shown (left to right in its slot).
	var v := variant(fam, key)
	if v.is_empty():
		return
	var s := state_of(v, st)
	var t := tex(str(s.get("file", "")))
	if t == null:
		return
	if v.has("slice"):
		nine(ci, t, r, v["slice"], u)
	else:
		ci.draw_texture_rect(t, r, false)
	var masks: Dictionary = s.get("masks", {})
	for ch in masks:
		var mt := tex(str(masks[ch]))
		if mt == null:
			continue
		var col: Color = tints.get(ch, seat())
		if ch == "fill":
			if fill < 0.0:
				continue
			col = tints.get("fill", seat())
			var sl: Array = v.get("slots", {}).get("fill", [0.0, 0.0, v["size"][0], v["size"][1]])
			var cut := (float(sl[0]) + float(sl[2]) * clampf(fill, 0.0, 1.0)) / float(v["size"][0])
			if v.has("slice"):                          # XP-BAR: 3-slice; the fill clip runs in the stretched rect
				cut = (float(sl[0]) * u + (r.size.x - (float(v["size"][0]) - float(sl[2])) * u) * clampf(fill, 0.0, 1.0)) / r.size.x
				nine(ci, mt, Rect2(r.position, r.size), v["slice"], u, col, cut)
				continue
			var ts := Vector2(mt.get_size())
			ci.draw_texture_rect_region(mt, Rect2(r.position, Vector2(r.size.x * cut, r.size.y)), Rect2(0, 0, ts.x * cut, ts.y), col)
			continue
		if v.has("slice"):
			nine(ci, mt, r, v["slice"], u, col)
		else:
			ci.draw_texture_rect(mt, r, false, col)


static func nine(ci: CanvasItem, t: Texture2D, r: Rect2, sl: Array, u: float, col := Color.WHITE, clip := 1.0) -> void:
	## A 9-slice: corners at their native size (sl = left, top, right, bottom in pt; the texture is 2 px per pt), edges and
	## centre stretched. clip < 1: only the left `clip` of the rect (a progress fill).
	var ts := Vector2(t.get_size())
	var px := 2.0                                     # texture px per pt (the 2x import)
	var l := float(sl[0]); var tp := float(sl[1]); var rr := float(sl[2]); var b := float(sl[3])
	var dl := minf(l * u, r.size.x / 2.0); var dr := minf(rr * u, r.size.x / 2.0)
	var dt := minf(tp * u, r.size.y / 2.0); var db := minf(b * u, r.size.y / 2.0)
	var xs := [r.position.x, r.position.x + dl, r.end.x - dr, r.end.x]
	var ys := [r.position.y, r.position.y + dt, r.end.y - db, r.end.y]
	var sx := [0.0, l * px, ts.x - rr * px, ts.x]
	var sy := [0.0, tp * px, ts.y - b * px, ts.y]
	var xmax := r.position.x + r.size.x * clip
	for i in range(3):
		for j in range(3):
			var d := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			var s := Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j])
			if d.size.x <= 0.0 or d.size.y <= 0.0 or s.size.x <= 0.0 or s.size.y <= 0.0:
				continue
			if d.position.x >= xmax:
				continue
			if d.end.x > xmax:                          # the fill's clip
				var f := (xmax - d.position.x) / d.size.x
				d.size.x *= f
				s.size.x *= f
			ci.draw_texture_rect_region(t, d, s, col)


const INK_CREAM := Color("faead1")                  # 45B2: cream text and glyphs on the copper SELECTED plates
static var _ink_cache: Dictionary = {}


static func ink_on(fam: String, key: String, st: String, slot: Array) -> Color:
	## The lettering colour for a face: dark on a light (cream) face, cream on a dark one (copper SELECTED, plum, DISABLED),
	## measured once per file under the label slot (the part's centre when it has none).
	var v := variant(fam, key)
	var file := str(state_of(v, st).get("file", ""))
	if _ink_cache.has(file):
		return _ink_cache[file]
	var col := INK_DARK
	var t := tex(file)
	var img: Image = t.get_image() if t != null else null
	if img != null:
		if img.is_compressed():
			img.decompress()
		var sz := Vector2(img.get_size())
		var pt_px := sz.x / float(v["size"][0])
		var r := Rect2(Vector2(float(slot[0]), float(slot[1])) * pt_px, Vector2(float(slot[2]), float(slot[3])) * pt_px) if slot.size() == 4 				else Rect2(sz * 0.3, sz * 0.4)
		var lum := 0.0
		var n := 0
		for i in range(5):
			for j in range(3):
				var p := r.position + r.size * Vector2((i + 0.5) / 5.0, (j + 0.5) / 3.0)
				var c := img.get_pixel(clampi(int(p.x), 0, img.get_width() - 1), clampi(int(p.y), 0, img.get_height() - 1))
				if c.a > 0.5:
					lum += c.get_luminance()
					n += 1
		if n > 0 and lum / n < 0.45:
			col = INK_OFF if st == "DISABLED" or st == "LOCKED" else INK_CREAM
	_ink_cache[file] = col
	return col


static func floor_px(m) -> float:
	## The text floor in canvas units (12.5 pt on a phone; 0 on desktop).
	return float(UiKit.px(m, 0.0)) if m != null else 0.0


static func fit(m, t: String, head: bool, size_cu: float, room: float, lo_frac := 1.0) -> int:
	## The font size (canvas units) at which `t` fits `room`, from size_cu down to the floor (x lo_frac).
	var f: Font = UiKit.HEAD if head else UiKit.BODY
	var lo := maxf(floor_px(m) * lo_frac, 1.0)
	var fs := maxf(size_cu, lo)
	while fs > lo and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(fs))).x > room:
		fs -= 0.5
	return maxi(1, int(round(fs)))


# ------------------------------------------------------------------ the stage
class Stage extends Control:
	## The remake's 812 x 375 pt canvas, mapped evenly into the menu content (centred). R / P convert points.
	var m                                              # the Menu
	var u := 1.0                                       # canvas units per pt
	var o := Vector2.ZERO                              # the canvas origin in this control

	func setup(menu, area: Vector2) -> void:
		m = menu
		size = area
		position = Vector2.ZERO
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		u = minf(area.x / DW, area.y / DH)
		o = ((area - Vector2(DW, DH) * u) / 2.0).floor()

	func R(x: float, y: float, w: float, h: float) -> Rect2:
		return Rect2(o + Vector2(x, y) * u, Vector2(w, h) * u)

	func P(x: float, y: float) -> Vector2:
		return o + Vector2(x, y) * u

	func pt_of(r: Rect2) -> Rect2:
		return Rect2((r.position - o) / u, r.size / u)

	func piece(fam: String, x: float, y: float, w: float, h: float, st := "STATIC", key := "") -> Piece:
		var p := Piece.new()
		p.fam = fam
		p.key = key if key != "" else Kit45.nearest(fam, w, h)
		p.st = st
		p.u = u
		var r := R(x, y, w, h)
		p.position = r.position
		p.size = r.size
		add_child(p)
		return p

	func key(fam: String, x: float, y: float, w: float, h: float, label: String, call: Callable, sel := false, off := false, k := "") -> Btn:
		var b := Btn.new()
		b.m = m
		b.fam = fam
		b.key = k if k != "" else Kit45.nearest(fam, w, h)
		b.label = label
		b.selected = sel
		b.u = u
		b.disabled = off
		var r := R(x, y, w, h)
		var hit := maxf(r.size.y, MIN_HIT * u)       # the tap box grows to 33 pt; the art stays its size, centred
		b.position = Vector2(r.position.x, r.position.y - (hit - r.size.y) / 2.0)
		b.size = Vector2(r.size.x, hit)
		b.art = Rect2(Vector2(0, (hit - r.size.y) / 2.0), r.size)
		if call.is_valid():
			b.pressed.connect(func(): UiKit.acknowledge(b, call))
		add_child(b)
		return b

	func txt(t: String, x: float, y: float, w: float, h: float, size_pt: float, col: Color, head := false, align := 0, lines := 1) -> Txt:
		var l := Txt.new()
		l.m = m
		l.text = t
		l.size_cu = size_pt * u
		l.col = col
		l.head = head
		l.align = align
		l.max_lines = lines
		var r := R(x, y, w, h)
		l.position = r.position
		l.size = r.size
		add_child(l)
		return l

	func pic(t: Texture2D, x: float, y: float, w: float, h: float, cover := false, mod := Color.WHITE) -> TextureRect:
		var tr := TextureRect.new()
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate = mod
		var r := R(x, y, w, h)
		tr.position = r.position
		tr.size = r.size
		tr.clip_contents = cover
		add_child(tr)
		return tr

	func tap(x: float, y: float, w: float, h: float, call: Callable) -> Button:
		## An invisible tap box over drawn art (a card, a row).
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		for sn in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			b.add_theme_stylebox_override(sn, StyleBoxEmpty.new())
		var r := R(x, y, w, h)
		b.position = r.position
		b.size = r.size
		if call.is_valid():
			b.pressed.connect(func(): UiKit.acknowledge(b, call))
		add_child(b)
		return b


# ------------------------------------------------------------------ nodes
class Piece extends Control:
	## A static part (cabinet, well, card face) at its rect; `fill` 0..1 shows its fill mask, `tints` per mask channel.
	var fam := ""
	var key := ""
	var st := "STATIC"
	var u := 1.0
	var fill := -1.0
	var tints := {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Kit45.draw_part(self, fam, key, st, Rect2(Vector2.ZERO, size), u, tints, fill)


class Btn extends Button:
	## A four-state key (NORMAL / PRESSED / SELECTED / DISABLED; SELECTED lights its seat mask) with a runtime label in the
	## part's label slot (or centred). `ink` overrides the lettering colour; `glyph` draws an icon at the left of the label.
	var m
	var fam := ""
	var key := ""
	var label := ""
	var selected := false
	var u := 1.0
	var art := Rect2()
	var ink := Color(0, 0, 0, 0)
	var glyph: Texture2D
	var glyph_rect := Rect2()                         # pt, inside the art (0 size = no glyph)
	var size_pt := 0.0                                # label size (0 = from the slot / art height)
	var lock_state := ""                              # a fixed state (LOCKED, EQUIPPED...) over the four
	var label_slot := false                           # the label sits in the part's own label slot (cards, tiles), not mid-face
	var value := ""                                   # SELECTOR-CARD: a second line (the value) under the label (the kicker)
	var acc_tex: Texture2D                            # SELECTOR-CARD: a thumbnail in the accessory slot
	var acc_col := Color(0, 0, 0, 0)                  # SELECTOR-CARD: a colour swatch in the accessory slot

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		for sn in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(sn, StyleBoxEmpty.new())
		text = label                                   # (tests and tools find keys by their text; drawn by _draw, not the Button)
		clip_text = true
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
			add_theme_color_override(k, Color(0, 0, 0, 0))
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)

	func state() -> String:
		if lock_state != "":
			return lock_state
		if disabled:
			return "DISABLED"
		if is_pressed() or get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED:
			return "PRESSED"
		return "SELECTED" if selected else "NORMAL"

	func _draw() -> void:
		var st := state()
		Kit45.draw_part(self, fam, key, st, art, u)
		var v := Kit45.variant(fam, key)
		var sl: Array = v.get("slots", {}).get("label", [])
		if value != "":                                # a selector: kicker over value, the accessory at the right
			var slots: Dictionary = v.get("slots", {})
			var vs: Array = slots.get("value", sl)
			var ic := Kit45.ink_on(fam, key, st, vs)
			var sr := func(a: Array) -> Rect2: return Rect2(art.position + Vector2(float(a[0]), float(a[1])) * u, Vector2(float(a[2]), float(a[3])) * u)
			var ac: Array = slots.get("accessory", [])
			var right := 0.0
			var room_v: Rect2 = sr.call(vs)                # FIX 2: the value first - the thumbnail only where the value still fits
			var need := UiKit.HEAD.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(maxf(13.0 * u, Kit45.floor_px(m))))).x
			var acc_room := room_v.size.x
			if not ac.is_empty():
				var ar0: Rect2 = sr.call(ac)
				acc_room = ar0.position.x - room_v.position.x - 3.0 * u
			if not ac.is_empty() and (acc_tex != null or acc_col.a > 0.0) and need <= acc_room:
				var ar: Rect2 = sr.call(ac)
				if acc_tex != null:
					var ts := Vector2(acc_tex.get_size())
					var k := minf(ar.size.x / ts.x, ar.size.y / ts.y)
					var d := ts * k
					draw_texture_rect(acc_tex, Rect2(ar.position + (ar.size - d) / 2.0, d), false)
				else:
					var sq := minf(ar.size.x, ar.size.y)
					draw_rect(Rect2(ar.position + (ar.size - Vector2(sq, sq)) / 2.0, Vector2(sq, sq)), acc_col)
				right = maxf(0.0, (float(sl[0]) + float(sl[2])) * u + art.position.x - ar.position.x + 3.0 * u) if not sl.is_empty() else 0.0
			var lr: Rect2 = sr.call(sl if not sl.is_empty() else [8, 0, art.size.x / u - 30.0, art.size.y / u / 2.0])
			var vr: Rect2 = sr.call(vs)
			lr.size.x -= right
			vr.size.x -= right
			Kit45.draw_text(self, m, label, lr, 12.5 * u, Color(ic, 0.72), false, 0, 1)
			Kit45.draw_text(self, m, value, vr, 13.0 * u, ic, true, 0, 1)
			return
		var lr := Rect2(art.position + Vector2(4, 0) * u, art.size - Vector2(8, 0) * u)
		if not sl.is_empty():
			lr = Rect2(art.position + Vector2(float(sl[0]), float(sl[1])) * u, Vector2(float(sl[2]), float(sl[3])) * u)
			if not label_slot:
				lr = Rect2(lr.position.x, art.position.y, lr.size.x, art.size.y)   # vertically: the whole face (the floor may outgrow the slot)
		if glyph != null and glyph_rect.size.x > 0.0:
			var gr := Rect2(art.position + glyph_rect.position * u, glyph_rect.size * u)
			draw_texture_rect(Kit45.white(glyph), gr, false, ink if ink.a > 0.0 else Kit45.ink_on(fam, key, st, sl))   # 45B2: cream on copper
			var gx := gr.end.x + 4.0 * u - art.position.x
			lr = Rect2(art.position.x + gx, lr.position.y, art.size.x - gx - 6.0 * u, lr.size.y)
		if label == "":
			return
		var col := ink if ink.a > 0.0 else Kit45.ink_on(fam, key, st, sl)
		var want := (size_pt if size_pt > 0.0 else minf(art.size.y / u * 0.48, 13.0)) * u
		var hf: Font = UiKit.BODY
		if hf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(maxf(Kit45.floor_px(m), 1.0)))).x > lr.size.x:
			var x0 := lr.position.x if glyph != null and glyph_rect.size.x > 0.0 else art.position.x + 4.0 * u
			lr = Rect2(x0, lr.position.y, art.end.x - 4.0 * u - x0, lr.size.y)   # FIX 2: the whole face before a cut
		Kit45.draw_text(self, m, label, lr, want, col, false, 1, 2)


class Txt extends Control:
	var m
	var text := ""
	var size_cu := 12.0
	var col := Color.WHITE
	var head := false
	var align := 0                                    # 0 left, 1 centre, 2 right
	var max_lines := 1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Kit45.draw_text(self, m, text, Rect2(Vector2.ZERO, size), size_cu, col, head, align, max_lines)


static func draw_text(ci: CanvasItem, m, t: String, r: Rect2, size_cu: float, col: Color, head := false, align := 0, max_lines := 1, lo_frac := 1.0) -> void:
	## Text in r, vertically centred: one line shrunk to fit (never under the floor), else word-wrapped onto max_lines,
	## else clipped with an ellipsis. Explicit "\n" splits lines.
	if t == "":
		return
	var f: Font = UiKit.HEAD if head else UiKit.BODY
	var lo := maxf(floor_px(m) * lo_frac, 1.0)
	var fs := maxf(size_cu, lo)
	var lines: Array = t.split("\n")
	var w := func(s: String, z: float) -> float: return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(z))).x
	var widest := func(ls: Array, z: float) -> float:
		var mx := 0.0
		for s in ls:
			mx = maxf(mx, w.call(s, z))
		return mx
	while fs > lo and widest.call(lines, fs) > r.size.x:
		fs -= 0.5
	var cap := max_lines
	if widest.call(lines, fs) > r.size.x and max_lines == 1 and lines.size() == 1 and t.contains(" ") 			and f.get_height(maxi(1, int(round(fs)))) * 0.98 * 2.0 <= r.size.y + 2.0:
		cap = 2                                        # designer 11 FIX 2: at the floor, two lines where the box holds them
	if widest.call(lines, fs) > r.size.x and cap > lines.size():
		var words := t.replace("\n", " ").split(" ")
		lines = []
		var cur := ""
		for wd in words:
			var tryl := wd if cur == "" else cur + " " + wd
			if cur != "" and w.call(tryl, fs) > r.size.x:
				lines.append(cur)
				cur = wd
			else:
				cur = tryl
		lines.append(cur)
		while lines.size() > cap:
			var last: String = lines.pop_back()
			lines[-1] = str(lines[-1]) + " " + last
	var ifs := maxi(1, int(round(fs)))
	var lh := f.get_height(ifs) * 0.98
	var asc := f.get_ascent(ifs)
	var total := lh * lines.size()
	var y := r.position.y + (r.size.y - total) / 2.0 + asc
	for s in lines:
		var line: String = s
		while line.length() > 1 and w.call(line, ifs) > r.size.x + 0.5:
			line = line.substr(0, line.length() - 2) + "…"
		if audit_on:
			audit_note(m, line, ifs, line != s)
		var lw: float = w.call(line, ifs)
		var x := r.position.x
		if align == 1:
			x += (r.size.x - lw) / 2.0
		elif align == 2:
			x += r.size.x - lw
		ci.draw_string(f, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, ifs, col)
		y += lh


# ------------------------------------------------------------------ keys for the Button-built screens
const KEY_CAP_L := 10.0                              # pt kept at the key's left (the chamfer)
const KEY_CAP_R := 20.0                              # pt kept at the right (the chamfer + the seat lamp)


static func caps(ci: RID, t: Texture2D, r: Rect2, u: float, col: Color) -> void:
	## A 33 pt key drawn into r: height mapped evenly (u = canvas units per pt), the two caps at their size, the face stretched.
	var ts := Vector2(t.get_size())
	var px := ts.y / 33.0
	var dl := minf(KEY_CAP_L * u, r.size.x * 0.3)
	var dr := minf(KEY_CAP_R * u, r.size.x * 0.4)
	var sl := dl / u * px
	var sr := dr / u * px
	var rid := t.get_rid()
	RenderingServer.canvas_item_add_texture_rect_region(ci, Rect2(r.position, Vector2(dl, r.size.y)), rid, Rect2(0, 0, sl, ts.y), col)
	RenderingServer.canvas_item_add_texture_rect_region(ci, Rect2(r.position.x + dl, r.position.y, r.size.x - dl - dr, r.size.y), rid,
			Rect2(sl, 0, ts.x - sl - sr, ts.y), col)
	RenderingServer.canvas_item_add_texture_rect_region(ci, Rect2(r.end.x - dr, r.position.y, dr, r.size.y), rid, Rect2(ts.x - sr, 0, sr, ts.y), col)


class KeyBox extends StyleBox:
	## A 45B key (PRIMARY-WIDE) as a StyleBox, for the screens still built from Buttons (VERSUS, PAUSE, WIN / LOSS, sheets):
	## the 33 pt variant nearest the key's width, the caps kept, the face stretched. SELECTED = the copper face with the seat
	## rim + lamp in the seat colour (45B2; GAP-LIST §0: rim, never the old cyan underline).
	var fam := "PRIMARY-WIDE"
	var st := "NORMAL"
	var mod := Color.WHITE

	func _draw(ci: RID, r: Rect2) -> void:
		var u := r.size.y / 33.0
		var v := Kit45.variant(fam, Kit45.nearest(fam, r.size.x / u, 33.0))
		if v.is_empty():
			return
		var s := Kit45.state_of(v, st)
		var t := Kit45.tex(str(s.get("file", "")))
		if t == null:
			return
		Kit45.caps(ci, t, r, u, mod)
		var masks: Dictionary = s.get("masks", {})
		for ch in masks:
			var mt := Kit45.tex(str(masks[ch]))
			if mt != null:
				Kit45.caps(ci, mt, r, u, Kit45.seat())


static func key_ink(st: String) -> Color:
	return ink_on("PRIMARY-WIDE", "229x33pt", st, [])


static var _white := {}


static func white(t: Texture2D) -> Texture2D:
	## A glyph painted in dark ink, as white with its alpha (cached), so it can be drawn in the face's ink colour.
	if t == null:
		return null
	if _white.has(t):
		return _white[t]
	var img := t.get_image()
	if img == null:
		return t
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var d := img.get_data()
	for i in range(0, d.size(), 4):
		d[i] = 255
		d[i + 1] = 255
		d[i + 2] = 255
	var w := ImageTexture.create_from_image(Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, d))
	_white[t] = w
	return w
