class_name MatchScreens
extends RefCounted
## Alpha 21 UI pass - the in-match screens (SCREEN-SYSTEM.md 17 PAUSE, 18 VICTORY, 19 DEFEAT, 20 MATCH DETAILS and the
## YOU'RE OUT card), built with UiKit straight on the match's canvas (the menu's shell isn't there). A MatchScreens is
## the object UiKit's pieces want - `content` + `_pt_factor()` (the menu's live phone fit, so taps stay >= 44 pt and
## text >= 12.5 pt) - over one full-screen layer that swallows every tap under it. Hud (show_end / pause_menu /
## show_out_panel) and MissionOverlay (the mission result) build their pages through it:
##   open(layer, mobile, f)   clears `layer` for a page in faction f's accent (again for a resize or another page)
##   result(d)                VICTORY / DEFEAT: kicker, headline, name, the hero, stars, three metrics, the actions
##   details(d, table)        MATCH DETAILS: the per-seat stats of seat_table(), CONTINUE / BACK
##   card(d)                  PAUSE / YOU'RE OUT: a centred card - kicker, headline, a line, the hero, the actions
##   seat_table(sim, human)   every per-seat stat the Sim / Progression.seat_stats record (pure; test_match_report)
## Faction accent = UI identity; seat colours (Rules) appear only where they name a seat of this match.

const DEFEAT_INK := Color("f4c7bd")                 # DEFEAT.'s headline: a pale warning, never a celebration
const GOOD := Color("59e07a")
const BAD := Color("ff6b6b")
const STAR_OFF := Color("3d5561")

var layer: Control
var content: Control                                # where UiKit adds (the layer, or a page group inside it)
var mobile := false
var f := "vex"


static func open(parent: Control, is_mobile: bool, faction: String) -> MatchScreens:
	var s := MatchScreens.new()
	s.layer = parent
	s.mobile = is_mobile
	s.f = faction if UiKit.ACCENTS.has(faction) else "vex"
	s.clear()
	return s


# ------------------------------------------------------------------ round 37B2 paint (hud-37): P6 shell, AI mark sockets, P7 buttons
var seat := ""                                      # the human's seat: the sockets' rim colour (neon = SEAT colour)
var _hero_pending: Array = []


func painted() -> bool:
	return HudLab.on() and HudLab.tex37("PAINT-P6-SHELL") != null and HudLab.tex37("PAINT-P7") != null


func ink() -> Color:
	return HudLab.INK if painted() else UiKit.INK


func muted() -> Color:
	return Color(HudLab.INK, 0.72) if painted() else UiKit.MUTED


func seat_col() -> Color:
	return Rules.seat_color(seat) if seat != "" else UiKit.accent(f)


func _nine(tex_name: String, r: Rect2, margin_px: Array, col := Color.WHITE) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.texture = HudLab.tex37(tex_name)
	n.patch_margin_left = margin_px[0]
	n.patch_margin_top = margin_px[1]
	n.patch_margin_right = margin_px[2]
	n.patch_margin_bottom = margin_px[3]
	n.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	n.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	n.modulate = col
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.size = r.size
	UiKit.add(self, n, r.position)
	return n


func shell(pos: Vector2, dims: Vector2) -> void:
	## P6-SHELL: the ivory modal / report sheet, 9-sliced (56 / 60 px margins at 4x). Falls back to the old panel.
	if not painted():
		UiKit.panel(self, pos, dims, f, false, Color(UiKit.PANEL, 0.97))
		return
	_nine("PAINT-P6-SHELL", Rect2(pos, dims), [56, 56, 56, 60])
	if HudLab.tex37("MASK-P6-OWNER-EDGE") != null:
		_nine("MASK-P6-OWNER-EDGE", Rect2(pos, dims), [56, 56, 56, 60], seat_col())


func socket(centre: Vector2, side: float, size_id: int) -> void:
	## The AI MARK SOCKET (paint + seat rim); the mark inside is the faction emblem until round 36 lands (stand-in, flagged).
	var d := side
	if painted():
		var r := Rect2(centre - Vector2(d, d) / 2.0, Vector2(d, d))
		var base := HudLab.tex37("PAINT-SOCKET-%d" % size_id)
		if base != null:
			var t := TextureRect.new()
			t.texture = base
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			t.size = r.size
			UiKit.add(self, t, r.position)
	var inner := d * 0.62
	UiKit.hero(self, f, centre - Vector2(inner, inner) / 2.0, Vector2(inner, inner), false)


