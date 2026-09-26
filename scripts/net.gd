extends Node
## Ooze Syndicate 2.0 - peer-to-peer rooms (autoload "Net"). Alpha 11's PeerJS approach, ported from
## Game/Alpha 11/scripts/network.gd (the P2P half) to 2.0's seats, maps and Sim:
## - the browser transport is web/peer-transport.js (window.OozePeer, room prefix "ooze20-");
## - four-character room codes, 2-6 players: free-for-all (1v1, FFA 3-5) and teams (2v2, 3v3, 2v2v2),
##   host-assigned seats (join order);
## - the HOST's Sim is the only simulation. Guests send orders (send, recall, upgrade, build, switch,
##   restore); the host validates ownership, rate-limits and answers every order with the same
##   feedback line the offline game toasts. The host broadcasts compressed snapshots ~10 Hz plus the
##   view's effect events; guests render snapshots with light prediction (lines keep moving);
## - version check, all-player loading barrier, round epochs, rematch (everyone accepts, fresh
##   simulation, same room), chat (256 chars, 50 messages, rate limits, host-assigned sender);
## - a guest dropping mid-match keeps the seat for RECONNECT (the AI plays it when EMPTY SEATS is on);
##   the host leaving closes the room;
## - window.oozeBusy (set_busy) tells web/update.js not to reload for a new build during a room.
## No host migration, no TURN relay: some networks cannot connect directly.

signal lobby_changed
signal rematch_changed
signal order_feedback(message: String)
signal seats_changed                               # host: which seats the AI plays changed

const VERSION_TAG := "ooze20-net-1"               # plus Rules.VERSION: guests must match the host exactly
const MODES := ["1v1", "FFA3", "FFA4", "FFA5", "2v2", "3v3", "2v2v2"]
const MODE_LABELS := {"1v1": "1 V 1", "FFA3": "FFA 3", "FFA4": "FFA 4", "FFA5": "FFA 5", "2v2": "2 V 2", "3v3": "3 V 3", "2v2v2": "2V2V2"}
const SLOTS := {"1v1": 2, "FFA3": 3, "FFA4": 4, "FFA5": 5, "2v2": 4, "3v3": 6, "2v2v2": 6}
const TEAM_MODES := ["2v2", "3v3", "2v2v2"]
const SEATS := ["A", "B", "C", "D", "E", "F"]
const FACTIONS := ["vex", "null", "bloom", "ember", "solar"]
const ACTIONS := ["send", "recall", "upgrade", "build_cannon", "build_forge", "restore", "switch"]
const SNAPSHOT_EVERY := 0.1
const KEYFRAME_EVERY := 10                         # every 10th snapshot carries every horde's path
const PATH_RESEND := 1.0                           # a changed path rides along for this many seconds
const MAX_PACKET := 8 * 1024 * 1024
const CHAT_MAX := 256
const CHAT_HISTORY := 50
const HOST_GRACE := 10.0                           # guests wait this long for a silent host (Daniele: 10 s)
const AI_FILL := ["", "Training", "Casual", "Standard", "Veteran", "Expert"]   # EMPTY SEATS setting: off or the AI level

var bridge                                         # window.OozePeer (or a test double)
var hosting := false
var connected := false                             # host: room open; guest: in the lobby
var room_code := ""
var status := ""
var roster := {}                                   # player id -> {"faction", "slot"}; host is 1
var links := {}                                    # host: remote peer string -> player id
var next_peer := 2
var remote_host := ""
var assigned_id := 0                               # guest: the id the host gave us
var preferred_faction := "null"
var colour := "A"                                  # your own view colour (local, like offline)
# room settings (host decides; guests receive them with the lobby)
var mode := "1v1"
var map_path := ""                                   # set from the map pool when a room opens
var siege := true
var last_stand := true
# match state
var match_round := 0
var active := false                                # a match is loaded or playing
var started := false                               # everyone loaded: the host's clock runs
var finished := false
var ready_peers := {}
var rematch_votes := {}
var match_info := {}                               # the launch packet of the current round
var sim: Sim                                       # set by main when the world is built
var main: Node                                     # the match scene (host runs orders through it)
var no_reload := false                             # tests: launch without reloading the scene
var ai_fill := ""                                  # host setting: "" = every seat needs a player, else the AI level for empty seats
var rejoin := {}                                   # guest: {code, token, faction} to RECONNECT to a dropped room
var _tokens := {}                                  # host: player id -> secret rejoin token (never broadcast)
var _fresh := false                                # guest: the first snapshot of a round (a rejoin catches up)
# pacing / limits
var _snap_clock := 0.0
var _snap_count := 0
var _since_snapshot := 0.0
var _elapsed := 0.0
var _path_seen := {}                               # host: horde id -> [path key, time it changed]
var _order_limits := {}
var _packet_limits := {}
var chat_history: Array = []
var chat_serial := 0
var _chat_limits := {}
var _chat_clock := 0.0
var _chat_revision := -1
var _chat_connected := false
var _maps := {}                                    # path -> map data (seats per mode, name)


# ------------------------------------------------------------------ queries
func in_room() -> bool:
	return bridge != null and (connected or hosting or remote_host != "" or room_code != "")


