class_name RewardTicker
extends Control
## A currency reward that counts up: "+140 SCRAP" with the currency's mark (PROGRESSION-DESIGN §8). For the tutorial's
## LESSON COMPLETE card, the match result's rewards strip and challenge claims. At most 280 x 44 pt; sized through a pt
## helper (the caller's, e.g. CoachOverlay._pt, or n * visible height / 390). No dependency on who shows it.
##   var t := RewardTicker.make(Rules.PROGRESSION["tutorial_lesson"], "soft", _pt)
##   card.add_child(t); t.play(); await t.finished
## The marks are drawn here (a hex nut for SCRAP, a chip for SYNDICATE CHIPS) until approved icons exist.

signal finished

const HEAD_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")
const COLOURS := {"soft": Color("e08a3a"), "premium": Color("f2c14e")}
const EDGE := Color(0.06, 0.07, 0.08, 0.9)
const MAX_W := 280.0
const H := 36.0                                    # pt, under the 44 pt ceiling

var amount := 0
var currency := "soft"
var duration := 0.9                                # seconds of counting; the pop after it is 0.25 s
var pt: Callable
var _t := -1.0                                     # < 0: not playing
var _shown := 0
var _pop := 0.0


static func make(p_amount: int, p_currency := "soft", p_pt := Callable()) -> RewardTicker:
	var t := RewardTicker.new()
	t.amount = p_amount
	t.currency = p_currency
	t.pt = p_pt
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _ready() -> void:
	_resize()


func play(instant := false) -> void:
	## Counts from 0 to `amount` (instant: shows the end at once and still emits `finished`, next frame).
	_resize()
	_t = duration if instant else 0.0
	_shown = amount if instant else 0
	set_process(true)
	queue_redraw()


func _p(n: float) -> float:
	if pt.is_valid():
		return float(pt.call(n))
	var vh := get_viewport_rect().size.y if is_inside_tree() else 390.0
	return n * vh / 390.0


func _font_size() -> int:
	return int(round(_p(H * 0.62)))


func _text() -> String:
	return Progression.amount_text(_shown, currency)


func _resize() -> void:
	var fs := _font_size()
	var w := _p(H) + _p(8) + HEAD_FONT.get_string_size(Progression.amount_text(amount, currency), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	custom_minimum_size = Vector2(minf(w + _p(6), _p(MAX_W)), _p(H))
	size = custom_minimum_size


func _process(delta: float) -> void:
	if _t < 0.0:
		set_process(false)
		return
	_t += delta
	var k := clampf(_t / maxf(duration, 0.001), 0.0, 1.0)
	_shown = int(round(amount * (1.0 - pow(1.0 - k, 3.0))))   # ease out: fast, then settles on the number
	_pop = clampf((_t - duration) / 0.25, 0.0, 1.0) if _t >= duration else 0.0
	queue_redraw()
	if _t >= duration + 0.25:
		_shown = amount
		_t = -1.0
		_pop = 0.0
		queue_redraw()
		finished.emit()


func _draw() -> void:
	var h := _p(H)
	var col: Color = COLOURS.get(currency, Color.WHITE)
	var bump := sin(_pop * PI) * 0.18                 # the mark pops once when the count lands
	var c := Vector2(h * 0.5, h * 0.5)
	var r := h * 0.42 * (1.0 + bump)
	if currency == "premium":
		draw_circle(c, r, EDGE)
		draw_circle(c, r * 0.88, col)
		for i in 8:                                  # the chip's edge notches
			var a := TAU * i / 8.0
			draw_line(c + Vector2.from_angle(a) * r * 0.62, c + Vector2.from_angle(a) * r * 0.86, EDGE, maxf(1.0, h * 0.07))
		draw_circle(c, r * 0.42, col.darkened(0.25))
	else:
		var hexa := PackedVector2Array()
		for i in 6:
			hexa.append(c + Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * r)
		draw_colored_polygon(hexa, EDGE)
		var inner := PackedVector2Array()
		for i in 6:
			inner.append(c + Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * r * 0.84)
		draw_colored_polygon(inner, col)
		draw_circle(c, r * 0.36, EDGE)               # the nut's hole
	var fs := _font_size()
	var x := h + _p(8)
	var y := h * 0.5 + fs * 0.36
	draw_string_outline(HEAD_FONT, Vector2(x, y), _text(), HORIZONTAL_ALIGNMENT_LEFT, size.x - x, fs, maxi(2, int(_p(3))), EDGE)
	draw_string(HEAD_FONT, Vector2(x, y), _text(), HORIZONTAL_ALIGNMENT_LEFT, size.x - x, fs, col.lerp(Color.WHITE, 0.35 + bump))
