class_name RelayBridge
extends RefCounted
## Ooze Syndicate 2.0 - the room-server transport (Alpha 20 stage 1). A drop-in for web/peer-transport.js
## (window.OozePeer): the same five calls Net makes - start / poll / send / closePeer / close - but over one
## WebSocket to server/relay.py instead of PeerJS data channels, so every network that reaches the server can
## play and native builds (Android / iOS) can join too. The relay only forwards strings; the host's Sim still
## owns every rule. poll() returns the relay's events as a JSON string, exactly like OozePeer.poll().

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


func _init(relay_url: String) -> void:
	url = relay_url


func start(is_host: bool, code: String) -> void:
	close()
	host = is_host
	if not host and not _valid_code(code):
		events.append({"type": "error", "message": "Enter the four-character room code."})
		return
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 9 * 1024 * 1024       # a keyframe snapshot can be large (Net.MAX_PACKET 8 MB)
	ws.outbound_buffer_size = 2 * 1024 * 1024
	ws.max_queued_packets = 4096
	hello = {"op": "host"} if host else {"op": "join", "code": code}
	opened = false
	closing = false
	_since = Time.get_ticks_msec()
	if ws.connect_to_url(url) != OK:
		ws = null
		events.append({"type": "error", "message": "Could not reach the room server."})


func poll() -> String:
	if ws != null:
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if not opened:
				opened = true
				ws.send_text(JSON.stringify(hello))
			while ws.get_available_packet_count() > 0:
				_take(ws.get_packet().get_string_from_utf8())
		elif state == WebSocketPeer.STATE_CLOSING:
			while ws.get_available_packet_count() > 0:  # the relay's last words arrive with its close
				_take(ws.get_packet().get_string_from_utf8())
		elif state == WebSocketPeer.STATE_CLOSED:
			while ws.get_available_packet_count() > 0:  # the relay's last words (an error, "closed")
				_take(ws.get_packet().get_string_from_utf8())
			if not closing:
				_lost()
			ws = null
		elif state == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() - _since > CONNECT_TIMEOUT * 1000.0:
			ws.close()
			ws = null
			events.append({"type": "error", "message": "Could not reach the room server. Check your connection."})
	var out := JSON.stringify(events)
	events = []
	return out


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


func _take(raw: String) -> void:
	var event = JSON.parse_string(raw)
	if not event is Dictionary:
		return
	if str(event.get("type", "")) == "data":       # only the newest snapshot per sender matters (as OozePeer)
		var data := str(event.get("data", ""))
		if data.begins_with("{\"kind\":\"state\""):
			for i in range(events.size()):
				var e: Dictionary = events[i]
				if str(e.get("type", "")) == "data" and e.get("peer") == event.get("peer") \
						and str(e.get("data", "")).begins_with("{\"kind\":\"state\""):
					events[i] = event
					return
	events.append(event)


func _lost() -> void:
	if not opened:
		events.append({"type": "error", "message": "Could not reach the room server. Check your connection."})
	elif host:
		events.append({"type": "error", "message": "Lost the room server. The room is closed."})
	else:
		for e in events:                           # the relay already said why (host left / room not found)
			if str(e.get("type", "")) in ["closed", "error"]:
				return
		events.append({"type": "closed", "peer": "host"})


static func _valid_code(code: String) -> bool:
	if code.length() != 4:
		return false
	for c in code:
		if not c in CODE_CHARS:
			return false
	return true
