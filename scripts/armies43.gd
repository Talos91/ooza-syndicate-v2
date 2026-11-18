extends Control
class_name Armies43
## ARMIES straight from the 43B-pack-ARMIES layout (Daniele 2026-11-18: "Yes, import it"; designer 10: parts = mock).
## assets/ui/armies43/layout.json = the delivered layout.json, body only (faction row, SKILLS / CUSTOMIZE, hero cabinet,
## ultimate cabinet, RESET, 14 skill cards; tools/prep_armies43.py). Bounds stay in the delivery's 4x px; the whole body
## is scaled evenly into the free area. Parts are drawn in z order, four-state families swap with each control's state
## (NORMAL / PRESSED / SELECTED / DISABLED, as the delivery's state_bindings), labels are runtime text from the game.
## The heroes are the game's own (hero_path + the seat-coloured neon line: goo = faction colour, neon = seat colour).

const DIR := "res://assets/ui/armies43/"
const BODY := Rect2(64, 196, 3120, 1100)
const TOP_ROW_H := 160.0                            # the faction / section row only (CUSTOMIZE keeps its own body)
const FACTIONS := ["vex", "null", "bloom", "ember", "solar"]
const SHORT := {}                                   # (45B: EMERGENCY EVAC keeps its name, two lines in SKILL-NAME-FACE-TALL)

static var _layout: Dictionary = {}

var m: Node                                         # the menu (callbacks + font floor)
var army := "vex"
var tab := "skills"
var s := 0.25                                       # canvas units per 4x px
var origin := Vector2.ZERO                          # the body's top-left in this control
var _els: Array = []
var _ctrl: Dictionary = {}                          # control id -> control dict
var _el_ctrl: Dictionary = {}                       # element id -> control id
var _state: Dictionary = {}                         # control id -> state string
var _pressed := ""
var _skill_of: Dictionary = {}                      # control id -> skill id
var _tex: Dictionary = {}
var on_tap: Callable                                # on_tap.call(control_id)


static func layout() -> Dictionary:
	if _layout.is_empty():
		var f := FileAccess.open(DIR + "layout.json", FileAccess.READ)
		if f != null:
			_layout = JSON.parse_string(f.get_as_text())
	return _layout


static func height_for(width: float, top_only: bool) -> float:
	## The canvas height the body takes at `width` (scale set by the width alone).
	return (TOP_ROW_H if top_only else BODY.size.y) * width / BODY.size.x


func setup(menu: Node, area: Rect2, f: String, t: String, tap: Callable) -> void:
	m = menu
	army = f
	tab = t
	on_tap = tap
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var L := layout()
	var top_only := tab != "skills"
	var bh := TOP_ROW_H if top_only else BODY.size.y
	s = minf(area.size.x / BODY.size.x, area.size.y / bh)
	position = area.position
	size = area.size
	origin = Vector2((area.size.x - BODY.size.x * s) / 2.0, 0.0)
	var skill_ids: Array = Rules.ACTIVE_SKILLS + Rules.MAP_SKILLS
	var k := 0
	for c in L.get("controls", []):
		_ctrl[c["id"]] = c
		for ch in c["children"]:
			_el_ctrl[ch] = c["id"]
		if str(c["id"]).begins_with("SKILL-") and k < skill_ids.size():
			_skill_of[c["id"]] = skill_ids[k]
			k += 1
	for e in L.get("elements", []):
		if top_only and e["y"] >= BODY.position.y + TOP_ROW_H:
			continue
		_els.append(e)
	_els.sort_custom(func(a, b): return a["z"] < b["z"])
	_refresh_states()
	_add_buttons(top_only)
	_add_heroes(top_only)


