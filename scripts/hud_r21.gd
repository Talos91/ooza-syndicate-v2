class_name HudR21
extends RefCounted
## ui-r21-import (2026-11-10, designer CODE JOB SPEC C): the round-21 style (Codex, DIRECTOR-PACKAGE/deliveries/21-hud-missing-style;
## designer check 0 fails) drawn inside the LOCKED round-20 shapes (deliveries/20-hud-missing-A, locked by Daniele 2026-11-10 after
## the throwaway in-game check ui-r20-geo bd30f9f) at the round-20 places (that branch's measured placement rules, ported here):
##   TOASTS     every line with no place of its own (Hud.note_line), two at most, centred under the top capsule (below the banner
##              slot while it shows), y = capsule bottom + 4 / + 27; kind bar in the kind's colour (Hud.kind_color: info / good =
##              the player's colour / build / warn).
##   NODE CARD  the inspected node, in the bottom band beside the SEND tank (tank art right + 10, band top `by`), 230 x 54:
##              owner emblem in the window, owner-coloured ring, FACTION · STRUCTURE · T<n> / the units tube lit to units / cap /
##              the status line.
##   COACH CARD the tutorial's card (CoachOverlay), the handler in the ring (Dr. Vesk's colour), up to 3 lines, the NEXT chevron
##              blinking while the step waits for GOT IT; from node card + 240 to the plate column - 10 (max 640), one row up
##              (from the node card's x) when that room is under 200 pt.
##   HINT STRIP the armed skill's line (SkillDock._hint) with its icon, at the coach card's x in the band's lower row (by + 26),
##              one row up when narrow; above the coach card while the coach shows.
## Resize = 3 parts: the fixed caps (geometry.json fixed_horizontal_caps_body_px) and the broad blank centre stretched (the
## centres have no variation along X, DELIVERY.md); rings, bolts, the kind bar and the chevron live in the caps and never squash.
## Compositing as round 19: fill -> each tube's halo (plain multiply tint on its alpha) -> each W tube through the emissive ramp
## (shaders/neon_ramp.gdshader, white core) -> text. No text is baked; words are real at 12.5 pt (x the HUD's pt).

const DIR := "res://assets/ui/r21/"
const PX := 6.0                                    # source px per pt
const M := 48.0                                    # canvas margin round every body (source px)
const TXT := Color("e8f6fb")
const VESK := Color("14d3e4")                      # Dr. Vesk is the VEX handler: UiKit.ACCENTS["vex"]
const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const TEXT_PT := 12.5
# canvas px, fixed caps (body px), a centre column to stretch (canvas px), body height pt, width range pt
const P := {
	"toast": {"cv": Vector2(1236, 216), "capL": 120.0, "capR": 84.0, "zone": 618.0, "h": 20.0},
	"coach_card": {"cv": Vector2(1794, 420), "capL": 384.0, "capR": 156.0, "zone": 1056.0, "h": 54.0},
	"node_card": {"cv": Vector2(1476, 420), "capL": 0.0, "capR": 0.0, "zone": 0.0, "h": 54.0},
	"hint_strip": {"cv": Vector2(1794, 264), "capL": 180.0, "capR": 48.0, "zone": 897.0, "h": 28.0},
}
const TUBES := {"toast": ["toast_kind"], "coach_card": ["coach_card_rim", "coach_card_ring", "coach_card_next"],
		"node_card": ["node_card_rim", "node_card_ring", "node_card_units"], "hint_strip": ["hint_strip_rim"]}
const TOAST_W := 190.0
const NODE_W := 230.0
const LIFE_FADE := 0.4

static var _tex := {}


static func tex(n: String) -> Texture2D:
	if not _tex.has(n):
		var p := DIR + n + ".png"
		_tex[n] = load(p) if ResourceLoader.exists(p) else null
	return _tex[n]


static func on() -> bool:
	## The round-21 pieces are THE pieces (no flag) wherever the round-19 HUD is on and their art is in the build.
	return HudR19.on() and tex("toast_fill") != null


static func measuring() -> bool:
	return "--r21-measure" in OS.get_cmdline_user_args()


static func text_w(t: String, px: float) -> float:
	return UI_FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(ceil(px))).x


