class_name RelayBridge
extends RefCounted
## Ooze Syndicate 2.0 - the room-server transport (Alpha 20 stage 1). A drop-in for web/peer-transport.js
## (window.OozePeer): the same five calls Net makes - start / poll / send / closePeer / close - but over one
## WebSocket to server/relay.py instead of PeerJS data channels, so every network that reaches the server can
## play and native builds (Android / iOS) can join too. The relay only forwards strings; the host's Sim still
## owns every rule. poll() returns the relay's events as a JSON string, exactly like OozePeer.poll().
## 0.20.2: every snapshot is handed on (Net's playout buffer spaces them out), and a guest can simulate a bad
## mobile link for tests: --netsim=<latency ms>,<jitter ms>,<stall every s>,<stall length s> on the command line or
## ?netsim=... on the page (in order, like TCP: a stall holds everything behind it).

const STATE_BACKLOG := 64 * 1024                   # skip a snapshot while this much is still queued (as PeerJS did)
const CONNECT_TIMEOUT := 15.0
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var url := ""
var ws: WebSocketPeer
var events: Array = []
var hello := {}
var opened := false                                # the socket reached OPEN
var closing := false                               # we closed it ourselves
var host := false
var _since := 0
var netsim := []                                   # [latency s, jitter s, stall every s, stall length s]; [] = off
var _held: Array = []                              # netsim: [release msec, raw] in arrival order
var _last_release := 0
var poll_json := true                              # poll() also builds the JSON string (legacy callers)
var _typed: Array = []                             # poll_events(): the events as they are (binary data included)
var bytes_in := 0                                  # bytes received (the probes' wire measure)


func _init(relay_url: String) -> void:
	url = relay_url
	var spec := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--netsim="):
			spec = arg.substr(9)
	if spec == "" and OS.has_feature("web"):
		var q = JavaScriptBridge.eval("new URLSearchParams(location.search).get('netsim')||''", true)
		spec = str(q) if q != null else ""
	var parts := spec.split(",")
	if parts.size() == 4:
		netsim = [float(parts[0]) / 1000.0, float(parts[1]) / 1000.0, float(parts[2]), float(parts[3])]


func start(is_host: bool, code: String) -> void:
	if not is_host and not _valid_code(code):
		close()
		_emit({"type": "error", "message": "Enter the four-character room code."})
		return
	start_with(is_host, {"op": "host"} if is_host else {"op": "join", "code": code})


func start_with(is_host: bool, first: Dictionary) -> void:
	## Open the socket and send `first` once it is up: {"op": "create", "version"} asks for a server-hosted
	## room (we join it as a guest), {"op": "host", "room", "secret"} is the server's own match host.
	close()
	host = is_host
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 9 * 1024 * 1024       # a keyframe snapshot can be large (Net.MAX_PACKET 8 MB)
	ws.outbound_buffer_size = 2 * 1024 * 1024
	ws.max_queued_packets = 4096
	hello = first
	opened = false
	closing = false
	_since = Time.get_ticks_msec()
	if ws.connect_to_url(url) != OK:
		ws = null
		_emit({"type": "error", "message": "Could not reach the room server."})


func poll() -> String:
	if ws != null:
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if not opened:
				opened = true
				ws.send_text(JSON.stringify(hello))
			while ws.get_available_packet_count() > 0:
				_arrive(_read())
		elif state == WebSocketPeer.STATE_CLOSING:
			while ws.get_available_packet_count() > 0:  # the relay's last words arrive with its close
				_arrive(_read())
		elif state == WebSocketPeer.STATE_CLOSED:
			while ws.get_available_packet_count() > 0:  # the relay's last words (an error, "closed")
				_arrive(_read())
			if not closing:
				_lost()
			ws = null
		elif state == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() - _since > CONNECT_TIMEOUT * 1000.0:
			ws.close()
			ws = null
			_emit({"type": "error", "message": "Could not reach the room server. Check your connection."})
	var now := Time.get_ticks_msec()
	while not _held.is_empty() and int(_held[0][0]) <= now:   # netsim: packets whose delay is over
		_take(_held.pop_front()[1])
	var out := JSON.stringify(events) if poll_json else ""
	events = []
	return out


