class_name R20Geo
extends Control
## THROWAWAY (branch ui-r20-geo, never released): the round-20 flat HUD pieces (Codex, deliveries/20-hud-missing-A) drawn in game at the
## wireframe v3 places behind the user arg `--r20-geo`: two toasts, the phone node card, and ONE of coach card (tutorial) / hint strip
## (match, `--r20-state=coach|hint`, default hint). Resize = 3 parts (left cap / stretched blank centre / right cap), never squashed.
## Real text at 12.5 pt. The rest of the HUD stays as demo13; its rects are measured for the overlap table.

const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const DIR := "res://assets/r20_geo/"
const PX := 6.0
const TXT := Color("e8f6fb")
const GLASS := Color("101418")

var hud
var tex := {}
var report := {}
var rects := {}
var texts := []
var u := 1.0
var state := "hint"
var toast_mode := "spec"
var _n := 0
var _sz := {}                                      # name -> canvas size px
var toast_a := "SLIME-C7 TOOK NODE 14"
var toast_b := "RIVAL-K2 SENDS 6 UNITS"
var coach_txt := "Tap a node you own to open its card, then pick UPGRADE or SWITCH. Send units along a lane to take a rival node."
var hint_txt := "SINKHOLE armed: tap a target in range to fire"
var node_line := "EMBER · VAT · T2"
var node_status := "SENDING 4 UNITS TO NODE 7"

# canvas px geometry (geometry.json), body offset 48
const PIECES := {
	"toast": {"canvas": Vector2(1236, 216), "capL": 120.0, "capR": 84.0, "zone": 618.0},
	"coach_card": {"canvas": Vector2(1794, 420), "capL": 384.0, "capR": 156.0, "zone": 1056.0},
	"node_card": {"canvas": Vector2(1476, 420), "capL": 0.0, "capR": 0.0, "zone": 0.0},
	"hint_strip": {"canvas": Vector2(1794, 264), "capL": 180.0, "capR": 48.0, "zone": 897.0},
}


static func wanted() -> bool:
	return "--r20-geo" in OS.get_cmdline_user_args()


func setup(h) -> void:
	hud = h
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--r20-toast="):
			toast_mode = a.substr(12)
		if a.begins_with("--r20-state="):
			state = a.substr(12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 40
	for n in PIECES:
		var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + n + ".png"))
		img.generate_mipmaps()
		tex[n] = ImageTexture.create_from_image(img)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _process(_dt: float) -> void:
	if hud.hint:
		hud.hint.modulate.a = 0.0
	queue_redraw()
	_n += 1
	if _n % 30 == 0 and not report.is_empty():
		print("R20REPORT ", JSON.stringify(report))


func _w(t: String, px: float) -> float:
	return UI_FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(ceil(px))).x


func _fit(t: String, room_px: float, size_px: float, min_px: float) -> float:
	var s := size_px
	while s > min_px and _w(t, s) > room_px:
		s -= 0.5
	return s


