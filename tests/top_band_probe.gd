extends Node
## TOP BAND probe (calm-pass, 2026-11-12; a dev tool, not a suite). Daniele on staging 0.24.1: "top hud bar covers ingame text".
## For every map in MapPool.test_scope() it plays an AI-vs-AI match (fixed seed) and, at several moments (start, mid game,
## Last Stand warning and drops), lists every piece of in-world text on screen - node badges, Last Stand signs, upgrade chips,
## callouts, every visible Label3D (relay tags IN / FERRY, floaters, tier labels) - and counts those that the top band covers:
## the score bar, the status line (LAST STAND · NEXT DROP ...), the banner and the catch-up tag.
## Windowed (needs a renderer), off-screen and silent:
##   Godot --path . --resolution 812x375 --audio-driver Dummy --position -6000,-6000 res://tests/top_band_probe.tscn -- \
##       --mobile --no-notice --no-telemetry tag=phone out=<file> [maps=R-01,E-01] [shots=<dir>]
## Output: one TOPBAND line per (map, moment) with the overlaps (text, rect, which band part), and a TOTAL line.

const MAIN := "res://main.tscn"
const MOMENTS := [5.0, 100.0, 200.0, 246.0, 275.0, 310.0]   # match seconds (Last Stand at 240)
const SAMPLE_FRAMES := 24                                   # frames played at each moment (every 3rd is measured)

var lines: PackedStringArray = []
var total := 0
var shots_dir := ""


func _ready() -> void:
	_run.call_deferred()


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return a.substr(name.length() + 1)
	return def


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _run() -> void:
	var out := _arg("out", "user://topband.txt")
	var tag := _arg("tag", "phone")
	shots_dir = _arg("shots", "")
	var only := _arg("maps", "")
	var main_script = load("res://scripts/main.gd")
	for path in MapPool.all():
		var code: String = path.get_file().substr(0, 4)
		if only != "" and not code in only.split(","):
			continue
		if only == "" and not code in MapPool.test_scope():
			continue
		var m := MapBuilder.load_map(path)
		var md: String = m["modes"][0]
		main_script.relaunch = {"faction": "vex", "rival": "ember", "mode": md, "map": path}
		var inst: Node = (load(MAIN) as PackedScene).instantiate()
		inst.demo = true
		inst.seed_value = 7
		get_tree().root.add_child(inst)
		await _frames(10)
		var wl = inst.world_layer
		var tries := 0
		while wl and wl.pipes and not wl.pipes.built and tries < 900:
			await get_tree().process_frame
			tries += 1
		var map_hits := 0
		for t in MOMENTS:
			var sim: Sim = inst.sim
			while sim.time < t and not sim.over:
				for ai in inst.ais:
					ai.think(sim, 0.1)
				sim.step(0.1)
			sim.fx_events.clear()
			if sim.over:
				break
			var seen := {}
			for f in range(SAMPLE_FRAMES):
				await get_tree().process_frame
				if f % 3 != 2:
					continue
				for hit in _overlaps(inst):
					seen[hit[0]] = hit
			var hits := seen.values()
			map_hits += hits.size()
			var txt := "%s | TOPBAND %s %-5s t=%3.0f overlaps %d" % [tag, code, md, t, hits.size()]
			for h in hits:
				txt += "  [%s @%s under %s]" % [h[0], h[1], h[2]]
			print(txt)
			lines.append(txt)
			if shots_dir != "" and (hits.size() > 0 or t in [5.0, 275.0]):
				DirAccess.make_dir_recursive_absolute(shots_dir)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/%s_%s_t%03d.png" % [shots_dir, tag, code, int(t)])
		total += map_hits
		var ml := "%s | MAP %s overlaps %d" % [tag, code, map_hits]
		print(ml)
		lines.append(ml)
		inst.queue_free()
		await _frames(3)
		var fa := FileAccess.open(out, FileAccess.WRITE)
		fa.store_string("\n".join(lines) + "\n")
	var tl := "%s | TOTAL overlaps %d" % [tag, total]
	print(tl)
	lines.append(tl)
	var fb := FileAccess.open(out, FileAccess.WRITE)
	fb.store_string("\n".join(lines) + "\n")
	print("TOPBAND DONE")
	get_tree().quit()