func _refresh_states() -> void:
	var lo := ArmyPresets.loadout_for(army)
	for id in _ctrl:
		var st := "NORMAL"
		if id.begins_with("FACTION-"):
			st = "SELECTED" if _faction_of(id) == army else "NORMAL"
		elif id == "SKILLS" or id == "CUSTOMIZE":
			st = "SELECTED" if id.to_lower() == tab else "NORMAL"
		elif id == "RESET":
			st = "DISABLED" if ArmyPresets.is_default(army) else "NORMAL"
		elif _skill_of.has(id):
			var sid: String = _skill_of[id]
			var slot := "active" if sid in Rules.ACTIVE_SKILLS else "map"
			if lo.get(slot, "") == sid:
				st = "SELECTED"
			elif not Progression.is_unlocked("skill:" + sid):
				st = "DISABLED"
		if id == _pressed and st != "DISABLED":
			st = "PRESSED"
		_state[id] = st


func _faction_of(cid: String) -> String:
	var n := cid.substr(8).to_lower()
	return "solar" if n == "aegis" else n


func skill_of(cid: String) -> String:
	return _skill_of.get(cid, "")


func rect_of(id: String) -> Rect2:
	## A control's (or the ultimate cabinet's, id "ULT") rect in the menu's content coordinates.
	var b: Array = [784, 392, 2152, 152] if id == "ULT" else _ctrl[id]["bounds"]
	return Rect2(position + origin + (Vector2(b[0], b[1]) - BODY.position) * s, Vector2(b[2], b[3]) * s)


