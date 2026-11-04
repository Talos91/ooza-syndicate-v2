class_name NavBar
extends Control
## The app shell's bottom tab bar (Alpha 21 UI pass, Daniele's navigation mockups 2026-09-28): HOME / PLAY /
## ARMIES / CAMPAIGN, the open one lit in the faction accent. Full screen width at the foot of every shell
## page, tabs at least 44 pt tall on phones. A tab calls Menu._on_tab(id) itself (0.22.1: bound to the Menu, which outlives a page rebuild).

signal tab_pressed(id: String)

const TABS := [["home", "HOME"], ["play", "PLAY"], ["armies", "ARMIES"], ["campaign", "CAMPAIGN"], ["profile", "PROFILE"]]

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
	var sf: Vector4 = menu.safe                        # the back reaches over the notch bands and the home indicator
	add_child(UiKit.rect(Vector2(-sf.x, 0), Vector2(w + sf.x + sf.z, h + sf.w), UiKit.BAR))
	add_child(UiKit.rect(Vector2(-sf.x, 0), Vector2(w + sf.x + sf.z, 1.0), Color(acc, 0.25)))
	var longest := 0.0                               # every tab as wide as the longest label needs (phones grow the text)
	for t in TABS:
		longest = maxf(longest, UiKit.text_w(menu, t[1], 15, true))
	var tw := minf(maxf(150.0, longest + 48.0), (w - 40.0) / TABS.size())
	var x0 := (w - tw * TABS.size()) / 2.0
	for i in range(TABS.size()):
		var id: String = TABS[i][0]
		# UI (0.22.1): through the Menu (it outlives a rebuild during the tap's flash frame), not this bar's signal
		var b := UiKit.make_btn(menu, TABS[i][1], Vector2(tw - 12.0, th), Callable(menu, "_on_tab").bind(id),
				"selected" if id == active else "tertiary", f, 15)
		if id != active:
			b.add_theme_color_override("font_color", UiKit.MUTED)
		b.position = Vector2(x0 + i * tw + 6.0, (h - b.size.y) / 2.0)
		add_child(b)
		buttons[id] = b