static func fit_line(t: String, room_px: float, px: float) -> String:
	## The line at full size; cut with an ellipsis when it does not fit (the 12.5 pt floor stays).
	if text_w(t, px) <= room_px:
		return t
	var segs := t.split(" · ")                     # the tail segments go first ("+0.9 / s · DOUBLE-TAP: UPGRADE" -> "+0.9 / s")
	while segs.size() > 1:
		segs.remove_at(segs.size() - 1)
		if text_w(" · ".join(segs), px) <= room_px:
			return " · ".join(segs)
	var s := t
	while s.length() > 1 and text_w(s.strip_edges() + "...", px) > room_px:
		s = s.left(s.length() - 1)
	return s.strip_edges() + "..."


static func wrap(t: String, room_px: float, last_room_px: float, px: float) -> Array:
	## Word wrap; the last line stays clear of the NEXT chevron (its last word goes down when it is wider than last_room_px).
	var lines := []
	var cur := ""
	for word in t.split(" ", false):
		var trial: String = word if cur == "" else cur + " " + word
		if text_w(trial, px) <= room_px or cur == "":
			cur = trial
		else:
			lines.append(cur)
			cur = word
	lines.append(cur)
	if lines.size() > 0 and text_w(lines[-1], px) > last_room_px:
		var parts: PackedStringArray = (lines[-1] as String).split(" ")
		if parts.size() > 1:
			lines[-1] = " ".join(parts.slice(0, parts.size() - 1))
			lines.append(parts[parts.size() - 1])
	return lines