func pbtn(text: String, pos: Vector2, dims: Vector2, call: Callable, kind := "secondary", size := 16.0) -> Button:
	## A P7 button (primary / secondary): painted, dark ink, the primary's accent rim in the faction accent.
	var b := UiKit.btn(self, text, pos, dims, call, kind, f, size)
	if not painted():
		return b
	var tn := "PAINT-P7" if kind == "primary" else "PAINT-P7-secondary"
	var sb := StyleBoxTexture.new()
	sb.texture = HudLab.tex37(tn)
	sb.texture_margin_left = 40
	sb.texture_margin_right = 40
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	var dim := sb.duplicate()
	dim.modulate_color = Color(0.9, 0.9, 0.9)
	for k in ["normal", "disabled"]:
		b.add_theme_stylebox_override(k, sb)
	for k in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(k, dim)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, HudLab.INK)
	if kind == "primary" and HudLab.tex37("MASK-P7-ACCENT-RIM") != null:
		var n := NinePatchRect.new()
		n.texture = HudLab.tex37("MASK-P7-ACCENT-RIM")
		n.patch_margin_left = 40
		n.patch_margin_right = 40
		n.modulate = UiKit.accent(f)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(n)
	return b


func _pt_factor() -> float:
	## Menu._pt_factor's formula on this canvas: 0.0 on desktop (no minimum applies).
	if not mobile or layer == null or not layer.is_inside_tree():
		return 0.0
	var v := full()
	if v.x <= 0.0 or v.y <= 0.0:
		return 0.0
	return UiKit.K * minf(v.x / 1280.0, v.y / 720.0) * UiKit.pt_per_px(v)


func full() -> Vector2:
	return layer.get_viewport_rect().size


func vp() -> Vector2:
	## The area the screen lays out in: the viewport inside the device's safe area (UiKit.safe_insets).
	var ins := UiKit.safe_insets(full())
	return full() - Vector2(ins.x + ins.z, ins.y + ins.w)


func phone() -> bool:
	return _pt_factor() > 0.0


func margin() -> float:
	return maxf(26.0, vp().x * 0.024)


func clear() -> void:
	for c in layer.get_children():
		layer.remove_child(c)
		c.queue_free()
	var ins := UiKit.safe_insets(full())
	layer.position = Vector2(ins.x, ins.y)             # inside the notch / home-indicator bands
	layer.size = vp()
	content = layer


func backdrop(dim: float, art := false) -> void:
	## The dim over the match (it stays visible behind a card), or the faction's environment (the results);
	## either way the layer takes every tap, so nothing reaches the map or the HUD under it.
	var v := full()                                    # the dim / art covers the whole screen, bands included
	var at := -layer.position
	if art:
		var tex := UiKit.background(f)
		if tex != null:
			var r := TextureRect.new()
			r.texture = tex
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			r.size = v
			r.position = at
			r.modulate = Color(0.52, 0.55, 0.6)
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layer.add_child(r)
	var shade := UiKit.rect(at, v, Color(UiKit.BASE, dim))
	shade.mouse_filter = Control.MOUSE_FILTER_STOP      # the bands outside the (inset) layer take taps too
	layer.add_child(shade)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP


func _group() -> Control:
	## A page group inside the layer (so a block can be centred after it is laid out); UiKit adds into it.
	var g := Control.new()
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(g)
	content = g
	return g


func _title(x: float, y: float, kicker: String, headline: String, size := 34.0) -> float:
	var k := UiKit.label(self, kicker.to_upper(), 12, UiKit.accent(f) if not painted() else ink().lerp(UiKit.accent(f), 0.35), true, 3)
	UiKit.add(self, k, Vector2(x, y))
	y += k.get_minimum_size().y + 2.0
	var h := UiKit.label(self, headline.to_upper(), size, ink(), true)
	UiKit.add(self, h, Vector2(x - 2.0, y))
	return y + h.get_minimum_size().y


func _wrapped(text: String, size: float, col: Color, pos: Vector2, w: float, head := false) -> float:
	## A word-wrapped label; returns its height.
	var l := UiKit.label(self, text, size, col, head)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var h := UiKit.text_h(self, text, size, w, head)
	l.size = Vector2(w, h)
	UiKit.add(self, l, pos)
	return h


func _hero_block(x0: float, x1: float, top: float, bottom: float, glow := true) -> void:
	## The faction's original character, as large as the column allows, and its tag under it.
	var tag := str(UiKit.TAGS.get(f, ""))
	var tag_h := UiKit.line_h(self, 14, true) + 14.0
	var hs := minf(x1 - x0, bottom - top - tag_h - 8.0)
	var pos := Vector2(x0 + (x1 - x0 - hs) / 2.0, top + (bottom - top - tag_h - 8.0 - hs) / 2.0)
	UiKit.hero(self, f, pos, Vector2(hs, hs), glow)
	var tw := UiKit.text_w(self, tag, 14, true) + tag.length() * 2.0 + 30.0
	UiKit.tag(self, tag, Vector2(pos.x + (hs - tw) / 2.0, pos.y + hs + 8.0), f)


# ------------------------------------------------------------------ 18 / 19: VICTORY / DEFEAT
func _split() -> float:
	## Where the hero column ends and the result's text column starts.
	return vp().x * (0.36 if phone() else 0.4)