static func band_rects(hud: Hud) -> Array:
	## [name, Rect2] of the top band: the score bar, the status line's pill, the banner, the catch-up tag.
	var out := []
	if hud.top_panel and hud.top_panel.is_visible_in_tree():
		out.append(["scorebar", hud.top_panel.get_global_rect()])
	if hud.r19_top and (hud.r19_top as Control).is_visible_in_tree():
		out.append(["scorebar19", (hud.r19_top as Control).get_global_rect()])
	var sl: Label = hud.status_label
	if sl and sl.is_visible_in_tree() and sl.text != "":
		var sw := sl.get_theme_font("font").get_string_size(sl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sl.get_theme_font_size("font_size")).x + 24.0 * hud.ui_scale
		var c := sl.get_global_rect().get_center()
		out.append(["status", Rect2(c.x - sw * 0.5, sl.get_global_rect().position.y, sw, sl.size.y)])
	if hud.banner and hud.banner.is_visible_in_tree() and hud.banner.modulate.a > 0.1:
		out.append(["banner", hud.banner.get_global_rect()])
	if hud.catchup_tag and hud.catchup_tag.is_visible_in_tree():
		out.append(["catchup", hud.catchup_tag.get_global_rect()])
	return out


static func world_texts(inst: Node) -> Array:
	## [label, Rect2] of every piece of in-world text on screen.
	var hud: Hud = inst.hud
	var cam: Camera3D = inst.cam
	var out := []
	for n in inst.sim.nodes:
		var id: int = n["id"]
		var r: Rect2 = hud.badge_rect(id)
		if r.size.x > 0.0:
			out.append(["badge#%d" % id, r])
			var bl = hud.get("badge_layer")
			if bl and not Calm.labels() and n["owner"] != "" and n["relay"] == "" and str(n["structure"]) in ["vat", "machinegoon"]:
				var cr: Rect2 = BadgeLayer.chip_rect(r, bl.chip_h())
				if bl.under_band(cr):
					cr.position.y = r.end.y            # (drawn under the badge instead)
				out.append(["chip#%d" % id, cr])
		if hud.overlay:
			var s: Rect2 = hud.overlay.sign_rect(id)
			if s.size.x > 0.0:
				out.append(["sign#%d" % id, s])
			var u: Rect2 = hud.overlay.upgrade_chip_rect(id)
			if u.size.x > 0.0:
				out.append(["upgrade#%d" % id, u])
	if hud.callouts:
		var i := 0
		for r in hud.callouts.rects():
			out.append(["callout%d" % i, r])
			i += 1
	for l in inst.find_children("*", "Label3D", true, false):
		var lab := l as Label3D
		if not lab.is_visible_in_tree() or lab.text.strip_edges() == "" or lab.modulate.a < 0.1:
			continue
		var r := TopBand.screen_rect(lab, cam)
		if "--tb-debug" in OS.get_cmdline_user_args() and r.position.y < 160:
			print("TBDBG '%s' bb=%d off=%s base=%s grp=%s parent=%s scale=%s pos=%s r=%s" % [lab.text, lab.billboard, lab.offset, lab.get_meta(&"tb_base", "-"), lab.is_in_group(TopBand.GROUP), lab.get_parent().name, lab.global_transform.basis.get_scale(), lab.global_position, r])
		if r.size.x > 0.0:
			out.append(["3d'%s'" % lab.text.replace("\n", " ").left(18), r])
	return out


static func label3d_rect(lab: Label3D, cam: Camera3D) -> Rect2:
	var p := lab.global_position
	if cam.is_position_behind(p):
		return Rect2()
	var font: Font = lab.font if lab.font else ThemeDB.fallback_font
	var sz := font.get_multiline_string_size(lab.text, HORIZONTAL_ALIGNMENT_CENTER, -1, lab.font_size) * lab.pixel_size
	var sc := lab.global_transform.basis.get_scale()
	sz *= Vector2(sc.x, sc.y)
	var bx := cam.global_transform.basis.x
	var by := cam.global_transform.basis.y
	if lab.billboard == BaseMaterial3D.BILLBOARD_DISABLED:
		bx = lab.global_transform.basis.x.normalized()
		by = lab.global_transform.basis.y.normalized()
	var off := lab.offset * lab.pixel_size
	var c := p + bx * off.x + by * off.y
	var box := Rect2(cam.unproject_position(c), Vector2.ZERO)
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		box = box.expand(cam.unproject_position(c + bx * (k.x * sz.x * 0.5) + by * (k.y * sz.y * 0.5)))
	return box


static func overlaps_of(inst: Node) -> Array:
	var band := []
	var bi := 0
	for r in (inst.hud as Hud).top_band_rects():
		band.append(["band%d(%d,%d %dx%d)" % [bi, r.position.x, r.position.y, r.size.x, r.size.y], r])
		bi += 1
	var out := []
	for w in world_texts(inst):
		var wr: Rect2 = w[1]
		for b in band:
			var ix: Rect2 = wr.intersection(b[1])
			if ix.size.x > 2.0 and ix.size.y > 2.0:
				out.append([w[0], "%d,%d %dx%d" % [wr.position.x, wr.position.y, wr.size.x, wr.size.y], b[0]])
				break
	return out


func _overlaps(inst: Node) -> Array:
	return overlaps_of(inst)