func _r(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(origin + (Vector2(x, y) - BODY.position) * s, Vector2(w, h) * s)


func _add_buttons(top_only: bool) -> void:
	var ids: Array = _ctrl.keys()
	if not top_only:
		ids.append("ULT")
	for id in ids:
		if top_only and id != "ULT" and _ctrl[id]["bounds"][1] >= BODY.position.y + TOP_ROW_H:
			continue
		if top_only and id == "ULT":
			continue
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		for sn in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			b.add_theme_stylebox_override(sn, StyleBoxEmpty.new())
		var r := rect_of(id)
		b.position = r.position - position
		b.size = r.size
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		var cid: String = id
		b.button_down.connect(func():
			_pressed = cid
			_refresh_states()
			queue_redraw())
		b.button_up.connect(func():
			_pressed = ""
			_refresh_states()
			queue_redraw())
		b.pressed.connect(func(): on_tap.call(cid))
		if id == "RESET":
			b.disabled = _state.get("RESET", "") == "DISABLED"
		b.name = "btn_" + cid
		add_child(b)


func _add_heroes(top_only: bool) -> void:
	## The game's heroes in the delivery's wells (fitted, centred, bottom-aligned like the proof), neon in the seat colour.
	var vc: Color = m._viewer_col() if m != null and m.has_method("_viewer_col") else Color(0, 0, 0, 0)
	for i in range(FACTIONS.size()):
		var x0 := 64.0 + i * 440.0
		_hero(FACTIONS[i], _r(x0 + 24.0, 214.0, 132.0, 124.0), vc)
	if not top_only:
		_hero(army, _r(130.0, 608.0, 548.0, 330.0), vc)   # (45B: room for the faction tagline under the hero)


func _hero(f: String, r: Rect2, vc: Color) -> void:
	var t := TextureRect.new()
	t.texture = UiKit.tex(UiKit.hero_path(f))
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.position = r.position
	t.size = r.size
	UiKit.hero_neon(t, f, vc)
	add_child(t)
	move_child(t, 0)                                 # under the buttons (they are invisible anyway)


func _t(file: String) -> Texture2D:
	if not _tex.has(file):
		_tex[file] = UiKit.tex(DIR + file)
	return _tex[file]


func _el_state(e: Dictionary) -> String:
	return _state.get(_el_ctrl.get(e["id"], ""), "")


func _binding(e: Dictionary) -> Dictionary:
	var cid: String = _el_ctrl.get(e["id"], "")
	if cid == "":
		return {}
	for b in _ctrl[cid]["state_bindings"]:
		if b["element"] == e["id"]:
			return b
	return {}


func _draw() -> void:
	var font_floor := float(UiKit.px(m, 0.0)) if m != null else 0.0
	for e in _els:
		var st := _el_state(e)
		var bd := _binding(e)
		if bd.has("visible_states") and not (st in bd["visible_states"]):
			continue
		if e.get("visible_states") != null and st != "" and not (st in e["visible_states"]):
			continue
		var r := _r(e["x"], e["y"], e["w"], e["h"])
		if e["type"] == "image":
			var file: String = e["file"]
			if file.begins_with("HERO-") and file != "HERO-CABINET.png" and file != "HERO-TITLE-BAR.png" and file != "HERO-WELL.png":
				continue                             # the game's own heroes (TextureRects)
			if bd.has("files") and st != "":
				file = bd["files"].get(st, file)
			var col := Color.WHITE
			if bd.has("alpha_mask_tints") and st != "":
				col = Color(bd["alpha_mask_tints"][st])
			elif e.has("alpha_mask_tint"):
				col = Color(e["alpha_mask_tint"])
			if file == "ICON-OVERDRIVE.png" and Rules.FACTION_ULTIMATE_ID.get(army, "") != "overdrive":
				var ic := ArmyPresets.icon(Rules.FACTION_ULTIMATE_ID.get(army, ""))
				if ic != null:
					var side := minf(r.size.x, r.size.y) * 1.25
					draw_texture_rect(ic, Rect2(r.get_center() - Vector2(side, side) / 2.0, Vector2(side, side)), false, Color("FAEAD1"))
				continue
			if file == "DIVIDER.png" and tab == "skills" and e["y"] > 560 and e["y"] < 1000:
				r.size.x = _r(1600.0, 0, 0, 0).position.x - 16.0 * s - r.position.x   # stops before the section subtitle
			if file.begins_with("SKILL-NAME-FACE") and _tall(_el_ctrl.get(e["id"], "")):
				_draw_tall_face(r, st if st != "" else "NORMAL")   # 45B SKILL-NAME-FACE-TALL: a two-line name (EMERGENCY EVAC)
				continue
			if file == "SEAT-LAMP.png":                # 45B2: the SELECTED faces carry their own seat lamp (mask)
				continue
			if SEL45.has(file):                        # 45B2 (designer 11 FIX 1): SELECTED faces from the overlay
				var fam: String = SEL45[file]
				var u := r.size.x / (float(e["w"]) / 4.0)
				Kit45.draw_part(self, fam, Kit45.nearest(fam, float(e["w"]) / 4.0, float(e["h"]) / 4.0), "SELECTED", r, u)
				continue
			var tx := _t(file)
			if tx != null:
				draw_texture_rect(tx, r, false, col)
		else:
			_draw_text(e, st, bd, font_floor)
	if tab == "skills":
		_draw_extras(font_floor)


const SEL45 := {"FACTION-TAB-SELECTED.png": "FACTION-TAB", "SECTION-TAB-SELECTED.png": "SECTION-TAB",
		"SKILL-CARD-SELECTED.png": "SKILL-CARD", "SKILL-NAME-FACE-SELECTED.png": "SKILL-NAME-FACE"}
const UP := Color("29d3e0")                         # a stat above 100 % (the remake's cyan)
const DOWN := Color("e2546a")                       # below 100 %


func _tall(cid: String) -> bool:
	## A skill name that cannot sit on one line at the 12.5 pt floor in its name face (SPORE BURST, FOG OF WAR, EMERGENCY EVAC).
	if not _skill_of.has(cid):
		return false
	var nm := _skill_label(cid)
	var fe := _face_of(cid)
	if fe.is_empty() or not nm.contains(" "):
		return false
	var fl := maxf(float(UiKit.px(m, 0.0)) if m != null else 0.0, 1.0)
	return UiKit.BODY.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(fl * 0.8))).x > _r(0, 0, float(fe["w"]) - 24.0, 0).size.x


func _skill_label(cid: String) -> String:
	var nm := ArmyPresets.skill_name(_skill_of[cid]).to_upper()
	return SHORT.get(nm, nm)