func online() -> bool:
	return bridge != null and active


func is_host() -> bool:
	return hosting


func local_id() -> int:
	return 1 if hosting else assigned_id


func slots() -> int:
	return SLOTS.get(mode, 2)


func seat_of(id: int) -> String:
	return SEATS[int(roster[id]["slot"])] if roster.has(id) else ""


func local_seat() -> String:
	return seat_of(local_id())


func label_of(id: int) -> String:
	## Chat and lobby name: the seat letter and faction (host-assigned, never typed by the player).
	if not roster.has(id):
		return "?"
	return "%s · %s" % [seat_of(id), str(roster[id]["faction"]).to_upper()]


func team_of_slot(slot: int) -> int:
	## Team modes take the map's teams (2v2 A+B vs C+D, 3v3, 2v2v2); FFA: everyone alone (-1).
	if not mode in TEAM_MODES:
		return -1
	var seats: Array = map_data(map_path).get("seats", {}).get(mode, [])
	for s in seats:
		if s["seat"] == SEATS[slot] and s.get("team") != null:
			return int(s["team"])
	return 0 if slot < 2 else 1


func can_start() -> bool:
	var full := roster.size() == slots() or (ai_fill != "" and roster.size() >= 1)
	return hosting and connected and not active and full and map_offers(map_path, mode)


func is_away(id: int) -> bool:
	return roster.has(id) and bool(roster[id].get("away", false))


func present_ids() -> Array:
	## Players still connected (a dropped player keeps their seat mid-match until they RECONNECT).
	return roster.keys().filter(func(id): return not is_away(int(id)))


func ai_seats() -> Dictionary:
	## Host: seat -> AI level for every seat the AI plays now: empty seats filled at launch, and
	## (with EMPTY SEATS on) the seat of a player who dropped, until they reconnect.
	var out: Dictionary = (match_info.get("ai", {}) as Dictionary).duplicate()
	if ai_fill != "":
		for id in roster:
			if is_away(int(id)):
				out[seat_of(int(id))] = ai_fill
	return out


func set_ai_fill(level: String) -> void:
	if hosting and not active and level in AI_FILL:
		ai_fill = level
		publish_lobby()


func map_data(path: String) -> Dictionary:
	if not _maps.has(path):
		var d = MapBuilder.load_map(path) if FileAccess.file_exists(path) else null
		_maps[path] = d if d is Dictionary else {}
	return _maps[path]


func map_offers(path: String, m: String) -> bool:
	return map_data(path).get("seats", {}).has(m)


func maps_for(m: String) -> Array:
	return MapPool.all().filter(func(p): return map_offers(p, m))


# ------------------------------------------------------------------ room lifecycle
func host_room(faction: String) -> Error:
	return _start(true, faction, "")


func join_room(code: String, faction: String) -> Error:
	return _start(false, faction, code)


func reconnect() -> Error:
	## RECONNECT: rejoin the room we dropped out of, into the same seat (the host holds it).
	if rejoin.is_empty():
		return ERR_UNAVAILABLE
	return _start(false, str(rejoin["faction"]), str(rejoin["code"]))


func _start(host: bool, faction: String, code: String) -> Error:
	leave(false)
	if not OS.has_feature("web"):
		status = "Online rooms run in the browser build (the playtest link)."
		lobby_changed.emit()
		return ERR_UNAVAILABLE
	bridge = JavaScriptBridge.get_interface("OozePeer")
	if bridge == null:
		status = "PeerJS is unavailable. Reload the page."
		lobby_changed.emit()
		return ERR_UNAVAILABLE
	set_busy(true)                                     # a room is open: a new build waits for the menu
	hosting = host
	preferred_faction = faction
	_elapsed = 0.0
	if host:
		roster = {1: {"faction": faction, "slot": 0}}
		if not map_offers(map_path, mode) or not map_path in MapPool.all():
			var pool := maps_for(mode)
			if pool.is_empty():
				mode = "1v1"
				pool = maps_for(mode)
			map_path = pool[0] if not pool.is_empty() else ""
	bridge.start(host, code.strip_edges().to_upper())
	status = "Connecting to the room service..."
	lobby_changed.emit()
	return OK


func leave(forget := true) -> void:
	## forget = false keeps the RECONNECT details (a dropped connection, not LEAVE ROOM).
	if forget:
		_save_rejoin({})
	if OS.has_feature("web"):
		var ui = JavaScriptBridge.get_interface("OozeChat")
		if ui != null:
			ui.sync(false, "[]", "")
	if bridge != null:
		bridge.close()
	bridge = null
	hosting = false
	connected = false
	room_code = ""
	remote_host = ""
	assigned_id = 0
	links = {}
	next_peer = 2
	roster = {}
	match_round = 0
	active = false
	started = false
	finished = false
	ready_peers = {}
	rematch_votes = {}
	match_info = {}
	chat_history = []
	chat_serial = 0
	_chat_limits = {}
	_chat_revision = -1
	_chat_connected = false
	_order_limits = {}
	_packet_limits = {}
	_path_seen = {}
	sim = null
	main = null
	_tokens = {}
	_fresh = false
	status = ""
	set_busy(false)


