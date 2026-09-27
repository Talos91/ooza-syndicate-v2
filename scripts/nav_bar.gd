class_name NavBar
extends Control
## The app shell's bottom tab bar (Alpha 21 UI pass, Daniele's navigation mockups 2026-09-28): HOME / PLAY /
## ARMIES / CAMPAIGN, the open one lit in the faction accent. Full screen width at the foot of every shell
## page, tabs at least 44 pt tall on phones. Menu routes `tab_pressed(id)` to its pages.

signal tab_pressed(id: String)

const TABS := [["home", "HOME"], ["play", "PLAY"], ["armies", "ARMIES"], ["campaign", "CAMPAIGN"]]

var menu                                           # the Menu (untyped: the pieces load without menu.gd)
var active := ""
var buttons := {}                                  # id -> Button (tests, Hud.action_rect-style lookups)


static func make(m, p_active: String, f := "vex") -> NavBar:
	var n := NavBar.new()
	n.menu = m
	n.active = p_active
	n._build(f)
	return n


func bar_height() -> float:
	return size.y


func _build(f: String) -> void:
	var w: float = menu.content.size.x
	var th := UiKit.tap_h(menu, 50.0)                 # a tab
	var h := th + 10.0
	size = Vector2(w, h)
	position = Vector2(0, float(menu.content.size.y) - h)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var acc := UiKit.accent(f)
	add_child(UiKit.rect(Vector2.ZERO, size, UiKit.BAR))
	add_child(UiKit.rect(Vector2.ZERO, Vector2(w, 1.0), Color(acc, 0.25)))
	var tw := minf(160.0, (w - 40.0) / TABS.size())
	var x0 := (w - tw * TABS.size()) / 2.0
	for i in range(TABS.size()):
		var id: String = TABS[i][0]
		var on := id == active
		var pos := Vector2(x0 + i * tw + 6.0, 5.0)
		var dims := Vector2(tw - 12.0, th)
		if on:                                        # the open tab: a lit panel with a bright foot line
			var p := NeonPanel.new()
			p.position = pos
			p.size = dims
			p.accent = acc
			p.fill = Color(acc.darkened(0.8), 0.9)
			p.cut = 8.0
			add_child(p)
			add_child(UiKit.rect(pos + Vector2(10, dims.y - 3.0), Vector2(dims.x - 20.0, 3.0), acc))
		var b := UiKit.flat_button(menu, TABS[i][1], 16, UiKit.INK if on else UiKit.MUTED)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_font_override("font", UiKit.HEAD)
		b.position = pos
		b.size = dims
		b.pressed.connect(func(): tab_pressed.emit.call_deferred(id))
		add_child(b)
		buttons[id] = b
