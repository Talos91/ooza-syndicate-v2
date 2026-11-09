class_name R18Geo
extends Control
## THROWAWAY (branch ui-r18-geometry-check, never released): the round-18 flat HUD geometry (Codex, deliveries/18-hud-geometry)
## drawn in game at the wireframe v3 positions (make_wireframes.py), behind the user arg `--r18-geo`. Flat pieces only, each scaled
## EVENLY (no 9-slice), real text in the geometry.json text-safe rects. Replaces: top bar, pause / music, banner, skill dock,
## and (as a mock at the wireframe position) the node radial. The SEND tank stays as demo12.

const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const SYMBOL_FONT := preload("res://assets/fonts/DejaVuSansMono.woff2")
const DIR := "res://assets/r18_geo/"
const PX := 6.0                                    # source px per pt
const TXT := Color("e8f6fb")

var hud                                           # Hud
var tex := {}
var report := {}                                  # measured, printed + saved for the sheet
var rects := {}                                   # name -> Rect2 in layout pt
var texts := []                                   # {name, w_pt, room_pt, size_pt}
var banner_text := "NO RELAYS ON THIS MAP"
var _n := 0
var u := 1.0                                      # screen px per layout pt


static func wanted() -> bool:
	return "--r18-geo" in OS.get_cmdline_user_args()


func setup(h) -> void:
	hud = h
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 40
	for n in ["skill_plate_active", "skill_plate_map", "skill_plate_ultimate", "top_capsule", "score_pill", "score_pill_mine",
			"square_button", "banner", "slice_40", "radial_hub"]:
		var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + n + ".png"))
		img.generate_mipmaps()
		tex[n] = ImageTexture.create_from_image(img)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _process(_dt: float) -> void:
	for c in [hud.top_panel, hud.status_label, hud.pause_button, hud.music_button, hud.banner, hud.catchup_tag, hud.debug_button, hud.chat_button]:
		if c:
			c.modulate.a = 0.0
	if hud.dock:
		hud.dock.modulate.a = 0.0
	queue_redraw()
	_n += 1
	if _n % 30 == 0 and not report.is_empty():
		print("R18REPORT ", JSON.stringify(report))


func _fit(t: String, room_px: float, size_px: float, min_px: float) -> float:
	var s := size_px
	while s > min_px and UI_FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(ceil(s))).x > room_px:
		s -= 0.5
	return s


