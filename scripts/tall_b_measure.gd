class_name TallBMeasure
extends Node
## ui-tall-b (designer spec D): a debug-only measure of the in-match HUD behind `--tall-b-measure=<json path>` (never in a normal
## run). After `--tall-b-measure-at=<s>` (default 8 s) it writes, in real screen pt: the screen, hud_k, the tall-B class, every HUD
## part's rect (the round-21 report's set: capsule, banner, toasts, node card, hint strip, coach card, goal strip, tank art, plates,
## each plate, map tag, PAUSE / MUSIC / DBG, keys hint, radial), every overlapping pair (all pairs), parts outside the safe area,
## plates under 44 pt, the visible texts and those under 12.5 pt x hud_k, the camera's fit rect and the map's projected box (its
## nodes' rims), so the sheet can say how much bigger the map is with the flag on.

var hud
var out_path := ""
var at := 8.0
var t := 0.0
var done := false


static func wanted() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tall-b-measure="):
			return a.substr(17)
	return ""


func setup(h) -> void:
	hud = h
	out_path = wanted()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tall-b-measure-at="):
			at = float(a.substr(20))


func _process(dt: float) -> void:
	if done:
		return
	t += dt
	if t >= at:
		done = true
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(measure(), " ", true))
			f.close()


static func _arr(r: Rect2) -> Array:
	return [snappedf(r.position.x, 0.1), snappedf(r.position.y, 0.1), snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)]


func _pt(g: Rect2, ppp: float) -> Rect2:
	return Rect2(g.position * ppp, g.size * ppp)


func measure() -> Dictionary:
	var vp: Vector2 = hud.root.get_viewport_rect().size
	var ppp := UiKit.pt_per_px(vp)                     # real screen pt per viewport px
	var k := UiKit.hud_k(vp)
	var ins := UiKit.safe_insets(vp) * ppp
	var W := vp.x * ppp
	var H := vp.y * ppp
	var safe := Rect2(ins.x, ins.y, W - ins.x - ins.z, H - ins.y - ins.w)
	var rects := {}
	var u: float = HudR19.u_of(hud) if hud.r19_top else 1.0
	if hud.r21:                                        # the round-21 report's rects are in layout pt (x u px): to real pt
		var rep: Dictionary = hud.r21.report(HudR21.band(hud))
		for key in rep["rects"]:
			var a: Array = rep["rects"][key]
			rects[key] = Rect2(a[0], a[1], a[2], a[3])
			rects[key] = Rect2((rects[key] as Rect2).position * u * ppp, (rects[key] as Rect2).size * u * ppp)
	else:
		for pair in [["plates", hud.dock], ["map_title", hud.map_title], ["pause_btn", hud.pause_button], ["music_btn", hud.music_button],
				["debug_btn", hud.debug_button], ["top_panel", hud.top_panel]]:
			var c: Control = pair[1]
			if c and c.is_visible_in_tree() and c.size.x > 1.0 and c.modulate.a > 0.01:
				rects[pair[0]] = _pt(c.get_global_rect(), ppp)
	if hud.chat_button and hud.chat_button.is_visible_in_tree():
		rects["chat_btn"] = _pt(hud.chat_button.get_global_rect(), ppp)
	var small_taps := []
	var plates := []
	if hud.dock and hud.dock.is_visible_in_tree():
		for i in range(hud.dock.slots.size()):
			var r := _pt((hud.dock.slots[i] as Control).get_global_rect(), ppp)
			plates.append(_arr(r))
			if r.size.x < 44.0 or r.size.y < 44.0:
				small_taps.append("plate_%d" % i)
	var overlaps := []
	var keys := rects.keys()
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			if (rects[keys[i]] as Rect2).intersects(rects[keys[j]]):
				overlaps.append("%s x %s" % [keys[i], keys[j]])
	var outside := []
	for key in keys:
		if not safe.grow(0.5).encloses(rects[key]):
			outside.append(key)
	var texts := []
	var cut := []
	_texts(hud.root, ppp, texts)
	if hud.r21:
		for tx in hud.r21.texts:
			texts.append({"name": "r21:" + str(tx["name"]) + ":" + str(tx["text"]).substr(0, 18), "size_pt": snappedf(float(tx["size_pt"]) * u * ppp, 0.01)})
			if not bool(tx["fits"]):
				cut.append("r21:" + str(tx["name"]))
	var floor_pt := 12.5 * k
	var small := []
	var min_pt := 999.0
	for tx in texts:
		min_pt = minf(min_pt, tx["size_pt"])
		if tx["size_pt"] < floor_pt - 0.05:
			small.append("%s %.1f pt" % [tx["name"], tx["size_pt"]])
	# the camera fit rect and the map's projected box
	var main = hud.main
	var box := Rect2()
	var cam: Camera3D = main.cam
	for n in main.sim.nodes:
		var p: Vector3 = n["pos"]
		for kk in range(12):
			var a := TAU * kk / 12.0
			var q := cam.unproject_position(p + Vector3(cos(a), 0.0, sin(a)) * (Rules.R + 1.0)) * ppp
			box = Rect2(q, Vector2.ZERO) if box.size == Vector2.ZERO and box.position == Vector2.ZERO else box.expand(q)
	var map_over := []
	for key in keys:
		if key in ["radial"]:
			continue
		if (rects[key] as Rect2).intersects(box):
			map_over.append(key)
	var fit := Rect2()
	if hud.has_method("tall_b_fit"):
		fit = _pt(hud.tall_b_fit(), ppp)
	var srect := {}
	for key in rects:
		srect[key] = _arr(rects[key])
	return {"W_pt": snappedf(W, 0.1), "H_pt": snappedf(H, 0.1), "aspect": snappedf(W / maxf(H, 1.0), 0.001), "hud_k": snappedf(k, 0.001),
		"tall_b_on": UiKit.tall_b_on, "tall_b": hud.tall_b() if hud.has_method("tall_b") else false, "safe": _arr(safe),
		"rects": srect, "plates": plates, "overlaps": overlaps, "outside_safe": outside, "small_taps": small_taps,
		"text_floor_pt": snappedf(floor_pt, 0.01), "text_min_pt": snappedf(min_pt, 0.01), "texts_under_floor": small, "texts_cut": cut,
		"fit_rect": _arr(fit), "map_box": _arr(box), "map_box_area_pt2": snappedf(box.size.x * box.size.y, 1.0),
		"hud_on_map_box": map_over, "cam_dist": snappedf(float(main.cam_dist), 0.01), "texts": texts}


func _texts(n: Node, ppp: float, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if (n is Label or n is Button) and n is Control:
		var c := n as Control
		var txt: String = (c as Label).text if c is Label else (c as Button).text
		if txt.strip_edges() != "" and c.modulate.a > 0.01:
			var fs := c.get_theme_font_size("font_size")
			out.append({"name": str(c.name) + ":" + txt.substr(0, 18).replace("\n", " "), "size_pt": snappedf(fs * c.get_global_transform().get_scale().y * ppp, 0.01)})
	for ch in n.get_children():
		_texts(ch, ppp, out)
