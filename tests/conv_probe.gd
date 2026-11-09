extends SceneTree
## Conveyor probe (demo-rules-pass): on every round-R map, a line sent along each conveyor / belt deck WITH its flow;
## prints the head's measured speed on the deck vs Rules.move_speed() (x2.25 expected) and the tag the view shows.
##   Godot --headless --path . --script res://tests/conv_probe.gd

func _sim(path: String) -> Sim:
	var m := MapBuilder.load_map(path)
	var seats := {}
	for st in m["seats"]["1v1"]:
		seats[int(st["node"])] = str(st["seat"])
	var s := Sim.new()
	s.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "null"}, 1)
	return s


func _run(path: String, ei: int) -> void:
	var s := _sim(path)
	var e: Dictionary = s.edges[ei]
	var flow := 0
	if s._conv_edges.has(ei):
		flow = int(s.nodes[int(s._conv_edges[ei])]["relay_index"])
	else:
		flow = int(s._belt_edges[ei])
	var fa: int = int(e["a"]) if flow == 0 else int(e["b"])   # the flow goes fa -> fb
	var fb: int = int(e["b"]) if flow == 0 else int(e["a"])
	var a := -1
	var b := -1
	for i in range(s.nodes.size()):                   # a real node pair whose route walks the deck with its flow
		if a >= 0 or str(s.nodes[i].get("node_kind", "")) == "junction":
			continue
		for j in range(s.nodes.size()):
			if i == j or str(s.nodes[j].get("node_kind", "")) == "junction":
				continue
			var r: Array = s.find_route(i, j)
			var k := r.find(fa)
			if k >= 0 and k + 1 < r.size() and int(r[k + 1]) == fb:
				a = i
				b = j
				break
	if a < 0:
		print("  %s deck %d: no route walks it %d->%d" % [path.get_file().substr(0, 4), ei, fa, fb])
		return
	var keep_b := -1
	for n in s.nodes:
		if n["owner"] == "B" and n["id"] != a and n["id"] != b:
			keep_b = n["id"]
	if keep_b < 0:                                    # seat B keeps a node, or the match is over and nothing moves
		for n in s.nodes:
			if n["id"] != a and n["id"] != b and str(n.get("node_kind", "")) != "junction":
				n["owner"] = "B"
				break
	s.nodes[a]["owner"] = "A"
	s.nodes[a]["units"] = 40.0
	s.nodes[b]["owner"] = "A"
	var h := s.send(a, b, 1.0)
	if h.is_empty():
		print("  %s deck %d: send %d->%d failed" % [path.get_file(), ei, a, b])
		return
	var sp := {}
	for x in h["spans"]:
		if int(x["edge"]) == ei:
			sp = x
	if sp.is_empty():
		print("  %s deck %d: route %s does not use it" % [path.get_file(), ei, h["route"]])
		return
	var t := 0.0
	var t_in := -1.0
	var t_out := -1.0
	var tag := 0
	while t < 40.0 and h in s.hordes:
		s.step(0.02)
		t += 0.02
		if t_in < 0.0 and float(h["s"]) >= float(sp["s0"]):
			t_in = t
		if t_in >= 0.0 and t_out < 0.0 and float(h["s"]) >= float(sp["s1"]):
			t_out = t
		if t_in >= 0.0 and t_out < 0.0:
			tag = int(h.get("conv", 0))
	var L := float(sp["s1"]) - float(sp["s0"])
	if t_out < 0.0:
		print("    (stalled: in hordes %s state %s s %.2f / L %.2f deck %.2f-%.2f route %s target owner %s units %.1f, over %s, closed %s)" % [h in s.hordes, h["state"], h["s"], h["L"],
				sp["s0"], sp["s1"], h["route"], s.nodes[b]["owner"], h["units"], s.get("over") if "over" in s else "?", [] if s.is_edge_open(ei) else [ei]])
	var v := L / maxf(t_out - t_in, 0.001) if t_out > 0.0 else 0.0
	print("  %s deck %d %s %d->%d (%.1f m): x%.2f measured, view tag %s" % [path.get_file().substr(0, 4), ei,
			"relay" if s._conv_edges.has(ei) else "belt", a, b, L, v / Rules.move_speed(), tag])


func _init() -> void:
	for f in DirAccess.get_files_at("res://maps4"):
		if not (f.begins_with("R-") and f.ends_with(".json")) or not f.substr(0, 4) in MapPool.PROTO:
			continue
		var s := _sim("res://maps4/" + f)
		var decks := s._conv_edges.keys() + s._belt_edges.keys()
		decks.sort()
		for ei in decks:
			_run("res://maps4/" + f, int(ei))
	quit(0)