func _text(t: String, centre: Vector2, room_px: float, size_pt: float, col := TXT, min_pt := 9.0, label := "") -> void:
	var s := _fit(t, room_px, size_pt * u, min_pt * u)
	var si := int(ceil(s))
	var w := UI_FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, si).x
	var asc := UI_FONT.get_ascent(si)
	var dsc := UI_FONT.get_descent(si)
	var p := Vector2(centre.x - w / 2.0, centre.y + (asc - dsc) / 2.0)
	draw_string(UI_FONT, p + Vector2(0, 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, si, Color(0, 0, 0, 0.7))
	draw_string(UI_FONT, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, si, col)
	texts.append({"name": label if label != "" else t, "text": t, "w_pt": snappedf(w / u, 0.1), "room_pt": snappedf(room_px / u, 0.1),
		"size_pt": snappedf(si / u, 0.1), "fits": w <= room_px + 0.5, "shrunk": s < size_pt * u - 0.01})


func _body(name: String, body_tl_pt: Vector2) -> void:
	## the piece's canvas (body + 48 px margin) placed so its BODY's top-left lands on body_tl_pt
	var s := u / PX
	draw_set_transform(body_tl_pt * u - Vector2(48, 48) * s, 0.0, Vector2(s, s))
	draw_texture(tex[name], Vector2.ZERO)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	texts.clear()
	var vp := get_viewport_rect().size
	u = hud.pt(1.0) * (1.0 if hud.mobile else 1.2)
	var ins := UiKit.safe_insets(vp) / u
	var W := vp.x / u
	var H := vp.y / u
	var R := W - ins.z - 4.0
	var by := (H - ins.w - 54.0 - 4.0) if ins.w > 0.0 else (H - 54.0 - 12.0)
	var py0 := maxf(48.0, (46.0 + by - 6.0 - (3.0 * 80.0 + 2.0 * 6.0)) / 2.0)
	rects.clear()
	rects["screen"] = Rect2(0, 0, W, H)
	rects["safe"] = Rect2(ins.x, ins.y, W - ins.x - ins.z, H - ins.y - ins.w)
	# ---- top capsule: body 320 x 36 at y4, centred; slots from geometry.json (capsule canvas px, body offset 48)
	var bx := W / 2.0 - 160.0
	var cap := Vector2(bx, 4.0)
	_body("top_capsule", cap)
	rects["capsule"] = Rect2(cap, Vector2(320, 36))
	var slot_l := Vector2(84 - 48, 72 - 48) / PX
	var slot_t := Vector2(792 - 48, 72 - 48) / PX
	var slot_r := Vector2(1260 - 48, 72 - 48) / PX
	_body("score_pill_mine", cap + slot_l)
	_body("score_pill", cap + slot_r)
	for spec in [[slot_l, "SLIME-C7 011", Color("5cf0a8"), "pill_you"], [slot_r, "RIVAL-K2 009", Color("ff6b6b"), "pill_rival"]]:
		var o: Vector2 = cap + (spec[0] as Vector2)
		# icon reserve [66,72,120,120] / text reserve [204,72,492,120] in the pill canvas (body offset 48)
		draw_circle((o + Vector2(66 - 48 + 60, 72 - 48 + 60) / PX) * u, 8.0 * u, spec[2])
		_text(spec[1], (o + Vector2(204 - 48 + 246, 72 - 48 + 60) / PX) * u, 492.0 / PX * u, 12.5, TXT, 9.0, spec[3])
	_text("00:15", (cap + slot_t + Vector2(216, 84) / PX) * u, 400.0 / PX * u, 14.0, TXT, 9.0, "timer")
	rects["pill_you"] = Rect2(cap + slot_l, Vector2(672, 168) / PX)
	rects["timer"] = Rect2(cap + slot_t, Vector2(432, 168) / PX)
	rects["pill_rival"] = Rect2(cap + slot_r, Vector2(672, 168) / PX)
	# ---- utilities: pause, music (right edge, y4, 40 pt, gap 4)
	for i in range(2):
		var x := R - 40.0 - i * 44.0
		_body("square_button", Vector2(x, 4.0))
		rects["util_%d" % i] = Rect2(x, 4, 40, 40)
		var c := Vector2(x + 20.0, 24.0) * u
		if i == 0:
			draw_rect(Rect2(c + Vector2(-7, -9) * u, Vector2(5, 18) * u), TXT)
			draw_rect(Rect2(c + Vector2(2, -9) * u, Vector2(5, 18) * u), TXT)
		else:
			var si := int(ceil(22.0 * u))
			draw_string(SYMBOL_FONT, c + Vector2(-si * 0.3, si * 0.33), "♪", HORIZONTAL_ALIGNMENT_LEFT, -1, si, TXT)
	# ---- banner slot under the bar: 320 x 36 at y50 (wireframe BANNER y46 + 4)
	var bb := Vector2(W / 2.0 - 160.0, 50.0)
	_body("banner", bb)
	rects["banner"] = Rect2(bb, Vector2(320, 36))
	_text(banner_text, (bb + Vector2(160, 18)) * u, (1920.0 - 2 * 130.0) / PX * u, 12.5, Color("ffc24a"), 9.0, "banner")
	# ---- skill plates, right column, 96 x 80 gap 6
	var px := R - 96.0
	var names := ["SINKHOLE", "DEMOLISH", "MELTDOWN"]
	var pl := ["skill_plate_active", "skill_plate_map", "skill_plate_ultimate"]
	var cols := [Color("36e3ff"), Color("3ee8b0"), Color("ffb238")]
	for i in range(3):
		var yy := py0 + i * 86.0
		_body(pl[i], Vector2(px, yy))
		rects["plate_%d" % i] = Rect2(px, yy, 96, 80)
		var wc := Vector2(px, yy) + Vector2(336 - 48, 234 - 48) / PX
		draw_circle(wc * u, 16.0 * u, Color(cols[i].r, cols[i].g, cols[i].b, 0.30))
		_text(str(i + 1), wc * u, 30.0 * u, 18.0, TXT, 12.0, "key_%d" % i)
		var nc := Vector2(px, yy) + Vector2(124 - 48 + 212, 408 - 48 + 48) / PX
		_text(names[i], nc * u, 424.0 / PX * u, 12.5, TXT, 9.0, "plate_%d_%s" % [i, names[i]])
	# ---- node radial, mock at the wireframe's example position: 3 slices (40 deg) + hub
	var cx := W / 2.0 + 10.0
	var cy := (46.0 + 40.0 + by) / 2.0 + 6.0
	var o2 := Vector2(cx, cy) * u
	var s := u / PX
	var words := ["UPGRADE", "GOOGAT", "SWITCH"]
	for i in range(3):
		var a := deg_to_rad(-150.0 + (i + 0.5) * 40.0)
		draw_set_transform(o2, a, Vector2(s, s))
		draw_texture(tex["slice_40"], Vector2(168, -245))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var pm := Vector2(cx, cy) + Vector2.from_angle(a) * 71.0
		_text(words[i], pm * u, 46.0 * u, 12.5, TXT, 9.0, "radial_%d" % i)
	draw_set_transform(o2 - Vector2(180, 180) * s, 0.0, Vector2(s, s))
	draw_texture(tex["radial_hub"], Vector2.ZERO)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_text("X", o2, 40.0 * u, 16.0, TXT, 12.0, "hub_close")
	rects["radial"] = Rect2(cx - 104.0, cy - 104.0, 208.0, 104.0 + 22.0)
	if hud.send_tank:
		var tg: Rect2 = hud.side_panel.get_global_rect()
		rects["tank_panel"] = Rect2(tg.position / u, tg.size / u)
	report = {"W_pt": snappedf(W, 0.1), "H_pt": snappedf(H, 0.1), "u": snappedf(u, 0.001), "texts": texts.duplicate(), "rects": {}}
	for k in rects:
		var r: Rect2 = rects[k]
		report["rects"][k] = [snappedf(r.position.x, 0.1), snappedf(r.position.y, 0.1), snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)]
	report["overlaps"] = overlaps()


func overlaps() -> Array:
	var out := []
	var keys := rects.keys().filter(func(k): return k != "screen" and k != "safe")
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			if str(keys[i]) == "capsule" and (str(keys[j]).begins_with("pill") or str(keys[j]) == "timer"):
				continue
			if (rects[keys[i]] as Rect2).intersects(rects[keys[j]]):
				out.append("%s x %s" % [keys[i], keys[j]])
	for k in keys:
		if not (rects["safe"] as Rect2).encloses(rects[k]):
			out.append("%s outside safe/screen" % k)
	return out
