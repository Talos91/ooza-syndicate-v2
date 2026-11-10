class_name HudR19
extends RefCounted
## ui-r19-import (2026-11-10): the round-19 HUD style (Codex, DIRECTOR-PACKAGE/deliveries/19-hud-style; designer check PASS) drawn
## inside the LOCKED round-18 shapes (deliveries/18-hud-geometry) at the round-18 positions (wireframe v3, the layout proven by the
## throwaway branch ui-r18-geometry-check r18_geo.gd). The real HUD path: the live controls (score pills, clock, PAUSE / MUSIC,
## the status / banner line, the skill plates, the node radial) are drawn with these pieces; the SEND tank stays (send_tank.gd).
## A piece is drawn whole and EVENLY scaled (6 source px per pt, x the HUD's px per pt; no 9-slice), its canvas's 48 px margin
## around the body. Compositing (DELIVERY.md): fill -> rim halo (multiply tint) -> W rim (white-core ramp shader, tint) ->
## skills: slot-colour window halo (multiply) -> coloured window tube (baked). Rim + halo tint = the player's goo colour
## (HudNoir.accent); banner = alert red / info cyan / win amber; pill tube brightness mine / plain / out is baked in the art.
## Top capsule + square buttons have no tube in the locked geometry: they get the designer's goo backlight halos
## (generated/r19-check-2026-11-10/W-backlight, Daniele 2026-11-09 "backlit in the goo colour").

const DIR := "res://assets/ui/r19/"
const PX := 6.0                                    # source px per pt
const MARGIN := 48.0                               # canvas margin round every body (source px)
const RAMP := preload("res://shaders/neon_ramp.gdshader")
const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const SYMBOL_FONT := preload("res://assets/fonts/DejaVuSansMono.woff2")
const TXT := Color("e8f6fb")
const ALERT := Color("ff3b4e")                     # banner tints (designer spec): alert red / info cyan / win amber
const INFO := Color("36e3ff")
const WIN := Color("ffc23d")
const HALO_A := 1.0                                # halos at their stored alpha (<= 94 / 255 delivered, <= 92 backlight)
# body sizes (pt) of the locked round-18 pieces (geometry.json body / 6)
const BODY := {"skill_plate": Vector2(96, 80), "top_capsule": Vector2(320, 36), "score_pill": Vector2(112, 28),
		"square_button": Vector2(40, 40), "banner": Vector2(320, 36), "slice_40": Vector2(68, 65.67), "radial_hub": Vector2(44, 44)}
# geometry.json features, in pt from the body's top-left
const CAP_SLOTS := [Vector2(6, 4), Vector2(124, 4), Vector2(202, 4)]   # capsule slots [84|792|1260, 72] - 48, / 6
const PILL_ICON := Vector2(11, 14)                 # icon_rect centre ((66 + 60 - 48) / 6, (72 + 60 - 48) / 6)
const PILL_TEXT := Vector2(67, 14)                 # text_rect centre ((204 + 246 - 48) / 6, 14)
const PILL_TEXT_W := 82.0                          # 492 / 6
const TIMER_C := Vector2(36, 14)                   # the capsule's middle slot (432 x 168 px) centre
const BANNER_TEXT_W := 264.0                       # text_rect 1584 / 6
const PLATE_WINDOW := Vector2(48, 31)              # window centre (336 - 48, 234 - 48) / 6; d 40 pt, ring d 46
const PLATE_WINDOW_D := 40.0
const PLATE_NAME := Vector2(48, 68)                # name strip centre; clear text rect 424 px = 70.7 pt
const PLATE_NAME_W := 70.7
const SLICE_R := [38.0, 104.0]                     # the radial ring, pt (r18 lock): labels at r 84, icons at r 58, hub r 22
const SLICE_LABEL_R := 84.0
const SLICE_ICON_R := 58.0
const SLICE_DEG := 40.0
const HUB_R := 22.0

static var _tex := {}
static var _ramp: ShaderMaterial


static func tex(n: String) -> Texture2D:
	if not _tex.has(n):
		var p := DIR + n + ".png"
		_tex[n] = load(p) if ResourceLoader.exists(p) else null
	return _tex[n]


static func ramp() -> ShaderMaterial:
	if _ramp == null:
		_ramp = ShaderMaterial.new()
		_ramp.shader = RAMP
	return _ramp


static func on() -> bool:
	## The round-19 HUD is THE HUD (no flag); off only where its art is missing (a stripped build).
	return tex("top_capsule_fill") != null


static func u_of(hud) -> float:
	## Screen px per layout pt: the HUD's pt (phones: real pt x hud_k; desktop: the 515 pt canvas) - desktop x 1.2, as the
	## tank and the wireframe v2 (763 x 429 pt) - the r18 check's numbers.
	return hud.pt(1.0) * (1.0 if hud.mobile else 1.2)