func _emit(e: Dictionary) -> void:
	events.append(e)
	_typed.append(e)


func poll_events() -> Array:
	## Net's call (net-5): the same events as poll(), as an Array - binary host packets ("bin", data = bytes)
	## can't ride a JSON string.
	poll_json = false
	poll()
	var out := _typed
	_typed = []
	return out


func send_bin(to: String, packet: PackedByteArray, is_state := false) -> bool:
	## A binary frame for the relay: [1][length of to][to][packet] - it forwards the packet to `to` as [2][...]["host"].
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	if is_state and ws.get_current_outbound_buffered_amount() > STATE_BACKLOG:
		return false                               # a slow link skips snapshots instead of falling behind
	var t := to.to_utf8_buffer()
	var frame := PackedByteArray([1, t.size()])
	frame.append_array(t)
	frame.append_array(packet)
	return ws.send(frame, WebSocketPeer.WRITE_MODE_BINARY) == OK


func _read():
	## One packet: text (the relay's JSON events) as a String, binary (a host packet) as bytes.
	var p := ws.get_packet()
	bytes_in += p.size()
	return p if not ws.was_string_packet() else p.get_string_from_utf8()


func send(to: String, data: String) -> bool:
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	if data.begins_with("{\"kind\":\"state\"") and ws.get_current_outbound_buffered_amount() > STATE_BACKLOG:
		return false                               # a slow link skips snapshots instead of falling behind
	return ws.send_text(JSON.stringify({"op": "send", "to": to, "data": data})) == OK


func closePeer(peer: String) -> void:
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN and host:
		ws.send_text(JSON.stringify({"op": "kick", "peer": peer}))


func close() -> void:
	if ws != null:
		closing = true
		ws.close(1000, "left")
	ws = null
	events = []
	_typed = []
	_held = []


func _arrive(raw) -> void:
	if netsim.is_empty() or host:
		_take(raw)
		return
	var now := Time.get_ticks_msec() / 1000.0
	var at := now + float(netsim[0]) + randf() * float(netsim[1])
	var every := float(netsim[2])
	if every > 0.0 and fmod(now, every) < float(netsim[3]):   # inside a stall: held until it ends
		at = maxf(at, now - fmod(now, every) + float(netsim[3]) + float(netsim[0]))
	var ms := maxi(int(at * 1000.0), _last_release)    # in order, like TCP
	_last_release = ms
	_held.append([ms, raw])


func _take(raw) -> void:
	## Every packet goes on, snapshots included: Net's playout buffer (0.20.2) spaces out a burst instead of
	## this dropping all but the newest. A binary frame [2][length][from][packet] is a host packet (net-5).
	if raw is PackedByteArray:
		var b: PackedByteArray = raw
		if b.size() >= 2 and b[0] == 2 and 2 + b[1] <= b.size():
			_typed.append({"type": "bin", "peer": b.slice(2, 2 + b[1]).get_string_from_utf8(), "data": b.slice(2 + b[1])})
		return
	var event = JSON.parse_string(str(raw))
	if event is Dictionary:
		_emit(event)


func _lost() -> void:
	if not opened:
		_emit({"type": "error", "message": "Could not reach the room server. Check your connection."})
	elif host:
		_emit({"type": "error", "message": "Lost the room server. The room is closed."})
	else:
		for e in events:                           # the relay already said why (host left / room not found)
			if str(e.get("type", "")) in ["closed", "error"]:
				return
		_emit({"type": "closed", "peer": "host"})


static func _valid_code(code: String) -> bool:
	if code.length() != 4:
		return false
	for c in code:
		if not c in CODE_CHARS:
			return false
	return true