func result_width() -> float:
	return vp().x - (_split() + margin() * 0.4) - margin()


func reward_scale(base: float) -> float:
	## RewardStrip's `scale` for the result column: its text grown to the phone minimum, its XP bar (440 x scale)
	## still inside the column.
	return clampf(UiKit.px(self, 14) / 14.0, base, maxf(base, result_width() / 450.0))


func _recolour(n: Node) -> void:
	## Ivory sheet: the strip's light text goes to the pack's dark ink.
	if "ink_text" in n:
		n.set("ink_text", HudLab.INK)
	if n is Label:
		(n as Label).add_theme_color_override("font_color", HudLab.INK)
	for c in n.get_children():
		_recolour(c)


func result(d: Dictionary) -> Dictionary:
	## d: won, draw, kicker, headline, name, sub (a line under the name), stars (-1: not a mission), star_note,
	## metrics [[value, caption] x 3], primary [text, Callable], details (Callable; invalid: no MATCH DETAILS),
	## quiet [[text, Callable]...], extras [Control...] (Progression's strip, the rematch line: placed as they are).
	## Returns {"stars": [Mark...], "primary": Button, "page": Control}.
	clear()
	backdrop(0.4, true)
	var v := vp()
	var ph := phone()
	var mg := margin()
	var out := {"stars": []}
	var split := _split()
	var sheet: NinePatchRect = null
	if painted():
		socket(Vector2((mg + split - mg * 0.5) / 2.0, v.y / 2.0), minf(minf(split - mg * 1.5, v.y - mg * 2.0 - 40.0), 200.0 * maxf(1.0, v.y / 375.0 * 0.8)), 200)
		var tg := str(UiKit.TAGS.get(f, ""))
		var tw := UiKit.text_w(self, tg, 14, true) + tg.length() * 2.0 + 30.0
		UiKit.tag(self, tg, Vector2((mg + split - mg * 0.5 - tw) / 2.0, v.y / 2.0 + minf(minf(split - mg * 1.5, v.y - mg * 2.0 - 40.0), 200.0 * maxf(1.0, v.y / 375.0 * 0.8)) / 2.0 + 10.0), f)
		sheet = _nine("PAINT-P6-SHELL", Rect2(Vector2.ZERO, Vector2(10, 10)), [56, 56, 56, 60])
	else:
		_hero_block(mg, split - mg * 0.5, mg, v.y - mg)
	var page := _group()
	var x := split + mg * 0.4
	var w := v.x - x - mg
	var y := 0.0
	var acc := ink().lerp(UiKit.accent(f), 0.3) if painted() else UiKit.accent(f)
	UiKit.add(self, UiKit.label(self, str(d.get("kicker", "")).to_upper(), 13, acc, true, 3), Vector2(x, y))
	y += UiKit.line_h(self, 13, true) + 2.0
	var won := bool(d.get("won", false))
	var hcol := ink() if won else (muted() if bool(d.get("draw", false)) else (HudLab.WARN_INK if painted() else DEFEAT_INK))
	var hsize := 60.0 if ph else 68.0
	var head := str(d.get("headline", ""))
	while hsize > 32.0 and UiKit.text_w(self, head, hsize, true) > w:   # the syndicate's longer lines shrink to fit
		hsize -= 4.0
	UiKit.add(self, UiKit.label(self, head, hsize, hcol, true), Vector2(x - 3.0, y))
	y += UiKit.line_h(self, hsize, true) + 2.0
	var name_text := str(d.get("name", "")).to_upper()
	if name_text != "":
		UiKit.add(self, UiKit.label(self, name_text, 20, ink(), true), Vector2(x, y))
		y += UiKit.line_h(self, 20, true) + 4.0
	# iOS (Safari's 320-340 pt, a narrow column): where the quiet buttons need a second row, the sub line (the matchup -
	# MATCH DETAILS shows it too) gives them its height
	var quiet_rows := maxi(1, ceili((d.get("quiet", []) as Array).size() / 3.0))   # (three per row, equal widths)
	var sub := str(d.get("sub", ""))
	if quiet_rows > 1 and ph:
		sub = ""
	if sub != "":
		y += _wrapped(sub, 15, muted(), Vector2(x, y), w) + 6.0
	var stars := int(d.get("stars", -1))
	if stars >= 0:                                     # campaign missions: earned filled gold, and the count
		var ss := 34.0
		var sx := x
		for i in range(3):
			var mk := Mark.new()
			mk.kind = "star"
			mk.color = UiKit.STAR if i < stars else STAR_OFF
			mk.size = Vector2(ss, ss)
			UiKit.add(self, mk, Vector2(sx, y + 4.0))
			(out["stars"] as Array).append(mk)
			sx += ss + 18.0
		var cnt := UiKit.label(self, "%d / 3" % stars, 18, UiKit.STAR if stars > 0 else UiKit.DIM, true)
		UiKit.add(self, cnt, Vector2(sx + 4.0, y + 4.0 + (ss - UiKit.line_h(self, 18, true)) / 2.0))
		y += ss + 12.0
		var note := str(d.get("star_note", ""))
		if note != "":
			y += _wrapped(note, 13, muted(), Vector2(x, y), w) + 6.0
	page.add_child(UiKit.rect(Vector2(x, y), Vector2(w, 1.0), Color(UiKit.FRAME, 0.9)))
	y += 12.0
	var metrics: Array = d.get("metrics", [])
	var cw := w / maxf(1.0, float(metrics.size()))
	for i in range(metrics.size()):
		var mv: Array = metrics[i]
		UiKit.add(self, UiKit.label(self, str(mv[0]), 28, ink(), true), Vector2(x + i * cw, y))
		UiKit.add(self, UiKit.label(self, str(mv[1]), 13, muted()), Vector2(x + i * cw, y + UiKit.line_h(self, 28, true)))
	if not metrics.is_empty():
		y += UiKit.line_h(self, 28, true) + UiKit.line_h(self, 13) + 10.0
		page.add_child(UiKit.rect(Vector2(x, y), Vector2(w, 1.0), Color(UiKit.FRAME, 0.9)))
		y += 12.0
	for c in d.get("extras", []):                      # Progression's strip (kept whole), the rematch line...
		var ctl := c as Control
		page.add_child(ctl)
		if painted():
			_recolour(ctl)
		# (in the tree first: a container measures its children there)
		var ms := ctl.get_combined_minimum_size()
		if ctl is RewardStrip:                         # its rows summed (the cached minimum lags a label behind)
			ms.y = 0.0
			for k in ctl.get_children():
				ms.y += (k as Control).get_combined_minimum_size().y
			ms.y += ctl.get_theme_constant("separation") * maxf(0.0, ctl.get_child_count() - 1)
		ctl.position = Vector2(x + maxf(0.0, (w - ms.x) / 2.0) if ctl is RewardStrip else x, y)
		ctl.size = Vector2(minf(ms.x, w) if ctl is RewardStrip else w, ms.y)
		y += ms.y + 10.0
	var prim: Array = d.get("primary", [])
	var det: Callable = d.get("details", Callable())
	# UX pass (Daniele 2026-11-04): two rows of the same total width - the primary (2 parts) + MATCH DETAILS (1 part), then
	# the quiet ways out sharing the second row in equal parts
	var gap := 10.0
	var dw := floorf((w - gap) / 3.0) if det.is_valid() else 0.0
	if not prim.is_empty():
		var pw := w - (dw + gap if det.is_valid() else 0.0)
		out["primary"] = pbtn(str(prim[0]), Vector2(x, y), Vector2(pw, 52.0), prim[1], "primary", 17)
	if det.is_valid():
		pbtn("MATCH DETAILS", Vector2(x + w - dw, y), Vector2(dw, 52.0), det, "secondary", 15)
	y += UiKit.tap_h(self, 52.0) + 8.0
	var quiet: Array = d.get("quiet", [])
	var per := mini(maxi(quiet.size(), 1), 3)           # up to three per row, equal widths
	var qw := floorf((w - gap * (per - 1)) / per)
	for i in range(quiet.size()):
		var q: Array = quiet[i]
		if i > 0 and i % per == 0:
			y += UiKit.tap_h(self, 44.0) + 8.0
		pbtn(str(q[0]), Vector2(x + (i % per) * (qw + gap), y), Vector2(qw, 44.0), q[1], "secondary", 14)
	if not (d.get("quiet", []) as Array).is_empty():
		y += UiKit.tap_h(self, 44.0)
	page.position.y = clampf((v.y - y) / 2.0, 8.0, maxf(8.0, v.y - y - 8.0))
	if sheet != null:
		var sp := Vector2(x - 24.0, page.position.y - 16.0)
		sheet.position = sp
		sheet.size = Vector2(w + 48.0, y + 32.0)
	out["page"] = page
	content = layer
	return out


