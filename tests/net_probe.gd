extends SceneTree
## Online smoothness probe (0.20.2): two players in a server room, a busy match (FFA 4 with two AI), and the numbers
## that decide how smooth guests look. Not a pass/fail test.
##   Godot --headless --path . --script res://tests/net_probe.gd [-- --relay=<url> --seconds=60 --mode=FFA4
##       --netsim=<latency ms>,<jitter ms>,<stall every s>,<stall length s>]   (netsim: a bad mobile link, RelayBridge)
## Prints: snapshot inter-arrival (mean, p50, p95, max, rate), snapshot size (delta / keyframe, bytes on the wire),
## order round trip (send -> feedback), and what the guest shows at 60 fps: FREEZE (frames where its match clock
## stood still, total and the longest) and JUMP (a line's movement in one frame beyond its smooth motion: the
## change of per-frame velocity x dt, in sim metres - a snap shows as a spike).

var gaps: Array = []
var rtts: Array = []
var sizes: Array = []
var key_sizes: Array = []
var jumps: Array = []
var freeze_total := 0.0
var freeze_long := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _net() -> Node:
	var n: Node = load("res://scripts/net.gd").new()
	n.no_reload = true
	n.allow_native = true
	root.add_child(n)
	return n


func _wait(cond: Callable, seconds := 10.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _build_sim(info: Dictionary) -> Sim:
	var map := MapBuilder.load_map(info["map"])
	var seats := {}
	var teams := {}
	for s in map["seats"][info["mode"]]:
		seats[int(s["node"])] = s["seat"]
		if info["mode"] in ["2v2", "3v3", "2v2v2"] and s.get("team") != null:
			teams[s["seat"]] = int(s["team"])
	var s := Sim.new()
	s.setup(map, MapBuilder.layout(map), seats, info["players"], int(info["seed"]), teams, info.get("loadouts", {}))
	return s


func _fake_main(s: Sim) -> Node3D:
	var m: Node3D = load("res://scripts/main.gd").new()
	m.sim = s
	return m


static func _stats(a: Array) -> String:
	if a.is_empty():
		return "n=0"
	var b := a.duplicate()
	b.sort()
	var total := 0.0
	for x in b:
		total += float(x)
	return "n=%d mean=%.1f p50=%.1f p95=%.1f max=%.1f" % [b.size(), total / b.size(), b[b.size() / 2],
			b[mini(b.size() - 1, int(b.size() * 0.95))], b[-1]]


func _horde_pos(s: Sim) -> Dictionary:
	var out := {}
	for h in s.hordes:
		out[int(h["id"])] = float(h["s"])
	return out


func _run() -> void:
	Engine.max_fps = 60                                # a phone's frame pacing, not a headless spin
	var seconds := 60.0
	var want_mode := "FFA4"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			seconds = float(arg.substr(10))
		elif arg.begins_with("--mode="):
			want_mode = arg.substr(7)
	var a := _net()
	print("relay: ", a.relay_url())
	a.test_room = true                             # a test room: real players may take its slot
	a.host_room("null")
	if not await _wait(func(): return (a.connected and a.room_owner > 0) or a.hosting or a.bridge == null, 30.0) or a.hosting:
		print("no server room: ", a.status)
		quit(2)
		return
	var b := _net()
	b.join_room(a.room_code, "vex")
	await _wait(func(): return b.connected and a.roster.size() == 2)
	a.set_mode(want_mode)
	await _wait(func(): return a.mode == want_mode)
	a.set_ai_fill("Standard")
	await _wait(func(): return a.ai_fill == "Standard")
	a.start_match()
	await _wait(func(): return a.active and b.active and not b.match_info.is_empty(), 15.0)
	var sa := _build_sim(a.match_info)
	var sb := _build_sim(b.match_info)
	a.world_ready(sa, _fake_main(sa))
	b.world_ready(sb, _fake_main(sb))
	await _wait(func(): return a.started and b.started, 60.0)
	print("room %s mode %s map %s - measuring %d s" % [a.room_code, a.mode, a.map_path.get_file(), int(seconds)])

	var sent_q: Array = []                              # send times waiting for their feedback line (FIFO)
	b.order_feedback.connect(func(_m):
		if not sent_q.is_empty():
			rtts.append((Time.get_ticks_usec() - int(sent_q.pop_front())) / 1000.0))
	var orders := 0
	var next_order := 1.0
	var last_arrival := -1
	var prev_since := 0.0
	var prev_pos := _horde_pos(sb)
	var prev_vel := {}
	var prev_clock := sb.time
	var frozen := 0.0
	var last_us := Time.get_ticks_usec()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0 and not sb.over:
		await process_frame
		var now_us := Time.get_ticks_usec()
		var dt := maxf(0.001, (now_us - last_us) / 1000000.0)
		last_us = now_us
		if sb.time <= prev_clock + 0.0001:              # the guest's clock stood still this frame
			frozen += dt
		else:
			if frozen > 0.0:
				freeze_total += frozen
				freeze_long = maxf(freeze_long, frozen)
			frozen = 0.0
		prev_clock = sb.time
		var pos := _horde_pos(sb)
		var vel := {}
		for id in pos:
			if prev_pos.has(id):
				vel[id] = (float(pos[id]) - float(prev_pos[id])) / dt
				if prev_vel.has(id):
					jumps.append(absf(float(vel[id]) - float(prev_vel[id])) * dt)
		prev_pos = pos
		prev_vel = vel
		if b._since_snapshot < prev_since:              # a snapshot arrived this frame
			var now := Time.get_ticks_usec()
			if last_arrival > 0:
				gaps.append((now - last_arrival) / 1000.0)
			last_arrival = now
			var delta := var_to_bytes(b.snapshot(sb, false)).compress(FileAccess.COMPRESSION_DEFLATE).size()
			sizes.append(delta * 4.0 / 3.0 + 40.0)      # base64 + the JSON envelopes
			if sizes.size() % 10 == 1:
				key_sizes.append(var_to_bytes(b.snapshot(sb, true)).compress(FileAccess.COMPRESSION_DEFLATE).size() * 4.0 / 3.0 + 40.0)
		prev_since = b._since_snapshot
		if (Time.get_ticks_msec() - t0) / 1000.0 > next_order:
			next_order += 1.0
			var mine := -1
			for i in range(sb.nodes.size()):
				if str(sb.nodes[i].get("owner", "")) == b.local_seat():
					mine = i
			if mine >= 0:
				orders += 1
				sent_q.append(Time.get_ticks_usec())
				b.order("upgrade", mine)
	print("match time on the guest: %.1f s (host clock), hordes now %d" % [sb.time, sb.hordes.size()])
	print("snapshot gap ms:   ", _stats(gaps), "  -> %.1f Hz" % (1000.0 / maxf(1.0, _mean(gaps))))
	print("snapshot bytes:    ", _stats(sizes), "  keyframe: ", _stats(key_sizes))
	print("  -> ~%.1f KB/s per guest" % (_mean(sizes) * (1000.0 / maxf(1.0, _mean(gaps))) / 1024.0))
	print("order round trip:  ", _stats(rtts))
	var big := jumps.filter(func(j): return j > 0.5).size()
	print("jump per frame (m): ", _stats(jumps), "  spikes > 0.5 m: %d (%.1f / min)" % [big, big * 60.0 / seconds])
	print("freeze: %.2f s total (%.1f %% of the time), longest %.2f s" % [freeze_total, 100.0 * freeze_total / seconds, freeze_long])
	print("corrections (the guest's prediction vs the host, per line per snapshot): > 0.5 m: %d (%.1f / min), largest %.2f m, hard snaps %d" % [
			b.corr_big, b.corr_big * 60.0 / seconds, b.corr_max, b.corr_snaps])
	print("playout delay at the end: %.2f s" % b._delay)
	a.leave()
	b.leave()
	await _wait(func(): return false, 1.0)
	quit(0)


static func _mean(a: Array) -> float:
	var t := 0.0
	for x in a:
		t += float(x)
	return t / maxf(1.0, a.size())
