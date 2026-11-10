extends SceneTree
## Conveyor probe (demo-rules-pass): on every round-R map, a line sent along each conveyor / belt deck WITH its flow;
## prints the head's measured speed on the deck vs Rules.move_speed() (x2.25 expected) and the tag the view shows.
##   Godot --headless --path . --script res://tests/conv_probe.gd [-- carry]   (carry: only the CONVEYOR CARRY section)
## CONVEYOR CARRY (demo-rules-pass-2, Daniele 2026-11-10): per map, a line's head speed before / on / after a belt and
## across a reverse belt, and the carry cleared by (a) arrival, (b) a fall, (c) a belt the other way.

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


func _belt_sense(s: Sim, ei: int, from_id: int) -> int:
	## 1 the route walks deck `ei` with its flow, -1 against, 0 not a belt (or flipping).
	var flow := -1
	if s._conv_edges.has(ei):
		flow = int(s.nodes[int(s._conv_edges[ei])]["relay_index"])
	elif s._belt_edges.has(ei):
		flow = int(s._belt_edges[ei])
	if flow < 0:
		return 0
	var fwd: bool = int(s.edges[ei]["a"]) == from_id
	return 1 if (flow == 0) == fwd else -1


func _plan(s: Sim, a: int, b: int) -> Array:
	## [[edge, sense, deck length]] along the route a -> b.
	var r: Array = s.find_route(a, b)
	var out := []
	for k in range(r.size() - 1):
		var ei: int = s._edge_index(r[k], r[k + 1])
		out.append([ei, _belt_sense(s, ei, int(r[k])), float(s.edges[ei]["geo"]["L"]) if s.edges[ei].has("geo") else 0.0])
	return out


func _find(s: Sim, want: String) -> Array:
	## A real node pair whose route shows the pattern: "carry" = plain deck, a belt, then >= 4 m of plain deck before
	## the target; "reverse" = a belt with the flow, later a belt against it.
	var real := []
	for n in s.nodes:
		if str(n.get("node_kind", "")) != "junction":
			real.append(n["id"])
	for a in real:
		for b in real:
			if a == b:
				continue
			var p := _plan(s, a, b)
			var first := -1
			for k in range(p.size()):
				if int(p[k][1]) != 0:
					first = k
					break
			if first < 0:
				continue
			if want == "carry":
				var after := 0.0
				var ok := true
				for k in range(first + 1, p.size()):
					if int(p[k][1]) != 0:
						ok = false
					after += float(p[k][2])
				if ok and after >= 4.0 and int(p[first][1]) > 0:
					return [a, b, p]
			else:
				for k in range(first + 1, p.size()):
					if int(p[k][1]) != 0 and int(p[k][1]) != int(p[first][1]):
						return [a, b, p]
	return []


func _launch(s: Sim, a: int, b: int) -> Dictionary:
	var keep_b := false
	for n in s.nodes:
		if n["owner"] == "B" and n["id"] != a and n["id"] != b:
			keep_b = true
	if not keep_b:
		for n in s.nodes:
			if n["id"] != a and n["id"] != b and str(n.get("node_kind", "")) != "junction":
				n["owner"] = "B"
				break
	for id in s.find_route(a, b):                     # every node on the way is own: no garrison stops the probe line
		if str(s.nodes[id].get("node_kind", "")) != "junction":
			s.nodes[id]["owner"] = "A"
	s.nodes[a]["units"] = 40.0
	return s.send(a, b, 0.1)


func _zone(h: Dictionary, belts: Array) -> String:
	## "before" no belt reached yet, "on" a body on a belt, "after" the whole line past the last belt crossed.
	var head: float = h["s"]
	var tail: float = head - Sim.chain_length(h)
	var seen := 0
	for sp in h["spans"]:
		if not int(sp["edge"]) in belts:
			continue
		if head >= float(sp["s0"]) and tail <= float(sp["s1"]):
			return "on"
		if tail > float(sp["s1"]):
			seen += 1
	return "before" if seen == 0 else ("after" if seen == 1 else "after%d" % seen)