func set_busy(b: bool) -> void:
	## Web only: window.oozeBusy makes web/update.js hold a new build's reload while a match or a room
	## is on (Net._start / leave; main sets it for every match and clears it on the menu).
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.oozeBusy=%s" % ("true" if b else "false"), true)


func fail(message: String) -> void:
	var was_playing := active
	leave(false)
	status = message
	lobby_changed.emit()
	if was_playing and not no_reload:                 # back to the front menu, which shows the reason
		get_tree().reload_current_scene()


# ------------------------------------------------------------------ lobby (host decides)
func set_mode(m: String) -> void:
	if not hosting or active or not m in MODES or roster.size() > SLOTS[m]:
		return
	var pool := maps_for(m)
	if pool.is_empty():                                # no map seats this mode: keep the current one
		return
	mode = m
	if not map_offers(map_path, mode):
		map_path = pool[0]
	_reseat()
	publish_lobby()


func set_map(path: String) -> void:
	if hosting and not active and map_offers(path, mode):
		map_path = path
		publish_lobby()


func toggle_siege() -> void:
	if hosting and not active:
		siege = not siege
		publish_lobby()


func toggle_last_stand() -> void:
	if hosting and not active:
		last_stand = not last_stand
		publish_lobby()


func set_faction(f: String) -> void:
	if not f in FACTIONS or active:
		return
	preferred_faction = f
	if hosting:
		if roster.has(1):
			roster[1]["faction"] = f
			publish_lobby()
	else:
		_send_to_host({"op": "faction", "faction": f})


func _reseat() -> void:
	## Seats stay packed from A in join order (host-assigned).
	var ids := roster.keys()
	ids.sort_custom(func(a, b): return int(roster[a]["slot"]) < int(roster[b]["slot"]))
	for i in range(ids.size()):
		roster[ids[i]]["slot"] = i


func publish_lobby() -> void:
	_broadcast("lobby", {"roster": roster, "mode": mode, "map": map_path, "siege": siege,
			"last_stand": last_stand, "round": match_round, "ai_fill": ai_fill})
	lobby_changed.emit()


func _register(remote: String, id: int, p: Dictionary) -> void:
	var token := str(p.get("token", ""))
	if token != "" and str(p.get("version", "")) == version():
		for old in roster:
			if is_away(int(old)) and _tokens.get(old, "") == token:
				_reclaim(remote, int(old))
				return
	if active or roster.has(id) or roster.size() >= slots() or str(p.get("version", "")) != version():
		_send(remote, "rejected", "Room full, match already started, or a different game version (reload the page).")
		return
	var used := []
	for player in roster.values():
		used.append(int(player["slot"]))
	var slot := 0
	while slot in used:
		slot += 1
	var f := str(p.get("faction", ""))
	roster[id] = {"faction": f if f in FACTIONS else FACTIONS[slot % FACTIONS.size()], "slot": slot}
	_tokens[id] = _new_token()
	_send(remote, "identity", {"id": id, "token": _tokens[id]})
	_send(remote, "chat_history", chat_history)
	publish_lobby()


func _reclaim(remote: String, id: int) -> void:
	## A dropped player is back: same id, same seat; mid-match they get the round and catch up.
	links[remote] = id
	roster[id].erase("away")
	_send(remote, "identity", {"id": id, "token": _tokens[id]})
	_send(remote, "chat_history", chat_history)
	if active:
		match_info["roster"] = roster
		_send(remote, "launch", match_info)
	_notice("Seat %s reconnected" % seat_of(id))
	seats_changed.emit()
	publish_lobby()


func _new_token() -> String:
	var b := PackedByteArray()
	for i in range(12):
		b.append(randi() % 256)
	return Marshalls.raw_to_base64(b)


func _notice(message: String) -> void:
	## Host: a line every player sees as a toast (drops, reconnects).
	_broadcast("notice", message)
	order_feedback.emit(message)


func version() -> String:
	return VERSION_TAG + "/" + Rules.VERSION


# ------------------------------------------------------------------ rounds
func start_match() -> void:
	if can_start():
		launch_round()


func launch_round() -> void:
	for id in roster.keys():                          # a new round: anyone still away has left
		if is_away(int(id)):
			roster.erase(id)
			_tokens.erase(id)
	_reseat()
	var players := {}
	for id in roster:
		players[seat_of(id)] = roster[id]["faction"]
	var ai := {}
	if ai_fill != "":
		for slot in range(roster.size(), slots()):     # EMPTY SEATS: the AI plays them
			var free := FACTIONS.filter(func(f): return not f in players.values())
			players[SEATS[slot]] = free[randi() % free.size()] if not free.is_empty() else FACTIONS[randi() % FACTIONS.size()]
			ai[SEATS[slot]] = ai_fill
	var info := {"round": match_round + 1, "map": map_path, "mode": mode, "seed": randi() % 100000,
			"players": players, "roster": roster, "ai": ai, "ai_fill": ai_fill,
			"rules": {"bridge_combat": siege, "last_stand": last_stand, "deck_speed": Rules.deck_speed,
					"node_speed_mult": Rules.node_speed_mult, "door_rate": Rules.door_rate,
					"node_fight_mult": Rules.node_fight_mult, "forge_bonus": Rules.forge_bonus,
					"hide_enemy_counts": Rules.hide_enemy_counts}}
	_broadcast("launch", info)
	_launch(info)


