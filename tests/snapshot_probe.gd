extends SceneTree
## Snapshot size probe (Alpha 21 net-5): a busy offline FFA 4 (four Standard AIs) played for 120 s; every second the
## host's snapshot is measured - total and per section, raw (var_to_bytes) and deflated, plus the base64 + JSON
## envelope it travels in today. Not a test.   Godot --headless --path . --script res://tests/snapshot_probe.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := ""
	for p in MapPool.battlefield():
		if MapBuilder.load_map(p).get("seats", {}).has("FFA4"):
			path = p
			break
	var map := MapBuilder.load_map(path)
	var seats := {}
	for s in map["seats"]["FFA4"]:
		seats[int(s["node"])] = s["seat"]
	var sim := Sim.new()
	sim.setup(map, MapBuilder.layout(map), seats, {"A": "vex", "B": "bloom", "C": "ember", "D": "solar"}, 11, {}, {})
	var ais := []
	for seat in ["A", "B", "C", "D"]:
		ais.append(SeatAI.new(seat, 2.5, "Standard"))
	var net: Node = load("res://scripts/net.gd").new()
	var totals := {}
	var key_snap := {}
	var n := 0
	var t := 0.0
	while t < 120.0 and not sim.over:
		for ai in ais:
			ai.think(sim, 0.05)
		sim.step(0.05)
		t += 0.05
		if int(t * 20.0) % 20 == 0:                    # once a second
			var snap: Dictionary = net.snapshot(sim, int(t) % 10 == 0)
			n += 1
			for k in snap:
				var raw := var_to_bytes(snap[k]).size()
				var z := var_to_bytes(snap[k]).compress(FileAccess.COMPRESSION_DEFLATE).size()
				var e: Array = totals.get(k, [0, 0])
				totals[k] = [e[0] + raw, e[1] + z]
			var q = _quant(snap)
			var qz := var_to_bytes(q).compress(FileAccess.COMPRESSION_DEFLATE).size()
			var e3: Array = totals.get("(quantised x100 ints)", [0, 0])
			totals["(quantised x100 ints)"] = [e3[0] + var_to_bytes(q).size(), e3[1] + qz]
			var sch = _schema(snap)
			var e4: Array = totals.get("(schema arrays)", [0, 0])
			totals["(schema arrays)"] = [e4[0] + var_to_bytes(sch).size(), e4[1] + var_to_bytes(sch).compress(FileAccess.COMPRESSION_DEFLATE).size()]
			if int(t) % 10 == 0:
				key_snap = snap
			var dl = _delta(snap, key_snap)
			var e5: Array = totals.get("(changed fields)", [0, 0])
			totals["(changed fields)"] = [e5[0] + var_to_bytes(dl).size(), e5[1] + var_to_bytes(dl).compress(FileAccess.COMPRESSION_DEFLATE).size()]
			var q64 = _q64(dl)
			var e6: Array = totals.get("(changed + 1/64)", [0, 0])
			totals["(changed + 1/64)"] = [e6[0] + var_to_bytes(q64).size(), e6[1] + var_to_bytes(q64).compress(FileAccess.COMPRESSION_DEFLATE).size()]
			var all_raw := var_to_bytes(snap).size()
			var all_z := var_to_bytes(snap).compress(FileAccess.COMPRESSION_DEFLATE).size()
			var e2: Array = totals.get("(all)", [0, 0])
			totals["(all)"] = [e2[0] + all_raw, e2[1] + all_z]
	print("map %s, %d samples over %.0f s, hordes at the end %d" % [path.get_file(), n, t, sim.hordes.size()])
	var snap2: Dictionary = net.snapshot(sim, false)
	if not (snap2["hordes"] as Array).is_empty():
		var h: Dictionary = snap2["hordes"][0]
		var per := []
		for k in h:
			per.append([k, var_to_bytes(h[k]).size()])
		per.sort_custom(func(x, y): return x[1] > y[1])
		print("  one horde (delta): ", per)
	var nd: Dictionary = snap2["nodes"][0]
	var pn := []
	for k in nd:
		pn.append([k, var_to_bytes(nd[k]).size()])
	pn.sort_custom(func(x, y): return x[1] > y[1])
	print("  one node: ", pn)
	var keys := totals.keys()
	keys.sort_custom(func(a, b): return totals[a][1] > totals[b][1])
	for k in keys:
		print("  %-14s raw %6.0f B   deflated %6.0f B" % [k, totals[k][0] / float(n), totals[k][1] / float(n)])
	var zall: float = totals["(all)"][1] / float(n)
	print("  binary frames of (changed + 1/64): ~%.0f B on the wire" % (totals["(changed + 1/64)"][1] / float(n) + 12.0))
	print("  on the wire today (base64 + JSON envelopes): ~%.0f B" % (zall * 4.0 / 3.0 + 60.0))
	net.free()
	quit(0)


static func _quant(v):
	## every float as an int in hundredths (a size experiment: what quantisation would save)
	if v is float:
		return int(round(v * 100.0))
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _quant(v[k])
		return d
	if v is Array:
		return (v as Array).map(func(x): return _quant(x))
	if v is PackedVector3Array or v is PackedFloat32Array:
		return v
	return v


static func _schema(snap: Dictionary) -> Dictionary:
	## nodes and hordes as value arrays in a fixed (sorted) key order - no key names on the wire
	var out := snap.duplicate()
	for sec in ["nodes", "hordes"]:
		var rows := []
		for d in snap[sec]:
			var keys: Array = (d as Dictionary).keys()
			keys.sort()
			rows.append(keys.map(func(k): return d[k]))
		out[sec] = rows
	return out


static func _delta(snap: Dictionary, key: Dictionary) -> Dictionary:
	## only the fields that differ from the last keyframe (nodes by index, hordes by id; new hordes whole)
	var out := snap.duplicate()
	var nodes := {}
	for i in range((snap["nodes"] as Array).size()):
		var d: Dictionary = snap["nodes"][i]
		var k: Dictionary = key["nodes"][i] if key.has("nodes") and i < (key["nodes"] as Array).size() else {}
		var ch := {}
		for f in d:
			if not k.has(f) or str(k[f]) != str(d[f]):
				ch[f] = d[f]
		if not ch.is_empty():
			nodes[i] = ch
	out["nodes"] = nodes
	var kh := {}
	if key.has("hordes"):
		for h in key["hordes"]:
			kh[h["id"]] = h
	var hordes := []
	for h in snap["hordes"]:
		var k: Dictionary = kh.get(h["id"], {})
		if k.is_empty():
			hordes.append(h)
			continue
		var ch := {"id": h["id"]}
		for f in h:
			if not k.has(f) or str(k[f]) != str(h[f]):
				ch[f] = h[f]
		hordes.append(ch)
	out["hordes"] = hordes
	return out


static func _q64(v):
	## floats rounded to 1/64: exact in float32, so var_to_bytes stores 4 bytes instead of 8 (no decoding needed)
	if v is float:
		return round(v * 64.0) / 64.0 if absf(v) < 100000.0 else v
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _q64(v[k])
		return d
	if v is Array:
		return (v as Array).map(func(x): return _q64(x))
	return v