func _face_of(cid: String) -> Dictionary:
	for x in _els:
		if x["type"] == "image" and _el_ctrl.get(x["id"], "") == cid and str(x["file"]).begins_with("SKILL-NAME-FACE"):
			return x
	return {}


func _skill_name(e: Dictionary, cid: String, st: String, bd: Dictionary) -> void:
	## designer 11 FIX 2 / 4: the whole name in its face (the tall face when it needs two lines), never under the floor;
	## drawn once (the delivered FOG OF / WAR pair: by the first element).
	for x in _els:
		if x["type"] == "text" and _el_ctrl.get(x["id"], "") == cid:
			if x["id"] != e["id"]:
				return
			break
	var fe := _face_of(cid)
	if fe.is_empty():
		return
	var r := _r(fe["x"], fe["y"], fe["w"], fe["h"])
	if _tall(cid):
		var sz := Vector2(r.size.x, r.size.x * 36.0 / 86.0)
		r = Rect2(Vector2(r.get_center().x - sz.x / 2.0, r.end.y - sz.y), sz)
	var col := Color(e["color"])
	if bd.has("text_colors") and st != "":
		col = Color(bd["text_colors"][st])
	if st == "SELECTED":
		col = Kit45.INK_CREAM                          # 45B2: cream on the copper SELECTED face
	Kit45.draw_text(self, m, _skill_label(cid), r.grow_individual(-_r(0, 0, 10, 0).size.x, 0, -_r(0, 0, 10, 0).size.x, 0),
			float(e["font"]["size_px"]) * s, col, false, 1, 2, 0.8)   # (this page's names: down to 80 % of the floor, as before)


func _draw_tall_face(face: Rect2, st: String) -> void:
	## The tall name face (86 x 36 pt, evenly scaled to the card's 71 pt face width), centred on the face, bottom-aligned.
	var t := Kit45.tex("SKILL-NAME-FACE-TALL-86x36pt-%s.png" % st)
	if t == null:
		return
	var sz := Vector2(face.size.x, face.size.x * 36.0 / 86.0)   # the card's face width, the tall face's own proportions
	draw_texture_rect(t, Rect2(Vector2(face.get_center().x - sz.x / 2.0, face.end.y - sz.y), sz), false)