func _text(t: String, left_px: float, room_px: float, cy_px: float, size_pt: float, label: String, min_pt := 9.0, col := TXT) -> void:
	## one line, left aligned from left_px, vertically centred on cy_px, shrunk to fit room_px (down to min_pt)
	var s := _fit(t, room_px, size_pt * u, min_pt * u)
	var si := int(ceil(s))
	var w := _w(t, si)
	var p := Vector2(left_px, cy_px + (UI_FONT.get_ascent(si) - UI_FONT.get_descent(si)) / 2.0)
	draw_string(UI_FONT, p + Vector2(0, 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, si, Color(0, 0, 0, 0.7))
	draw_string(UI_FONT, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, si, col)
	texts.append({"name": label, "w_pt": snappedf(w / u, 0.1), "room_pt": snappedf(room_px / u, 0.1), "size_pt": snappedf(si / u, 0.1),
		"fits": w <= room_px + 0.5, "shrunk": s < size_pt * u - 0.01})


func _wrap(t: String, room_px: float, last_room_px: float, size_px: float) -> Array:
	var lines := []
	var cur := ""
	for word in t.split(" "):
		var trial := word if cur == "" else cur + " " + word
		if _w(trial, size_px) <= room_px or cur == "":
			cur = trial
		else:
			lines.append(cur)
			cur = word
	lines.append(cur)
	# the last line must stay clear of the chevron: if it is wider than last_room, push its last word down
	if _w(lines[-1], size_px) > last_room_px and lines.size() > 0:
		var parts: PackedStringArray = (lines[-1] as String).split(" ")
		if parts.size() > 1:
			lines[-1] = " ".join(parts.slice(0, parts.size() - 1))
			lines.append(parts[parts.size() - 1])
	return lines


class Map:
	var bx := 0.0          # body left, screen px
	var by := 0.0          # body top
	var tw := 0.0          # body width, screen px
	var s := 1.0           # screen px per source px
	var cw := 0.0          # canvas width, source px
	var capR := 0.0

	func x(cx: float) -> float:
		## canvas x of a feature inside the RIGHT cap follows the right edge, everything else the left edge
		if cx >= cw - 48.0 - capR:
			return bx + tw - (cw - 48.0 - cx) * s
		return bx + (cx - 48.0) * s

	func y(cy: float) -> float:
		return by + (cy - 48.0) * s


func _piece(name: String, body_tl_pt: Vector2, w_pt: float) -> Map:
	var P: Dictionary = PIECES[name]
	var cv: Vector2 = P["canvas"]
	var m := Map.new()
	m.s = u / PX
	m.bx = body_tl_pt.x * u
	m.by = body_tl_pt.y * u
	m.tw = w_pt * u
	m.cw = cv.x
	m.capR = P["capR"]
	var t: Texture2D = tex[name]
	var s := m.s
	if P["zone"] == 0.0:
		draw_texture_rect(t, Rect2(m.bx - 48.0 * s, m.by - 48.0 * s, cv.x * s, cv.y * s), false)
		return m
	var lw: float = 48.0 + P["capL"]
	var rw: float = 48.0 + P["capR"]
	draw_texture_rect_region(t, Rect2(m.bx - 48.0 * s, m.by - 48.0 * s, lw * s, cv.y * s), Rect2(0, 0, lw, cv.y))
	var cx0: float = m.bx + P["capL"] * s
	var cx1: float = m.bx + m.tw - P["capR"] * s
	draw_texture_rect_region(t, Rect2(cx0, m.by - 48.0 * s, cx1 - cx0, cv.y * s), Rect2(P["zone"], 0, 12, cv.y))
	draw_texture_rect_region(t, Rect2(cx1, m.by - 48.0 * s, rw * s, cv.y * s), Rect2(cv.x - rw, 0, rw, cv.y))
	return m


func _bar(m: Map, col: Color) -> void:
	# kind bar [108,78,18,60] r9
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(9.0 * m.s))
	draw_style_box(sb, Rect2(m.x(108), m.y(78), 18.0 * m.s, 60.0 * m.s))


