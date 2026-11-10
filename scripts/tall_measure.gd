class_name TallMeasure
extends Node
## ui-tall-k (designer spec B): a debug-only measure of the in-match HUD, like the r20 check's measure-r20-v2.json, behind the
## user arg `--tall-measure=<json path>`: after `--tall-measure-at=<s>` (default 8 s) it writes the screen in pt, hud_k, the tall
## class, the rects of every HUD part (pt), every pair that overlaps, parts outside the safe area, and the size of every visible
## HUD text (real pt; the floor = 12.5 pt x hud_k). Never in a normal run.

var hud
var out_path := ""
var at := 8.0
var t := 0.0
var done := false


static func wanted() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tall-measure="):
			return a.substr(15)
	return ""


func setup(h) -> void:
	hud = h
	out_path = wanted()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tall-measure-at="):
			at = float(a.substr(18))


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


func _r(g: Rect2, ppp: float) -> Rect2:
	return Rect2(g.position * ppp, g.size * ppp)


func _arr(r: Rect2) -> Array:
	return [snappedf(r.position.x, 0.1), snappedf(r.position.y, 0.1), snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)]


func measure() -> Dictionary:
	var vp: Vector2 = hud.root.get_viewport_rect().size
	var ppp := UiKit.pt_per_px(vp)                     # real screen pt per viewport px
	var k := UiKit.hud_k(vp)
	var ins := UiKit.safe_insets(vp) * ppp
	var W := vp.x * ppp
	var H := vp.y * ppp
	var rects := {}
	var safe := Rect2(ins.x, ins.y, W - ins.x - ins.z, H - ins.y - ins.w)
	if hud.send_tank and hud.send_tank.picture():
		var st = hud.send_tank
		var o: Vector2 = st.get_global_rect().position
		var a: Vector2 = o + st.cv(Vector2(st.PIC_X, st.PIC_Y))
		var b: Vector2 = o + st.cv(Vector2(st.PIC_X + st.PIC_W, st.PIC_Y + 1080.0))
		rects["tank(art)"] = _r(Rect2(a, b - a), ppp)
	for pair in [["top_panel", hud.top_panel], ["dock", hud.dock], ["version_tag", hud.version_label], ["map_title", hud.map_title],
			["pause_btn", hud.pause_button], ["music_btn", hud.music_button], ["debug_btn", hud.debug_button], ["chat_btn", hud.chat_button],
			["status_line", hud.status_label], ["hint", hud.hint], ["banner", hud.banner]]:
		var c: Control = pair[1]
		if c and c.is_visible_in_tree() and c.size.x > 1.0 and c.modulate.a > 0.01:
			if c is Label and (c as Label).text.strip_edges() == "":
				continue
			rects[pair[0]] = _r(c.get_global_rect(), ppp)
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
	var floor_pt := 12.5 * k
	var small := []
	_texts(hud.root, ppp, texts)
	var min_pt := 999.0
	for tx in texts:
		min_pt = minf(min_pt, tx["size_pt"])
		if tx["size_pt"] < floor_pt - 0.05:
			small.append("%s %.1f pt" % [tx["name"], tx["size_pt"]])
	var srect := {}
	for key in rects:
		srect[key] = _arr(rects[key])
	return {"W_pt": snappedf(W, 0.1), "H_pt": snappedf(H, 0.1), "aspect": snappedf(W / maxf(H, 1.0), 0.001), "hud_k": snappedf(k, 0.001),
		"hud_k_height_only": snappedf(UiKit.hud_k_for(H), 0.001), "tall_k_on": UiKit.tall_k_on, "tall": UiKit.is_tall(vp),
		"safe": _arr(safe), "rects": srect, "overlaps": overlaps, "outside_safe": outside,
		"text_floor_pt": snappedf(floor_pt, 0.01), "text_min_pt": snappedf(min_pt, 0.01), "texts_under_floor": small, "texts": texts}


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
