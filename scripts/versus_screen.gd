class_name VersusScreen
extends CanvasLayer
## VERSUS (Alpha 21 UI pass, screen system 15): the card between DEPLOY (or a campaign mission's START) and the
## battle - your side left (YOU / SEAT A, with any AI allies), the rivals right (RIVAL / SEAT B; free-for-alls and
## teams: every rival's faction, compact), VS between them, the map / mode / difficulty line, ENTER BATTLE. A tap
## anywhere, a key, or AUTO_SECONDS goes on. It sits over the freshly built match, which is held paused until then
## (hold_match / hold_mission), so the match's own set-up and clock are untouched - it only starts a moment later.
## Never shown for online rooms, lessons, the dedicated host, headless runs or command-line match / screenshot runs
## (wanted()); a RESTART / REMATCH relaunches straight into the match (main._ready -> _start_map), so it never slows
## repeated play; a campaign RETRY (the same mission again, relaunched) skips it too. Canvas units like the menu's
## shell pages (UiKit), >= 44 pt / 12.5 pt on phones.

signal finished

const AUTO_SECONDS := 3.0
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
	return UiKit.K * minf(vp.x / 1280.0, vp.y / 720.0) * (390.0 / vp.y)


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
	content = Control.new()
	content.size = vp / s
	content.scale = Vector2(s, s)
	content.mouse_filter = Control.MOUSE_FILTER_STOP     # a tap anywhere goes on (and nothing reaches the board)
	content.gui_input.connect(_on_input)
	add_child(content)
	var W := content.size.x
	var H := content.size.y
	var you := str(main.HUMAN)
	var yf := str(main.SEAT_FACTIONS[you])
	var acc := UiKit.accent(yf)
	var bg := TextureRect.new()                     # your faction's environment, dark, over the waiting board
	bg.texture = UiKit.background(yf)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.42, 0.45, 0.5)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.size = content.size
	content.add_child(bg)
	content.add_child(UiKit.rect(Vector2.ZERO, content.size, Color(UiKit.BASE, 0.35)))
	var sides := _sides()
	var x := maxf(26.0, W * 0.024)
	var top := 26.0 if mobile else 40.0
	var bh := UiKit.tap_h(self, 50.0)
	var info_h := UiKit.line_h(self, 15, true)
	var hint_h := UiKit.line_h(self, 12)
	var foot := bh + info_h + hint_h + 30.0
	var col_h := H - top - foot - 20.0
	var half := (W - x * 2.0) * 0.4
	_side(sides[0], Vector2(x, top), Vector2(half, col_h), true)
	_side(sides[1], Vector2(W - x - half, top), Vector2(half, col_h), false)
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


func _side(seats: Array, pos: Vector2, dims: Vector2, mine: bool) -> void:
	## One side: the kicker, then each seat's character, name and seat (one large; several smaller, side by side).
	if seats.is_empty():
		return
	var f0 := str(main.SEAT_FACTIONS[seats[0]])
	var kick := ("YOU / SEAT %s" % seats[0]) if mine else ("RIVAL / SEAT %s" % seats[0] if seats.size() == 1 else "RIVALS")
	if mine and seats.size() > 1:
		kick = "YOUR TEAM"
	var k := UiKit.label(self, kick, 13, UiKit.accent(f0) if (mine or seats.size() == 1) else UiKit.MUTED, true, 3)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.size = Vector2(dims.x, UiKit.line_h(self, 13, true))
	k.position = pos
	content.add_child(k)
	var n := seats.size()
	var name_h := UiKit.line_h(self, 34 if n == 1 else 18, true) + UiKit.line_h(self, 12) + 8.0
	var avail := dims.y - k.size.y - 12.0 - name_h
	var gap := 12.0
	var hs := minf(avail, (dims.x - gap * (n - 1)) / float(n))
	var row_w := hs * n + gap * (n - 1)
	var x0 := pos.x + (dims.x - row_w) / 2.0
	var hy := pos.y + k.size.y + 12.0 + (avail - hs) / 2.0
	var from := -60.0 if mine else 60.0
	for i in range(n):
		var seat := str(seats[i])
		var f := str(main.SEAT_FACTIONS[seat])
		var cell := Control.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.position = Vector2(x0 + i * (hs + gap), hy)
		cell.size = Vector2(hs, hs + name_h)
		content.add_child(cell)
		var hero := UiKit.hero(self, f, Vector2.ZERO, Vector2(hs, hs))
		for c in [content.get_child(content.get_child_count() - 2), hero]:   # the glow and the cutout, into the cell
			content.remove_child(c)
			cell.add_child(c)
		var who := _title_of(seat, f)
		if n > 1:                                    # compact: the seat alone under the name
			who[1] = ("YOU  ·  SEAT %s" if seat == str(main.HUMAN) else "SEAT %s") % seat
		var lw := hs + gap if n > 1 else maxf(hs, 160.0)
		var nm := UiKit.label(self, who[0], 34 if n == 1 else 18, UiKit.INK, true)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.clip_text = true
		nm.size = Vector2(lw, UiKit.line_h(self, 34 if n == 1 else 18, true))
		nm.position = Vector2((hs - nm.size.x) / 2.0, hs + 4.0)
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


func _title_of(seat: String, f: String) -> Array:
	## [name, caption] under a character: the faction and its seat; a mission's rival by its name.
	var nm: String = UiKit.NAMES.get(f, f.to_upper())
	var cap := "%s  ·  SEAT %s" % [UiKit.SUBS.get(f, ""), seat]
	if mission_key != "" and seat != str(main.HUMAN):
		var r := Campaign.rival_of(Campaign.mission(mission_key))
		return [str(r.get("name", nm)), "%s  ·  %s" % [nm, UiKit.SUBS.get(f, "")]]
	return [nm, cap]


func _info_line() -> String:
	var mp := str(main.map.get("name", "")).replace("*", "").to_upper()
	if mission_key != "":
		return "%s  ·  CAMPAIGN  ·  %s" % [mp, str(main.ai_level).to_upper()]
	return "%s  ·  %s  ·  %s" % [mp, Menu.MODE_NAMES.get(str(main.mode), str(main.mode)), str(main.ai_level).to_upper()]


func _tick_text() -> void:
	if is_instance_valid(_count):
		_count.text = "TAP ANYWHERE  ·  STARTING IN %d" % maxi(1, int(ceil(_left)))


func _process(dt: float) -> void:
	if _gone or _shot != "":
		return
	_t += dt
	_left -= dt
	_tick_text()
	if _left <= 0.0:
		_go()


func _on_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
		content.accept_event()
		_go()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		get_viewport().set_input_as_handled()
		_go()


func _go() -> void:
	## On to the battle: once, the card fades, the match runs.
	if _gone:
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