func _window(m: Map, letter: String, col: Color) -> void:
	# skill-window circle: centre (222,210) d240 -> placeholder emblem disc + letter
	var c := Vector2(m.x(222), m.y(210))
	draw_circle(c, 112.0 * m.s, Color(col.r, col.g, col.b, 0.35))
	draw_circle(c, 56.0 * m.s, col)
	var si := int(ceil(22.0 * u))
	var w := _w(letter, si)
	draw_string(UI_FONT, c + Vector2(-w / 2.0, (UI_FONT.get_ascent(si) - UI_FONT.get_descent(si)) / 2.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, si, Color("101418"))


func _draw() -> void:
	texts.clear()
	var vp := get_viewport_rect().size
	u = hud.pt(1.0) * (1.0 if hud.mobile else 1.2)
	var ins := UiKit.safe_insets(vp) / u
	var W := vp.x / u
	var H := vp.y / u
	var R := W - ins.z - 4.0
	var L := ins.x + 4.0
	var by := (H - ins.w - 54.0 - 4.0) if ins.w > 0.0 else (H - 54.0 - 12.0)
	var px := R - 96.0
	rects.clear()
	rects["screen"] = Rect2(0, 0, W, H)
	rects["safe"] = Rect2(ins.x, ins.y, W - ins.x - ins.z, H - ins.y - ins.w)
	var tank := Rect2()
	if hud.send_tank and hud.send_tank.picture():
		# the tank's VISIBLE art (300 x 1080 source px, drip + dropped tip below it), not its transparent panel
		var st = hud.send_tank
		var o: Vector2 = st.get_global_rect().position
		var a: Vector2 = o + st.cv(Vector2(st.PIC_X, st.PIC_Y))
		var b: Vector2 = o + st.cv(Vector2(st.PIC_X + st.PIC_W, st.PIC_Y + 1080.0))
		tank = Rect2(a / u, (b - a) / u)
		rects["tank(art)"] = tank
	# real HUD parts the new pieces must clear
	for pair in [["top_panel(current)", hud.top_panel], ["dock(current)", hud.dock], ["version_tag", hud.version_label], ["map_title", hud.map_title]]:
		var c: Control = pair[1]
		if c and c.is_visible_in_tree() and c.size.x > 1.0:
			var g := c.get_global_rect()
			rects[pair[0]] = Rect2(g.position / u, g.size / u)
	# ---- toasts: body 190 x 20 at (L, 4) and (L, 27); text-safe left 144-48 = 96 px from the body, right 62 px
	var tw := 190.0
	var tdata := [[toast_a, Color("5cf0a8"), 4.0, "toast_1"], [toast_b, Color("ff6b6b"), 27.0, "toast_2"]]
	var tx := L
	if toast_mode == "right" and tank.size.x > 0.0:     # ALT (finding): start right of the tank art, end 5 pt before the capsule's locked left edge
		tx = tank.end.x + 6.0
		tw = clampf(W / 2.0 - 160.0 - 5.0 - tx, 96.0, 190.0)
	for d in tdata:
		var tl := Vector2(tx, d[2])
		var m := _piece("toast", tl, tw)
		_bar(m, d[1])
		var left := m.x(144)
		var right := m.bx + m.tw - 62.0 * m.s
		_text(d[0], left, right - left, m.y(108), 12.5, d[3] + "_text")
		rects[d[3]] = Rect2(tl, Vector2(tw, 20))
	# ---- bottom band: node card at (tank right + 10, by) 230 x 54; coach / hint from + 240 to the plate column - 10 (max 640)
	var mid := (tank.end.x if tank.size.x > 0.0 else L + 71.0) + 10.0
	var nc := Vector2(mid, by)
	var mn := _piece("node_card", nc, 230.0)
	rects["node_card"] = Rect2(nc, Vector2(230, 54))
	_window(mn, "E", Color("ff8a3d"))
	_text(node_line, mn.x(412), 940.0 * mn.s, mn.y(120), 12.5, "node_line")
	# units bar: tube [414,204,936,12] -> 5 of 8 filled, rest dimmed to glass
	var fill := 0.62
	var tube_x0 := mn.x(414)
	var tube_w := 936.0 * mn.s
	var dim := StyleBoxFlat.new()
	dim.bg_color = Color(0.18, 0.2, 0.23, 1.0)
	dim.set_corner_radius_all(int(6.0 * mn.s))
	draw_style_box(dim, Rect2(tube_x0 + tube_w * fill, mn.y(204), tube_w * (1.0 - fill), 12.0 * mn.s))
	var uw := _w("5 / 8", int(ceil(12.5 * u)))
	_text("5 / 8", mn.x(1352) - uw, uw + 2.0, mn.y(120), 12.5, "node_units", 9.0, Color("ffd9a8"))
	_text(node_status, mn.x(412), 940.0 * mn.s, mn.y(300), 12.5, "node_status")
	var cx := mid + 240.0
	var cw := minf(640.0, px - 10.0 - cx)
	var ct := Vector2(cx, by)
	if state == "coach":
		var m := _piece("coach_card", ct, cw)
		rects["coach_card"] = Rect2(ct, Vector2(cw, 54))
		_window(m, "V", Color("b48cff"))
		var left := m.x(412)
		var right := m.bx + m.tw - (1746.0 - 1654.0) * m.s
		var last_right := m.bx + m.tw - (1746.0 - 1602.0) * m.s
		var size_px: float = ceil(12.5 * u)
		var lines := _wrap(coach_txt, right - left, last_right - left, size_px)
		var lead := 14.5 * u
		var y0 := m.y(207.5) - lead * (lines.size() - 1) / 2.0
		for i in range(lines.size()):
			var room := (last_right if i == lines.size() - 1 else right) - left
			_text(lines[i], left, room, y0 + i * lead, 12.5, "coach_line_%d" % (i + 1))
		texts.append({"name": "coach_lines", "count": lines.size(), "fits": lines.size() <= 3})
	else:
		var hy := by + 26.0
		var m := _piece("hint_strip", Vector2(cx, hy), cw)
		rects["hint_strip"] = Rect2(Vector2(cx, hy), Vector2(cw, 28))
		# icon reserve [66,72,120,120]: placeholder skill dot
		draw_circle(Vector2(m.x(126), m.y(132)), 40.0 * m.s, Color("36e3ff"))
		var left := m.x(204)
		var right := m.bx + m.tw - (1746.0 - 1718.0) * m.s
		_text(hint_txt, left, right - left, m.y(132), 12.5, "hint_line")
	report = {"W_pt": snappedf(W, 0.1), "H_pt": snappedf(H, 0.1), "u": snappedf(u, 0.001), "state": state, "texts": texts.duplicate(), "rects": {}}
	for k in rects:
		var r: Rect2 = rects[k]
		report["rects"][k] = [snappedf(r.position.x, 0.1), snappedf(r.position.y, 0.1), snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)]
	report["overlaps"] = overlaps()


func overlaps() -> Array:
	var out := []
	var new_keys := ["toast_1", "toast_2", "node_card", "coach_card", "hint_strip"]
	for a in new_keys:
		if not rects.has(a):
			continue
		for b in rects:
			if b == a or b == "screen" or b == "safe":
				continue
			if (rects[a] as Rect2).intersects(rects[b]) and not (b in new_keys and str(a) >= str(b)):
				out.append("%s x %s" % [a, b])
		if not (rects["safe"] as Rect2).encloses(rects[a]):
			out.append("%s outside safe/screen" % a)
	return out
