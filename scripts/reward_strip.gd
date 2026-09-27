class_name RewardStrip
extends VBoxContainer
## The results screen's rewards (PROGRESSION-DESIGN §8): what the match paid (the lines + a SCRAP count-up, chips when a
## level paid some), the XP bar filling from before to after with a flash at each level-up, and one note line
## (challenges done, a faction vat unlocked, or "XP only" against easy AI). Built from Progression.record_match's
## output (main.rewards). `scale` is the HUD's ui_scale.

const UI_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const HEAD_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")
const XP_COLOUR := Color("5fd7ff")
const GOLD := Color("ffd15c")


static func make(r: Dictionary, scale: float) -> RewardStrip:
	var s := RewardStrip.new()
	s.add_theme_constant_override("separation", int(6 * scale))
	s._build(r, scale)
	return s


func _build(r: Dictionary, scale: float) -> void:
	var lines: Array = r.get("lines", [])
	var soft := 0
	var chips := 0
	var names := []
	for l in lines:
		soft += int(l.get("soft", 0))
		chips += int(l.get("premium", 0))
		if not l.has("level_up"):
			names.append(str(l["what"]))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(14 * scale))
	add_child(row)
	var what := _label(" · ".join(names), 15, scale, Color("c8e6ee"))
	row.add_child(what)
	var pt := func(n: float) -> float: return n * scale * 0.8
	var tickers := []
	if soft > 0:
		tickers.append(RewardTicker.make(soft, "soft", pt))
	if chips > 0:
		tickers.append(RewardTicker.make(chips, "premium", pt))
	for t in tickers:
		row.add_child(t)
	var bar := XpBar.new()
	bar.from_xp = int(r.get("xp_before", 0))
	bar.to_xp = int(r.get("xp_after", 0))
	bar.scale_k = scale
	bar.custom_minimum_size = Vector2(440, 26) * scale
	add_child(bar)
	var note := _note(r)
	if note != "":
		add_child(_label(note, 14, scale, GOLD))
	# the count-ups start together once the strip is on screen
	ready.connect(func():
		for t in tickers:
			t.play()
		bar.play(), CONNECT_ONE_SHOT)


static func _note(r: Dictionary) -> String:
	var parts := []
	for item in r.get("unlocked", []):
		parts.append("%s VAT UNLOCKED" % str(item).get_slice(":", 2).to_upper())
	var done: Array = r.get("challenges", [])
	if not done.is_empty():
		parts.append("%d CHALLENGE%s DONE - CLAIM %s IN CHALLENGES" % [done.size(), "S" if done.size() > 1 else "",
				"THEM" if done.size() > 1 else "IT"])
	if not r.get("full_pay", true) and parts.is_empty():
		parts.append("vs %s AI: XP only - SCRAP from Veteran up" % str(r.get("ai_level", "")).to_upper())
	return "  ·  ".join(parts)


func _label(text: String, size_value: int, scale: float, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UI_FONT)
	l.add_theme_font_size_override("font_size", int(round(size_value * scale)))
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


class XpBar extends Control:
	## LEVEL n, a bar from the XP before to after (over level-ups: fills, flashes, carries on), "+N XP".
	var from_xp := 0
	var to_xp := 0
	var scale_k := 1.0
	var duration := 1.2
	var _t := -1.0
	var _flash := 0.0
	var _last_level := -1

	func play() -> void:
		_t = 0.0
		_last_level = int(Progression.level_for(from_xp)["level"])
		set_process(true)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func _process(delta: float) -> void:
		if _t < 0.0:
			return
		_t += delta
		var lv := int(Progression.level_for(_shown())["level"])
		if lv != _last_level:
			_last_level = lv
			_flash = 1.0
		_flash = maxf(0.0, _flash - delta * 1.6)
		queue_redraw()
		if _t >= duration and _flash <= 0.0:
			set_process(false)

	func _shown() -> int:
		var k := clampf(_t / duration, 0.0, 1.0) if _t >= 0.0 else 0.0
		return int(round(lerpf(from_xp, to_xp, 1.0 - pow(1.0 - k, 2.0))))

	func _draw() -> void:
		var lf := Progression.level_for(_shown())
		var fs := int(round(14 * scale_k))
		var tag := "LEVEL %d" % int(lf["level"])
		var tag_w := HEAD_FONT.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10 * scale_k
		var col := XP_COLOUR.lerp(Color.WHITE, _flash)
		draw_string(HEAD_FONT, Vector2(0, size.y * 0.5 + fs * 0.36), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		var gain := "+%d XP" % (to_xp - from_xp)
		var gain_w := UI_FONT.get_string_size(gain, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10 * scale_k
		var bar := Rect2(tag_w, size.y * 0.25, size.x - tag_w - gain_w, size.y * 0.5)
		draw_rect(bar, Color(0.02, 0.05, 0.07, 0.9))
		var f := clampf(float(lf["into"]) / maxf(1.0, float(lf["need"])), 0.0, 1.0)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), col)
		draw_rect(bar, XP_COLOUR.darkened(0.3), false, maxf(1.0, scale_k))
		draw_string(UI_FONT, Vector2(size.x - gain_w + 10 * scale_k, size.y * 0.5 + fs * 0.36), gain, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, XP_COLOUR)
		if _flash > 0.0:
			draw_string(HEAD_FONT, Vector2(bar.position.x + bar.size.x * 0.5 - 30 * scale_k, bar.position.y - 2 * scale_k),
					"LEVEL UP", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(GOLD, _flash))
