class_name NavBar
extends Control
## The app shell's bottom tab bar (Alpha 21 UI pass, Daniele's navigation mockups 2026-09-28): HOME / PLAY /
## ARMIES / CAMPAIGN, the open one lit in the faction accent. Full screen width at the foot of every shell
## page, tabs at least 44 pt tall on phones. A tab calls Menu._on_tab(id) itself (0.22.1: bound to the Menu, which outlives a page rebuild).

signal tab_pressed(id: String)

const TABS := [["home", "HOME"], ["armies", "ARMIES"], ["profile", "PROFILE"], ["guide", "GUIDE"]]   # UX pass: no PLAY tab (HOME plays); 2026-11-05: no CAMPAIGN tab (HOME's tile)

var menu                                           # the Menu (untyped: the pieces load without menu.gd)
var active := ""
var shade: Control                               # the bar's fill (HOME, 35C2: a glass strip over the painting)
var buttons := {}                                  # id -> Button (tests, Hud.action_rect-style lookups)


static func make(m, p_active: String, f := "vex") -> NavBar:
	var n := NavBar.new()
	n.menu = m
	n.active = p_active
	if not TABS.any(func(t): return t[0] == p_active):
		n.active = "home"                              # a page without a tab of its own (CAMPAIGN since 2026-11-05) sits under HOME
	n._build(f)
	return n


func bar_height() -> float:
	return size.y


func _build(_f: String) -> void:
	## UI remake 45B (GAP-LIST §0): the 45B NAV-CABINET full width, four cream NAV-BUTTON keys (100 x 30 pt, the 43B line
	## glyphs), the open tab SELECTED = the cyan seat rim on the whole key (not an underline). Centred, the remake's 38 pt bar.
	var w: float = menu.content.size.x
	var u := minf(w / Kit45.DW, float(menu.content.size.y) / Kit45.DH)
	var h := 42.0 * u                                  # IMPORT-45B-SPEC fix 2: native 42 pt (y 333..375), buttons 6 pt clear
	size = Vector2(w, h)
	position = Vector2(0, float(menu.content.size.y) - h)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var sf: Vector4 = menu.safe                        # the cabinet reaches over the notch bands and the home indicator
	var sh := Control.new()
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.position = Vector2(-sf.x, 0)
	sh.size = Vector2(w + sf.x + sf.z, h + sf.w)
	sh.draw.connect(func():
		Kit45.nine(sh, Kit45.tex("NAV-CABINET-812x42pt-STATIC.png"), Rect2(Vector2.ZERO, sh.size), Kit45.variant("NAV-CABINET")["slice"], u))
	shade = sh
	add_child(shade)
	Bars45.ornament(self, "FLUTED-TRIM", Rect2(Vector2(23.0, 18.875) * u, Vector2(85.5, 7.75) * u))     # spec fix 1: x 23 and
	Bars45.ornament(self, "FLUTED-TRIM", Rect2(Vector2(w - (Kit45.DW - 673.0) * u, 18.875 * u), Vector2(85.5, 7.75) * u))   # x 673, cy 355.75
	Bars45.bolts(self, size, u)
	var span := 100.0 * TABS.size() + 6.0 * (TABS.size() - 1)
	var x0 := (w - span * u) / 2.0
	for i in range(TABS.size()):
		var id: String = TABS[i][0]
		var b := Kit45.Btn.new()
		b.m = menu
		b.fam = "NAV-BUTTON"
		b.key = "100x30pt"
		b.label = TABS[i][1]
		b.u = u
		b.selected = id == active
		b.glyph = Kit45.art("NAV-%s-INK" % id.to_upper())
		b.glyph_rect = Rect2(11, 7, 15, 16)
		b.size_pt = 12.5
		var hit := maxf(30.0 * u, Kit45.MIN_HIT * u)
		b.position = Vector2(x0 + i * 106.0 * u, 6.0 * u - (hit - 30.0 * u) / 2.0)
		b.size = Vector2(100.0 * u, hit)
		b.art = Rect2(Vector2(0, (hit - 30.0 * u) / 2.0), Vector2(100.0, 30.0) * u)
		# UI (0.22.1): through the Menu (it outlives a rebuild during the tap's flash frame), not this bar's signal
		b.pressed.connect(Callable(menu, "_on_tab").bind(id))
		add_child(b)
		buttons[id] = b