# ------------------------------------------------------------------ 20: MATCH DETAILS
func details(d: Dictionary, table: Dictionary) -> void:
	## d: name, sub ("1v1 · 03:42"), outcome ("VICTORY"), back (Callable), primary [text, Callable] (or none),
	## notes [[kind "star"|"check"|"cross", text, ok]...] (a mission's stars and optional objective, over the table).
	clear()
	backdrop(0.55, true)
	var v := vp()
	var ph := phone()
	var mg := margin()
	var acc := ink().lerp(UiKit.accent(f), 0.3) if painted() else UiKit.accent(f)
	var top := mg * (0.4 if ph else 0.7)
	var y := UiKit.title(self, mg, top, "AFTER ACTION", "MATCH DETAILS.", f, 34.0 * (0.8 if ph else 1.0)) + 10.0
	UiKit.back_link(self, v.x - mg, top, d.get("back", Callable()))
	var bh := UiKit.tap_h(self, 50.0)
	var bottom := v.y - mg * 0.5 - bh
	var prim: Array = d.get("primary", [])
	if not prim.is_empty():
		var bw := maxf(220.0, UiKit.text_w(self, str(prim[0]), 17, true) + 60.0)
		pbtn(str(prim[0]), Vector2(v.x - mg - bw, bottom), Vector2(bw, 50.0), prim[1], "primary", 17)
	var sub := str(d.get("sub", ""))
	if sub != "":
		UiKit.add(self, UiKit.label(self, sub, 14, UiKit.MUTED), Vector2(mg, bottom + (bh - UiKit.line_h(self, 14)) / 2.0))
	var row_h := UiKit.line_h(self, 15) + (14.0 if ph else 16.0)
	var notes: Array = d.get("notes", [])
	var rows: Array = table.get("rows", [])
	var inner_h := (notes.size() + rows.size()) * row_h
	var head_h := 12.0 + maxf(UiKit.line_h(self, 18, true), UiKit.line_h(self, 12, true) + 10.0) + 10.0 + UiKit.line_h(self, 12, true) * 2.0 + 12.0
	var box := Rect2(mg, y, v.x - 2.0 * mg, minf(bottom - 12.0 - y, head_h + inner_h + 10.0))   # no taller than its rows
	shell(box.position, box.size)
	var pad := 18.0
	var x0 := box.position.x + pad
	var x1 := box.end.x - pad
	var ty := box.position.y + (20.0 if painted() else 12.0)
	UiKit.add(self, UiKit.label(self, str(d.get("name", "")).to_upper(), 18, ink(), true), Vector2(x0, ty))
	var outcome := str(d.get("outcome", ""))
	if outcome != "":                                  # the result chip, top right
		var ow := UiKit.text_w(self, outcome, 12, true) + outcome.length() + 24.0   # (+1 px a glyph: its spacing)
		var oh := UiKit.line_h(self, 12, true) + 10.0
		content.add_child(UiKit.rect(Vector2(x1 - ow, ty), Vector2(ow, oh), Color(UiKit.FRAME, 0.7)))
		UiKit.add(self, UiKit.label(self, outcome, 12, UiKit.INK, true, 1), Vector2(x1 - ow + 11.0, ty + 5.0))
	ty += maxf(UiKit.line_h(self, 18, true), UiKit.line_h(self, 12, true) + 10.0) + 10.0
	# the header row
	var cols: Array = table.get("cols", [])
	var label_w := (x1 - x0) * (0.4 if cols.size() <= 2 else 0.3)
	var col_w := (x1 - x0 - label_w) / maxf(1.0, float(cols.size()))
	var lh := UiKit.line_h(self, 12, true)
	var two := false                                   # "YOU / SOLAR" on one line, or over two where it doesn't fit
	for c in cols:
		two = two or UiKit.text_w(self, "%s / %s" % [c["head"], c["faction"]], 12, true) + 16.0 > col_w - 12.0
	var hh := lh * (2.0 if two else 1.0)
	UiKit.add(self, UiKit.label(self, "MATCH STAT", 12, acc, true, 2), Vector2(x0 + 12.0, ty + hh - lh))
	for i in range(cols.size()):
		var c: Dictionary = cols[i]
		# (an escaped newline: the literal one this had became "\r\n" in a CRLF checkout, and the second line of a
		# two-line head fell onto the first row - HUD pass: the names made two-line heads common)
		var hl := UiKit.label(self, ("%s\n%s" if two else "%s / %s") % [c["head"], c["faction"]], 12, acc, true, 1)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hl.clip_text = true
		hl.size = Vector2(col_w - 12.0, hh)
		UiKit.add(self, hl, Vector2(x0 + label_w + i * col_w, ty))
		var cw := minf(46.0, col_w - 12.0)             # the seat's own colour: which side of the board it was
		var bx := x0 + label_w + (i + 1) * col_w - 12.0 - cw
		content.add_child(UiKit.rect(Vector2(bx, ty + hh + 9.0), Vector2(cw, 3.0), Rules.seat_color(str(c["seat"]))))
		if c.has("f"):                                 # its race emblem beside the colour
			UiKit.emblem_rect(self, str(c["f"]), Vector2(bx - 24.0, ty + hh + 1.0), 19.0)
	ty += hh + 26.0
	content.add_child(UiKit.rect(Vector2(x0, ty - 1.0), Vector2(x1 - x0, 1.0), Color(UiKit.FRAME, 0.9)))
	# the rows (a mission's notes first), scrolling when they don't fit
	var avail := box.end.y - 8.0 - ty
	var scroll := TouchScroll.new()
	scroll.position = Vector2(x0, ty)
	scroll.size = Vector2(x1 - x0, avail)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if inner_h > avail else ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.custom_minimum_size = Vector2(x1 - x0 - (14.0 if inner_h > avail else 0.0), inner_h)
	scroll.add_child(inner)
	var keep := content
	content = inner
	var ry := 0.0
	for n in notes:                                    # [kind, text, ok]
		var mk := Mark.new()
		mk.kind = str(n[0])
		var ok := bool(n[2])
		mk.color = (Color("d99a1c") if ok else Color("9fb3b3")) if mk.kind == "star" else (Color("2f9a52") if ok else Color("c4383f"))
		var ms := UiKit.line_h(self, 15) * 0.8
		mk.size = Vector2(ms, ms)
		UiKit.add(self, mk, Vector2(12.0, ry + (row_h - ms) / 2.0))
		var nl := UiKit.label(self, str(n[1]), 15, ink() if ok else muted())
		nl.clip_text = true
		nl.size = Vector2(inner.custom_minimum_size.x - ms - 30.0, UiKit.line_h(self, 15))
		UiKit.add(self, nl, Vector2(ms + 24.0, ry + (row_h - UiKit.line_h(self, 15)) / 2.0))
		inner.add_child(UiKit.rect(Vector2(0, ry + row_h - 1.0), Vector2(inner.custom_minimum_size.x, 1.0), Color(UiKit.FRAME, 0.6)))
		ry += row_h
	for r in rows:                                     # [label, [value per column]]
		var ll := UiKit.label(self, str(r[0]), 15, ink())
		UiKit.add(self, ll, Vector2(12.0, ry + (row_h - UiKit.line_h(self, 15)) / 2.0))
		var vals: Array = r[1]
		for i in range(vals.size()):
			var vl := UiKit.label(self, str(vals[i]), 15, ink() if i == 0 else muted())
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			vl.size = Vector2(col_w - 12.0, UiKit.line_h(self, 15))
			UiKit.add(self, vl, Vector2(label_w + i * col_w, ry + (row_h - UiKit.line_h(self, 15)) / 2.0))
		inner.add_child(UiKit.rect(Vector2(0, ry + row_h - 1.0), Vector2(inner.custom_minimum_size.x, 1.0), Color(UiKit.FRAME, 0.6)))
		ry += row_h
	content = keep