func _launch(info: Dictionary) -> void:
	match_info = info
	match_round = int(info["round"])
	roster = info["roster"]
	mode = str(info["mode"])
	map_path = str(info["map"])
	var r: Dictionary = info["rules"]
	siege = bool(r["bridge_combat"])
	last_stand = bool(r["last_stand"])
	Rules.bridge_combat = siege
	Rules.last_stand = last_stand
	Rules.deck_speed = float(r["deck_speed"])
	Rules.node_speed_mult = float(r["node_speed_mult"])
	Rules.door_rate = float(r["door_rate"])
	Rules.node_fight_mult = float(r["node_fight_mult"])
	Rules.forge_bonus = float(r["forge_bonus"])
	Rules.hide_enemy_counts = bool(r.get("hide_enemy_counts", false))   # the host's option, the same for all
	ai_fill = str(info.get("ai_fill", ""))
	active = true
	started = false
	finished = false
	_fresh = true
	ready_peers = {}
	rematch_votes = {}
	_order_limits = {}
	_path_seen = {}
	_snap_clock = 0.0
	_snap_count = 0
	_since_snapshot = 0.0
	sim = null
	if not no_reload:
		get_tree().reload_current_scene()


func world_ready(s: Sim, m: Node) -> void:
	## Called by main once this browser has built the round's world (the loading barrier).
	sim = s
	main = m
	if hosting:
		mark_ready(1)
	else:
		_send_to_host({"op": "loaded", "round": match_round})


func mark_ready(id: int) -> void:
	if not active or not roster.has(id):
		return
	ready_peers[id] = true
	if started:                                        # a reconnected player caught up
		_snap_count = 0                                # the next snapshot is a keyframe: the returning guest gets every path
		for remote in links:
			if links[remote] == id:
				_send(remote, "begin", {"round": match_round})
		return
	_check_barrier()


func _check_barrier() -> void:
	if not active or started:
		return
	for id in present_ids():
		if not ready_peers.has(id):
			return
	_broadcast("begin", {"round": match_round})
	_begin()


func _begin() -> void:
	started = true
	_since_snapshot = 0.0


func peer_left(id: int) -> void:
	if not hosting or not roster.has(id):
		return
	if active:                                         # mid-match: hold the seat for a RECONNECT
		roster[id]["away"] = true
		rematch_votes.erase(id)
		ready_peers.erase(id)
		_notice("Seat %s lost connection - they can RECONNECT%s" % [seat_of(id), " (the AI plays it meanwhile)" if ai_fill != "" else ""])
		seats_changed.emit()
		_check_barrier()
		publish_lobby()
		_check_rematch()
		return
	roster.erase(id)
	_tokens.erase(id)
	rematch_votes.erase(id)
	ready_peers.erase(id)
	_reseat()
	publish_lobby()


func return_to_room(message: String) -> void:
	if hosting:                                        # back in the lobby: dropped players are gone
		for id in roster.keys():
			if is_away(int(id)):
				roster.erase(id)
				_tokens.erase(id)
		_reseat()
		publish_lobby()                                # the guests get the repacked seats
	active = false
	started = false
	finished = false
	ready_peers = {}
	rematch_votes = {}
	status = message
	sim = null
	lobby_changed.emit()
	if not no_reload:
		get_tree().reload_current_scene()             # main opens the lobby page while in a room


# ------------------------------------------------------------------ orders
func order(action: String, a: int, args := {}) -> void:
	## A guest's order goes to the host; the host's own orders run straight through main.
	if not online() or not started or finished:
		return
	if hosting:
		var r: Array = main.perform(local_seat(), action, a, args)
		order_feedback.emit(r[1])
	else:
		_send_to_host({"op": "order", "round": match_round, "action": action, "a": a, "args": args})


func _execute(id: int, p: Dictionary) -> Array:
	## Host-side validation of a guest's order: known action, sane numbers, the round, the rate.
	if not active or not started or finished or not roster.has(id) or main == null:
		return [false, ""]
	var now := Time.get_ticks_msec()
	var rate: Dictionary = _order_limits.get(id, {"at": now, "count": 0})
	if now - int(rate["at"]) > 1000:
		rate = {"at": now, "count": 0}
	rate["count"] = int(rate["count"]) + 1
	_order_limits[id] = rate
	if int(rate["count"]) > 20:
		return [false, "Too many orders - slow down"]
	var action = p.get("action", null)
	var a = p.get("a", null)
	var args = p.get("args", {})
	if not action is String or not action in ACTIONS or not _is_int(a) or not args is Dictionary or args.size() > 2:
		return [false, "Order rejected"]
	var clean := {}
	if action == "send":
		if not _is_int(args.get("to", null)) or not (args.get("fraction", null) is float or args.get("fraction", null) is int):
			return [false, "Order rejected"]
		var f := float(args["fraction"])
		if not is_finite(f) or f <= 0.0 or f > 1.0:
			return [false, "Order rejected"]
		clean = {"to": int(args["to"]), "fraction": f}
	return main.perform(seat_of(id), action, int(a), clean)