static func layers(base: String) -> Dictionary:
	## The layer textures of one piece state: fill / halo / rim / neon_glow / neon (null where the piece has none).
	var d := {"fill": tex(base + "_fill"), "halo": tex(base + "_rim_glow"), "rim": tex(base + "_rim"),
			"neon_glow": tex(base + "_neon_glow"), "neon": tex(base + "_neon")}
	if base == "slice_40":
		d = {"fill": tex("slice_40_off"), "halo": tex("slice_40_lit_glow"), "rim": tex("slice_40_lit"), "neon_glow": null, "neon": null}
	var back := tex(base + "_backlight_glow")       # top capsule, square buttons: the goo backlight (no tube in the lock)
	if back != null:
		d["halo"] = back
		d["rim"] = null
	return d


class Piece:
	## One round-19 piece: its BODY's top-left at `position`, `size` = the body (px). Draws fill + halo itself, the W rim on a child
	## with the ramp material, the window halo / tube on a second child; content (words, icons) goes on later children.
	extends Control
	var base := ""
	var k := 1.0                                   # screen px per source px (= u / 6)
	var tint := Color.WHITE                        # rim + halo (the goo colour / banner tint)
	var neon_tint := Color.WHITE                   # skills: the slot colour of the window halo
	var lit := true                                # radial: false = the fill alone (slice off)
	var dim := 1.0                                 # a disabled piece's alpha on its glow layers
	var flare := 0.0                               # skills: a cast flares the window tube
	var window := true                             # false: the window halo / tube are drawn by the owner (over its goo)
	var _l := {}
	var _tube: Control
	var _top: Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_tube = Control.new()
		_tube.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tube.material = HudR19.ramp()
		_tube.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_tube.draw.connect(_draw_tube)
		add_child(_tube)
		_top = Control.new()
		_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_top.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_top.draw.connect(_draw_top)
		add_child(_top)

	func set_base(b: String) -> void:
		if b == base:
			return
		base = b
		_l = HudR19.layers(b)
		redraw()

	func place(body_tl: Vector2, u: float, body_pt: Vector2) -> void:
		k = u / HudR19.PX
		position = body_tl
		size = body_pt * u
		redraw()

	func redraw() -> void:
		queue_redraw()
		_tube.queue_redraw()
		_top.queue_redraw()

	func _canvas(ci: CanvasItem, t: Texture2D, col: Color) -> void:
		if t == null:
			return
		ci.draw_set_transform(-Vector2.ONE * HudR19.MARGIN * k, 0.0, Vector2(k, k))
		ci.draw_texture(t, Vector2.ZERO, col)
		ci.draw_set_transform(Vector2.ZERO)

	func _draw() -> void:
		_canvas(self, _l.get("fill"), Color.WHITE)
		if lit:
			_canvas(self, _l.get("halo"), Color(tint, HudR19.HALO_A * dim))

	func _draw_tube() -> void:
		if lit:
			_canvas(_tube, _l.get("rim"), Color(tint, dim))

	func _draw_top() -> void:
		if window:
			draw_window(_top, flare)

	func draw_window(ci: CanvasItem, fl: float) -> void:
		## The skill window's slot-colour halo (multiply) and its coloured tube (baked white core); a flare brightens it.
		_canvas(ci, _l.get("neon_glow"), Color(neon_tint, HudR19.HALO_A * dim))
		_canvas(ci, _l.get("neon"), Color(1, 1, 1, maxf(0.3, dim)))
		if fl > 0.0:
			_canvas(ci, _l.get("neon"), Color(1.6, 1.6, 1.6, fl))


static func text(ci: CanvasItem, t: String, centre: Vector2, room_px: float, size_px: float, col: Color, min_px: float,
		font: Font = UI_FONT) -> void:
	## One line centred on `centre`, shrunk (to min_px) to fit room_px, with a soft shadow.
	var s := size_px
	while s > min_px and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(ceil(s))).x > room_px:
		s -= 0.5
	var si := int(ceil(s))
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, si).x
	var p := Vector2(centre.x - w / 2.0, centre.y + (font.get_ascent(si) - font.get_descent(si)) / 2.0)
	ci.draw_string(font, p + Vector2(0, maxf(1.0, si / 14.0)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, si, Color(0, 0, 0, 0.7 * col.a))
	ci.draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, si, col)