# ------------------------------------------------------------------ 17: PAUSE, and YOU'RE OUT
func card(d: Dictionary) -> Dictionary:
	## d: kicker, headline, body, actions [[text, Callable, kind]...] (the first is the primary), pairs [[text, Callable]]
	## (two side by side: the pause's toggles; placed after the first action), pairs2 (a second row of them under the
	## first: the pause's MUSIC toggles), glow (the hero's accent glow), dim.
	## No actions: a message card (the mission's closing line) - no hero either. Returns {"buttons": [Button...]} in
	## the order given (pairs after the actions).
	clear()
	backdrop(float(d.get("dim", 0.62)))
	var v := vp()
	var ph := phone()
	var mg := margin()
	var pad := float(d.get("pad", 28.0))
	var actions: Array = d.get("actions", [])
	var pairs: Array = d.get("pairs", [])
	var pairs2: Array = d.get("pairs2", []) if not pairs.is_empty() else []
	var bw := 520.0 if ph else 300.0
	for row in [pairs, pairs2]:
		for p in row:                                  # wide enough that the toggles' text never clips
			bw = maxf(bw, (UiKit.text_w(self, str(p[0]), 14, true) + 34.0) * (row as Array).size() + 10.0)
	var cw := minf(v.x - 2.0 * mg, (1080.0 if ph else 700.0) + bw - (520.0 if ph else 300.0))
	var row_h := float(d.get("row_h", 48.0))          # 0.22.4: PAUSE > SETTINGS (6 rows) overflowed a 585 px phone
	var row_gap := float(d.get("row_gap", 10.0))      # by ~8 px; that card alone asks for a tighter row_h/row_gap
	var bh := UiKit.tap_h(self, row_h)                # (never below the 44 pt tap minimum) - every other card()
	var rows := actions.size() + (1 if not pairs.is_empty() else 0) + (1 if not pairs2.is_empty() else 0)
	var col_h := maxf(0.0, rows * (bh + row_gap) - row_gap)   # caller keeps the defaults above and is unaffected
	if rows == 0:
		cw = minf(v.x - 2.0 * mg, 980.0 if ph else 620.0)
	var body := str(d.get("body", ""))
	var body_h := UiKit.text_h(self, body, 14, cw - 2.0 * pad) + 6.0 if body != "" else 0.0
	var head_h := UiKit.line_h(self, 12, true) + 2.0 + UiKit.line_h(self, 34, true) + 8.0
	var hero_h := minf(maxf(col_h, 230.0 if ph else 170.0), cw - bw - 3.0 * pad)   # a short column still shows the character
	var ch := pad + head_h + body_h + (10.0 + maxf(col_h, hero_h) if rows > 0 else 0.0) + pad
	# iOS (Safari's 320-340 pt: PAUSE > SETTINGS ran off the screen): the actions after the first go two to a row, then
	# the body line goes
	var act_pairs := false
	if ch > v.y - 12.0 and actions.size() > 2:
		act_pairs = true
		for k in range(1, actions.size()):             # wide enough that the halves' text never clips
			bw = maxf(bw, (UiKit.text_w(self, str(actions[k][0]), 14, true) + 30.0) * 2.0 + 10.0)
		bw = minf(bw, cw - 3.0 * pad - 120.0)
		rows = 1 + ceili((actions.size() - 1) / 2.0) + (1 if not pairs.is_empty() else 0) + (1 if not pairs2.is_empty() else 0)
		col_h = maxf(0.0, rows * (bh + row_gap) - row_gap)
		hero_h = minf(maxf(col_h, 230.0 if ph else 170.0), cw - bw - 3.0 * pad)
		ch = pad + head_h + body_h + 10.0 + maxf(col_h, hero_h) + pad
	if ch > v.y - 12.0 and body != "":
		ch -= body_h
		body = ""
		body_h = 0.0
	var pos := ((v - Vector2(cw, ch)) / 2.0).floor()
	pos.y = maxf(pos.y, 6.0)
	shell(pos, Vector2(cw, ch))
	var y := _title(pos.x + pad, pos.y + pad, str(d.get("kicker", "")), str(d.get("headline", ""))) + 6.0
	if body != "":
		y += _wrapped(body, 14, muted(), Vector2(pos.x + pad, y), cw - 2.0 * pad)
	y += 10.0
	var block_h := maxf(col_h, hero_h)
	var hs := minf(hero_h, block_h)
	if rows == 0:
		return {"buttons": []}
	var sd := minf(hs, 150.0 if not ph else hs)
	socket(Vector2(pos.x + pad + (cw - bw - 3.0 * pad) / 2.0, y + block_h / 2.0), sd, 120)
	var bx := pos.x + cw - pad - bw
	var by := y + (block_h - col_h) / 2.0
	var out := {"buttons": []}
	for i in range(actions.size()):
		var a: Array = actions[i]
		var kind := str(a[2]) if a.size() > 2 else ("primary" if i == 0 else "secondary")
		var half := act_pairs and i > 0
		var aw := (bw - 10.0) / 2.0 if half else bw
		var ax := bx + (aw + 10.0 if half and (i - 1) % 2 == 1 else 0.0)
		if half and (i - 1) % 2 == 0 and i == actions.size() - 1:
			aw = bw                                    # an odd one out keeps the full width
		var b := pbtn(str(a[0]), Vector2(ax, by), Vector2(aw, bh), a[1], kind, 16 if not half else 14)
		(out["buttons"] as Array).append(b)
		if not half or (i - 1) % 2 == 1 or i == actions.size() - 1:
			by += bh + row_gap
		if i == 0 and not pairs.is_empty():            # the toggles, side by side under the primary (one or two rows)
			for row in [pairs, pairs2]:
				if (row as Array).is_empty():
					continue
				var pw := (bw - 10.0 * float((row as Array).size() - 1)) / float((row as Array).size())   # n toggles, 10 px gaps
				for j in range((row as Array).size()):
					var p: Array = row[j]
					(out["buttons"] as Array).append(pbtn(str(p[0]), Vector2(bx + j * (pw + 10.0), by), Vector2(pw, bh),
							p[1], "secondary", 14))
				by += bh + row_gap
	return out


