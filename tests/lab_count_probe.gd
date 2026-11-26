extends SceneTree
## LAB COUNT SIZE probe (lab4 job 3, card COUNT SIZE). A dev tool, not a suite. Headless, through the lab guard:
##   Godot --headless --path . --script res://tests/lab_count_probe.gd -- --pt-height=390 pw=844 notch=47
## The window is (pw x pt-height) pt at 2 px per pt; the card's match (L11C, locked lab camera) at each count_scale. Prints
##   COUNT x<k> digit <m> m  aim <pt> pt  min <pt>  max <pt>  (nodes <n>)  badges_shown <n>
## = the vat-screen digit height projected through the game's camera at the start view: at the node nearest the aim (what the
## overlay shows), and the smallest / largest over every node (far nodes are smaller in perspective). Render-free: geometry only.
const LabCards := preload("res://scripts/lab_cards.gd")
const LabMenu := preload("res://scripts/lab_menu.gd")


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return a.substr(name.length() + 1)
	return def


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var pw := float(_arg("pw", "844"))
	var ph := UiKit.test_pt_h if UiKit.test_pt_h > 0.0 else 390.0
	root.size = Vector2i(int(pw * 2.0), int(ph * 2.0))
	await _frames(3)
	var notch := float(_arg("notch", "0"))
	var vp0 := root.get_visible_rect().size
	UiKit.test_insets = Vector4(notch / UiKit.pt_per_px(vp0), 0.0, notch / UiKit.pt_per_px(vp0), 0.0)
	var card := LabCards.find("count")
	for k in range(3):
		LabMenu.picks = {"count": {"count_scale": k}}
		LabMenu.apply_card(card)
		load("res://scripts/main.gd").relaunch = {"faction": "vex", "rival": "null", "mode": "1v1",
				"map": LabCards.map_path(str(card["map"]))}
		change_scene_to_file("res://main.tscn")
		await _frames(60)
		var m: Node = current_scene
		var vc = m.get("vat_count")
		if vc == null:
			print("COUNT x? no vat_count")
			continue
		var lo := INF
		var hi := 0.0
		for id in vc.screens:
			var p: float = vc.digit_pt_at(id, m.cam)
			lo = minf(lo, p)
			hi = maxf(hi, p)
		var shown := 0
		for id in m.hud.badges:
			if (m.hud.badges[id]["panel"] as Control).visible:
				shown += 1
		print("COUNT x%s digit %.2f m  aim %.1f pt  min %.1f  max %.1f  (nodes %d)  badges_shown %d  view %s pt  cam %.1f m pitch %.0f" % [
				str(card["choices"][0]["values"][k]), vc.digit_height_m(), vc.digit_pt(m.cam), lo, hi, vc.screens.size(), shown,
				str(vp0 * UiKit.pt_per_px(vp0)), float(m.cam_dist), float(m.cam_pitch)])
	LabMenu.reset_card()
	quit(0)
