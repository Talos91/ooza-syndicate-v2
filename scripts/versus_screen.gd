class_name VersusScreen
extends CanvasLayer
## VERSUS (Alpha 21 UI pass, screen system 15): the card between DEPLOY (or a campaign mission's START) and the
## battle - your side left (YOU / SEAT A, with any AI allies; you by your name), the rivals right (RIVAL / SEAT B; free-for-alls and
## teams: every rival's faction, compact), VS between them, the map / mode / difficulty line, ENTER BATTLE. A tap
## anywhere, a key, or AUTO_SECONDS goes on. It sits over the freshly built match, which is held paused until then
## (hold_match / hold_mission), so the match's own set-up and clock are untouched - it only starts a moment later.
## Never shown for lessons, the dedicated host, headless runs or command-line match / screenshot runs (wanted());
## a RESTART / REMATCH relaunches straight into the match (main._ready -> _start_map), so it never slows repeated
## play; a campaign RETRY (the same mission again, relaunched) skips it too. Canvas units like the menu's shell
## pages (UiKit), >= 44 pt / 12.5 pt on phones.
## ONLINE (0.22.3, Daniele 2026-09-29: "every time you press DEPLOY you can see the map loading"): a room's round
## shows the card too (hold_online, from main._start_online), as a loading screen: it covers the map build and the
## warm-up and only goes once this client is loaded (Warmup gone, a few frames drawn), the round runs (Net.started:
## the host's loading barrier passed) and - a guest - the first snapshot is in; at least Rules.VERSUS_ONLINE_MIN s,
## at most Rules.VERSUS_ONLINE_MAX s (then the HUD's waiting text takes over). It never pauses or holds the match:
## the host's clock and the barrier are untouched (the fairness rules stay). A tap / key before that does nothing;
## the countdown line says what it waits for. Nothing runs once it has gone (it frees itself).

signal finished

const AUTO_SECONDS := 3.0
const STAGE_FLOOR := 0.8                           # the stages' platform ring centre (fraction of the art's height)
const SKIP_ARGS := ["--map=", "--demo", "--shots=", "--ff=", "--menu-", "--mission", "--tutorial=", "--scenario=",
		"--thumb=", "--focus="]
static var last_mission := ""                      # the mission the card was last offered for (its RETRY skips it)
static var _mission_ok := false                    # start_mission's verdict, used by the next _mission_start

var main: Node
var mobile := false
var content: Control
var mission_key := ""
var _t := 0.0
var _left := 0.0                                   # seconds before AUTO continues (the countdown line)
var _count: Label
var _gone := false
var _shot := ""
var online := false                                # ONLINE: a room's round (hold_online) - a loading screen, not a hold
var net: Node = null                               # ONLINE: the Net the card watches (the autoload; tests hand in theirs)
var _frames := 0                                   # ONLINE: frames drawn under the card (the warm-up needs a few)


# ------------------------------------------------------------------ when (main.gd's hooks)
static func wanted(m) -> bool:
	## The card only for a match picked in the menu, on a screen, by a player.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--versus-shot="):              # the screenshot helper asks for it
			return true
	if Net.dedicated or m.online or m.director != null or DisplayServer.get_name() == "headless":
		return false
	for a in OS.get_cmdline_user_args():
		for p in SKIP_ARGS:
			if a.begins_with(p):
				return false
	return true


static func hold_match(m) -> void:
	## After main.start_match's _start_map (the match built, running): pause it under the card; the card's end resumes it.
	if not wanted(m):
		return
	m.paused = true
	var v := VersusScreen.new()
	v.main = m
	v.finished.connect(func(): m.paused = false)
	m.add_child(v)


static func hold_online(m) -> bool:
	## main._start_online, after _start_map: the card over a room's round while it loads (never the room server's
	## match host, a lesson, a headless run). The match is not paused: Net's barrier and the host's clock run as before.
	if Net.dedicated or m.director != null or DisplayServer.get_name() == "headless":
		return false
	for a in OS.get_cmdline_user_args():
		for p in SKIP_ARGS:
			if a.begins_with(p):
				return false
	var v := VersusScreen.new()
	v.main = m
	v.online = true
	v.net = Net
	m.add_child(v)
	return true


