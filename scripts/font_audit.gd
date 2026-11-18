extends RefCounted
## Dev: --font-audit=<dir> (with --mobile --pt-height=N). Opens ARMIES > SKILLS (both sections) and ARMIES > CUSTOMIZE
## (every category) for every faction, and for each view records every label drawn through the 45B kit (Kit45.draw_text,
## Armies43's own lines) plus every visible Label / Button the engine draws: its size in pt and whether an ellipsis cut it.
## Writes <dir>/audit.txt (one line per view + the labels under 12.5 pt or cut) and <dir>/<view>.png, then quits.

const FACTIONS := ["vex", "null", "bloom", "ember", "solar"]


static func run(main: Node, menu, dir: String) -> void:
	Kit45.audit_on = true
	DirAccess.make_dir_recursive_absolute(dir)
	var views: Array = []
	for f in FACTIONS:
		views.append([f, "skills", "active"])
		views.append([f, "skills", "map"])
		menu._army = f
		for c in menu._ward_cats():
			views.append([f, "customize", c])
	var p: float = UiKit.pt(menu)
	var out: Array = ["# font audit %s  viewport %s  1 canvas unit = %.4f pt  floor %d cu = %.2f pt" % [
			Time.get_datetime_string_from_system(), str(main.get_viewport().get_visible_rect().size), p,
			UiKit.px(menu, 0.0), UiKit.px(menu, 0.0) * p]]
	var worst := 999.0
	var bad := 0
	for v in views:
		menu._skill_tip = ""
		menu._ward_sel = {}
		if v[1] == "skills":
			menu._skills_slot = v[2]
			menu._army_tab = "skills"
		else:
			menu._army_tab = "customize"
			menu._ward_cat = v[2]
		menu.show_armies(v[0])
		for i in range(8):
			await main.get_tree().process_frame
		var wait := 0
		while LookThumbs.busy() and wait < 600:
			await main.get_tree().process_frame
			wait += 1
		Kit45.audit.clear()
		_redraw_all(menu)
		await RenderingServer.frame_post_draw
		var rows: Array = Kit45.audit.duplicate()
		_engine_labels(menu, p, rows)
		var name := "%s-%s-%s" % [v[1], v[0], v[2]]
		main.get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
		var mn := 999.0
		var issues := {}
		for r in rows:
			mn = minf(mn, float(r[1]))
			if float(r[1]) < 12.5 - 0.01 or r[2]:
				issues["%s @ %.2f pt%s" % [r[0], r[1], "  CUT" if r[2] else ""]] = true
		worst = minf(worst, mn)
		bad += issues.size()
		out.append("%-28s labels %3d  min %.2f pt  under/cut %d" % [name, rows.size(), mn, issues.size()])
		for t in issues:
			out.append("    " + t)
	out.append("TOTAL views %d  min %.2f pt  under-floor-or-cut %d" % [views.size(), worst, bad])
	var fa := FileAccess.open(dir.path_join("audit.txt"), FileAccess.WRITE)
	fa.store_string("\n".join(out) + "\n")
	fa.close()
	print("\n".join(out))
	main.get_tree().quit()


static func _redraw_all(n: Node) -> void:
	if n is CanvasItem:
		(n as CanvasItem).queue_redraw()
	for c in n.get_children():
		_redraw_all(c)


static func _engine_labels(n: Node, p: float, rows: Array) -> void:
	## Labels / Buttons the engine draws (Kit45.Btn keeps a transparent text for tests: skipped).
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if (n is Label or n is Button) and not (n is Kit45.Btn):
		var t: String = n.text
		var col: Color = n.get_theme_color("font_color")
		if t.strip_edges() != "" and col.a > 0.01:
			rows.append([t, n.get_theme_font_size("font_size") * p, false])
	for c in n.get_children():
		_engine_labels(c, p, rows)