func _carry_case(path: String, want: String, clear: String) -> void:
	## clear: "arrive" (run to the target), "fall" (cut a sliver of its tail once it is past the belt).
	var s := _sim(path)
	var pick := _find(s, want)
	var tag := path.get_file().substr(0, 4)
	if pick.is_empty():
		print("  %s %s: no route" % [tag, want])
		return
	var belts := []
	var senses := []
	for x in pick[2]:
		if int(x[1]) != 0:
			belts.append(int(x[0]))
			senses.append(int(x[1]))
	var h := _launch(s, pick[0], pick[1])
	if h.is_empty():
		print("  %s %s: send failed" % [tag, want])
		return
	var acc := {}
	var carry_seen := {}
	var t := 0.0
	var cut_done := false
	var after_cut := [0.0, 0]
	var arrived_carry := "?"
	var last_belt_sense := 0
	while t < 150.0 and h in s.hordes:
		var s0: float = h["s"]
		var z0 := _zone(h, belts)
		var on_node := false
		for ns in h.get("node_spans", []):
			if s0 >= float(ns["s0"]) and s0 <= float(ns["s1"]):
				on_node = true
		var st0: String = h["state"]
		s.step(0.02)
		t += 0.02
		if not (h in s.hordes):
			break
		if st0 == "move" and h["state"] == "move" and not on_node and not h.get("blocked", false):
			var v: float = (float(h["s"]) - s0) / 0.02 / Rules.move_speed()
			var key := z0
			if z0 == "on":
				key = "on(%+d)" % int(h.get("conv", 0))
				last_belt_sense = int(h.get("conv", 0))
			if cut_done:
				after_cut[0] += v
				after_cut[1] += 1
			else:
				if not acc.has(key):
					acc[key] = [0.0, 0]
				acc[key][0] += v
				acc[key][1] += 1
				carry_seen[key] = int(h.get("conv_carry", 0))
		if clear == "fall" and not cut_done and _zone(h, belts).begins_with("after") and float(h["s"]) - Sim.chain_length(h) > 0.0:
			var tail: float = float(h["s"]) - Sim.chain_length(h)
			s._cut_range(h, tail, tail + 0.2, false)
			cut_done = true
			carry_seen["cut"] = int(h.get("conv_carry", 0))
		if h["state"] == "absorb" and arrived_carry == "?":
			arrived_carry = str(int(h.get("conv_carry", 0)))
	var row := "  %s %-7s %-6s %d->%d belts %s:" % [tag, want, clear, pick[0], pick[1], senses]
	for k in ["before", "on(+1)", "on(-1)", "after", "after2"]:
		if acc.has(k):
			row += "  %s x%.2f (carry %+d)" % [k, acc[k][0] / maxf(acc[k][1], 1), carry_seen.get(k, 0)]
	if clear == "fall":
		row += "  | after fall: x%.2f carry %+d" % [after_cut[0] / maxf(after_cut[1], 1), carry_seen.get("cut", 0)] if cut_done else "  | no cut"
	else:
		row += "  | at the target: carry %s%s" % [arrived_carry, "" if h in s.hordes or arrived_carry != "?" else " (line gone: %s, s %.1f / L %.1f, state %s)" % [str(s.fx_events.map(func(e): return e["type"])), float(h["s"]), float(h["L"]), h["state"]]]
	print(row)


func _carry() -> void:
	print("CONVEYOR CARRY (x%.2f with / x%.2f against; head speed / Rules.move_speed, node platforms left out)" % [
			float(Rules.RELAYS_PROTO["conveyor"]["with"]), float(Rules.RELAYS_PROTO["conveyor"]["against"])])
	for f in DirAccess.get_files_at("res://maps4"):
		if not (f.begins_with("R-") and f.ends_with(".json")) or not f.substr(0, 4) in MapPool.PROTO:
			continue
		var s := _sim("res://maps4/" + f)
		if s._conv_edges.is_empty() and s._belt_edges.is_empty():
			continue
		_carry_case("res://maps4/" + f, "carry", "arrive")
		_carry_case("res://maps4/" + f, "carry", "fall")
		_carry_case("res://maps4/" + f, "reverse", "arrive")


func _init() -> void:
	_carry()
	if "carry" in OS.get_cmdline_user_args():
		quit(0)
		return
	for f in DirAccess.get_files_at("res://maps4"):
		if not (f.begins_with("R-") and f.ends_with(".json")) or not f.substr(0, 4) in MapPool.PROTO:
			continue
		var s := _sim("res://maps4/" + f)
		var decks := s._conv_edges.keys() + s._belt_edges.keys()
		decks.sort()
		for ei in decks:
			_run("res://maps4/" + f, int(ei))
	quit(0)