func online_loaded() -> bool:
	## ONLINE: this client's world is built and its effects warmed (Warmup freed itself; a few frames drawn).
	return _frames > Rules.WARMUP_FRAMES + 1 and main.get_node_or_null("Warmup") == null


func online_ready() -> bool:
	## ONLINE: the battlefield may show - loaded here, the round running (the barrier passed), a guest's first snapshot in.
	if not online_loaded() or net == null or not bool(net.started):
		return false
	return bool(net.hosting) or int(net._rx_snaps) > 0


func online_done() -> bool:
	## ONLINE: the card may go - ready and on screen for VERSUS_ONLINE_MIN, or VERSUS_ONLINE_MAX passed (the HUD says why).
	return (online_ready() and _t >= Rules.VERSUS_ONLINE_MIN) or _t >= Rules.VERSUS_ONLINE_MAX


func online_wait_text() -> String:
	## ONLINE: the countdown line - what the card still waits for.
	if not online_loaded():
		return "LOADING THE BATTLEFIELD…"
	if net == null or not bool(net.started):
		return "WAITING FOR EVERY PLAYER TO LOAD…"
	if not bool(net.hosting) and int(net._rx_snaps) == 0:
		return "WAITING FOR THE HOST'S FIRST FRAME…"
	return "ENTERING BATTLE…"


static func note_mission(key: String, from_menu: bool) -> void:
	## main.start_mission: the card for a mission started from the campaign page or a new one (NEXT MISSION), not for
	## a RETRY of the same mission.
	_mission_ok = from_menu or key != last_mission
	last_mission = key


static func hold_mission(m) -> bool:
	## main._mission_start (the briefing's START): true = the card is up and calls _mission_start again when it ends.
	if not _mission_ok or not wanted(m):
		return false
	_mission_ok = false
	m.paused = true                                   # (--mission-start comes here unpaused)
	var v := VersusScreen.new()
	v.main = m
	v.mission_key = str(m.mission.key) if m.mission != null else ""
	v.finished.connect(func(): m._mission_start())
	m.add_child(v)
	return true


# ------------------------------------------------------------------ the card
func _ready() -> void:
	layer = 6                                        # over the HUD (1) and the mission overlay (3)
	mobile = bool(main.mobile)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--versus-shot="):
			_shot = a.substr(14)
	_left = AUTO_SECONDS
	get_viewport().size_changed.connect(_build)
	_build()
	if _shot != "":
		_shoot()


func _pt_factor() -> float:
	## Menu._pt_factor's rule (UiKit reads it): raw unit -> pt at the live fit, 0.0 on desktop.
	if not mobile:
		return 0.0
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return 0.0
	return UiKit.K * minf(vp.x / 1280.0, vp.y / 720.0) * UiKit.pt_per_px(vp)


func _sides() -> Array:
	## [your side, the rivals]: seat letters, yours first. Allies (team modes) stand with you.
	var you := str(main.HUMAN)
	var mine := [you]
	var them := []
	var seats: Array = main.sim.factions.keys()
	seats.sort()
	for s in seats:
		if str(s) == you:
			continue
		if main.sim.allied(str(s), you):
			mine.append(str(s))
		else:
			them.append(str(s))
	return [mine, them]