func _draw_extras(font_floor: float) -> void:
	## The remake's hero card and section lines (45B ARMIES-SKILLS): the faction tagline under the hero, the stats as a
	## two-column table (above 100 % cyan, below red) and the section subtitles beside ACTIVE / MAP SKILL.
	var f := UiKit.BODY
	var fs := maxi(1, int(round(maxf(36.0 * s, font_floor))))
	var asc := (f.get_ascent(fs) - f.get_descent(fs)) / 2.0
	var tag := str(Rules.FACTION_TAGLINES.get(army, "")).to_upper()
	var tfit := Kit45.fit(m, tag, false, 30.0 * s, 640.0 * s)
	if tag != "" and f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfit).x > 640.0 * s:
		tag = ""                                       # designer 11 FIX 2: a small screen has no room for it at the floor
	if tag != "":
		var tfs := tfit
		var tw := f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		var p := _r(404.0, 970.0, 0, 0).position
		draw_string(f, Vector2(p.x - tw / 2.0, p.y + (f.get_ascent(tfs) - f.get_descent(tfs)) / 2.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color("d9c0b3"))
	var rows := [[["SPD", "speed"], ["HP", "health"]], [["ATK", "attack"], ["PROD", "production"]], [["GARRISON", "garrison"], ["", ""]]]
	var ys := [1110.0, 1170.0, 1230.0] if _compact() else [1206.0, 1240.0, 1274.0]
	var cols := [[116.0, 380.0], [430.0, 690.0]]
	for i in range(rows.size()):
		for j in range(rows[i].size()):
			var k: String = rows[i][j][0]
			if k == "":
				continue
			var v := _st(rows[i][j][1])
			var vt := "%d%%" % v
			var p := _r(cols[j][0], ys[i], 0, 0).position
			draw_string(f, Vector2(p.x, p.y + asc), k, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("e7b68b"))
			var vc := UP if v > 100 else (DOWN if v < 100 else Color("faead1"))
			var vw := f.get_string_size(vt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var q := _r(cols[j][1] if k != "GARRISON" else 560.0, ys[i], 0, 0).position
			q.x = maxf(q.x, p.x + f.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0 * s + vw)   # FIX 2: never on its label
			draw_string(f, Vector2(q.x - vw, q.y + asc), vt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, vc)
	for sub in [["Combat skills on every map", 608.0], ["Relay skills require a map with relays", 972.0]]:
		var sfs := Kit45.fit(m, sub[0], false, 34.0 * s, 1080.0 * s)
		var p2 := _r(1620.0, sub[1], 0, 0).position
		draw_string(f, Vector2(p2.x, p2.y + (f.get_ascent(sfs) - f.get_descent(sfs)) / 2.0), sub[0], HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color("d9c0b3"))


func _text_for(e: Dictionary) -> Array:
	## The runtime words for a text element: [lines...] (empty = the delivered text).
	var cid: String = _el_ctrl.get(e["id"], "")
	if cid.begins_with("FACTION-"):
		return [UiKit.NAMES[_faction_of(cid)]]
	if _skill_of.has(cid):
		var nm := ArmyPresets.skill_name(_skill_of[cid]).to_upper()
		nm = SHORT.get(nm, nm)                         # designer 10: the mock's short name (EVAC), one line
		var parts: Array = []
		for ch in _ctrl[cid]["children"]:
			for x in _els:
				if x["id"] == ch and x["type"] == "text":
					parts.append(ch)
		if parts.size() > 1:
			var w := nm.split(" ")
			var half := ceili(w.size() / 2.0)
			var l1 := " ".join(w.slice(0, half))
			var l2 := " ".join(w.slice(half))
			return [l1 if parts[0] == e["id"] else l2]
		return [nm]
	var ult: String = Rules.FACTION_ULTIMATE_ID.get(army, "")
	var ftrait: Array = Rules.faction_trait(army)
	match e["id"]:
		"e054": return [str(UiKit.SUBS.get(army, "")) if str(UiKit.SUBS.get(army, "")) != "" else "OOZE"]
		"e055": return [UiKit.NAMES[army]]
		"e059": return ["TRAIT  /  " + str(ftrait[0]).to_upper()]   # the remake: TRAIT / name, then the stats table (_draw_stats)
		"e060" when _compact(): return [""]                 # a small screen (floor 12.5 pt): the trait name + the stats table only
		"e061" when _compact(): return [""]
		"e060", "e061":
			var lines := _wrap(str(ftrait[1]), e, 580.0)
			var i := 0 if e["id"] == "e060" else 1
			return [lines[i] if i < lines.size() else ""]
		"e062", "e063": return [""]
		"e070": return [ArmyPresets.skill_name(ult).to_upper()]
		"e071": return ["~%d s charge" % int(Rules.ult_charge_time(ult))]
	return [str(e.get("text", ""))]


func _compact() -> bool:
	## The phone's 12.5 pt floor is well over the delivered 9 pt body text (a 16:9 phone: the body scales down to fit).
	return m != null and float(UiKit.px(m, 0.0)) > 37.0 * s * 1.25


func _stats1() -> String:
	return "SPD %d   HP %d   ATK %d" % [_st("speed"), _st("health"), _st("attack")]


func _stats2() -> String:
	return "PROD %d    GARRISON %d" % [_st("production"), _st("garrison")]


func _st(k: String) -> int:
	return roundi(Rules.stat(army, k) * 100.0)


func _font_of(e: Dictionary) -> Font:
	return UiKit.HEAD if str(e["font"].get("role", "")) == "title" else UiKit.BODY


func _wrap(t: String, e: Dictionary, room4x: float) -> Array:
	## The trait line split in two at the element's font size (whole words).
	var f := _font_of(e)
	var fs := maxi(1, roundi(maxf(float(e["font"]["size_px"]) * s, float(UiKit.px(m, 0.0)) if m != null else 0.0)))
	var room := room4x * s
	var out: Array = []
	var cur := ""
	for word in t.split(" "):
		var tryl := word if cur == "" else cur + " " + word
		if cur != "" and f.get_string_size(tryl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room and out.size() < 1:
			out.append(cur)
			cur = word
		else:
			cur = tryl
	out.append(cur)
	return out


func _room(e: Dictionary) -> float:
	## The widest a label may grow (4x px) before it shrinks: its face / tab / cabinet.
	var cid: String = _el_ctrl.get(e["id"], "")
	var fam: String = _ctrl[cid]["family"] if cid != "" else ""
	match fam:
		"SKILL-CARD": return 264.0
		"FACTION-TAB": return 236.0
		"SECTION-TAB": return 384.0
		"RESET-BUTTON": return 184.0
	match e["id"]:
		"e054", "e055": return 560.0
		"e070": return 440.0
		"e071": return 1000.0
	return 600.0


func _draw_text(e: Dictionary, st: String, bd: Dictionary, font_floor: float) -> void:
	var scid: String = _el_ctrl.get(e["id"], "")
	if _skill_of.has(scid):
		_skill_name(e, scid, st, bd)
		return
	var lines := _text_for(e)
	var t: String = lines[0]
	if t == "":
		return
	var f := _font_of(e)
	var fs := maxf(float(e["font"]["size_px"]) * s, font_floor)
	var room := _room(e) * s
	while fs > font_floor * 0.8 and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(fs))).x > room:
		fs -= 0.5
	var two: Array = []
	while fs > font_floor * 0.8 and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(fs))).x > room:
		fs -= 0.5                                    # one line first (SPORE BURST): down to 80 % of the floor
	if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(fs))).x > room and t.contains(" "):
		var w := t.split(" ")                        # still too wide (EMERGENCY EVAC): two lines in the face
		var half := ceili(w.size() / 2.0)
		two = [" ".join(w.slice(0, half)), " ".join(w.slice(half))]
		fs = maxf(float(e["font"]["size_px"]) * s, font_floor)
		while fs > font_floor * 0.8 and maxf(f.get_string_size(two[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(fs))).x,
				f.get_string_size(two[1], HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(fs))).x) > room:
			fs -= 0.5
	var ifs := maxi(1, int(round(fs)))
	var col := Color(e["color"])
	if bd.has("text_colors") and st != "":
		col = Color(bd["text_colors"][st])
		if st == "SELECTED" and _el_ctrl.get(e["id"], "") in ["SKILLS", "CUSTOMIZE"]:
			col = Kit45.INK_CREAM                      # 45B2: cream on the copper SELECTED tab
	elif e.has("state_colors") and st != "":
		col = Color(e["state_colors"].get(st, e["color"]))
	var ap: Array = e.get("anchor_position", [e["x"], e["y"] + e["h"] / 2.0])
	var p := origin + (Vector2(ap[0], ap[1]) - BODY.position) * s
	var asc := f.get_ascent(ifs)
	var desc := f.get_descent(ifs)
	if not two.is_empty():
		var lh := float(ifs) * 1.05                  # the delivered FOG OF / WAR spacing (40 px at 36 px)
		for i in range(2):
			var w2 := f.get_string_size(two[i], HORIZONTAL_ALIGNMENT_LEFT, -1, ifs).x
			draw_string(f, Vector2(p.x - w2 / 2.0, p.y + (asc - desc) / 2.0 + (i - 0.5) * lh), two[i], HORIZONTAL_ALIGNMENT_LEFT, -1, ifs, col)
		return
	var sz := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, ifs)
	var x := p.x - sz.x / 2.0 if str(e["anchor"]).begins_with("m") else p.x
	var y := p.y + (asc - desc) / 2.0
	draw_string(f, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, ifs, col)