# ------------------------------------------------------------------ the verdict (Daniele 2026-09-28: "something more
# thematic for win/loss on the syndicate theme, kinda a joke in game lore") - [kicker, headline], one per match (the seed,
# so everyone in a room reads the same line); the outcome still reads first, and MATCH DETAILS keeps VICTORY / DEFEAT.
const WIN_LINES := [["QUARTERLY TARGETS: EXCEEDED", "HOSTILE TAKEOVER."], ["THE BOARD IS DELIGHTED", "MARKET CORNERED."],
		["SHAREHOLDERS: THRILLED", "ACQUISITION COMPLETE."], ["BONUSES ALL ROUND", "MONOPOLY ACHIEVED."]]
const LOSS_LINES := [["THE BOARD WOULD LIKE A WORD", "LIQUIDATED."], ["PLEASE CLEAR YOUR DESK", "BOUGHT OUT."],
		["SHAREHOLDERS: FURIOUS", "RESTRUCTURED."], ["YOUR ASSETS ARE THEIR ASSETS NOW", "ASSETS SEIZED."]]
const DRAW_LINES := [["NOBODY GETS A BONUS", "HUNG BOARD."], ["THE AUDITORS ARE CONFUSED", "MERGER PENDING."]]


static func verdict(won: bool, draw: bool, seed: int) -> Array:
	var pool: Array = DRAW_LINES if draw else (WIN_LINES if won else LOSS_LINES)
	return pool[absi(seed) % pool.size()]