func _build() -> void:
	if _gone:
		return
	if is_instance_valid(content):
		content.queue_free()
	var vp := get_viewport().get_visible_rect().size
	var s := minf(vp.x / 1280.0, vp.y / 720.0)
	var ins := UiKit.safe_insets(vp)                   # inside the notch / home-indicator bands
	content = Control.new()
	content.position = Vector2(ins.x, ins.y)
	content.size = (vp - Vector2(ins.x + ins.z, ins.y + ins.w)) / s
	content.scale = Vector2(s, s)
	content.mouse_filter = Control.MOUSE_FILTER_STOP     # a tap anywhere goes on (and nothing reaches the board)
	content.gui_input.connect(_on_input)
	add_child(content)
	var W := content.size.x
	var H := content.size.y
	var you := str(main.HUMAN)
	var yf := str(main.SEAT_FACTIONS[you])
	var acc := UiKit.accent(yf)
	var full := Rect2(-Vector2(ins.x, ins.y) / s, vp / s)   # the art still fills the whole screen (bands too)
	var sides := _sides()
	# Daniele's FINAL VERSUS art (2026-09-28): each side on its own faction's empty stage, split down the middle -
	# placed once the sides are laid out, so each creature stands on its platform
	var hw := full.size.x / 2.0
	var stages := [_stage_half(Rect2(full.position, Vector2(hw, full.size.y))),
			_stage_half(Rect2(full.position + Vector2(hw, 0), Vector2(hw, full.size.y)))]
	var shade := UiKit.rect(full.position, full.size, Color(UiKit.BASE, 0.0))
	shade.mouse_filter = Control.MOUSE_FILTER_STOP     # a tap in a band goes on too (never to the board)
	shade.gui_input.connect(_on_input)
	content.add_child(shade)
	_wash(Rect2(full.position.x + hw - 150.0, full.position.y, 300.0, full.size.y), true)   # the seam, under VS
	_wash(Rect2(full.position.x, full.end.y - 210.0, full.size.x, 210.0), false)           # the foot
	var x := maxf(26.0, W * 0.024)
	var top := 26.0 if mobile else 40.0
	var bh := UiKit.tap_h(self, 50.0)
	var info_h := UiKit.line_h(self, 15, true)
	var hint_h := UiKit.line_h(self, 12)
	var foot := bh + info_h + hint_h + 30.0
	var col_h := H - top - foot - 20.0
	var half := (W - x * 2.0) * 0.4
	var floor0 := _side(sides[0], Vector2(x, top), Vector2(half, col_h), true)
	var floor1 := _side(sides[1], Vector2(W - x - half, top), Vector2(half, col_h), false)
	_place_stage(stages[0], _side_faction(sides[0], yf), floor0 if floor0 > 0.0 else floor1)
	_place_stage(stages[1], _side_faction(sides[1], yf), floor1 if floor1 > 0.0 else floor0)
	# VS, its glow, between the two
	var vs_c := Vector2(W / 2.0, top + col_h * 0.45)
	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(acc, 0.42))
	grad.set_color(1, Color(acc, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.size = Vector2(260, 260)
	glow.position = vs_c - glow.size / 2.0
	content.add_child(glow)
	var vs := UiKit.label(self, "VS", 76, acc, true)
	vs.add_theme_color_override("font_outline_color", Color(acc.darkened(0.6), 0.9))
	vs.add_theme_constant_override("outline_size", 10)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.size = Vector2(240, UiKit.line_h(self, 76, true))
	vs.position = vs_c - vs.size / 2.0
	vs.pivot_offset = vs.size / 2.0
	content.add_child(vs)
	# the line, ENTER BATTLE, the countdown
	var y := H - foot
	var line := UiKit.label(self, _info_line(), 15, UiKit.INK, true, 2)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.size = Vector2(W, info_h)
	line.position = Vector2(0, y)
	content.add_child(line)
	y += info_h + 12.0
	var bt := "ENTER BATTLE  →"
	var bw := UiKit.text_w(self, bt, 17, true) + 56.0
	var b := UiKit.make_btn(self, bt, Vector2(bw, 50), _go, "primary", yf, 17)
	b.position = Vector2((W - bw) / 2.0, y)
	content.add_child(b)
	y += b.size.y + 8.0
	_count = UiKit.label(self, "", 12, UiKit.DIM, true, 2)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.size = Vector2(W, hint_h)
	_count.position = Vector2(0, y)
	content.add_child(_count)
	_tick_text()
	if _t == 0.0:                                     # the entrance, once: VS lands, the sides slide in
		vs.scale = Vector2(1.6, 1.6)
		vs.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(vs, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(vs, "modulate:a", 1.0, 0.25)


func _side_faction(seats: Array, fallback: String) -> String:
	return str(main.SEAT_FACTIONS[seats[0]]) if not seats.is_empty() else fallback


func _stage_half(r: Rect2) -> TextureRect:
	## One half of the screen, clipped, for a side's stage (its art placed by _place_stage).
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = r.position
	clip.size = r.size
	content.add_child(clip)
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.modulate = Color(0.82, 0.84, 0.88)
	clip.add_child(t)
	return t


func _place_stage(t: TextureRect, f: String, floor_y: float) -> void:
	## The faction's stage covering its half, scaled / shifted so the platform's centre (STAGE_FLOOR) sits at
	## `floor_y` (page units) - where the side's creatures stand.
	t.texture = UiKit.stage(f)
	var clip := t.get_parent() as Control
	var r := Rect2(clip.position, clip.size)
	var fy := clampf(floor_y - r.position.y, r.size.y * 0.3, r.size.y * 0.95)   # in the half's own units
	var cover := maxf(r.size.x, r.size.y)
	var side := clampf(maxf(fy / STAGE_FLOOR, (r.size.y - fy) / (1.0 - STAGE_FLOOR)), cover, cover * 1.35)   # zoom capped:
	t.size = Vector2(side, side)                                    # a high floor line (FFA rows) lets the platform sit lower
	t.position = Vector2((r.size.x - side) / 2.0, clampf(fy - side * STAGE_FLOOR, r.size.y - side, 0.0))


func _wash(r: Rect2, across: bool) -> void:
	## A dark wash: `across` = a vertical seam band (dark in its middle), else a foot band (dark at its bottom).
	var g := Gradient.new()
	g.set_color(0, Color(UiKit.BASE, 0.0))
	if across:
		g.add_point(0.5, Color(UiKit.BASE, 0.62))
		g.set_color(g.get_point_count() - 1, Color(UiKit.BASE, 0.0))
	else:
		g.set_color(1, Color(UiKit.BASE, 0.88))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2.ZERO
	gt.fill_to = Vector2(1, 0) if across else Vector2(0, 1)
	var w := TextureRect.new()
	w.texture = gt
	w.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.position = r.position
	w.size = r.size
	content.add_child(w)


func _side(seats: Array, pos: Vector2, dims: Vector2, mine: bool) -> float:
	## One side: the kicker, then each seat's character (standing on the side's stage), emblem, name and seat (one
	## large; several smaller, side by side). Returns the floor line the side's front row stands on (0: no seats).
	if seats.is_empty():
		return 0.0
	var f0 := str(main.SEAT_FACTIONS[seats[0]])
	var kick := ("YOU / SEAT %s" % seats[0]) if mine else ("RIVAL / SEAT %s" % seats[0] if seats.size() == 1 else "RIVALS")
	if mine and seats.size() > 1:
		kick = "YOUR TEAM"
	var k := UiKit.label(self, kick, 13, UiKit.accent(f0) if (mine or seats.size() == 1) else UiKit.INK, true, 3)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.size = Vector2(dims.x, UiKit.line_h(self, 13, true))
	k.position = pos
	var kw := UiKit.text_w(self, kick, 13, true) + kick.length() * 3.0 + 28.0   # on a dark plate: the sky is bright
	content.add_child(UiKit.rect(Vector2(pos.x + (dims.x - kw) / 2.0, pos.y - 5.0), Vector2(kw, k.size.y + 10.0),
			Color(UiKit.BASE, 0.82)))
	content.add_child(k)
	var n := seats.size()
	var name_h := UiKit.line_h(self, 34 if n == 1 else 18, true) + UiKit.line_h(self, 12) + 8.0
	var gap := 12.0
	# one row, or two (3+ seats: FFA 4 / 5, 3v3) when that makes the characters bigger - the side's height is there
	var room := dims.y - k.size.y - 12.0
	var cols := n
	var hs := minf(room - name_h, (dims.x - gap * (n - 1)) / float(n))
	if n >= 3:
		var c2 := int(ceil(n / 2.0))
		var hs2 := minf((room - 2.0 * name_h - gap) / 2.0, (dims.x - gap * (c2 - 1)) / float(c2))
		if hs2 > hs:
			cols = c2
			hs = hs2
	var rows := int(ceil(n / float(cols)))
	var block_h := rows * (hs + name_h) + (rows - 1) * gap
	var y0 := pos.y + k.size.y + 12.0 + (room - block_h) / 2.0
	var from := -60.0 if mine else 60.0
	var floor_y := y0 + (rows - 1) * (hs + name_h + gap) + hs * 0.97   # the front (last) row's feet
	for i in range(n):
		var seat := str(seats[i])
		var f := str(main.SEAT_FACTIONS[seat])
		var cell := Control.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var r := i / cols
		var in_row := mini(cols, n - r * cols)              # a short last row is centred on its own
		var row_w := hs * in_row + gap * (in_row - 1)
		cell.position = Vector2(pos.x + (dims.x - row_w) / 2.0 + (i % cols) * (hs + gap), y0 + r * (hs + name_h + gap))
		cell.size = Vector2(hs, hs + name_h)
		content.add_child(cell)
		var hero := UiKit.hero(self, f, Vector2.ZERO, Vector2(hs, hs), false)
		content.remove_child(hero)                    # the cutout, into the cell (on the stage: no glow)
		cell.add_child(hero)
		var who := _title_of(seat, f)
		if n > 1:                                    # compact: one short line under the name
			who[1] = _compact_of(seat, f)
		var lw := hs + gap if n > 1 else maxf(hs, 160.0)
		var fs := 34 if n == 1 else 18
		var nh := UiKit.line_h(self, fs, true)
		var es := nh * 0.9                            # the race emblem, left of the name
		var name_w := minf(UiKit.text_w(self, str(who[0]), fs, true), lw - es - 8.0)
		var plate := UiKit.rect(Vector2((hs - lw) / 2.0, hs + 2.0), Vector2(lw, nh + UiKit.line_h(self, 12) + 12.0),
				Color(UiKit.BASE, 0.8))                # the name reads on the bright platform
		cell.add_child(plate)
		var em := TextureRect.new()
		em.texture = UiKit.emblem(f, es)
		em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		em.mouse_filter = Control.MOUSE_FILTER_IGNORE
		em.size = Vector2(es, es)
		em.position = Vector2((hs - name_w - es - 8.0) / 2.0, hs + 4.0 + (nh - es) / 2.0)
		cell.add_child(em)
		var nm := UiKit.label(self, who[0], fs, UiKit.INK, true)
		nm.clip_text = true
		nm.size = Vector2(name_w + 4.0, nh)
		nm.position = Vector2(em.position.x + es + 8.0, hs + 4.0)
		cell.add_child(nm)
		var sub := UiKit.label(self, who[1], 12, UiKit.MUTED, true, 2)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.clip_text = true
		sub.size = Vector2(lw, UiKit.line_h(self, 12))
		sub.position = Vector2((hs - sub.size.x) / 2.0, nm.position.y + nm.size.y)
		cell.add_child(sub)
		var dot := UiKit.rect(Vector2((hs - 36.0) / 2.0, sub.position.y + sub.size.y + 4.0), Vector2(36, 3), Rules.seat_color(seat))
		cell.add_child(dot)                          # the seat's ownership colour (never the faction accent)
		if _t == 0.0:
			var end := cell.position
			cell.position.x += from
			cell.modulate.a = 0.0
			var tw := create_tween().set_parallel(true)
			tw.tween_property(cell, "position", end, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.05 * i)
			tw.tween_property(cell, "modulate:a", 1.0, 0.3).set_delay(0.05 * i)
	return floor_y


func _title_of(seat: String, f: String) -> Array:
	## [name, caption] under a character. HUD pass (Daniele: "if the user is a human his name needs to be shown ...
	## instead of his faction only"): a human by the player's name over the faction; an AI by its faction over its
	## level ("MAW  ·  VETERAN AI"); a mission's rival by its name.
	var nm: String = UiKit.NAMES.get(f, f.to_upper())
	var sub: String = UiKit.SUBS.get(f, "")
	if mission_key != "" and seat != str(main.HUMAN):
		var r := Campaign.rival_of(Campaign.mission(mission_key))
		return [str(r.get("name", nm)), "%s  ·  %s" % [nm, sub]]
	var w: Dictionary = main.seat_who(seat) if main.has_method("seat_who") else {}
	if bool(w.get("human", false)):
		return [str(w["name"]) if str(w["name"]) != "" else "PLAYER", "%s  ·  %s" % [nm, sub]]
	if not w.is_empty():
		return [nm, "%s  ·  %s" % [sub, str(w["tag"])]]
	return [nm, "%s  ·  SEAT %s" % [sub, seat]]


func _compact_of(seat: String, f: String) -> String:
	## The one short line under a name when a side shows several seats: a human's faction (yours: YOU first), an
	## AI's level.
	var w: Dictionary = main.seat_who(seat) if main.has_method("seat_who") else {}
	if w.is_empty():
		return ("YOU  ·  SEAT %s" if seat == str(main.HUMAN) else "SEAT %s") % seat
	if bool(w["human"]):
		return ("YOU  ·  %s" if bool(w["you"]) else "%s") % str(UiKit.NAMES.get(f, f.to_upper()))
	return str(w["tag"])


func _info_line() -> String:
	var mp := str(main.map.get("name", "")).replace("*", "").to_upper()
	if mission_key != "":
		return "%s  ·  CAMPAIGN  ·  %s" % [mp, str(main.ai_level).to_upper()]
	if online and net != null:
		return "%s  ·  %s  ·  ROOM %s  ·  ROUND %d" % [mp, Menu.MODE_NAMES.get(str(main.mode), str(main.mode)), str(net.room_code), int(net.match_round)]
	return "%s  ·  %s  ·  %s" % [mp, Menu.MODE_NAMES.get(str(main.mode), str(main.mode)), str(main.ai_level).to_upper()]


func _tick_text() -> void:
	if not is_instance_valid(_count):
		return
	if online:
		_count.text = online_wait_text()
		return
	_count.text = "TAP ANYWHERE  ·  STARTING IN %d" % maxi(1, int(ceil(_left)))


func _process(dt: float) -> void:
	if _gone:
		return
	if online:                                       # a loading screen: goes by itself once loaded, running and MIN up
		_frames += 1
		_tick_text()
		if _shot != "":                              # (the screenshot helper: the line is live, the card stays)
			return
		_t += dt
		if online_done():
			_go()
		return
	if _shot != "":
		return
	_t += dt
	_left -= dt
	_tick_text()
	if _left <= 0.0:
		_go()


func _on_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
		get_viewport().set_input_as_handled()          # (the content or the full-screen shade: either took it)
		_go()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		get_viewport().set_input_as_handled()
		_go()


func _go() -> void:
	## On to the battle: once, the card fades, the match runs.
	if _gone or (online and not online_done()):      # ONLINE: a tap can't reveal a battlefield that isn't there yet
		return
	_gone = true
	finished.emit()
	var tw := create_tween()
	tw.tween_property(content, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)


func _shoot() -> void:
	## --versus-shot=<png>: the card once its entrance has played, saved, then quit.
	for i in range(50):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot)
	print("screenshot ", _shot)
	get_tree().quit()