static func _is_int(v) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) == floorf(float(v)) and absf(float(v)) < 10000000.0


# ------------------------------------------------------------------ rematch
func request_rematch() -> void:
	if not active or not finished:
		return
	if hosting:
		accept_rematch(1)
	else:
		_send_to_host({"op": "rematch", "round": match_round})


func accept_rematch(id: int) -> void:
	if not active or not finished or not roster.has(id):
		return
	rematch_votes[id] = true
	_broadcast("rematch_votes", {"round": match_round, "votes": rematch_votes})
	rematch_changed.emit()
	_check_rematch()


func _check_rematch() -> void:
	if not hosting or not active or not finished:
		return
	var present := present_ids()
	if present.is_empty() or present.any(func(id): return not rematch_votes.has(id)):
		return
	if present.size() == slots() or ai_fill != "":
		launch_round()
	else:                                              # a seat is empty and no AI may take it
		var msg := "A player is missing - back to the lobby. Invite someone with the same code."
		return_to_room(msg)                            # publishes the repacked lobby first...
		_broadcast("room_reset", msg)                  # ...so the guests keep this reason as their status


# ------------------------------------------------------------------ snapshots
static func path_key(h: Dictionary) -> String:
	var pts: PackedVector3Array = h["pts"]
	return "%s|%.3f|%d|%s" % [str(h["route"]), float(h["L"]), pts.size(), str(h.get("retreat", false))]


const PATH_FIELDS := ["pts", "cum", "fast", "spans", "node_spans"]
const NODE_SKIP := ["pos", "transit", "category", "center", "relay", "buildable", "id"]


func snapshot(s: Sim, keyframe: bool) -> Dictionary:
	## The host's state for the guests: everything the view reads that changes during a match.
	## Horde paths (the long point lists) ride along only when they changed recently or on keyframes.
	var nodes := []
	for n in s.nodes:
		var d := {}
		for k in n:
			if not k in NODE_SKIP:
				d[k] = n[k]
		var tr := {}
		for seat in n["transit"]:
			var t: Dictionary = n["transit"][seat]
			tr[seat] = {"units": t["units"], "hordes": (t["hordes"] as Array).map(func(h): return h["id"])}
		d["transit"] = tr
		nodes.append(d)
	var hs := []
	var alive := {}
	for h in s.hordes:
		var key := path_key(h)
		var seen: Array = _path_seen.get(h["id"], ["", 0.0])
		if seen[0] != key:
			seen = [key, s.time]
			_path_seen[h["id"]] = seen
		var send_path: bool = keyframe or s.time - float(seen[1]) < PATH_RESEND
		var d := {"_pk": key}
		for k in h:
			if send_path or not k in PATH_FIELDS:
				d[k] = h[k]
		hs.append(d)
		alive[h["id"]] = true
	for id in _path_seen.keys():
		if not alive.has(id):
			_path_seen.erase(id)
	var snap := {"round": match_round, "t": s.time, "over": s.over, "winner": s.winner, "next_id": s._next_id,
			"nodes": nodes, "hordes": hs, "fights": s.fights, "fight_info": s.fight_info,
			"collapsed": s.collapsed, "eliminated": s.eliminated,
			"ls": [s.last_stand_active, s.last_stand_method, s.last_stand_order, s.last_stand_final,
					s.last_stand_next, s.last_stand_warn_node, s.last_stand_warn_t, s.last_stand_wave, s._next_wave_at,
					s.last_stand_waves, s.last_stand_keep, s.last_stand_warn, s.last_stand_queue],
			"losses": [s.combat_losses, s.fall_losses]}
	if s.over:
		snap["events"] = s.events                    # the end screen's captures count
	return snap