# ------------------------------------------------------------------ the numbers
static func clock(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]


static func ordinal(n: int) -> String:
	return "%d%s" % [n, {1: "st", 2: "nd", 3: "rd"}.get(n if n < 20 else n % 10, "th")]


static func nodes_held(sim: Sim, seat: String) -> int:
	var held := 0
	for n in sim.nodes:
		if n["owner"] == seat and not sim.collapsed.get(n["id"], false):
			held += 1
	return held


static func seat_table(sim: Sim, human: String, heads := {}) -> Dictionary:
	## Every per-seat number this device can show (the Sim's events through Progression.seat_stats - the same counting
	## as the rewards and the server's report - plus the board at the end). {cols: [{seat, head, faction}], rows:
	## [[label, [value per column]]]}: you first, then your team-mates, then every rival. Rows a match can't have
	## (relays on a map without them, skills with ABILITIES off, monsters nobody launched) are left out. heads (HUD
	## pass: seat -> [head, second line], Hud._seat_heads): a human column by the player's name over the faction, an AI
	## column by faction over its level; without it, YOU / ALLY / RIVAL over the faction.
	var seats: Array = sim.factions.keys()
	seats.sort()
	var order := [human]
	for s in seats:
		if s != human and sim.allied(s, human):
			order.append(s)
	for s in seats:
		if not s in order:
			order.append(s)
	var rivals := order.filter(func(s): return not sim.allied(s, human)).size()
	var cols := []
	var st := {}
	var rn := 0
	for s in order:
		var head := "YOU"
		if s != human:
			if sim.allied(s, human):
				head = "ALLY"
			else:
				rn += 1
				head = "RIVAL" if rivals == 1 else "RIVAL %d" % rn
		var fname := str(UiKit.NAMES.get(str(sim.factions[s]), str(sim.factions[s]).to_upper()))
		if heads.has(s):
			head = str(heads[s][0])
			fname = str(heads[s][1])
		cols.append({"seat": s, "head": head, "faction": fname, "f": str(sim.factions[s])})   # "f": its race emblem
		st[s] = Progression.seat_stats(sim, s)
	var rows := []
	var col := func(fn: Callable) -> Array:
		return order.map(func(s): return fn.call(s))
	rows.append(["Nodes held", col.call(func(s): return "%d / %d" % [nodes_held(sim, s), sim.nodes.size()])])
	rows.append(["Captures", col.call(func(s): return st[s]["captures"])])
	rows.append(["Nodes lost", col.call(func(s): return st[s]["nodes_lost"])])
	rows.append(["Sends", col.call(func(s): return st[s]["sends"])])
	rows.append(["Units lost in combat", col.call(func(s): return st[s]["units_lost_combat"])])
	rows.append(["Units lost to falls", col.call(func(s): return st[s]["units_lost_falls"])])
	if sim.has_relays:
		rows.append(["Relays fired", col.call(func(s): return st[s]["relay_fires"])])
		rows.append(["Rivals dropped by relays", col.call(func(s): return st[s]["void_drops"])])
	if sim.abilities_on:
		rows.append(["Skills used", col.call(func(s): return st[s]["skills"])])
	if order.any(func(s): return int(st[s]["monster_launches"]) > 0):
		rows.append(["Monsters launched", col.call(func(s): return st[s]["monster_launches"])])
		rows.append(["Units kicked off by monsters", col.call(func(s): return st[s]["monster_kicked"])])
	rows.append(["Final strength", col.call(func(s): return Rules.shown(sim.seat_strength(s)))])
	if sim.teams.is_empty() and order.size() > 2:     # free-for-all: where everyone finished
		var placed := Progression.placements(sim)
		rows.append(["Placement", col.call(func(s): return ordinal(int(placed.get(s, order.size()))))])
	if order.any(func(s): return float(st[s]["out_at_s"]) >= 0.0):
		rows.append(["Out at", col.call(func(s): return clock(float(st[s]["out_at_s"])) if float(st[s]["out_at_s"]) >= 0.0 else "-")])
	return {"cols": cols, "rows": rows}


# ------------------------------------------------------------------ drawn marks
class Mark extends Control:
	## A star, a tick or a cross, drawn (the web build has no symbol-font fallback for them).
	var kind := "star"
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		match kind:
			"star":
				var pts := PackedVector2Array()
				for i in range(10):
					var a := -PI / 2.0 + i * PI / 5.0
					pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
				draw_colored_polygon(pts, color)
			"check":
				draw_polyline(PackedVector2Array([c + Vector2(-0.8, 0.0) * r, c + Vector2(-0.25, 0.6) * r,
						c + Vector2(0.85, -0.65) * r]), color, maxf(2.0, r * 0.32), true)
			_:
				var w := maxf(2.0, r * 0.3)
				draw_line(c + Vector2(-0.7, -0.7) * r, c + Vector2(0.7, 0.7) * r, color, w, true)
				draw_line(c + Vector2(-0.7, 0.7) * r, c + Vector2(0.7, -0.7) * r, color, w, true)