class TopLayer:
	## The top capsule (your pill, the clock, the rival's pill) and the banner slot under it, drawn from the live HUD each frame.
	## The old top bar / status line / banner keep their logic (texts, reveal gates) but are hidden (Hud.layout / _process).
	extends Control
	var hud
	var cap: Piece
	var pills: Array = []                          # [yours, rival]
	var ban: Piece
	var words: Control
	var u := 1.0
	var seats := ["", ""]
	var banner_text := ""
	var banner_col := HudR19.INFO
	var ban_show := false
	var shot_banner := ""                          # --r19-banner=alert|info|win (screenshots only)

	func setup(h) -> void:
		hud = h
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		cap = Piece.new()
		cap.set_base("top_capsule")
		add_child(cap)
		for i in range(2):
			var p := Piece.new()
			p.set_base("score_pill_mine" if i == 0 else "score_pill")
			add_child(p)
			pills.append(p)
		ban = Piece.new()
		ban.set_base("banner")
		add_child(ban)
		words = Control.new()
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.set_anchors_preset(Control.PRESET_FULL_RECT)
		words.draw.connect(_draw_words)
		add_child(words)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--r19-banner="):
				shot_banner = arg.substr(13)
		# your seat left; the rival = the first seat of the other side (1v1 / 2 sides: the demo's matches)
		var groups: Array = hud._seat_groups()
		seats[0] = hud.human
		for gi in range(groups.size()):
			for s in groups[gi]:
				if s != hud.human and seats[1] == "" and not (hud.human in groups[gi]):
					seats[1] = s

	func capsule_rect() -> Rect2:
		return Rect2(cap.position, cap.size)

	func layout(vp: Vector2) -> void:
		u = HudR19.u_of(hud)
		var W := vp.x / u
		var tl := Vector2(W / 2.0 - 160.0, 4.0) * u
		cap.place(tl, u, HudR19.BODY["top_capsule"])
		pills[0].place(tl + HudR19.CAP_SLOTS[0] * u, u, HudR19.BODY["score_pill"])
		pills[1].place(tl + HudR19.CAP_SLOTS[2] * u, u, HudR19.BODY["score_pill"])
		ban.place(Vector2(W / 2.0 - 160.0, 50.0) * u, u, HudR19.BODY["banner"])
		for p in [cap, ban] + pills:
			(p as Piece).tint = HudNoir.accent
		words.queue_redraw()

	func sync() -> void:
		var tp: Control = hud.top_panel
		visible = tp.visible and hud.root.visible
		cap.visible = tp.visible
		for i in range(2):
			var p: Piece = pills[i]
			p.visible = seats[i] != ""
			if seats[i] != "":
				p.set_base(("score_pill_out" if hud._seat_out(seats[i]) else ("score_pill_mine" if i == 0 else "score_pill")))
		# the slot: the Last Stand status line (alert) first, else a banner message (its kind's tint)
		var st: String = hud.status_label.text if hud.status_label.visible else ""
		var t := ""
		var col := HudR19.INFO
		if st != "":
			t = st
			col = HudR19.ALERT
		elif hud.banner.visible and hud.banner.modulate.a > 0.01 and hud.banner.text != "":
			t = hud.banner.text
			var kd: String = hud.kind_of(t)
			col = HudR19.ALERT if kd == "warn" else (HudR19.WIN if kd == "good" else HudR19.INFO)
		if shot_banner != "":                       # screenshot helper --r19-banner=alert|info|win (a sample line in that tint)
			t = {"alert": "LAST STAND in 30 s", "info": "NO RELAYS ON THIS MAP", "win": "VICTORY - SLIME SYNDICATE"}.get(shot_banner, "")
			col = {"alert": HudR19.ALERT, "info": HudR19.INFO, "win": HudR19.WIN}.get(shot_banner, HudR19.INFO)
		ban_show = t != ""
		ban.visible = ban_show
		if t != banner_text or col != banner_col:
			banner_text = t
			banner_col = col
			ban.tint = col
			ban.redraw()
		words.queue_redraw()

	func _draw_words() -> void:
		if cap.visible:
			HudR19.text(words, str(hud.stats_label.text), cap.position + (HudR19.CAP_SLOTS[1] + HudR19.TIMER_C) * u, 68.0 * u,
					14.0 * u, TXT, 10.0 * u, SYMBOL_FONT)
		for i in range(2):
			var p: Piece = pills[i]
			if not p.visible:
				continue
			var chip: Dictionary = hud.top_chips.get(seats[i], {})
			var out: bool = hud._seat_out(seats[i])
			var em: TextureRect = chip.get("emblem")
			if em and em.texture:
				var es := 18.0 * u
				var r := Rect2(p.position + HudR19.PILL_ICON * u - Vector2(es, es) / 2.0, Vector2(es, es))
				words.draw_texture_rect(em.texture, r, false, Color(Rules.seat_color(seats[i]), 0.45 if out else 1.0))
			var lbl: Label = chip.get("label")
			var nm: String = hud.seat_label(seats[i]).to_upper()
			var t := "%s %s" % [nm, lbl.text if lbl else ""]
			HudR19.text(words, t.strip_edges(), p.position + HudR19.PILL_TEXT * u, HudR19.PILL_TEXT_W * u, 12.5 * u,
					Color(TXT, 0.5 if out else 1.0), 9.0 * u)
		if ban_show:
			HudR19.text(words, banner_text, ban.position + Vector2(160, 18) * u, HudR19.BANNER_TEXT_W * u, 12.5 * u,
					banner_col.lerp(Color.WHITE, 0.35), 9.0 * u)
			ban.modulate.a = 1.0 if hud.status_label.text != "" or shot_banner != "" else clampf(hud.banner.modulate.a, 0.0, 1.0)