static func apply_snapshot(s: Sim, snap: Dictionary) -> void:
	## Guest side: overwrite the local Sim with the host's state. Owner changes fire `captured` and
	## the end fires `finished`, exactly as the host's own Sim does, so the view needs no net code.
	var old := {}
	for h in s.hordes:
		old[h["id"]] = h
	var hs := []
	for h in snap["hordes"]:
		if not h.has("pts"):                          # no path this time: keep the one we had
			var prev: Dictionary = old.get(h["id"], {})
			if not prev.is_empty() and prev.get("_pk", "") == h["_pk"]:
				for k in PATH_FIELDS:
					h[k] = prev[k]
			elif (h["route"] as Array).size() < 2:     # a line recalled before its first deck: no path to build
				if not prev.is_empty():
					for k in PATH_FIELDS:
						h[k] = prev[k]
				else:
					var p0: Vector3 = s.nodes[int(h["route"][0])]["pos"]
					h["pts"] = PackedVector3Array([p0])
					h["cum"] = PackedFloat32Array([0.0])
					h["fast"] = PackedByteArray([1])
					h["spans"] = []
					h["node_spans"] = []
			else:                                     # missed it: rebuild from the route until a keyframe
				var path := s.build_path(h["route"])
				h["pts"] = path["pts"]
				h["cum"] = path["cum"]
				h["fast"] = path["fast"]
				h["spans"] = path["spans"]
				h["node_spans"] = path["node_spans"]
		hs.append(h)
	s.hordes = hs
	var by_id := {}
	for h in hs:
		by_id[h["id"]] = h
	var changes := []
	for i in range(mini(s.nodes.size(), snap["nodes"].size())):
		var n: Dictionary = s.nodes[i]
		var d: Dictionary = snap["nodes"][i]
		var before: String = n["owner"]
		for k in d:
			if k != "transit":
				n[k] = d[k]
		var tr := {}
		for seat in d["transit"]:
			var t: Dictionary = d["transit"][seat]
			tr[seat] = {"units": t["units"], "hordes": (t["hordes"] as Array).filter(func(id): return by_id.has(id)).map(func(id): return by_id[id])}
		n["transit"] = tr
		if n["owner"] != before:
			changes.append([i, n["owner"], before])
	s.time = float(snap["t"])
	s._next_id = int(snap["next_id"])
	s.fights = snap["fights"]
	s.fight_info = snap["fight_info"]
	s.collapsed = snap["collapsed"]
	s.eliminated = snap["eliminated"]
	var ls: Array = snap["ls"]
	s.last_stand_active = ls[0]
	s.last_stand_method = ls[1]
	s.last_stand_order = ls[2]
	s.last_stand_final = ls[3]
	s.last_stand_next = ls[4]
	s.last_stand_warn_node = ls[5]
	s.last_stand_warn_t = ls[6]
	s.last_stand_wave = ls[7]
	s._next_wave_at = ls[8]
	if ls.size() > 11:                                # maps 3.0 ring waves
		s.last_stand_waves = ls[9]
		s.last_stand_keep = ls[10]
		s.last_stand_warn = ls[11]
	if ls.size() > 12:                                # 0.18.4: the ring's drop queue
		s.last_stand_queue = ls[12]
	s.combat_losses = snap["losses"][0]
	s.fall_losses = snap["losses"][1]
	for c in changes:
		s.captured.emit(c[0], c[1], c[2])
	if snap.has("events"):
		s.events = snap["events"]
	if bool(snap["over"]) and not s.over:
		s.over = true
		s.winner = str(snap["winner"])
		s.finished.emit(s.winner)


static func predict(s: Sim, dt: float) -> void:
	## Light prediction between snapshots: the clock runs and lines keep moving at their speed.
	s.time += dt
	for h in s.hordes:
		if h["state"] != "move" or h.get("blocked", false):
			continue
		var mult: float = Rules.platform_mult() if Sim.sample(h, h["s"])[2] else 1.0
		if Rules.bridge_combat and s.on_enemy_goo(h):
			mult *= Rules.GOO_SLOW
		var ds: float = Rules.move_speed() * h.get("speed", 1.0) * s.stat(h["owner"], "speed") * mult * dt
		if h["streaming"]:
			ds = minf(ds, Rules.exit_rate() * Rules.metres_per_unit() * dt)
		if h.get("pour", false):                    # walking off a lip: the head stays, the line pours on
			h["fcut"] = float(h.get("fcut", 0.0)) + ds
			h["units"] = maxf(0.0, h["units"] - ds / Rules.metres_per_unit())
			continue
		h["s"] = minf(h["s"] + ds, h["L"])


func push_effects(events: Array) -> void:
	## Host: the view's one-off effects (bursts, falls, relay ticks, collapses) for the guests.
	if hosting and online() and not events.is_empty() and _has_guests():
		_broadcast("effects", {"round": match_round, "events": events})


# ------------------------------------------------------------------ loop
func _process(dt: float) -> void:
	if bridge == null:
		return
	_poll(dt)
	_poll_chat_ui(dt)
	if not active or not started or sim == null:
		return
	if hosting:
		_snap_clock += dt
		var every := SNAPSHOT_EVERY if not finished else 1.0   # the end screen: frozen state; a slow resend covers a dropped packet
		if _snap_clock >= every or (sim.over and not finished):
			_snap_clock = 0.0
			_snap_count += 1
			if _has_guests():                          # alone with the AI: nobody to send to
				var packet := var_to_bytes(snapshot(sim, _snap_count % KEYFRAME_EVERY == 1)).compress(FileAccess.COMPRESSION_DEFLATE)
				_broadcast_raw("state", packet)
			if sim.over:
				finished = true
	else:
		_since_snapshot += minf(dt, 0.25)            # a tab back from the background: one huge frame
		if _since_snapshot < 0.35 and not sim.over:
			predict(sim, minf(dt, 0.05))
		if _since_snapshot > HOST_GRACE:
			fail("The host stopped responding for %d s. RECONNECT to try the room again." % int(HOST_GRACE))