static func line(ci: CanvasItem, t: String, left: float, cy: float, px: float, col: Color) -> void:
	## One line left-aligned from `left`, centred on cy, the HUD's soft text shadow under it.
	var si := int(ceil(px))
	var p := Vector2(left, cy + (UI_FONT.get_ascent(si) - UI_FONT.get_descent(si)) / 2.0)
	ci.draw_string(UI_FONT, p + Vector2(0, maxf(1.0, si / 14.0)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, si, Color(0, 0, 0, 0.7 * col.a))
	ci.draw_string(UI_FONT, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, si, col)


class Piece:
	## One round-21 piece: its BODY's top-left at `position`, `size` = the body (px, any width in the piece's range). Fill and
	## halos on itself, the W tubes on a ramp child, the content (`content` callable, drawn on the top child) over them.
	extends Control
	var piece := ""
	var u := 1.0                                   # screen px per pt
	var tints := {}                                # tube layer -> tint (alpha = its strength)
	var clip := {}                                 # tube layer -> right end, canvas px (node units tube)
	var content: Callable
	var _tube: Control
	var _top: Control

	func _init(p: String) -> void:
		piece = p
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_tube = Control.new()
		_tube.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tube.material = HudR19.ramp()
		_tube.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_tube.draw.connect(_draw_tubes)
		add_child(_tube)
		_top = Control.new()
		_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_top.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_top.draw.connect(func(): if content.is_valid(): content.call(_top, self))
		add_child(_top)

	func place(tl_px: Vector2, u_px: float, w_pt: float) -> void:
		u = u_px
		position = tl_px
		size = Vector2(w_pt, HudR21.P[piece]["h"]) * u
		redraw()

	func redraw() -> void:
		queue_redraw()
		_tube.queue_redraw()
		_top.queue_redraw()

	func s() -> float:
		return u / HudR21.PX

	func cx(c: float) -> float:
		## A canvas x to local px: a feature in the RIGHT cap follows the right edge, everything else the left edge.
		var d: Dictionary = HudR21.P[piece]
		var cw: float = (d["cv"] as Vector2).x
		if d["zone"] != 0.0 and c >= cw - HudR21.M - float(d["capR"]):
			return size.x - (cw - HudR21.M - c) * s()
		return (c - HudR21.M) * s()

	func cy(c: float) -> float:
		return (c - HudR21.M) * s()

	func layer(ci: CanvasItem, t: Texture2D, col: Color, clip_x := INF) -> void:
		## One canvas-size layer, 3-part stretched to the body width (whole and evenly scaled for the node card).
		if t == null:
			return
		var d: Dictionary = HudR21.P[piece]
		var cv: Vector2 = d["cv"]
		var k := s()
		var o := -Vector2.ONE * HudR21.M * k
		if d["zone"] == 0.0:
			var w := minf(cv.x, clip_x)
			ci.draw_texture_rect_region(t, Rect2(o, Vector2(w, cv.y) * k), Rect2(0, 0, w, cv.y), col)
			return
		var lw: float = HudR21.M + float(d["capL"])
		var rw: float = HudR21.M + float(d["capR"])
		ci.draw_texture_rect_region(t, Rect2(o, Vector2(lw, cv.y) * k), Rect2(0, 0, lw, cv.y), col)
		var x0: float = float(d["capL"]) * k
		var x1: float = size.x - float(d["capR"]) * k
		if x1 > x0:
			ci.draw_texture_rect_region(t, Rect2(x0, o.y, x1 - x0, cv.y * k), Rect2(float(d["zone"]) + 4.0, 0, 4.0, cv.y), col)
		ci.draw_texture_rect_region(t, Rect2(x1, o.y, rw * k, cv.y * k), Rect2(cv.x - rw, 0, rw, cv.y), col)

	func _draw() -> void:
		layer(self, HudR21.tex(piece + "_fill"), Color.WHITE)
		for l in HudR21.TUBES[piece]:
			var c: Color = tints.get(l, Color(0, 0, 0, 0))
			if c.a > 0.0:
				layer(self, HudR21.tex(l + "_glow"), Color(c, HudR19.HALO_A * c.a), float(clip.get(l, INF)))

	func _draw_tubes() -> void:
		for l in HudR21.TUBES[piece]:
			var c: Color = tints.get(l, Color(0, 0, 0, 0))
			if c.a > 0.0:
				layer(_tube, HudR21.tex(l), c, float(clip.get(l, INF)))


static func band(hud) -> Dictionary:
	## The round-20 places (ui-r20-geo r20_geo.gd, designer v3), in layout pt (u = HudR19.u_of): the band top `by`, the node card's
	## x `mid` (tank art right + 10), the plate column's left `px`, the coach / hint strip's x and width, and whether the band is
	## narrow (under 200 pt of room right of the node card: coach / hint go one row up from `mid`).
	var vp: Vector2 = hud.root.get_viewport_rect().size
	var u: float = HudR19.u_of(hud)
	var ins := UiKit.safe_insets(vp) / u
	var W := vp.x / u
	var H := vp.y / u
	var L := ins.x + 4.0
	var R := W - ins.z - 4.0
	var by := (H - ins.w - 54.0 - 4.0) if ins.w > 0.0 else (H - 54.0 - 12.0)
	var tank := Rect2()
	if hud.send_tank and hud.send_tank.picture() and hud.side_panel.visible:
		var st = hud.send_tank
		var o: Vector2 = st.get_global_rect().position
		var a: Vector2 = o + st.cv(Vector2(st.PIC_X, st.PIC_Y))
		var b: Vector2 = o + st.cv(Vector2(st.PIC_X + st.PIC_W, st.PIC_Y + 1080.0))
		tank = Rect2(a / u, (b - a) / u)
	var px := R - 96.0
	if hud.dock and hud.dock.is_visible_in_tree():
		px = hud.dock.get_global_rect().position.x / u
	var mid := (tank.end.x if tank.size.x > 0.0 else L + 71.0) + 10.0
	var cx := mid + NODE_W + 10.0
	var narrow := (px - 10.0 - cx) < 200.0
	var sx := mid if narrow else cx
	var sw := minf(640.0, px - 10.0 - sx)
	var d := {"u": u, "W": W, "H": H, "L": L, "R": R, "by": by, "tank": tank, "px": px, "mid": mid, "narrow": narrow,
			"sx": sx, "sw": sw, "safe": Rect2(ins.x, ins.y, W - ins.x - ins.z, H - ins.y - ins.w)}
	if hud.has_method("tall_b") and hud.tall_b() and hud.dock and hud.dock.is_visible_in_tree():
		var tag := Rect2()
		if hud.map_title and hud.map_title.is_visible_in_tree():
			tag = hud.map_title.get_global_rect()
			tag = Rect2(tag.position / u, tag.size / u)
		_tall_b_band(d, hud.dock.get_global_rect(), tag)
	return d


static func _tall_b_band(d: Dictionary, row_px: Rect2, tag: Rect2) -> void:
	## ui-tall-b (designer spec D): the plate row is centred on the safe bottom, so the band runs BESIDE it: the node card left of
	## the row (at the tank's right + 10, as on a phone), the coach card / hint strip right of it (row right + 10 to the safe right).
	## Where a side has no room (node card: 230 pt; coach / hint: under 200 pt) the piece goes one row up, above the plate row
	## (the r20 narrow rule); a second piece that does not fit beside it there goes one more row up.
	var u: float = d["u"]
	var row := Rect2(row_px.position / u, row_px.size / u)
	var R: float = d["R"]
	var mid: float = d["mid"]
	var by := row.end.y - 54.0                      # the band's 54 pt pieces bottom-aligned with the row
	var up := row.position.y - 6.0 - 54.0           # one row up, above the plates
	var tank: Rect2 = d["tank"]
	var node_beside := row.position.x - 10.0 - mid >= NODE_W
	if not node_beside and maxf(tank.end.y, tag.end.y) < by - 4.0 and row.position.x - 10.0 - float(d["L"]) >= NODE_W:
		mid = d["L"]                                # the tank column ends above the band: the card starts at the safe left
		node_beside = true
	var node := Rect2(mid, by if node_beside else up, NODE_W, 54.0)
	var coach := Rect2()
	var right_room := R - (row.end.x + 10.0)
	if right_room >= 200.0:
		coach = Rect2(row.end.x + 10.0, by, minf(640.0, right_room), 54.0)
	elif not node_beside and R - (node.end.x + 10.0) >= 200.0:
		coach = Rect2(node.end.x + 10.0, up, minf(640.0, R - node.end.x - 10.0), 54.0)
	elif node_beside:
		coach = Rect2(mid, up, minf(640.0, R - mid), 54.0)
	else:
		coach = Rect2(mid, up - 58.0, minf(640.0, R - mid), 54.0)
	var hint := Rect2(coach.position.x, coach.end.y - 28.0, coach.size.x, 28.0)
	d["by"] = by
	d["px"] = row.position.x
	d["narrow"] = coach.position.y < by
	d["sx"] = coach.position.x
	d["sw"] = coach.size.x
	d["node_r"] = node
	d["coach_r"] = coach
	d["hint_r"] = hint
	d["row"] = row
	var raised := 9999.0                           # the top of whatever goes above the plate row (the fit keeps clear of it)
	if not node_beside:
		raised = minf(raised, node.position.y)
	if coach.position.y < by:
		raised = minf(raised, coach.position.y)
	if raised < 9999.0:
		d["raise_top"] = raised


static func coach_rect(hud) -> Rect2:
	## The coach card's body, layout pt.
	var b := band(hud)
	if b.has("coach_r"):                           # ui-tall-b: beside / above the centred plate row
		return b["coach_r"]
	return Rect2(Vector2(b["sx"], b["by"] - (58.0 if b["narrow"] else 0.0)), Vector2(b["sw"], 54.0))


static func hint_rect(hud, coach_up: bool) -> Rect2:
	## The hint strip's body, layout pt: the band's lower row (one row up when narrow), above the coach card while it shows.
	var b := band(hud)
	if b.has("hint_r"):                            # ui-tall-b: the coach card's lower row; above the coach card while it shows
		var c: Rect2 = b["coach_r"]
		return Rect2(Vector2(c.position.x, c.position.y - 32.0), Vector2(c.size.x, 28.0)) if coach_up else b["hint_r"]
	var y: float = b["by"] + 26.0
	if b["narrow"]:
		y = b["by"] - 32.0
	if coach_up:
		y = coach_rect(hud).position.y - 32.0
	return Rect2(Vector2(b["sx"], y), Vector2(b["sw"], 28.0))


class Layer:
	## The Hud's round-21 layer: the toast stack, the node card (the inspector's card, drawn here at its band place) and the hint
	## strip. Owned by Hud (setup / sync every frame); the coach card is CoachOverlay's (it asks coach_rect()).
	extends Control
	var hud
	var toasts: Array = []                         # [{text, kind, t}] newest first
	var pieces: Array = []                         # piece i draws toasts[i]
	var node_card: Piece
	var hint: Piece
	var u := 1.0
	var coach_up := false                          # the tutorial's coach card is showing (the hint strip stacks above it)
	var coach_body := Rect2()                      # its body, layout pt (for the measure)
	var _hint_text := ""
	var _hint_icon: Texture2D
	var _n := 0
	var _shot_skip := 0                            # --r21-skip=N (screenshots): the tutorial's SKIP GOAL N times at 2 s (a 3-line goal)
	var _shot_toasts: Array = []                   # --r21-toasts=good,warn (screenshots): two real lines through Hud.note_line at 9 s
	var texts := []                                # --r21-measure: every line drawn this frame

	func setup(h) -> void:
		hud = h
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		node_card = Piece.new("node_card")
		node_card.content = _draw_node
		node_card.visible = false
		add_child(node_card)
		hint = Piece.new("hint_strip")
		hint.content = _draw_hint
		hint.visible = false
		add_child(hint)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--r21-skip="):
				_shot_skip = int(a.substr(11))
			if a.begins_with("--r21-toasts="):
				_shot_toasts = Array(a.substr(13).split(","))
		for i in range(2):
			var t := Piece.new("toast")
			t.content = _draw_toast.bind(i)
			t.visible = false
			add_child(t)
			pieces.append(t)
			toasts.append({"text": "", "kind": "", "t": 0.0})

	func toast(text: String, kind: String) -> void:
		## A new line on top; the older one moves down; a third pushes the oldest out.
		toasts[1] = toasts[0]
		toasts[0] = {"text": text, "kind": kind, "t": float(Rules.HUD_LINE_LIFE)}

	func sync(dt: float) -> void:
		var vp: Vector2 = hud.root.get_viewport_rect().size
		u = HudR19.u_of(hud)
		visible = hud.root.visible
		var b := HudR21.band(hud)
		if _shot_skip > 0 and float(hud.sim.time) >= 2.0 and hud.main.get("director") != null:
			for i in range(_shot_skip):
				hud.main.director.skip_step()
			_shot_skip = 0
		if not _shot_toasts.is_empty() and float(hud.sim.time) >= 9.0:
			var lines := {"info": "The Last Stand starts at 3:00", "good": "Node captured: +6 units", "build": "Upgrade started: T2 in 12 s",
					"warn": "Not enough units to upgrade"}
			for k in _shot_toasts:
				hud.note_line(str(lines.get(k, k)), str(k))
			_shot_toasts = []
		_n += 1
		if HudR21.measuring() and _n % 6 == 0:       # (last frame's lines: the pieces draw after this)
			print("R21REPORT ", JSON.stringify(report(b)))
		texts.clear()
		# ---- toasts: centred under the capsule (under the banner slot while it shows)
		var y0 := 4.0
		if hud.r19_top:
			var cap: Rect2 = hud.r19_top.capsule_rect()
			y0 = cap.end.y / u + 4.0
			if hud.r19_top.ban.visible and hud.r19_top.ban.modulate.a > 0.01:
				y0 = (hud.r19_top.ban.position.y + hud.r19_top.ban.size.y) / u + 4.0
		for i in range(2):
			var d: Dictionary = toasts[i]
			d["t"] = maxf(0.0, float(d["t"]) - dt)
			var p: Piece = pieces[i]
			p.visible = float(d["t"]) > 0.0 and str(d["text"]) != "" and hud.shows("notices")
			if p.visible:
				p.place(Vector2(b["W"] / 2.0 - TOAST_W / 2.0, y0 + 23.0 * i) * u, u, TOAST_W)
				p.tints = {"toast_kind": hud.kind_color(str(d["kind"]))}
				p.modulate.a = clampf(float(d["t"]) / LIFE_FADE, 0.0, 1.0)
		# ---- node card: the inspected node, bottom band beside the tank
		var nid: int = hud.inspector_id
		node_card.visible = nid >= 0 and is_instance_valid(hud.inspector)
		if node_card.visible:
			var n: Dictionary = hud.sim.nodes[nid]
			node_card.place((b["node_r"].position if b.has("node_r") else Vector2(b["mid"], b["by"])) * u, u, NODE_W)
			var col: Color = hud.inspector_col
			var owner := str(n["owner"])
			var hidden_pop: bool = owner != "" and not hud.sim.allied(owner, hud.human)
			var cap_u := maxf(float(hud.sim.node_cap(n)), 1.0)
			var units: float = hud.sim.garrison_total(n) if hud.sim.allied_units(n) > 0.0001 else float(n["units"])
			var f := 0.0 if hidden_pop else clampf(units / cap_u, 0.0, 1.0)
			node_card.tints = {"node_card_rim": HudNoir.accent, "node_card_ring": col if owner != "" else Color(HudNoir.MUTED, 0.6),
					"node_card_units": Color(col, 1.0 if f > 0.0 else 0.0)}
			node_card.clip = {"node_card_units": 414.0 + (1350.0 - 414.0) * f, "node_card_units_glow": 398.0 + (1366.0 - 398.0) * f}
			node_card.redraw()
		# ---- hint strip: the armed skill's line
		var dock = hud.dock
		var armed: bool = dock != null and dock.armed >= 0 and dock.is_visible_in_tree()
		hint.visible = armed
		if armed:
			var id: String = hud.sim.skill_id(hud.human, dock.SLOTS[dock.armed])
			_hint_icon = HudSkin.skill_icon(id)
			_hint_text = dock.hint_label.text
			var r := HudR21.hint_rect(hud, coach_up)
			var need := HudR21.text_w(_hint_text.replace("  ·  tap the slot again to cancel", ""), _px()) / u + 31.0
			if not b.has("hint_r") and not b["narrow"] and not coach_up and need > r.size.x:   # too short for the line: one row up from the node card's x
				r = Rect2(Vector2(b["mid"], b["by"] - 32.0), Vector2(minf(640.0, b["px"] - 10.0 - b["mid"]), 28.0))
			hint.place(r.position * u, u, r.size.x)
			hint.tints = {"hint_strip_rim": HudNoir.accent}
			dock.hint_panel.visible = false
		if hud.hint:                                  # (the desktop keys line under the band: off while the strip shows)
			hud.hint.modulate.a = 0.0 if armed or node_card.visible else 1.0

	# ---------------------------------------------------------------- content
	func _px() -> float:
		return HudR21.TEXT_PT * u

	func _note(name: String, t: String, room_px: float, px: float) -> void:
		texts.append({"name": name, "text": t, "w_pt": snappedf(HudR21.text_w(t, px) / u, 0.1), "room_pt": snappedf(room_px / u, 0.1),
				"size_pt": snappedf(ceil(px) / u, 0.1), "fits": HudR21.text_w(t, px) <= room_px + 0.5})

	func _draw_toast(ci: CanvasItem, p: Piece, i: int) -> void:
		var d: Dictionary = toasts[i]
		var left := p.cx(144.0)
		var room := p.size.x - 62.0 * p.s() - left
		var t := HudR21.fit_line(str(d["text"]), room, _px())
		HudR21.line(ci, t, left, p.cy(108.0), _px(), HudR21.TXT)
		_note("toast_%d" % (i + 1), t, room, _px())

	func _draw_node(ci: CanvasItem, p: Piece) -> void:
		var nid: int = hud.inspector_id
		if nid < 0:
			return
		var n: Dictionary = hud.sim.nodes[nid]
		var owner := str(n["owner"])
		var hidden_pop: bool = owner != "" and not hud.sim.allied(owner, hud.human)
		# window: the owner's emblem in the owner's colour (a neutral node: the plain glass)
		if owner != "":
			var em: Texture2D = hud.emblem_texture(str(hud.sim.factions.get(owner, "null")))
			if em:
				var es := 28.0 * u
				ci.draw_texture_rect(em, Rect2(Vector2(p.cx(222.0), p.cy(210.0)) - Vector2(es, es) / 2.0, Vector2(es, es)), false,
						Rules.seat_color(owner))
		var left := p.cx(412.0)
		var room := 940.0 * p.s()
		var who := "NEUTRAL" if owner == "" else str(hud.sim.factions.get(owner, "")).to_upper()
		var tier := ""
		if (n["relay"] == "" and str(n["structure"]) in ["vat", "machinegoon", ""]) or n["relay"] == "launcher":
			tier = " · %s%d" % ["M" if n["structure"] == "machinegoon" else "T", int(n["tier"])]
		var head: String = "%s · %s%s" % [who, hud._structure_word(n), tier]
		var cnt := ""
		if not hidden_pop:
			var cap_u := maxf(float(hud.sim.node_cap(n)), 1.0)
			var units: float = hud.sim.garrison_total(n) if hud.sim.allied_units(n) > 0.0001 else float(n["units"])
			cnt = "%d / %d" % [Rules.shown(units), Rules.shown(cap_u)]
		var cw := HudR21.text_w(cnt, _px()) + (6.0 * u if cnt != "" else 0.0)
		var h1 := HudR21.fit_line(head, room - cw, _px())
		HudR21.line(ci, h1, left, p.cy(120.0), _px(), HudR21.TXT)
		_note("node_line", h1, room - cw, _px())
		if cnt != "":
			HudR21.line(ci, cnt, left + room - HudR21.text_w(cnt, _px()), p.cy(120.0), _px(), hud.inspector_col.lerp(Color.WHITE, 0.45))
			_note("node_units", cnt, HudR21.text_w(cnt, _px()) + 1.0, _px())
		var st: String = hud._status_line(n, hidden_pop)
		if owner != "" and Sim.has_vat(n) and float(n["armour"]) < float(n["armour_cap"]) - 0.0001 and NodeNoir.shield_count(float(n["armour_cap"])) > 0:
			st += ("" if st == "" else " · ") + "ARMOUR FULL IN %d s" % int(ceil(hud.sim.armour_full_in(n)))
		if st != "":
			var s2 := HudR21.fit_line(st, room, _px())
			HudR21.line(ci, s2, left, p.cy(300.0), _px(), Color("c8e6ee"))
			_note("node_status", s2, room, _px())

	func _draw_hint(ci: CanvasItem, p: Piece) -> void:
		if _hint_icon:
			var side := 18.0 * u
			SkillDock.draw_icon_fit(ci, _hint_icon, Vector2(p.cx(126.0), p.cy(132.0)), side, HudNoir.INK)
		var left := p.cx(204.0)
		var room := p.size.x - 28.0 * p.s() - left
		var t := _hint_text
		if HudR21.text_w(t, _px()) > room:            # the cancel tail goes first, then the line is cut
			t = t.replace("  ·  tap the slot again to cancel", "")
		t = HudR21.fit_line(t, room, _px())
		HudR21.line(ci, t, left, p.cy(132.0), _px(), HudR21.TXT)
		_note("hint_line", t, room, _px())

	# ---------------------------------------------------------------- measure (--r21-measure)
	func report(b: Dictionary) -> Dictionary:
		var rects := {}
		var add := func(k: String, c: Control):
			if c and c.is_visible_in_tree() and c.size.x > 1.0 and c.modulate.a > 0.01 and c.self_modulate.a > 0.01:
				var g := c.get_global_rect()
				rects[k] = Rect2(g.position / u, g.size / u)
		for i in range(2):
			add.call("toast_%d" % (i + 1), pieces[i])
		add.call("node_card", node_card)
		add.call("hint_strip", hint)
		if coach_up and coach_body.size.x > 0.0:
			rects["coach_card"] = coach_body
		if hud.main.get("coach") != null:
			var sr: Rect2 = hud.main.coach.strip_rect()
			if sr.size.x > 0.0:
				rects["goal_strip"] = Rect2(sr.position / u, sr.size / u)
		if (b["tank"] as Rect2).size.x > 0.0:
			rects["tank(art)"] = b["tank"]
		if hud.r19_top:
			var cap: Rect2 = hud.r19_top.capsule_rect()
			rects["capsule"] = Rect2(cap.position / u, cap.size / u)
			if hud.r19_top.ban.visible:
				var bn: Control = hud.r19_top.ban
				rects["banner"] = Rect2(bn.position / u, bn.size / u)
		add.call("plates", hud.dock)
		add.call("version_tag", hud.version_label)
		add.call("map_title", hud.map_title)
		add.call("pause_btn", hud.pause_button)
		add.call("music_btn", hud.music_button)
		add.call("debug_btn", hud.debug_button)
		add.call("keys_hint", hud.hint)
		if is_instance_valid(hud.inspector):
			var fan := Rect2()
			for a in hud.inspector_actions:
				var r: Rect2 = a["button"].bbox_global()
				fan = r if fan.size.x == 0.0 else fan.merge(r)
			if fan.size.x > 0.0:
				rects["radial"] = Rect2(fan.position / u, fan.size / u)
		var out := []
		var mine := ["toast_1", "toast_2", "node_card", "hint_strip", "coach_card", "goal_strip"]
		for a in mine:
			if not rects.has(a):
				continue
			for k in rects:
				if k == a or (k in mine and mine.find(k) < mine.find(a)):
					continue
				if (rects[a] as Rect2).intersects(rects[k]):
					out.append("%s x %s" % [a, k])
			if not (b["safe"] as Rect2).grow(0.5).encloses(rects[a]):
				out.append("%s outside safe" % a)
		var rr := {}
		for k in rects:
			var r: Rect2 = rects[k]
			rr[k] = [snappedf(r.position.x, 0.1), snappedf(r.position.y, 0.1), snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)]
		return {"W_pt": snappedf(b["W"], 0.1), "H_pt": snappedf(b["H"], 0.1), "u": snappedf(u, 0.001), "narrow": b["narrow"],
				"rects": rr, "texts": texts.duplicate(), "overlaps": out}
