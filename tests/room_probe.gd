extends Node
## Render probe for the room lobby and a room match (0.18.7: team switching and room colours) without
## browsers: the autoload Net talks to other Net instances in this process through a loopback bridge that
## carries the real envelopes (JSON + base64 + deflate), so the lobby and the launch are the real protocol.
##   Godot --path . res://tests/room_probe.tscn -- --probe=<state> --view=host|guest [--window=WxH] [--mobile]
##       [--menu-shot=<png>] | [--match-shot=<png> --at=25 --save=<file> | --load=<file>]
## states: teams-before (2v2 on A-01: the guest joined seat B, the rival team), teams-after (the guest took
## JOIN TEAM to the host's team and picked a colour), teams-move (host view: a guest row picked for MOVE),
## ffa (four players' colour picks), match (a 2v2 round, both humans on one team).
## Every player brings an ARMIES loadout (SKILLS 2.0: the lobby rows show its three icons).
## Match: the host run plays --at seconds (AI on every seat), freezes, saves the launch + a keyframe
## snapshot (--save) and screenshots; the guest run (--load) gets that launch and snapshot from an
## in-process host over the loopback, so both screenshots show the same moment.

class Loop:
	extends RefCounted
	var name := ""
	var hub: Dictionary
	var queue: Array = []
	func _init(n: String, h: Dictionary) -> void:
		name = n
		hub = h
		hub[n] = self
	func start(_host, _code) -> void: pass
	func send(remote, data) -> bool:
		if hub.has(str(remote)):
			hub[str(remote)].queue.append({"type": "data", "peer": name, "data": str(data)})
		return true
	func close() -> void: pass
	func closePeer(_remote) -> void: pass
	func poll() -> String:
		var r := JSON.stringify(queue)
		queue = []
		return r

const MAP_2V2 := "res://maps4/A-01-orbital-nexus.json"   # A+C against B+D: join order splits two players
var hub := {}
var peers := {}                                          # name -> the other Net instances
var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("window"):
		var wh := str(args["window"]).split("x")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	var state := str(args.get("probe", "teams-after"))
	var guest_view := str(args.get("view", "host")) == "guest"
	if state == "match" and args.has("load"):
		await _guest_match()
		return
	# the room: Net (this window) is the host or the guest; the rest are extra Net nodes
	var h: Node = Net if not guest_view else _peer("host")
	h.bridge = Loop.new("host", hub)
	h.hosting = true
	h.connected = true
	h.room_code = "K7QX"
	h.mode = "FFA4" if state == "ffa" else "2v2"
	h.map_path = MAP_2V2 if h.mode == "2v2" else h.maps_for(h.mode)[0]
	h.preferred_faction = "null"
	h.loadout = {"active": "ghost_line", "map": "relay_hack"}
	h.roster = {1: {"faction": "null", "slot": 0, "colour": "", "loadout": h.loadout}}
	h._fix_colours()
	var names := ["gf"] if state != "ffa" else ["gf", "p3", "p4"]
	var factions := {"gf": "bloom", "p3": "ember", "p4": "solar"}
	for n in names:
		var g: Node = Net if (guest_view and n == "gf") else _peer(n)
		g.bridge = Loop.new(n, hub)
		g.room_code = "K7QX"
		g.preferred_faction = factions[n]
		g.loadout = {"gf": {"active": "spore_burst", "map": "bypass"}, "p3": {"active": "scorch", "map": "demolish"}, "p4": {"active": "fortify", "map": "anchor"}}[n]
		hub[n].queue.append({"type": "connection", "peer": "host"})
		hub["host"].queue.append({"type": "connection", "peer": n})
		await _frames(4)
	var gf: Node = Net if guest_view else peers["gf"]
	await _frames(6)
	if state in ["teams-after", "teams-move", "match"]:
		gf.switch_team(h.team_of(1))                      # the guest's JOIN TEAM on the host's team
		await _frames(4)
		gf.set_colour("green")
		await _frames(4)
		h.set_colour("cyan")
	if state == "ffa":
		gf.set_colour("purple")
		peers.get("p3", Net).set_colour("gold")
		await _frames(4)
		h.set_colour("cyan")
	if state == "match":
		h.set_ai_fill("Standard")
		await _frames(4)
		await _host_match(h)
		return
	await _frames(6)
	print("probe roster (host): ", h.roster)
	print("probe roster (guest): ", gf.roster)
	_open_main()                                         # main opens the lobby (Net is in a room)
	if state == "teams-move":
		await _frames(5)
		var menu = get_tree().current_scene.menu_layer
		menu._move_pick = gf.assigned_id if not guest_view else -1
		menu.show_lobby()