func _poll(dt: float) -> void:
	_elapsed += minf(dt, 0.25)
	var events = JSON.parse_string(str(bridge.poll()))
	if not events is Array:
		return
	for event in events:
		if bridge == null or not event is Dictionary:
			return
		match str(event.get("type", "")):
			"open":
				room_code = str(event.get("code", ""))
				connected = hosting
				status = ("ROOM %s - share the code; keep this tab open" % room_code) if hosting else ("Joining room %s..." % room_code)
				lobby_changed.emit()
			"connection":
				if hosting:
					var held := roster.keys().any(func(id): return is_away(int(id)))
					if links.size() >= slots() - 1 or (active and not held):   # mid-match: only to reclaim a held seat
						bridge.closePeer(event["peer"])
						continue
					links[event["peer"]] = next_peer
					next_peer += 1
				else:
					remote_host = str(event["peer"])
					var reg := {"op": "register", "version": version(), "faction": preferred_faction}
					if not rejoin.is_empty() and str(rejoin["code"]) == room_code:
						reg["token"] = rejoin["token"]
					_send_to_host(reg)
			"data":
				if hosting:
					_host_receive(str(event["peer"]), str(event["data"]))
				elif str(event["peer"]) == remote_host:
					_guest_receive(str(event["data"]))
			"closed":
				if hosting:
					var id: int = links.get(event["peer"], -1)
					links.erase(event["peer"])
					if id >= 0:
						peer_left(id)
				else:
					fail("The host left or the connection was lost. The room is closed." if connected else "The room did not let us in: it is full or its match already started.")
			"error":
				fail(str(event.get("message", "Connection failed.")))
			"signalling-lost":
				if not active:
					status = "Room service disconnected. Players already here can stay; new joins need a new room."
					lobby_changed.emit()
	if bridge != null and not connected and _elapsed > 30.0:
		fail("Could not reach the room. Try another network; some networks block direct connections.")


func _host_receive(remote: String, raw: String) -> void:
	if not links.has(remote) or raw.length() > 4096:
		return
	var id := int(links[remote])
	var now := Time.get_ticks_msec()
	var rate: Dictionary = _packet_limits.get(id, {"at": now, "count": 0})
	if now - int(rate["at"]) > 1000:
		rate = {"at": now, "count": 0}
	rate["count"] = int(rate["count"]) + 1
	_packet_limits[id] = rate
	if int(rate["count"]) > 30:
		bridge.closePeer(remote)
		return
	var p = JSON.parse_string(raw)
	if not p is Dictionary:
		return
	var op := str(p.get("op", ""))
	if op == "register":
		_register(remote, id, p)
		return
	if not roster.has(id):
		return
	match op:
		"chat":
			if p.get("text", null) is String and not accept_chat(id, p["text"]):
				_send(remote, "chat_error", "Please wait a moment before sending again.")
		"faction":
			var f := str(p.get("faction", ""))
			if f in FACTIONS and not active:
				roster[id]["faction"] = f
				publish_lobby()
		"rematch":
			if _is_int(p.get("round", null)) and int(p["round"]) == match_round:
				accept_rematch(id)
		"loaded":
			if _is_int(p.get("round", null)) and int(p["round"]) == match_round:
				mark_ready(id)
		"order":
			if not _is_int(p.get("round", null)) or int(p["round"]) != match_round:
				return
			var r := _execute(id, p)
			if str(r[1]) != "":
				_send(remote, "feedback", str(r[1]))


func _guest_receive(raw: String) -> void:
	if raw.length() > MAX_PACKET:
		return
	var envelope = JSON.parse_string(raw)
	if not envelope is Dictionary or not envelope.get("data", null) is String:
		return
	var bytes := Marshalls.base64_to_raw(envelope["data"]).decompress_dynamic(MAX_PACKET, FileAccess.COMPRESSION_DEFLATE)
	var data = bytes_to_var(bytes)
	match str(envelope.get("kind", "")):
		"identity":
			if data is Dictionary:
				assigned_id = int(data["id"])
				_save_rejoin({"code": room_code, "token": str(data["token"]), "faction": preferred_faction})
		"notice":
			order_feedback.emit(str(data))
		"lobby":
			if not data is Dictionary:
				return
			roster = data["roster"]
			mode = str(data["mode"])
			map_path = str(data["map"])
			siege = bool(data["siege"])
			last_stand = bool(data["last_stand"])
			ai_fill = str(data.get("ai_fill", ""))
			connected = true
			status = "ROOM %s - waiting for the host to deploy" % room_code
			lobby_changed.emit()
		"launch":
			if data is Dictionary:
				_launch(data)
		"begin":
			if data is Dictionary and int(data.get("round", -1)) == match_round:
				_begin()
		"state":
			if data is Dictionary and int(data.get("round", -1)) == match_round and sim != null and active:
				apply_snapshot(sim, data)
				_since_snapshot = 0.0
				if _fresh:                            # joined late (RECONNECT): drop the nodes that already fell
					_fresh = false
					for id in sim.collapsed:
						sim.fx_events.append({"type": "collapse", "node": id})
				if sim.over:
					finished = true
		"effects":
			if data is Dictionary and int(data.get("round", -1)) == match_round and sim != null:
				sim.fx_events.append_array(data["events"])
		"feedback":
			order_feedback.emit(str(data))
		"rematch_votes":
			if data is Dictionary and int(data.get("round", -1)) == match_round:
				rematch_votes = data["votes"]
				rematch_changed.emit()
		"room_reset":
			return_to_room(str(data))
		"chat_history":
			if data is Array:
				chat_history = data
				chat_serial += 1
		"chat_error":
			_chat_error(str(data))
		"rejected":
			_save_rejoin({})                          # that room will not take us back
			fail(str(data))


# ------------------------------------------------------------------ rejoin details
func _ready() -> void:
	if OS.has_feature("web"):                          # a reloaded tab can still RECONNECT
		var raw = JavaScriptBridge.eval("(()=>{try{return sessionStorage.getItem('ooze20-rejoin')||''}catch(e){return ''}})()", true)
		var text := str(raw) if raw != null else ""   # blocked site storage: nothing to rejoin
		var d = JSON.parse_string(text) if text != "" else null
		if d is Dictionary and d.has("code") and d.has("token") and d.has("faction"):
			rejoin = d


func _save_rejoin(d: Dictionary) -> void:
	rejoin = d
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{sessionStorage.setItem('ooze20-rejoin', %s)}catch(e){}" % JSON.stringify(JSON.stringify(d)) if not d.is_empty()
				else "try{sessionStorage.removeItem('ooze20-rejoin')}catch(e){}", true)


# ------------------------------------------------------------------ transport
func _encode(kind: String, packed: PackedByteArray) -> String:
	return "{\"kind\":" + JSON.stringify(kind) + ",\"data\":" + JSON.stringify(Marshalls.raw_to_base64(packed)) + "}"


func _send(remote: String, kind: String, data) -> void:
	if bridge != null:
		bridge.send(remote, _encode(kind, var_to_bytes(data).compress(FileAccess.COMPRESSION_DEFLATE)))


func _broadcast(kind: String, data) -> void:
	_broadcast_raw(kind, var_to_bytes(data).compress(FileAccess.COMPRESSION_DEFLATE))


func _broadcast_raw(kind: String, packed: PackedByteArray) -> void:
	if bridge == null or not hosting:
		return
	var envelope := _encode(kind, packed)            # one envelope for every guest
	for remote in links:
		if roster.has(links[remote]):
			bridge.send(remote, envelope)


func _has_guests() -> bool:
	## Host: is any connected guest still seated (the same test _broadcast_raw sends by)?
	for remote in links:
		if roster.has(links[remote]):
			return true
	return false


func _send_to_host(packet: Dictionary) -> void:
	if bridge != null and remote_host != "":
		bridge.send(remote_host, JSON.stringify(packet))


# ------------------------------------------------------------------ chat (Alpha 11 rules)
func send_chat(message: String) -> void:
	if not connected:
		return
	if hosting:
		if not accept_chat(1, message):
			_chat_error("Please wait a moment before sending again.")
	else:
		_send_to_host({"op": "chat", "text": message.left(CHAT_MAX)})


func accept_chat(id: int, message: String) -> bool:
	## Host only: clean the text, rate-limit (5 per 10 s, 0.7 s apart), stamp the sender's id and seat.
	if not roster.has(id):
		return false
	var clean := ""
	for i in range(mini(message.length(), CHAT_MAX)):
		var c := message.unicode_at(i)
		if c >= 32 and c != 127:
			clean += message.substr(i, 1)
	clean = clean.strip_edges()
	if clean.is_empty():
		return false
	var now := Time.get_ticks_msec()
	var recent: Array = (_chat_limits.get(id, []) as Array).filter(func(t): return now - int(t) < 10000)
	if recent.size() >= 5 or (not recent.is_empty() and now - int(recent[-1]) < 700):
		return false
	recent.append(now)
	_chat_limits[id] = recent
	chat_serial += 1
	chat_history.append({"id": chat_serial, "pid": id, "who": label_of(id), "seat": seat_of(id), "text": clean})
	if chat_history.size() > CHAT_HISTORY:
		chat_history.pop_front()
	_broadcast("chat_history", chat_history)
	return true


func _poll_chat_ui(dt: float) -> void:
	if not OS.has_feature("web"):
		return
	_chat_clock += dt
	if _chat_clock < 0.1:
		return
	_chat_clock = 0.0
	var ui = JavaScriptBridge.get_interface("OozeChat")
	if ui == null:
		return
	var message := str(ui.takeMessage())
	if not message.is_empty():
		send_chat(message)
	if _chat_revision != chat_serial or _chat_connected != connected:
		ui.sync(connected, JSON.stringify(chat_history), str(local_id()))   # "You" by player id: seats repack
		_chat_revision = chat_serial
		_chat_connected = connected


func open_chat() -> void:
	## The game's CHAT buttons open the native panel (typing happens in the DOM, phone keyboards).
	if OS.has_feature("web"):
		var ui = JavaScriptBridge.get_interface("OozeChat")
		if ui != null:
			ui.show()


func chat_unread() -> int:
	if not OS.has_feature("web") or not connected:
		return 0
	var ui = JavaScriptBridge.get_interface("OozeChat")
	return int(ui.unread()) if ui != null else 0


func _chat_error(message: String) -> void:
	if OS.has_feature("web"):
		var ui = JavaScriptBridge.get_interface("OozeChat")
		if ui != null:
			ui.error(message)