func _open_main() -> void:
	## The match scene next to this probe (a scene change would free the probe mid-way).
	var m: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m


func _peer(n: String) -> Node:
	var p: Node = load("res://scripts/net.gd").new()
	p.no_reload = true
	get_tree().root.add_child.call_deferred(p)
	peers[n] = p
	return p


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _build_sim(info: Dictionary) -> Sim:
	var map := MapBuilder.load_map(info["map"])
	var seats := {}
	var teams := {}
	for s in map["seats"][info["mode"]]:
		seats[int(s["node"])] = s["seat"]
		if s.get("team") != null:
			teams[s["seat"]] = int(s["team"])
	var s := Sim.new()
	s.setup(map, MapBuilder.layout(map), seats, info["players"], int(info["seed"]), teams)
	return s


func _host_match(h: Node) -> void:
	## Host view: deploy, the guest peer loads its world, every seat plays itself (AI) until --at.
	h.no_reload = true
	h.start_match()
	await _frames(4)
	var gf: Node = peers["gf"]
	gf.world_ready(_build_sim(gf.match_info), null)
	_open_main()
	await _frames(3)
	var m = get_tree().current_scene
	while m == null or m.sim == null or not m.started:
		await get_tree().process_frame
		m = get_tree().current_scene
	for seat in ["A", "C"]:                               # the two humans: let the AI play them for the picture
		m.ais.append(SeatAI.new(seat, 2.5, "Standard"))
	var at := float(args.get("at", "25"))
	while m.sim.time < at:
		await get_tree().process_frame
	Net.started = false                                   # freeze the host's Sim here
	if args.has("save"):
		var f := FileAccess.open(str(args["save"]), FileAccess.WRITE)
		f.store_var({"info": Net.match_info, "snap": Net.snapshot(m.sim, true)}, false)
		f.close()
	print("probe colours: ", Net.match_info["colours"], " you: ", Net.local_seat())
	await _shot(m)


func _guest_match() -> void:
	## Guest view: an in-process host holds the saved round and moment; this window is the guest.
	var f := FileAccess.open(str(args["load"]), FileAccess.READ)
	var saved: Dictionary = f.get_var(false)
	f.close()
	var info: Dictionary = saved["info"]
	var h: Node = _peer("host")
	await _frames(1)
	h.bridge = Loop.new("host", hub)
	h.hosting = true
	h.connected = true
	h.room_code = "K7QX"
	h.roster = info["roster"]
	var gid := -1
	for id in h.roster:
		if int(id) != 1:
			gid = int(id)
	h.links["gf"] = gid
	Net.bridge = Loop.new("gf", hub)
	Net.room_code = "K7QX"
	Net.remote_host = "host"
	Net.assigned_id = gid
	Net.connected = true
	Net.no_reload = true
	h._launch(info)
	h._broadcast("launch", info)
	var hs := _build_sim(info)
	Net.apply_snapshot(hs, saved["snap"])
	h.world_ready(hs, null)
	await _frames(3)                                      # the guest receives the launch
	_open_main()
	await _frames(3)
	var m = get_tree().current_scene
	while m == null or m.sim == null or not m.started:
		await get_tree().process_frame
		m = get_tree().current_scene
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:             # snapshots of the frozen moment arrive; the join toasts fade
		await get_tree().process_frame
	print("probe colours: ", Net.match_info["colours"], " you: ", Net.local_seat(), " t=", m.sim.time)
	await _shot(m)


func _shot(m) -> void:
	await _frames(20)
	await RenderingServer.frame_post_draw
	var out := str(args.get("match-shot", "user://room_probe.png"))
	get_viewport().get_texture().get_image().save_png(out)
	print("screenshot ", out)
	get_tree().quit()
