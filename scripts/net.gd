extends Node
## Ooze Syndicate 2.0 - online rooms (autoload "Net"). Began as Alpha 11's PeerJS approach, ported from
## Game/Alpha 11/scripts/network.gd (the P2P half) to 2.0's seats, maps and Sim:
## - the transport is RelayBridge (the room server, see ROOM SERVER below; the PeerJS rooms were removed in Alpha 21);
## - four-character room codes, 2-6 players: free-for-all (1v1, FFA 3-5) and teams (2v2, 3v3, 2v2v2),
##   host-assigned seats (join order); in team modes every player can switch team in the lobby (JOIN
##   TEAM, host-validated: a team never exceeds its seats; the host can move players too) and the team
##   decides the seat the player gets at DEPLOY (Daniele, 0.18.7: "there should be so i can switch to my
##   gf team");
## - room colours (Daniele, 0.18.7: the same colours on every screen): every player picks a hue in the
##   lobby, unique in the room, teammates in one hue family (Rules.colour_families); the host validates,
##   and the launch carries the seat -> hue map (room_colours) that every browser renders;
## - the HOST's Sim is the only simulation. Guests send orders (send, recall, upgrade, build, switch,
##   restore); the host validates ownership, rate-limits and answers every order with the same
##   feedback line the offline game toasts. The host broadcasts compressed snapshots ~10 Hz plus the
##   view's effect events; guests render snapshots with light prediction (lines keep moving);
## - version check, all-player loading barrier, round epochs, rematch (everyone accepts, fresh
##   simulation, same room), chat (256 chars, 50 messages, rate limits, host-assigned sender);
## - a guest dropping mid-match keeps the seat for RECONNECT (the AI plays it when EMPTY SEATS is on);
##   the host leaving closes the room;
## - window.oozeBusy (set_busy) tells web/update.js not to reload for a new build during a room.
## SKILLS 2.0 (0.18.7): a cast is an order like a send - order("cast", slot index 0/1/2, {"target": t}) - the
## host validates it with Sim.cast_check and answers with the feedback line. Loadouts ride in the roster
## (set_loadout; a missing one = the faction's default) and the launch packet ("loadouts": seat -> {active,
## map}); ABILITIES ON/OFF is a room setting (toggle_abilities, launch "rules" "abilities_on"). Snapshots
## carry the skill state (effects, cooldowns, charge, demolished decks). Ghost Lines stay secret: the
## broadcast snapshot strips the decoy keys (SECRET_HORDE) and each guest gets a private "ghosts" packet
## listing only its own decoys; fx events marked "private" go to that seat only.
## STRUCTURES 2.1 + TEAMS (0.18.10): new orders "build" (args {"kind": vat / machinegoon / laser / forge /
## monster_hub}), "launch_monster" (a = the hub, args {"to": node}) and "eject" (a = the node), validated by the
## host's Sim (Sim.structure_order: the same feedback line offline). Snapshots carry the new node fields (they
## ride with every node key: "structure", "allies", "arrivals", "shot", "monster_ready_t", "hub_monster"), the
## monsters and the 7:00 draw line ("structs"). Protocol ooze20-net-3.
## ROOM SERVER (Alpha 20 stage 1): the transport is RelayBridge -> server/relay.py (one WebSocket per player,
## the server forwards strings), so strict networks work (Alpha 21: the old ?relay=peerjs rooms are gone). The
## room's creator still hosts the Sim (stage 2 moves it onto the server). No host migration.
## SERVER-HOSTED ROOMS (Alpha 20 stage 2): CREATE ROOM asks the room server for a room it hosts itself
## (host_room -> {"op": "create"}); the server starts this same build headless with --dedicated, which runs
## the room as host with NO seat of its own (roster ids start at 2), and the creator joins as the first guest.
## The ROOM OWNER (Net.room_owner: the first player in, then the next one present if they drop) runs the lobby: the
## lobby controls send {"op": "lobby", "fn", "arg"} and the host applies them only from the owner. So no
## player's device runs the match: a phone in the background just drops its own seat for a RECONNECT. When the
## server has no match host free, or runs another game version, the room falls back to the creator's browser
## as host (the stage-1 rooms). Protocol ooze20-net-4 ("owner" in the lobby packet, the owner's lobby ops).
## SMOOTH SERVER ROOMS (0.20.2, Daniele: "it lags ... connection"): the server's match host runs at 40 fps and sends
## 20 snapshots a second on an even clock (the remainder carries over). A guest in a server room plays them out
## through a small buffer (PLAYOUT_DELAY behind the newest), so bursty mobile data arrives evenly; lines keep moving
## up to EXTRAPOLATE seconds without news, and a correction glides in over BLEND seconds instead of snapping.
## Browser-hosted fallback rooms keep the 0.20.0 behaviour (10 Hz, applied on arrival).
## SMALLER SNAPSHOTS (Alpha 21, ooze20-net-5): between keyframes (once a second) a snapshot carries only the node and
## line fields that differ from the last keyframe (_wire_state); the guest rebuilds the whole snapshot from its copy
## of that keyframe (_unwire_state) - a missed delta costs nothing. Floats are rounded to 1/64 (exact in float32, so
## var_to_bytes stores 4 bytes). Over RelayBridge the host's packets travel as binary frames (no base64 / JSON
## envelope); a bridge without send_bin (the tests' double) keeps the text envelopes. ~57 % fewer bytes on a busy FFA 4.
## ACCOUNTS (0.20.5, with Progression): the device sets `auth_token` (its Supabase access token; "" = signed out) and
## sends it as "auth" in register. A server room's match host verifies it (GET /auth/v1/user) and keeps seat -> user id
## on the host only (never broadcast). When a server room's round ends and a seat has a user id, the host POSTs the
## signed MatchReport to the `match-result` edge function (retries, and the room stays open until it is sent). The
## Supabase address, key and the signing secret come from the server's environment (OOZE_SUPABASE_URL / _KEY,
## OOZE_MATCH_SECRET from /opt/ooze/secrets.env); browser-hosted rooms never report (unranked).
## READY (Alpha 21, Daniele 2026-09-28; protocol ooze20-net-6): every player but the room owner presses READY in the lobby
## (roster[id]["ready"], host-validated); a ready player's faction / colour / team / skills / cosmetics are locked until
## they un-ready, and DEPLOY (can_start) waits for all_ready(). The owner counts as ready - DEPLOY is their ready. An owner's
## settings change (mode, map, EMPTY SEATS, LAST STAND, ABILITIES, moving a player) and the return to the lobby un-ready
## everyone; the players whose flag an owner's change reset get "Settings changed - press READY again".
## NAMES (Alpha 21, Daniele 2026-09-28; ooze20-net-7): every player's display name (the ACCOUNT name, own_name()) rides in
## register; the host cleans it (NAME_MAX printable characters, trimmed) and makes it unique in the room ("NAME (2)"),
## roster[id]["name"]. name_of(id) = that name, or "PLAYER <seat>" without one; the chat stamp and every screen
## (main.seat_who) use it. Client-sent: a server room could verify it against the account's profile later (OPEN-QUESTIONS).
## ROOM LIMITS (Alpha 21, Daniele 2026-09-28): a server room with no round running (lobby, results) closes after ROOM_IDLE
## (10 min; a notice ROOM_IDLE_WARN before, then "rejected" with the reason), so idle tabs can't hold the server's match
## slots; the relay lets one address hold 2 server rooms (a refusal with code "limit" is shown, not a browser fallback).

signal lobby_changed
signal rematch_changed
signal order_feedback(message: String)
signal seats_changed                               # host: which seats the AI plays changed

const VERSION_TAG := "ooze20-net-7"               # plus Rules.VERSION: guests must match the host exactly (2: team switch, room colours; 3: structures 2.1, teams; 4: server-hosted rooms, room owner; 5: delta snapshots, binary frames; 6: READY; 7: player names)
const MODES := ["1v1", "FFA3", "FFA4", "FFA5", "2v2", "3v3", "2v2v2"]
const MODE_LABELS := {"1v1": "1 V 1", "FFA3": "FFA 3", "FFA4": "FFA 4", "FFA5": "FFA 5", "2v2": "2 V 2", "3v3": "3 V 3", "2v2v2": "2V2V2"}
const SLOTS := {"1v1": 2, "FFA3": 3, "FFA4": 4, "FFA5": 5, "2v2": 4, "3v3": 6, "2v2v2": 6}
const TEAM_MODES := ["2v2", "3v3", "2v2v2"]
const SEATS := ["A", "B", "C", "D", "E", "F"]
const FACTIONS := ["vex", "null", "bloom", "ember", "solar"]
const ACTIONS := ["send", "recall", "upgrade", "build_cannon", "build_forge", "restore", "switch", "cast",
		"build", "launch_monster", "eject"]
const STRUCTURE_ACTIONS := ["build", "launch_monster", "eject"]   # run through Sim.structure_order
const BUILD_KINDS := ["vat", "machinegoon", "laser", "forge", "monster_hub"]
const SNAPSHOT_EVERY := 0.1                        # a browser host (fallback rooms)
const SNAPSHOT_EVERY_SERVER := 0.05                # the server's match host (0.20.2: 20 Hz)
const KEYFRAME_EVERY := 10                         # every 10th snapshot carries every horde's path (20th at 20 Hz: once a second)
const PLAYOUT_DELAY := 0.12                        # server rooms: a guest shows the match this far behind the newest snapshot...
const PLAYOUT_DELAY_MAX := 0.35                    # ...up to this after a stall (Alpha 21: adaptive), easing back over PLAYOUT_EASE
const PLAYOUT_EASE := 20.0                         # seconds from the max back to PLAYOUT_DELAY while updates arrive evenly
const STALL := 0.25                                # an arrival gap this long is a stall (at 20 Hz a gap is 0.05 s)
const EXTRAPOLATE := 0.5                           # lines keep moving this long after the last snapshot applied
const BLEND := 0.15                                # a snapshot's correction glides in over this long...
const BLEND_MAX := 6.0                             # ...unless it is bigger than this (sim metres): then it snaps
const PLAYOUT_MAX := 40                            # queued snapshots beyond this are dropped (a tab back from the background)
const PATH_RESEND := 1.0                           # a changed path rides along for this many seconds
const MAX_PACKET := 1024 * 1024                   # 0.21.4: a packet, deflated or not (the largest keyframe measured: 81 KB raw /
                                                   # 13 KB deflated, M-58 2v2 late game; net-1's JSON snapshots needed 8 MB)
const CHAT_MAX := 256
const NAME_MAX := 16                               # NAMES: a player's name in the room, in characters
const CHAT_HISTORY := 50
const HOST_GRACE := 10.0                           # guests wait this long for a silent host (Daniele: 10 s)
const RELAY_URL := "wss://rooms.oozesyndicate.com/ooze"   # server/relay.py behind Caddy on the Vultr box (the domain since 0.21.11; wss://45-32-126-20.sslip.io/ooze still answers for older builds)
const DEDICATED_FPS := 40                          # the server's match host: a steady Sim step, no screen to draw; 2 frames a snapshot
const DEDICATED_IDLE := 30.0                       # a server match everyone dropped out of waits this long for a RECONNECT (0.22.1: was 90; the relay also closes it at 30 s)
const DEDICATED_LOBBY_IDLE := 5.0                  # an empty server lobby closes (nobody can come back to a lobby seat)
const DEDICATED_BOOT_IDLE := 20.0                  # the creator never arrived
const ROOM_IDLE := 600.0                           # a server room with no round running (lobby, results) closes after this
const ROOM_IDLE_WARN := 60.0                       # ...with a notice this long before (Daniele 2026-09-28: idle rooms close after 10 min)
const FALLBACK_CODES := ["no-server", "version", "busy"]   # create refused: host in this browser instead
const REMATCH_AI := "Standard"                     # REMATCH ON A RANDOM MAP picked a bigger mode: the AI fills the extra seats
const AI_FILL := ["", "Training", "Casual", "Standard", "Veteran", "Expert"]   # EMPTY SEATS setting: off or the AI level

var bridge                                         # RelayBridge (or a test double)
var hosting := false
var connected := false                             # host: room open; guest: in the lobby
var room_code := ""
var status := ""
var roster := {}                                   # player id -> {"faction", "slot", "colour"}; host is 1
var links := {}                                    # host: remote peer string -> player id
var next_peer := 2
var remote_host := ""
var assigned_id := 0                               # guest: the id the host gave us
var preferred_faction := "null"
var colour := ""                                   # the hue you asked for (a Rules.HUES key; "" = the host picks one)
# room settings (host decides; guests receive them with the lobby)
var mode := "1v1"
var map_path := ""                                   # set from the map pool when a room opens
const siege := false                               # 0.18.7: SIEGE is deactivated - rooms play BRAWL (the wire fields stay, fixed)
var last_stand := true
var abilities := true                              # ABILITIES ON/OFF (0.18.7: default on in both modes)
var loadout := {}                                  # your own {"active", "map"} (empty = the faction's default)
var cosmetic := {}                                 # your own COSMETICS pick {family: id} (0.19.0; empty = default)
var auth_token := ""                               # 0.20.5: your Supabase access token (Progression sets it; "" = a guest)
var player_name := ""                              # NAMES: tests / --player-name; "" = the ACCOUNT's name (own_name)
var own_ghosts := {}                               # guest: horde id -> true for our own decoys (host tells us only)
var _ghosts_sent := {}                             # host: remote -> the ghost list last sent to it
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
var allow_native := false                          # tests: rooms outside the browser build (the relay works natively)
var dedicated := false                             # this process is the room server's match host (--dedicated): no seat
var room_owner := -1                                    # the player id who runs the lobby (browser host: 1; server room: the first in)
var server_rooms := true                           # CREATE ROOM asks the server to host (false: this browser hosts)
var test_room := false                             # tests: the room is a test - a real player's room may take its server slot
var _creating := false                             # guest: our create request is on its way (a refusal falls back)
var _server_room := ""                             # --room / --secret: the server room this match host serves
var _server_secret := ""
var _empty_t := 0.0                                # dedicated: seconds with nobody in the room
var _users := {}                                   # dedicated: player id -> verified Supabase user id (host only)
var _round_started_at := 0                         # dedicated: unix time the round began (the report's match_id)
var _reported_round := -1
var _report_pending := 0                           # reports still being sent (the room waits for them)
var _ever_joined := false
var _idle_t := 0.0                                 # dedicated: seconds without a round running while players are in the room
var _idle_warned := false
var _room_idle := ROOM_IDLE                        # tests: --idle-close=<s> (a local relay's --host-arg)
var _closing := false
var ai_fill := ""                                  # host setting: "" = every seat needs a player, else the AI level for empty seats
# UI (Daniele 2026-09-28): the ROOM OWNER picks the match background for everyone - "auto" (the map's own) / "rotate" (the next
# one each round) / "0".."n" (that one). The host resolves it to one index at launch (match_info "backdrop", -1 = the map's
# own), so every screen - a headless match host's too - shows the same. Offline each player keeps their own (UiKit).
var room_backdrop := "auto"
const BACKDROP_COUNT := 5                          # Scenery.BATTLE_BACKDROPS.size() (net.gd loads without Scenery)
# The backdrop pick is cosmetic: unlike the other owner settings it does NOT un-READY anyone (🖥️ Server review, 2026-09-29) - on purpose.
# --- end UI ---
var rejoin := {}                                   # guest: {code, token, faction} to RECONNECT to a dropped room
var _tokens := {}                                  # host: player id -> secret rejoin token (never broadcast)
var _fresh := false                                # guest: the first snapshot of a round (a rejoin catches up)
# pacing / limits
var _snap_clock := 0.0
var _snap_count := 0
var _since_snapshot := 0.0
var _play_q: Array = []                            # server-room guest: ["state" | "effects", data] waiting to be shown
var _play_t := -1.0                                # the host time the guest shows now (-1: not started)
var _latest_t := 0.0                               # the newest snapshot's host time
var _since_applied := 0.0                          # seconds since a snapshot was last shown
var _key_snap := {}                                # host: the last keyframe as sent (deltas are against it)
var _key_id := 0
var _base_snap := {}                               # guest: the last keyframe received (a delta rebuilds from it)
var _delay := PLAYOUT_DELAY                        # the playout delay now (adaptive, Alpha 21)
var _calm := 0.0                                   # seconds since the last stall
var _last_arrival := 0                             # msec of the last snapshot's arrival
var corr_big := 0                                  # probe / CONNECTION: corrections > 0.5 m this round, the largest, hard snaps
var corr_max := 0.0
var corr_snaps := 0
# the PAUSE panel's connection line (net_stats_line): is a stutter the network or the device?
var _arrivals: Array = []                          # guest: msec of the snapshots in the last 5 s
var _freeze_n := 0                                 # guest: times this round the shown clock stood still >= 0.1 s
var _freeze_s := 0.0
var _freeze_run := 0.0
var _last_clock := -1.0
var _order_sent: Array = []                        # guest: msec of orders waiting for their feedback line
var _rtt_ms := -1.0
# NET (0.22.x, Daniele: tell a slow phone from a bad connection in the telemetry): the round's totals, round_net_stats()
var _rx_snaps := 0                                 # guest: snapshots received this round
var _rx_first := 0                                 # msec of the first one
var _gap_max := 0                                  # the longest gap between two (msec)
var _rtt_n := 0
var _rtt_sum := 0.0
var _rtt_max := 0.0
var _delay_max := 0.0
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


func server_hosted() -> bool:
	## This room runs on the room server (ranked: its rounds are reported); false in a browser-hosted fallback room and
	## offline. True on every player's device (the owner is a player, never id 1) and on the match host itself.
	return dedicated or (not hosting and bridge != null and room_owner > 1)


func can_control() -> bool:
	## The lobby's controls (mode, map, settings, MOVE, DEPLOY, the random rematch map): the browser host, or a
	## server room's owner. The server's own match host decides nothing by itself.
	if hosting:
		return not dedicated
	return assigned_id > 0 and room_owner == assigned_id


func local_id() -> int:
	return 1 if hosting else assigned_id


func slots() -> int:
	return SLOTS.get(mode, 2)


func seat_of(id: int) -> String:
	return SEATS[int(roster[id]["slot"])] if roster.has(id) else ""


func local_seat() -> String:
	return seat_of(local_id())


func label_of(id: int) -> String:
	## Chat and rematch name: the player's name and faction, stamped by the host (NAMES, net-7; was the seat letter).
	if not roster.has(id):
		return "?"
	return "%s · %s" % [name_of(id).to_upper(), str(roster[id]["faction"]).to_upper()]


# --- NAMES (Alpha 21, ooze20-net-7): players' display names in the room ---
func name_of(id: int) -> String:
	## A player's name in this room (host-cleaned, unique), or "PLAYER <seat>" when they have none.
	if not roster.has(id):
		return ""
	var nm := str(roster[id].get("name", ""))
	return nm if nm != "" else "PLAYER %s" % seat_of(id)


func own_name() -> String:
	## Your display name for the room: player_name (tests), else the ACCOUNT's profile name (its last stored copy when it
	## isn't signed in this run), else "" (the room calls you PLAYER <seat>).
	var nm := player_name
	if nm == "" and Account.enabled:
		var acct = Account._instance                   # the running one only: reading a name never starts an account
		if acct != null and is_instance_valid(acct):
			nm = str(acct.player_name)
		if nm == "":
			var cf := ConfigFile.new()
			if cf.load(Account.path) == OK:
				nm = str(cf.get_value("session", "name", ""))
	return clean_name(nm)


static func clean_name(raw) -> String:
	## Host and client: printable characters only, spaces collapsed, trimmed, at most NAME_MAX.
	var out := ""
	var s := str(raw) if raw is String else ""
	for i in range(s.length()):
		var c := s.unicode_at(i)
		if c < 32 or c == 127 or (c >= 0x200B and c <= 0x200F) or c == 0xFEFF:
			continue
		if c == 32 and (out.is_empty() or out.ends_with(" ")):
			continue
		out += s.substr(i, 1)
		if out.length() >= NAME_MAX:
			break
	return out.strip_edges()


func _unique_name(nm: String, id: int) -> String:
	## Host: two players with one name become "NAME" and "NAME (2)" (the later one gets the suffix).
	if nm == "":
		return ""
	var taken := {}
	for other in roster:
		if int(other) != id:
			taken[str(roster[other].get("name", "")).to_lower()] = true
	if not taken.has(nm.to_lower()):
		return nm
	for n in range(2, 10):
		var tail := " (%d)" % n
		var cand := nm.substr(0, NAME_MAX - tail.length()).strip_edges() + tail
		if not taken.has(cand.to_lower()):
			return cand
	return ""
# --- end NAMES ---


func team_of_slot(slot: int) -> int:
	## Team modes take the map's teams (2v2 A+B vs C+D, 3v3, 2v2v2); FFA: everyone alone (-1).
	if not mode in TEAM_MODES:
		return -1
	var seats: Array = map_data(map_path).get("seats", {}).get(mode, [])
	for s in seats:
		if s["seat"] == SEATS[slot] and s.get("team") != null:
			return int(s["team"])
	return 0 if slot < 2 else 1


func team_ids() -> Array:
	## Team modes: the teams the room's map seats this mode in, in seat order (FFA: none).
	var out := []
	if mode in TEAM_MODES:
		for slot in range(slots()):
			if not team_of_slot(slot) in out:
				out.append(team_of_slot(slot))
	return out


func team_of(id: int) -> int:
	return team_of_slot(int(roster[id]["slot"])) if roster.has(id) else -1


func free_slot_in(team: int) -> int:
	## The first seat of `team` no player holds (-1: the team is full). A seat the AI would fill is free.
	var taken := {}
	for player in roster.values():
		taken[int(player["slot"])] = true
	for slot in range(slots()):
		if not taken.has(slot) and team_of_slot(slot) == team:
			return slot
	return -1


func colour_of(id: int) -> String:
	return str(roster[id].get("colour", "")) if roster.has(id) else ""


func families() -> Array:
	## Team modes: the hue families the teams take (Rules.colour_families); FFA: none.
	return Rules.colour_families(team_ids().size()) if mode in TEAM_MODES else []


static func family_of(fams: Array, key: String) -> int:
	for i in range(fams.size()):
		if key in fams[i]:
			return i
	return -1


func colour_allowed(id: int, key: String) -> bool:
	## A hue is free for `id` when no other player has it and, in team modes, it belongs to a family no
	## player of another team uses (teammates share one family; picking another free family moves your
	## whole team to it - _fix_colours).
	if not roster.has(id) or not Rules.HUES.has(key):
		return false
	var fams := families()
	var fam := family_of(fams, key)
	if mode in TEAM_MODES and fam < 0:
		return false
	for other in roster:
		if int(other) == id:
			continue
		var c := colour_of(int(other))
		if c == key or (fam >= 0 and team_of(int(other)) != team_of(id) and family_of(fams, c) == fam):
			return false
	return true


func room_colours() -> Dictionary:
	## Seat -> hue key for every seat of the mode: the players' picks, then the AI seats - FFA the next
	## free hue (Rules.FFA_ORDER), teams a free hue of the team's family (an all-AI team takes a family
	## nobody uses). The host sends it with the launch; every browser renders exactly this map.
	var out := {}
	var used := {}
	for id in roster:
		var c := colour_of(int(id))
		if Rules.HUES.has(c) and not used.has(c):
			out[seat_of(int(id))] = c
			used[c] = true
	var fams := families()
	var team_fam := {}
	var fam_used := {}
	if not fams.is_empty():
		for slot in range(slots()):                    # the players' teams keep their family
			var f := family_of(fams, str(out.get(SEATS[slot], "")))
			if f >= 0 and not team_fam.has(team_of_slot(slot)) and not fam_used.has(f):
				team_fam[team_of_slot(slot)] = f
				fam_used[f] = true
		for slot in range(slots()):                    # an all-AI team: the first free family
			var t := team_of_slot(slot)
			for f in range(fams.size()):
				if not team_fam.has(t) and not fam_used.has(f):
					team_fam[t] = f
					fam_used[f] = true
	for slot in range(slots()):
		if out.has(SEATS[slot]):
			continue
		var pool: Array = Rules.FFA_ORDER
		if team_fam.has(team_of_slot(slot)):
			pool = (fams[team_fam[team_of_slot(slot)]] as Array) + Rules.FFA_ORDER   # its family first
		for k in pool:
			if not used.has(k):
				out[SEATS[slot]] = k
				used[k] = true
				break
	return out


func _fix_colours(first := -1, last := -1) -> void:
	## Host: give every player a valid hue after any lobby change - unique; in team modes each team in one
	## family (claimed by its first player in seat order whose hue is in a family still free; `first`
	## goes before everyone, `last` after: a pick wins, a newcomer or a team switcher adapts).
	var ids := roster.keys()
	ids.sort_custom(func(a, b): return int(roster[a]["slot"]) < int(roster[b]["slot"]))
	if roster.has(first):
		ids.erase(first)
		ids.push_front(first)
	if roster.has(last):
		ids.erase(last)
		ids.push_back(last)
	var used := {}
	var fams := families()
	var team_fam := {}
	var fam_used := {}
	for id in ids:
		var f := family_of(fams, colour_of(int(id)))
		if f >= 0 and not team_fam.has(team_of(int(id))) and not fam_used.has(f):
			team_fam[team_of(int(id))] = f
			fam_used[f] = true
	for id in ids:
		for f in range(fams.size()):
			if not team_fam.has(team_of(int(id))) and not fam_used.has(f):
				team_fam[team_of(int(id))] = f
				fam_used[f] = true
	for id in ids:
		var c := colour_of(int(id))
		var pool: Array = Rules.FFA_ORDER
		if team_fam.has(team_of(int(id))):
			pool = fams[team_fam[team_of(int(id))]]
		if not c in pool or used.has(c):
			c = ""
			for k in pool + Rules.FFA_ORDER:
				if not used.has(k):
					c = k
					break
		roster[id]["colour"] = c
		used[c] = true


func can_start() -> bool:
	var full := roster.size() == slots() or (ai_fill != "" and roster.size() >= 1)
	return (hosting or can_control()) and connected and not active and full and map_offers(map_path, mode) and all_ready()


# --- READY (Alpha 21, ooze20-net-6): the lobby's per-player ready flag ---
func is_ready(id: int) -> bool:
	## A player is ready when they pressed READY; the room owner always is (DEPLOY is their ready).
	return roster.has(id) and (id == room_owner or bool(roster[id].get("ready", false)))


func all_ready() -> bool:
	## Every player present is ready (AI seats and the owner always are): DEPLOY waits for this.
	for id in present_ids():
		if not is_ready(int(id)):
			return false
	return true


func ready_locked() -> bool:
	## Your picks (faction, colour, team, skills, cosmetics) are locked: you are READY and not the owner.
	return _locked(local_id())


func _locked(id: int) -> bool:
	return roster.has(id) and id != room_owner and bool(roster[id].get("ready", false))


func set_ready(on: bool) -> void:
	## READY / UN-READY in the lobby (a guest; the owner has DEPLOY instead). The host validates it.
	if active or local_id() == room_owner:
		return
	if hosting:
		_set_ready(local_id(), on)
	else:
		_send_to_host({"op": "ready", "ready": on})


func _set_ready(id: int, on: bool) -> void:
	## Host: a player's READY.
	if not hosting or active or not roster.has(id) or id == room_owner or bool(roster[id].get("ready", false)) == on:
		return
	roster[id]["ready"] = on
	publish_lobby()


func _unready_all() -> void:
	## Host: an owner's settings change - everyone confirms again; only the players whose flag was set hear why.
	for id in roster:
		if bool(roster[id].get("ready", false)):
			roster[id]["ready"] = false
			for remote in links:
				if int(links[remote]) == int(id):
					_send(remote, "notice", "Settings changed - press READY again")


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


func set_room_backdrop(v: String) -> void:
	## UI: the owner's BACKGROUND pick for the room (the same checks as the other owner settings).
	if _ask_owner("backdrop", v):
		return
	var ok := v in ["auto", "rotate"] or (v.is_valid_int() and int(v) >= 0 and int(v) < BACKDROP_COUNT)
	if hosting and not active and ok and v != room_backdrop:
		room_backdrop = v
		publish_lobby()


func _backdrop_index() -> int:
	## UI: the round's background for match_info: -1 = the map's own (Scenery.backdrop_for's hash), else that index;
	## ROTATE moves on by one each round, from a room-dependent start.
	if room_backdrop.is_valid_int():
		return clampi(int(room_backdrop), 0, BACKDROP_COUNT - 1)
	if room_backdrop == "rotate":
		return absi(hash(room_code) + match_round + 1) % BACKDROP_COUNT
	return -1


func set_ai_fill(level: String) -> void:
	if _ask_owner("ai_fill", level):
		return
	if hosting and not active and level in AI_FILL and level != ai_fill:
		ai_fill = level
		_unready_all()
		publish_lobby()


func map_data(path: String) -> Dictionary:
	if not _maps.has(path):
		var d = MapBuilder.load_map(path) if FileAccess.file_exists(path) else null
		_maps[path] = d if d is Dictionary else {}
	return _maps[path]


func map_offers(path: String, m: String) -> bool:
	return map_data(path).get("seats", {}).has(m)


func maps_for(m: String) -> Array:
	return MapPool.battlefield().filter(func(p): return map_offers(p, m))   # TUTORIAL: lesson maps never in a room


# ------------------------------------------------------------------ room lifecycle
func host_room(faction: String) -> Error:
	## CREATE ROOM: the room server hosts it (stage 2) unless it can't.
	if server_rooms:
		return _start(false, faction, "", true)
	return _start(true, faction, "")


func join_room(code: String, faction: String) -> Error:
	return _start(false, faction, code)


func reconnect() -> Error:
	## RECONNECT: rejoin the room we dropped out of, into the same seat (the host holds it).
	if rejoin.is_empty():
		return ERR_UNAVAILABLE
	return _start(false, str(rejoin["faction"]), str(rejoin["code"]))


func _start(host: bool, faction: String, code: String, create := false) -> Error:
	leave(false)
	if not OS.has_feature("web") and not allow_native:
		status = "Online rooms run in the browser build (the playtest link)."
		lobby_changed.emit()
		return ERR_UNAVAILABLE
	bridge = RelayBridge.new(relay_url())
	set_busy(true)                                     # a room is open: a new build waits for the menu
	hosting = host
	preferred_faction = faction
	_elapsed = 0.0
	_creating = create
	if host:
		room_owner = 1
		roster = {1: {"faction": faction, "slot": 0, "colour": colour, "loadout": loadout, "cosmetic": cosmetic, "name": own_name()}}
		if not map_offers(map_path, mode) or not map_path in MapPool.battlefield():   # TUTORIAL: never a lesson map
			var pool := maps_for(mode)
			if pool.is_empty():
				mode = "1v1"
				pool = maps_for(mode)
			map_path = pool[0] if not pool.is_empty() else ""
		_fix_colours()
	if create:
		bridge.start_with(false, {"op": "create", "version": version(), "test": test_room})
	else:
		bridge.start(host, code.strip_edges().to_upper())
	status = "Connecting to the room service..."
	lobby_changed.emit()
	return OK


func _start_dedicated() -> void:
	## --dedicated: the room server started this build to host room --room; nobody plays here.
	leave(false)
	bridge = RelayBridge.new(relay_url())
	hosting = true
	room_owner = -1
	roster = {}
	var pool := maps_for(mode)
	map_path = pool[0] if not pool.is_empty() else ""
	bridge.start_with(true, {"op": "host", "room": _server_room, "secret": _server_secret})
	status = "Match host for room %s" % _server_room
	print("dedicated host for room ", _server_room, " (", version(), ")")


func _fallback_host(why: String) -> void:
	## The server could not host (no match host, another version, busy): this browser hosts, as in stage 1.
	var f := preferred_faction
	_start(true, f, "")
	status = "The match server is %s - this browser hosts the room (UNRANKED: results don't count)" % ("busy" if why == "busy" else "unavailable")
	lobby_changed.emit()


func relay_url() -> String:
	## The room server (Alpha 20): RELAY_URL, or ?relay=<ws(s) url> on the page / --relay=<url> on the
	## command line (local tests).
	var pick := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--relay="):
			pick = arg.substr(8)
	if pick == "" and OS.has_feature("web"):
		var q = JavaScriptBridge.eval("new URLSearchParams(location.search).get('relay')||''", true)
		pick = str(q) if q != null else ""
	if pick.begins_with("ws://") or pick.begins_with("wss://"):
		return pick
	return RELAY_URL


func leave(forget := true) -> void:
	## forget = false keeps the RECONNECT details (a dropped connection, not LEAVE ROOM).
	_creating = false
	room_owner = -1
	room_backdrop = "auto"                             # UI: a new room starts on the map's own background
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
	if dedicated:                                      # the server's match host: its room is gone
		print("dedicated host stops: ", message)
		get_tree().quit()
		return
	var was_playing := active
	leave(false)
	status = message
	lobby_changed.emit()
	if was_playing and not no_reload:                 # back to the front menu, which shows the reason
		get_tree().reload_current_scene()


# ------------------------------------------------------------------ lobby (host decides)
func _ask_owner(fn: String, arg = null) -> bool:
	## Not the host: a room owner's lobby change goes to the server's match host; anyone else can't change it.
	## true = handled here (the caller stops).
	if hosting:
		return false
	if can_control() and not active:
		_send_to_host({"op": "lobby", "fn": fn, "arg": arg})
	return true


func _owner_op(id: int, p: Dictionary) -> void:
	## Host: a lobby change from the room owner (the same checks as the host's own buttons).
	if id != room_owner:
		return
	var arg = p.get("arg", null)
	match str(p.get("fn", "")):
		"mode":
			set_mode(str(arg))
		"map":
			if str(arg) in maps_for(mode):
				set_map(str(arg))
		"last_stand":
			if arg is bool and arg != last_stand:
				toggle_last_stand()
		"abilities":
			if arg is bool and arg != abilities:
				toggle_abilities()
		"ai_fill":
			set_ai_fill(str(arg))
		"backdrop":                                    # UI: the owner's BACKGROUND pick
			set_room_backdrop(str(arg))
		"move":
			if arg is Array and (arg as Array).size() == 2 and _is_int(arg[0]) and _is_int(arg[1]):
				move_to_team(int(arg[0]), int(arg[1]))
		"start":
			start_match()
		"rematch_map":                                 # REMATCH ON A RANDOM MAP: the owner's pick, then their vote
			if arg is Array and (arg as Array).size() == 2 and active and finished:
				var m := str(arg[1])
				if m in MODES and present_ids().size() <= SLOTS[m] and str(arg[0]) in maps_for(m):
					map_path = str(arg[0])
					mode = m
				accept_rematch(id)


func propose_rematch(path: String, m: String) -> void:
	## A server room's owner: REMATCH ON A RANDOM MAP (the host applies the pick and counts the vote).
	if not hosting and can_control() and active and finished:
		_send_to_host({"op": "lobby", "fn": "rematch_map", "arg": [path, m]})


func _pick_owner() -> void:
	## A server room: the owner left (or dropped) - the longest-standing player still here runs the lobby.
	if not dedicated or (roster.has(room_owner) and not is_away(room_owner)):
		return
	var ids := present_ids()
	ids.sort()
	room_owner = int(ids[0]) if not ids.is_empty() else -1
	if room_owner > 0:
		_notice("Seat %s now runs the room" % seat_of(room_owner))


func set_mode(m: String) -> void:
	if _ask_owner("mode", m):
		return
	if not hosting or active or not m in MODES or roster.size() > SLOTS[m]:
		return
	var pool := maps_for(m)
	if pool.is_empty():                                # no map seats this mode: keep the current one
		return
	var before := _teams_now()                         # team modes: everyone keeps their team where it exists
	mode = m
	if not map_offers(map_path, mode):
		map_path = pool[0]
	_reseat(before)
	_unready_all()
	publish_lobby()


func set_map(path: String) -> void:
	if _ask_owner("map", path):
		return
	if hosting and not active and map_offers(path, mode):
		var before := _teams_now()                     # another map may seat the teams differently
		map_path = path
		_reseat(before)
		_unready_all()
		publish_lobby()


func toggle_last_stand() -> void:
	if _ask_owner("last_stand", not last_stand):
		return
	if hosting and not active:
		last_stand = not last_stand
		_unready_all()
		publish_lobby()


func toggle_abilities() -> void:
	if _ask_owner("abilities", not abilities):
		return
	if hosting and not active:
		abilities = not abilities
		_unready_all()
		publish_lobby()


func set_loadout(lo: Dictionary) -> void:
	## Your skill loadout for the next round: {"active": id, "map": id} (Rules.ACTIVE_SKILLS / MAP_SKILLS).
	var clean := _clean_loadout(lo)
	if active or ready_locked():
		return
	loadout = clean
	if hosting:
		if roster.has(1):
			roster[1]["loadout"] = clean
			publish_lobby()
	else:
		_send_to_host({"op": "loadout", "active": clean.get("active", ""), "map": clean.get("map", "")})


static func _clean_loadout(lo) -> Dictionary:
	var out := {}
	if lo is Dictionary:
		if str(lo.get("active", "")) in Rules.ACTIVE_SKILLS:
			out["active"] = str(lo["active"])
		if str(lo.get("map", "")) in Rules.MAP_SKILLS:
			out["map"] = str(lo["map"])
	return out


# --- 0.19.0 cosmetics (HUD agent, spec I): the local ARMIES > COSMETICS pick rides in the roster like
# the skill loadout, so every screen can call Cosmetics.set_loadout for a remote seat too. ---
func set_cosmetic(c: Dictionary) -> void:
	## Your COSMETICS pick for the next round: {family: id} (Cosmetics.OPTIONS).
	var clean := _clean_cosmetic(c)
	if active or ready_locked():
		return
	cosmetic = clean
	if hosting:
		if roster.has(1):
			roster[1]["cosmetic"] = clean
			publish_lobby()
	else:
		_send_to_host({"op": "cosmetic", "cosmetic": clean})


static func _clean_cosmetic(c) -> Dictionary:
	var out := {}
	if c is Dictionary:
		for family in Cosmetics.OPTIONS:
			var id := str(c.get(family, ""))
			if id in (Cosmetics.OPTIONS[family] as Array):
				out[family] = id
	return out


func set_faction(f: String) -> void:
	if not f in FACTIONS or active or ready_locked():
		return
	preferred_faction = f
	if hosting:
		if roster.has(1):
			roster[1]["faction"] = f
			publish_lobby()
	else:
		_send_to_host({"op": "faction", "faction": f})


func set_colour(key: String) -> void:
	## Your hue in the lobby: the host validates it (pick_colour) and publishes the room.
	if active or not Rules.HUES.has(key) or ready_locked():
		return
	colour = key
	if hosting:
		pick_colour(1, key)
	else:
		_send_to_host({"op": "colour", "colour": key})


func pick_colour(id: int, key: String) -> bool:
	if not hosting or active or not colour_allowed(id, key):
		return false
	roster[id]["colour"] = key
	_fix_colours(id)                                   # the pick wins; teammates follow its family
	publish_lobby()
	return true


func switch_team(team: int) -> void:
	## JOIN TEAM in the lobby: the host validates it (move_to_team).
	if active or ready_locked():
		return
	if hosting:
		move_to_team(1, team)
	else:
		_send_to_host({"op": "team", "team": team})


func move_to_team(id: int, team: int) -> bool:
	## Host: a player (their own JOIN TEAM, or the host moving them) takes the first free seat of `team`;
	## a full team takes nobody. Empty seats stay for the AI (EMPTY SEATS) or later players.
	if not hosting:
		if id != assigned_id:                          # a server room's owner moving someone
			_ask_owner("move", [id, team])
		return false
	if active or not mode in TEAM_MODES or not roster.has(id) or not team in team_ids() or team_of(id) == team:
		return false
	var slot := free_slot_in(team)
	if slot < 0:
		return false
	roster[id]["slot"] = slot
	_fix_colours(-1, id)                               # the newcomer takes the team's family
	_unready_all()                                     # a ready player can't switch team: this is the owner moving someone
	publish_lobby()
	return true


func _teams_now() -> Dictionary:
	var out := {}
	if mode in TEAM_MODES:
		for id in roster:
			out[id] = team_of(int(id))
	return out


func _reseat(teams := {}) -> void:
	## FFA: seats stay packed from A in join order (host-assigned). Team modes: every player keeps their
	## seat, or their team (`teams`: id -> team, taken before a mode or map change) in its first free
	## seat; a player whose team is gone or full takes the first free seat. Colours follow.
	var ids := roster.keys()
	ids.sort_custom(func(a, b): return int(roster[a]["slot"]) < int(roster[b]["slot"]))
	if not mode in TEAM_MODES:
		for i in range(ids.size()):
			roster[ids[i]]["slot"] = i
		_fix_colours()
		return
	var used := {}
	var left := []
	for id in ids:
		var s := int(roster[id]["slot"])
		var want := int(teams.get(id, team_of_slot(s) if s < slots() else -1))
		if s < slots() and not used.has(s) and team_of_slot(s) == want:
			used[s] = true
		else:
			left.append([id, want])
	var still := []
	for e in left:
		var placed := false
		for s in range(slots()):
			if not used.has(s) and team_of_slot(s) == e[1]:
				roster[e[0]]["slot"] = s
				used[s] = true
				placed = true
				break
		if not placed:
			still.append(e[0])
	for id in still:
		for s in range(slots()):
			if not used.has(s):
				roster[id]["slot"] = s
				used[s] = true
				break
	_fix_colours()


func publish_lobby() -> void:
	_broadcast("lobby", {"roster": roster, "mode": mode, "map": map_path, "siege": siege,
			"last_stand": last_stand, "round": match_round, "ai_fill": ai_fill, "abilities": abilities, "owner": room_owner,
			"backdrop": room_backdrop})                # UI: an older client ignores it
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
	roster[id] = {"faction": f if f in FACTIONS else FACTIONS[slot % FACTIONS.size()], "slot": slot, "colour": "",
			"loadout": _clean_loadout(p.get("loadout", {})), "cosmetic": _clean_cosmetic(p.get("cosmetic", {}))}
	roster[id]["name"] = _unique_name(clean_name(p.get("name", "")), id)   # NAMES (net-7)
	var want := str(p.get("colour", ""))
	if colour_allowed(id, want):
		roster[id]["colour"] = want
	_fix_colours(-1, id)                               # a newcomer's hue gives way to the room's
	_ever_joined = true
	var auth = p.get("auth", "")
	if dedicated and auth is String and auth != "" and (auth as String).length() < 3000:
		_verify_auth(id, auth)
	if dedicated and not roster.has(room_owner):            # a server room: the first player in runs it
		room_owner = id
	_tokens[id] = _new_token()
	_send(remote, "identity", {"id": id, "token": _tokens[id]})
	_send(remote, "chat_history", chat_history)
	publish_lobby()


func _reclaim(remote: String, id: int) -> void:
	## A dropped player is back: same id, same seat; mid-match they get the round and catch up.
	links[remote] = id
	roster[id].erase("away")
	if dedicated and (not roster.has(room_owner) or is_away(room_owner)):
		room_owner = id
	_send(remote, "identity", {"id": id, "token": _tokens[id]})
	_send(remote, "chat_history", chat_history)
	if active:
		match_info["roster"] = roster
		_send(remote, "launch", match_info)
	_notice("Seat %s reconnected" % seat_of(id))
	seats_changed.emit()
	publish_lobby()


func _new_token() -> String:
	return Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(12))   # 0.21.4: crypto-grade (was randi())


func _notice(message: String) -> void:
	## Host: a line every player sees as a toast (drops, reconnects).
	_broadcast("notice", message)
	order_feedback.emit(message)


func version() -> String:
	return VERSION_TAG + "/" + Rules.VERSION


# ------------------------------------------------------------------ rounds
func start_match() -> void:
	if not hosting:
		if can_start():
			_ask_owner("start")
		return
	if can_start():
		launch_round()


func launch_round(fill := "") -> void:
	## fill: the AI level for seats nobody holds when EMPTY SEATS is off (REMATCH ON A RANDOM MAP).
	for id in roster.keys():                          # a new round: anyone still away has left
		if is_away(int(id)):
			roster.erase(id)
			_tokens.erase(id)
	_reseat()
	_pick_owner()
	var players := {}
	var loadouts := {}                                 # players' picks; AI seats get their faction default in Sim.setup
	var cosmetics := {}                                 # players' COSMETICS picks (0.19.0); AI seats: default
	for id in roster:
		players[seat_of(id)] = roster[id]["faction"]
		var lo := _clean_loadout(roster[id].get("loadout", {}))
		if not lo.is_empty():
			loadouts[seat_of(id)] = lo
		var co := _clean_cosmetic(roster[id].get("cosmetic", {}))
		if not co.is_empty():
			cosmetics[seat_of(id)] = co
	var ai := {}
	var level := ai_fill if ai_fill != "" else fill
	if level != "":
		for slot in range(slots()):                    # EMPTY SEATS: the AI plays them (team modes: any seat)
			if players.has(SEATS[slot]):
				continue
			var free := FACTIONS.filter(func(f): return not f in players.values())
			players[SEATS[slot]] = free[randi() % free.size()] if not free.is_empty() else FACTIONS[randi() % FACTIONS.size()]
			ai[SEATS[slot]] = level
	var info := {"round": match_round + 1, "map": map_path, "mode": mode, "seed": randi() % 100000,
			"players": players, "roster": roster, "ai": ai, "ai_fill": ai_fill, "colours": room_colours(), "loadouts": loadouts,
			"backdrop": _backdrop_index(),             # UI: the round's background, the same on every screen
			"cosmetics": cosmetics,
			"rules": {"bridge_combat": siege, "last_stand": last_stand, "abilities_on": abilities, "deck_speed": Rules.deck_speed,
					"node_speed_mult": Rules.node_speed_mult, "door_rate": Rules.door_rate,
					"node_fight_mult": Rules.node_fight_mult, "forge_bonus": Rules.forge_bonus,
					"hide_enemy_counts": Rules.hide_enemy_counts, "balance_preset": Rules.BALANCE_PRESET}}
	_broadcast("launch", info)
	_launch(info)


func _launch(info: Dictionary) -> void:
	match_info = info
	match_round = int(info["round"])
	roster = info["roster"]
	mode = str(info["mode"])
	map_path = str(info["map"])
	var r: Dictionary = info["rules"]
	last_stand = bool(r["last_stand"])                 # (r["bridge_combat"] is always false: BRAWL only)
	Rules.bridge_combat = false
	Rules.last_stand = last_stand
	Rules.deck_speed = float(r["deck_speed"])
	Rules.node_speed_mult = float(r["node_speed_mult"])
	Rules.door_rate = float(r["door_rate"])
	Rules.node_fight_mult = float(r["node_fight_mult"])
	Rules.apply_balance(str(r.get("balance_preset", "")))   # the host's balance preset (0.18.7; "" = default numbers)
	Rules.forge_bonus = float(r["forge_bonus"])
	Rules.hide_enemy_counts = bool(r.get("hide_enemy_counts", false))   # the host's option, the same for all
	abilities = bool(r.get("abilities_on", true))
	Rules.abilities_on = abilities
	own_ghosts = {}
	_ghosts_sent = {}
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
	_key_snap = {}
	_base_snap = {}
	_play_q = []
	_play_t = -1.0
	_latest_t = 0.0
	_since_applied = 0.0
	_arrivals = []
	_delay = PLAYOUT_DELAY
	_calm = 0.0
	_last_arrival = 0
	corr_big = 0
	corr_max = 0.0
	corr_snaps = 0
	_freeze_n = 0
	_freeze_s = 0.0
	_freeze_run = 0.0
	_last_clock = -1.0
	_order_sent = []
	_rx_snaps = 0                                  # NET: the round's network totals start again
	_rx_first = 0
	_gap_max = 0
	_rtt_n = 0
	_rtt_sum = 0.0
	_rtt_max = 0.0
	_delay_max = 0.0
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
	_round_started_at = int(Time.get_unix_time_from_system())
	_since_snapshot = 0.0


func peer_left(id: int) -> void:
	if not hosting or not roster.has(id):
		return
	if active:                                         # mid-match: hold the seat for a RECONNECT
		roster[id]["away"] = true
		rematch_votes.erase(id)
		ready_peers.erase(id)
		_notice("Seat %s lost connection - they can RECONNECT%s" % [seat_of(id), " (the AI plays it meanwhile)" if ai_fill != "" else ""])
		_pick_owner()
		seats_changed.emit()
		_check_barrier()
		publish_lobby()
		_check_rematch()
		return
	roster.erase(id)
	_tokens.erase(id)
	_users.erase(id)
	rematch_votes.erase(id)
	ready_peers.erase(id)
	_reseat()
	_pick_owner()
	publish_lobby()


func return_to_room(message: String) -> void:
	if hosting:                                        # back in the lobby: dropped players are gone
		for id in roster.keys():
			if is_away(int(id)):
				roster.erase(id)
				_tokens.erase(id)
		_reseat()
		_pick_owner()
		for id in roster:                              # a new lobby: everyone confirms again (no toast: they know)
			roster[id]["ready"] = false
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
		var r: Array = sim.structure_order(local_seat(), action, a, args) if action in STRUCTURE_ACTIONS \
				else main.perform(local_seat(), action, a, args)
		order_feedback.emit(r[1])
	else:
		_send_to_host({"op": "order", "round": match_round, "action": action, "a": a, "args": args})
		_order_sent.append(Time.get_ticks_msec())
		if _order_sent.size() > 20:
			_order_sent.pop_front()


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
	if action == "cast":                               # a = slot index; the host's Sim checks the rest
		if int(a) < 0 or int(a) > 2:
			return [false, "Order rejected"]
		var t = clean_target(args.get("target", null))
		if t is bool:
			return [false, "Order rejected"]
		clean = {"target": t}
	if action == "send":
		if not _is_int(args.get("to", null)) or not (args.get("fraction", null) is float or args.get("fraction", null) is int):
			return [false, "Order rejected"]
		var f := float(args["fraction"])
		if not is_finite(f) or f <= 0.0 or f > 1.0:
			return [false, "Order rejected"]
		clean = {"to": int(args["to"]), "fraction": f}
	if action == "build":
		if not args.get("kind", null) is String or not args["kind"] in BUILD_KINDS:
			return [false, "Order rejected"]
		clean = {"kind": str(args["kind"])}
	if action == "launch_monster":
		if not _is_int(args.get("to", null)):
			return [false, "Order rejected"]
		clean = {"to": int(args["to"])}
	if action in STRUCTURE_ACTIONS:                    # the host's Sim validates ownership, costs and reach
		if sim == null or int(a) < 0 or int(a) >= sim.nodes.size():
			return [false, "Order rejected"]
		return sim.structure_order(seat_of(id), action, int(a), clean)
	return main.perform(seat_of(id), action, int(a), clean)


static func clean_target(t):
	## A cast target off the wire: null, an int id, or a short array of ints / a fraction / "jam" / "fire".
	## Anything else -> false (rejected).
	if t == null:
		return null
	if _is_int(t):
		return int(t)
	if t is Array and (t as Array).size() >= 1 and (t as Array).size() <= 3:
		var out := []
		for x in t:
			if _is_int(x):
				out.append(int(x))
			elif x is float and is_finite(x) and x > 0.0 and x <= 1.0:
				out.append(float(x))
			elif x is String and x in ["jam", "fire"]:
				out.append(x)
			else:
				return false
		return out
	return false


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


func rematch_status() -> Dictionary:
	## For the results screen: {"mine": did I vote, "ready": [labels], "waiting": [labels]} over the players still here.
	var ready := []
	var waiting := []
	for id in present_ids():
		(ready if rematch_votes.has(id) else waiting).append(label_of(int(id)) + ("  (you)" if int(id) == local_id() else ""))
	return {"mine": rematch_votes.has(local_id()), "ready": ready, "waiting": waiting}


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
	elif mode != str(match_info.get("mode", mode)):    # the random rematch map seats more than are here: the AI fills the
		launch_round(REMATCH_AI)                        # rest (Daniele, 0.19.0: "AI fills the rest"; it used to send the room back to the lobby)
	else:                                              # a seat is empty and no AI may take it
		var msg := "A player is missing - back to the lobby. Invite someone with the same code."
		return_to_room(msg)                            # publishes the repacked lobby first...
		_broadcast("room_reset", msg)                  # ...so the guests keep this reason as their status


# ------------------------------------------------------------------ snapshots
static func path_key(h: Dictionary) -> String:
	var pts: PackedVector3Array = h["pts"]
	return "%s|%.3f|%d|%s" % [str(h["route"]), float(h["L"]), pts.size(), str(h.get("retreat", false))]


const PATH_FIELDS := ["pts", "cum", "fast", "spans", "node_spans"]
const SECRET_HORDE := ["decoy", "echo", "ghost_left", "landed", "blame"]   # never broadcast (the Ghost Line bluff)
const NODE_SKIP := ["pos", "transit", "category", "center", "relay", "buildable", "id", "node_kind"]


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
			if (send_path or not k in PATH_FIELDS) and not k in SECRET_HORDE:
				d[k] = h[k]
		hs.append(d)
		alive[h["id"]] = true
	for id in _path_seen.keys():
		if not alive.has(id):
			_path_seen.erase(id)
	var ms := []                                      # monsters: their path arrays only on keyframes (guests rebuild them)
	for m in s.monsters:
		var md := {}
		for k in m:
			if keyframe or not k in PATH_FIELDS:
				md[k] = m[k]
		ms.append(md)
	var snap := {"round": match_round, "t": s.time, "over": s.over, "winner": s.winner, "next_id": s._next_id,
			"nodes": nodes, "hordes": hs, "fights": s.fights, "fight_info": s.fight_info,
			"collapsed": s.collapsed, "eliminated": s.eliminated,
			"ls": [s.last_stand_active, s.last_stand_method, s.last_stand_order, s.last_stand_final,
					s.last_stand_next, s.last_stand_warn_node, s.last_stand_warn_t, s.last_stand_wave, s._next_wave_at,
					s.last_stand_waves, s.last_stand_keep, s.last_stand_warn, s.last_stand_queue,
					s.very_last_stand_active, s.very_last_stand_gap, s.last_stand_gap],
			"losses": [s.combat_losses, s.fall_losses],
			"skills": [s.effects, s.demolished, s.skill_cd, s.ult_charge, s.ult_since],
			"structs": [ms, s._next_monster, s.draw_line]}
	if s.over:
		snap["events"] = s.events                    # the end screen's captures count
	return snap


func _wire_state(full: Dictionary, keyframe: bool) -> Dictionary:
	## Host (net-5): a keyframe goes whole (and becomes the base); in between, only what differs from it -
	## per node index its changed fields, per line its id + changed fields (a line newer than the keyframe whole).
	if keyframe or _key_snap.is_empty():
		_key_id += 1
		_key_snap = full
		var k: Dictionary = _q64(full)
		k["key"] = _key_id
		return k
	var out := {}
	for f in full:
		if f != "nodes" and f != "hordes":
			out[f] = full[f]
	var nodes := {}
	var kn: Array = _key_snap["nodes"]
	var fn: Array = full["nodes"]
	for i in range(fn.size()):
		var d: Dictionary = fn[i]
		var k: Dictionary = kn[i] if i < kn.size() else {}
		var ch := {}
		for f in d:
			if not k.has(f) or k[f] != d[f]:
				ch[f] = d[f]
		if not ch.is_empty():
			nodes[i] = ch
	var kh := {}
	for h in _key_snap["hordes"]:
		kh[h["id"]] = h
	var hordes := []
	for h in full["hordes"]:
		var k: Dictionary = kh.get(h["id"], {})
		if k.is_empty():
			hordes.append(h)
			continue
		var ch := {"id": h["id"]}
		for f in h:
			if not k.has(f) or k[f] != h[f]:
				ch[f] = h[f]
		hordes.append(ch)
	out["nodes_d"] = nodes
	out["hordes"] = hordes
	out["base"] = _key_id
	return _q64(out)


func _unwire_state(w: Dictionary) -> Dictionary:
	## Guest (net-5): a keyframe is stored as the base; a delta is laid over a copy of it. A delta for a keyframe we
	## don't have (joined mid-second, or a skipped keyframe) is dropped - the next keyframe comes within a second.
	if w.has("key"):
		_base_snap = w
		return w
	if not w.has("base"):                              # a pre-net-5 whole snapshot
		return w
	if _base_snap.is_empty() or int(_base_snap.get("key", -1)) != int(w["base"]):
		return {}
	var full := {}
	for f in w:
		if f != "nodes_d" and f != "hordes" and f != "base":
			full[f] = w[f]
	var nodes := []
	var nd: Dictionary = w["nodes_d"]
	var bn: Array = _base_snap["nodes"]
	for i in range(bn.size()):
		var d: Dictionary = (bn[i] as Dictionary).duplicate()
		if nd.has(i):
			d.merge(nd[i], true)
		nodes.append(d)
	var bh := {}
	for h in _base_snap["hordes"]:
		bh[h["id"]] = h
	var hordes := []
	for h in w["hordes"]:
		var b: Dictionary = bh.get(h["id"], {})
		if b.is_empty():
			hordes.append(h)
		else:
			var d: Dictionary = b.duplicate()
			d.merge(h, true)
			hordes.append(d)
	full["nodes"] = nodes
	full["hordes"] = hordes
	return full


static func _q64(v):
	## Floats rounded to 1/64: exact in float32, so var_to_bytes stores 4 bytes, and the guest needs no decoding.
	if v is float:
		return round(v * 64.0) / 64.0 if absf(v) < 100000.0 else v
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _q64(v[k])
		return d
	if v is Array:
		var a := []
		for x in v:
			a.append(_q64(x))
		return a
	return v


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
		if not d.has("structure") and d.has("attachment"):   # a pre-2.1 host: its cannons read as lasers
			n["structure"] = "laser" if d["attachment"] == "cannon" else (str(d["attachment"]) if d["attachment"] != "" \
					else ("" if n["relay"] != "" else "vat"))
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
	if ls.size() > 14:                                # 0.18.9: Very Last Stand
		s.very_last_stand_active = ls[13]
		s.very_last_stand_gap = ls[14]
	if ls.size() > 15:                                # 2026-09-27: the adaptive ring drop gap (drop_in countdowns)
		s.last_stand_gap = ls[15]
	s.combat_losses = snap["losses"][0]
	s.fall_losses = snap["losses"][1]
	if snap.has("skills"):                            # SKILLS 2.0: effects, demolished decks, cooldowns, charge
		var sk: Array = snap["skills"]
		s.effects = sk[0]
		s.demolished = sk[1]
		s.skill_cd = sk[2]
		s.ult_charge = sk[3]
		s.ult_since = sk[4]
		s._index_effects()
	if snap.has("structs"):                           # 0.18.10: monsters and the 7:00 draw line
		var st: Array = snap["structs"]
		var had := {}
		for m in s.monsters:
			had[m["id"]] = m
		for m in st[0]:
			if not m.has("pts"):                      # a lean snapshot: keep the path we have, or build it from the route
				var prev: Dictionary = had.get(m["id"], {})
				var path: Dictionary = prev if prev.has("pts") else s.build_path(m["route"])
				for k in PATH_FIELDS:
					m[k] = path[k]
		s.monsters = st[0]
		s._next_monster = int(st[1])
		s.draw_line = str(st[2])
	for c in changes:
		s.captured.emit(c[0], c[1], c[2])
	if snap.has("events"):
		s.events = snap["events"]
	if bool(snap["over"]) and not s.over:
		s.over = true
		s.winner = str(snap["winner"])
		s.finished.emit(s.winner)


func _verify_auth(id: int, token: String) -> void:
	## Server room: who is this player? GET /auth/v1/user with their access token; a 200 maps the seat to the user id
	## (guest accounts too), anything else leaves them a guest (plays, no rewards).
	var url := OS.get_environment("OOZE_SUPABASE_URL")
	var key := OS.get_environment("OOZE_SUPABASE_KEY")
	if url == "" or key == "":
		return
	var req := HTTPRequest.new()
	req.timeout = 10.0
	add_child(req)
	req.request_completed.connect(func(result, code, _h, body):
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and roster.has(id):
			var u = JSON.parse_string(body.get_string_from_utf8())
			if u is Dictionary and str(u.get("id", "")) != "":
				_users[id] = str(u["id"])
				print("seat of player %d: account %s%s" % [id, str(u["id"]).left(8), " (guest)" if u.get("is_anonymous", false) else ""]))
	if req.request(url + "/auth/v1/user", ["apikey: " + key, "Authorization: Bearer " + token]) != OK:
		req.queue_free()


func _report_round() -> void:
	## Server room, a round just ended: the signed MatchReport, if any seat belongs to an account (Progression: a room
	## with nobody signed in credits nobody, so it sends nothing).
	var secret := OS.get_environment("OOZE_MATCH_SECRET")
	var url := OS.get_environment("OOZE_SUPABASE_URL")
	if secret == "" or url == "" or sim == null:
		return
	var users := {}
	var left := {}
	for id in roster:
		var seat := seat_of(int(id))
		if _users.has(id):
			users[seat] = _users[id]
		if is_away(int(id)):
			left[seat] = true
	if users.is_empty():
		print("round %d: no signed-in seat - not reported" % match_round)
		return
	var report := MatchReport.payload(sim, match_info, users, left, _server_room, match_round, _round_started_at)
	var seats := []                                    # one line in the room log: who was reported, who won
	for st in report["seats"]:
		seats.append("%s %s%s%s" % [st["seat"], str(st["user_id"]).left(8) if st["user_id"] != null else ("AI" if st["ai_level"] != null else "guest"),
				" won" if st["won"] else "", " left" if st["left_early"] else ""])
	print("report %s %s: %s" % [report["match_id"], report["mode"], ", ".join(seats)])
	var body := JSON.stringify(report)
	_report_pending += 1
	_post_report(url + "/functions/v1/match-result", secret, body, 0)


func _post_report(url: String, secret: String, body: String, attempt: int) -> void:
	## Signed per attempt (the timestamp must be fresh); network errors and 5xx retry after 3 / 10 / 30 s.
	var ts := int(Time.get_unix_time_from_system())
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	req.request_completed.connect(func(result, code, _h, resp):
		req.queue_free()
		var text: String = resp.get_string_from_utf8().left(200)
		if result == HTTPRequest.RESULT_SUCCESS and code < 500:
			print("match report %d: %s" % [code, text])
			_report_pending -= 1
		elif attempt < 3:
			print("match report retry %d (%s %d)" % [attempt + 1, result, code])
			get_tree().create_timer([3.0, 10.0, 30.0][attempt]).timeout.connect(func(): _post_report(url, secret, body, attempt + 1))
		else:
			print("match report given up (%s %d): %s" % [result, code, text])
			_report_pending -= 1)
	var headers := ["Content-Type: application/json", "x-ooze-ts: %d" % ts, "x-ooze-sig: " + MatchReport.sign(secret, ts, body)]
	if req.request(url, headers, HTTPClient.METHOD_POST, body) != OK:
		req.queue_free()
		_report_pending -= 1


func _track_freeze(dt: float) -> void:
	## Guest: a freeze = the shown match clock standing still for 0.1 s or more while the round runs.
	if finished or sim.over:
		return
	if sim.time <= _last_clock + 0.0001:
		_freeze_run += dt
	else:
		if _freeze_run >= 0.1:
			_freeze_n += 1
			_freeze_s += _freeze_run
		_freeze_run = 0.0
	_last_clock = sim.time


func round_net_stats() -> Dictionary:
	## NET: this guest's network over the round, for the match telemetry: updates a second, the longest gap between two,
	## freezes, the order round trip (mean / worst), the largest playout buffer, corrections. {} on a host or offline.
	if hosting or bridge == null or _rx_snaps < 2:
		return {}
	var span := maxf(0.001, (_last_arrival - _rx_first) / 1000.0)
	return {"hz": snappedf((_rx_snaps - 1) / span, 0.1), "gap_max_ms": _gap_max, "freezes": _freeze_n,
			"freeze_s": snappedf(_freeze_s, 0.1), "rtt_ms": int(round(_rtt_sum / _rtt_n)) if _rtt_n > 0 else -1,
			"rtt_max_ms": int(_rtt_max), "buffer_max_s": snappedf(_delay_max, 0.01), "corrections": corr_big,
			"hard_snaps": corr_snaps, "server_hosted": server_hosted()}


func net_stats_line() -> String:
	## The PAUSE panel in an online round (Daniele: "some stutter here and there"): the device's frame rate, how
	## many updates arrive a second, the freezes this round and the order round trip - a screenshot tells a slow
	## phone (low fps) from a bad connection (few updates, freezes, a long round trip).
	var fps := int(Engine.get_frames_per_second())
	if hosting:
		return "CONNECTION  %d fps  ·  this device hosts the room" % fps
	var span := 5.0
	if not _arrivals.is_empty():
		span = clampf((Time.get_ticks_msec() - int(_arrivals[0])) / 1000.0, 1.0, 5.0)
	var rate := _arrivals.size() / span
	var rtt := ("%d ms" % int(_rtt_ms)) if _rtt_ms >= 0.0 else "- ms"
	var buf := ("  ·  buffer %.2f s" % _delay) if _smooth() else ""
	return "CONNECTION  %d fps  ·  %d updates/s  ·  %d freeze%s (%.1f s)  ·  round trip %s%s" % [
			fps, int(round(rate)), _freeze_n, "" if _freeze_n == 1 else "s", _freeze_s, rtt, buf]


func _smooth() -> bool:
	## A guest in a server-hosted room (0.20.2 smoothing); fallback rooms keep the old apply-on-arrival.
	return not hosting and room_owner > 1 and sim != null


func _apply_state(data: Dictionary) -> void:
	## Show one snapshot. Server rooms: a line the snapshot moves by less than BLEND_MAX keeps its shown place and
	## glides to the host's over BLEND (blend), and the shown clock never runs backwards by a little.
	var shown := {}
	if _smooth():
		for h in sim.hordes:
			shown[h["id"]] = [float(h["s"]), str(h.get("_pk", ""))]
	var clock := sim.time
	apply_snapshot(sim, data)
	_mark_ghosts()
	_since_applied = 0.0
	if not shown.is_empty():
		for h in sim.hordes:
			var was = shown.get(h["id"], null)
			if was != null and str(was[1]) == str(h.get("_pk", "")):
				var d := float(h["s"]) - float(was[0])
				if absf(d) > 0.5:
					corr_big += 1
				corr_max = maxf(corr_max, absf(d))
				if absf(d) >= BLEND_MAX:
					corr_snaps += 1
				if absf(d) < BLEND_MAX:
					h["_corr"] = d
					h["s"] = float(was[0])
		if clock > sim.time and clock - sim.time < EXTRAPOLATE:
			sim.time = clock
	if _fresh:                                        # joined late (RECONNECT): drop the nodes that already fell
		_fresh = false
		for id in sim.collapsed:
			sim.fx_events.append({"type": "collapse", "node": id})
	if sim.over:
		finished = true


func _playout(dt: float) -> void:
	## Server-room guest: release queued snapshots when the shown clock reaches them. The shown clock runs
	## PLAYOUT_DELAY behind the newest snapshot, a little faster or slower (up to 10 %) to stay there; far off (the
	## start, a long stall, a tab back) it jumps.
	_since_applied += dt
	if _play_q.is_empty():
		if _play_t >= 0.0:
			_play_t += dt
		return
	while _play_q.size() > PLAYOUT_MAX:                # far behind: the old snapshots are history (effects still play)
		var old: Array = _play_q.pop_front()
		if old[0] == "effects" and sim != null:
			sim.fx_events.append_array(old[1]["events"])
	_calm += dt
	if _calm > 5.0 and _delay > PLAYOUT_DELAY:         # steady for a while: ease back towards the short delay
		_delay = maxf(PLAYOUT_DELAY, _delay - dt * (PLAYOUT_DELAY_MAX - PLAYOUT_DELAY) / PLAYOUT_EASE)
	var target := _latest_t - _delay
	if _play_t < 0.0 or absf(target - _play_t) > 0.5:
		_play_t = target
	else:
		_play_t += dt * clampf(1.0 + (target - _play_t) * 2.0, 0.9, 1.1)
	while not _play_q.is_empty():
		var e: Array = _play_q[0]
		if e[0] == "state" and float(e[1].get("t", 0.0)) > _play_t:
			break
		_play_q.pop_front()
		if e[0] == "state":
			_apply_state(e[1])
		elif sim != null:
			sim.fx_events.append_array(e[1]["events"])


static func blend(s: Sim, dt: float) -> void:
	## A snapshot's correction (Net._apply_state) glides in: a share each frame, all of it within ~BLEND.
	var k := minf(1.0, dt / BLEND)
	for h in s.hordes:
		if h.has("_corr"):
			var c := float(h["_corr"])
			var step := c * k
			h["s"] = clampf(float(h["s"]) + step, 0.0, float(h["L"]))
			if absf(c - step) < 0.001:
				h.erase("_corr")
			else:
				h["_corr"] = c - step


static func predict(s: Sim, dt: float) -> void:
	## Light prediction between snapshots: the clock runs and lines keep moving at their speed.
	s.time += dt
	for h in s.hordes:
		if h["state"] != "move" or h.get("blocked", false):
			continue
		var mult: float = Rules.platform_mult() if Sim.sample(h, h["s"])[2] else 1.0
		var boost := s.skill_speed(h)                 # Surge / Rewire
		mult *= s.deck_slow(h) * boost                # enemy goo or Mire, the stronger
		var ds: float = Rules.move_speed() * h.get("speed", 1.0) * s.stat(h["owner"], "speed") * mult * dt
		if h["streaming"]:
			ds = minf(ds, Rules.exit_rate() * Rules.metres_per_unit() * maxf(boost, s.door_mult(h)) * dt)   # Surge: the door doubles too
		if h.get("pour", false):                    # walking off a lip: the head stays, the line pours on
			h["fcut"] = float(h.get("fcut", 0.0)) + ds
			h["units"] = maxf(0.0, h["units"] - ds / Rules.metres_per_unit())
			continue
		h["s"] = minf(h["s"] + ds, h["L"])
	for m in s.monsters:                              # monsters keep walking between snapshots
		if m["state"] == "walking" and m.has("cum"):
			m["s"] = minf(float(m["s"]) + s.monster_speed() * dt, float(m["L"]))
			m["pos"] = Sim.sample(m, m["s"])[0]


func push_effects(events: Array) -> void:
	## Host: the view's one-off effects (bursts, falls, relay ticks, collapses) for the guests. An event
	## with a "private" seat goes to that seat's guest only (Ghost Line casts, Echo Split's echo list).
	if not (hosting and online() and not events.is_empty() and _has_guests()):
		return
	var public := events.filter(func(e): return not (e as Dictionary).has("private"))
	if not public.is_empty():
		_broadcast("effects", {"round": match_round, "events": public})
	for e in events:
		if (e as Dictionary).has("private"):
			for remote in links:
				if roster.has(links[remote]) and seat_of(links[remote]) == str(e["private"]):
					_send(remote, "effects", {"round": match_round, "events": [e]})


func _send_ghosts(keyframe: bool) -> void:
	## Host: each guest learns which lines are ITS decoys (never anyone else's), when that changes.
	var by_seat := {}
	for h in sim.hordes:
		if h.get("decoy", false):
			if not by_seat.has(h["owner"]):
				by_seat[h["owner"]] = []
			by_seat[h["owner"]].append(h["id"])
	for remote in links:
		if not roster.has(links[remote]):
			continue
		var ids: Array = by_seat.get(seat_of(links[remote]), [])
		if keyframe or _ghosts_sent.get(remote, []) != ids:
			_ghosts_sent[remote] = ids
			_send(remote, "ghosts", {"round": match_round, "ids": ids})


# ------------------------------------------------------------------ loop
func _process(dt: float) -> void:
	if bridge == null:
		return
	_poll(dt)
	_poll_chat_ui(dt)
	if dedicated and bridge != null and connected:     # an empty server room closes itself
		_empty_t = _empty_t + dt if present_ids().is_empty() else 0.0
		if _report_pending == 0 and _empty_t > (DEDICATED_BOOT_IDLE if not _ever_joined else (DEDICATED_IDLE if active else DEDICATED_LOBBY_IDLE)):
			fail("room empty")
			return
		if _idle_check(dt):
			return
	if not active or not started or sim == null:
		return
	if hosting:
		_snap_clock += dt
		var rate := SNAPSHOT_EVERY_SERVER if dedicated else SNAPSHOT_EVERY
		var every := rate if not finished else 1.0     # the end screen: frozen state; a slow resend covers a dropped packet
		if _snap_clock >= every - 0.001 or (sim.over and not finished):
			_snap_clock = minf(_snap_clock - every, every) if not finished else 0.0   # carry the remainder: an even cadence
			_snap_count += 1
			var key := _snap_count % int(round(KEYFRAME_EVERY * SNAPSHOT_EVERY / rate)) == 1
			if _has_guests():                          # alone with the AI: nobody to send to
				var packet := var_to_bytes(_wire_state(snapshot(sim, key), key)).compress(FileAccess.COMPRESSION_DEFLATE)
				_broadcast_raw("state", packet)
				_send_ghosts(key)
			if sim.over:
				finished = true
				if dedicated and _reported_round != match_round:
					_reported_round = match_round
					_report_round()
	elif _smooth():
		_since_snapshot += minf(dt, 0.25)            # arrivals (the host-silence check below)
		var fdt := minf(dt, 0.25)
		_playout(fdt)
		if _since_applied < EXTRAPOLATE and not sim.over:
			predict(sim, minf(dt, 0.05))
		blend(sim, minf(dt, 0.05))
		_track_freeze(fdt)
		if _since_snapshot > HOST_GRACE:
			fail("The host stopped responding for %d s. RECONNECT to try the room again." % int(HOST_GRACE))
	else:
		_since_snapshot += minf(dt, 0.25)            # a tab back from the background: one huge frame
		if _since_snapshot < 0.35 and not sim.over:
			predict(sim, minf(dt, 0.05))
		_track_freeze(minf(dt, 0.25))
		if _since_snapshot > HOST_GRACE:
			fail("The host stopped responding for %d s. RECONNECT to try the room again." % int(HOST_GRACE))


func _idle_check(dt: float) -> bool:
	## The server's match host: a room where no round runs (the lobby, the results) for _room_idle closes, so idle tabs
	## can't hold the server's few match slots; a notice warns everyone ROOM_IDLE_WARN before. true = closing.
	if _closing:
		return true
	if active and started and not finished:
		_idle_t = 0.0
		_idle_warned = false
		return false
	if present_ids().is_empty():                       # an empty room has its own, shorter rules above
		return false
	_idle_t += dt
	var warn := minf(ROOM_IDLE_WARN, _room_idle * 0.5)
	if not _idle_warned and _idle_t >= _room_idle - warn:
		_idle_warned = true
		_notice("Nothing played for a while: this room closes in %d s unless a round starts" % int(round(_room_idle - _idle_t)))
	if _idle_t < _room_idle or _report_pending > 0:
		return false
	_closing = true
	var why := "Room closed: nothing was played in it for %s." % ("%d min" % int(round(_room_idle / 60.0)) if _room_idle >= 60.0 else "%d s" % int(_room_idle))
	print("room idle ", int(_idle_t), " s - closing")
	for remote in links:                               # "rejected": the guest shows why and forgets the RECONNECT
		_send(remote, "rejected", why)
	get_tree().create_timer(1.0).timeout.connect(func(): fail("room idle"))   # let the last packets leave first
	return true


func _poll(dt: float) -> void:
	_elapsed += minf(dt, 0.25)
	var events = bridge.poll_events() if bridge.has_method("poll_events") else JSON.parse_string(str(bridge.poll()))
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
					if links.size() >= slots() - (0 if dedicated else 1) or (active and not held):   # mid-match: only to reclaim a held seat (a server host takes no seat)
						bridge.closePeer(event["peer"])
						continue
					links[event["peer"]] = next_peer
					next_peer += 1
				else:
					_creating = false
					remote_host = str(event["peer"])
					var reg := {"op": "register", "version": version(), "faction": preferred_faction, "colour": colour, "loadout": loadout, "cosmetic": cosmetic, "name": own_name()}
					if auth_token != "":
						reg["auth"] = auth_token          # 0.20.5: verified by a server room's host (not the reconnect "token")
					if not rejoin.is_empty() and str(rejoin["code"]) == room_code:
						reg["token"] = rejoin["token"]
					_send_to_host(reg)
			"data":
				if hosting:
					_host_receive(str(event["peer"]), str(event["data"]))
				elif str(event["peer"]) == remote_host:
					_guest_receive(str(event["data"]))
			"bin":                                     # net-5: the host's packets as binary frames (RelayBridge)
				if not hosting and str(event["peer"]) == remote_host and event.get("data") is PackedByteArray:
					var b: PackedByteArray = event["data"]
					if b.size() >= 2 and b.size() <= MAX_PACKET and b[0] < b.size():
						_guest_handle(b.slice(1, 1 + b[0]).get_string_from_utf8(),
								b.slice(1 + b[0]).decompress_dynamic(MAX_PACKET, FileAccess.COMPRESSION_DEFLATE))
			"closed":
				if hosting:
					var id: int = links.get(event["peer"], -1)
					links.erase(event["peer"])
					if id >= 0:
						peer_left(id)
				else:
					fail("The host left or the connection was lost. The room is closed." if connected else "The room did not let us in: it is full or its match already started.")
			"error":
				if _creating and str(event.get("code", "")) in FALLBACK_CODES:
					_fallback_host.call_deferred(str(event.get("code", "")))
					bridge.close()
					bridge = null
					return
				fail(str(event.get("message", "Connection failed.")))
	if bridge != null and not connected and _elapsed > 30.0:
		fail("Could not reach the room. Check your connection and try again.")


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
		"ready":                                       # READY (ooze20-net-6)
			if p.get("ready", null) is bool:
				_set_ready(id, p["ready"])
		"faction":
			var f := str(p.get("faction", ""))
			if f in FACTIONS and not active and not _locked(id):
				roster[id]["faction"] = f
				publish_lobby()
		"colour":
			if p.get("colour", null) is String and not active and not _locked(id):
				pick_colour(id, p["colour"])
		"team":
			if _is_int(p.get("team", null)) and not active and not _locked(id):
				move_to_team(id, int(p["team"]))
		"loadout":
			if not active and not _locked(id):
				roster[id]["loadout"] = _clean_loadout({"active": p.get("active", ""), "map": p.get("map", "")})
				publish_lobby()
		"lobby":                                       # a server room's owner runs the lobby (stage 2)
			if not active or str(p.get("fn", "")) == "rematch_map":
				_owner_op(id, p)
		"cosmetic":                                    # 0.19.0: the local ARMIES > COSMETICS pick (HUD agent)
			if not active and not _locked(id):
				roster[id]["cosmetic"] = _clean_cosmetic(p.get("cosmetic", {}))
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
	_guest_handle(str(envelope.get("kind", "")), bytes)


func _guest_handle(kind: String, bytes: PackedByteArray) -> void:
	var data = bytes_to_var(bytes)
	match kind:
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
			last_stand = bool(data["last_stand"])
			ai_fill = str(data.get("ai_fill", ""))
			room_backdrop = str(data.get("backdrop", "auto"))   # UI
			abilities = bool(data.get("abilities", true))
			connected = true
			room_owner = int(data.get("owner", 1))
			status = ("ROOM %s - you run this room: DEPLOY when ready" if can_control() else "ROOM %s - waiting for the host to deploy") % room_code
			lobby_changed.emit()
		"launch":
			if data is Dictionary:
				_launch(data)
		"begin":
			if data is Dictionary and int(data.get("round", -1)) == match_round:
				_begin()
		"state":
			if data is Dictionary:
				data = _unwire_state(data)            # net-5: a delta becomes the whole snapshot (or {} without its keyframe)
			if data is Dictionary and not data.is_empty() and int(data.get("round", -1)) == match_round and sim != null and active:
				_since_snapshot = 0.0
				var now_ms := Time.get_ticks_msec()
				if _last_arrival > 0 and (now_ms - _last_arrival) / 1000.0 > STALL:   # a stall: hold more in hand next time
					_delay = clampf(maxf(_delay, (now_ms - _last_arrival) / 1000.0 * 0.5 + 0.1), PLAYOUT_DELAY, PLAYOUT_DELAY_MAX)
					_calm = 0.0
				if _last_arrival > 0:                  # NET: the round's longest gap between two snapshots
					_gap_max = maxi(_gap_max, now_ms - _last_arrival)
				_last_arrival = now_ms
				_arrivals.append(now_ms)
				_rx_snaps += 1
				if _rx_first == 0:
					_rx_first = now_ms
				_delay_max = maxf(_delay_max, _delay)
				while not _arrivals.is_empty() and now_ms - int(_arrivals[0]) > 5000:
					_arrivals.pop_front()
				if _smooth() and not _fresh:           # server rooms: the playout buffer shows it on time
					_latest_t = maxf(_latest_t, float(data.get("t", 0.0)))
					_play_q.append(["state", data])
				else:
					_apply_state(data)
		"effects":
			if data is Dictionary and int(data.get("round", -1)) == match_round and sim != null:
				if _smooth() and not _play_q.is_empty():   # after the snapshot it belongs to
					_play_q.append(["effects", data])
				else:
					sim.fx_events.append_array(data["events"])
		"ghosts":
			if data is Dictionary and int(data.get("round", -1)) == match_round:
				own_ghosts = {}
				for i in data.get("ids", []):
					own_ghosts[int(i)] = true
				_mark_ghosts()
		"feedback":
			var now := Time.get_ticks_msec()
			while not _order_sent.is_empty() and now - int(_order_sent[0]) > 3000:   # unanswered orders are not a round trip
				_order_sent.pop_front()
			if not _order_sent.is_empty():
				var rtt := float(now - int(_order_sent.pop_front()))
				_rtt_ms = rtt if _rtt_ms < 0.0 else lerpf(_rtt_ms, rtt, 0.3)
				_rtt_n += 1                            # NET
				_rtt_sum += rtt
				_rtt_max = maxf(_rtt_max, rtt)
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


func _mark_ghosts() -> void:
	## Guest: put the decoy flag back on our own Ghost Lines (the broadcast snapshot never carries it).
	if sim == null:
		return
	for h in sim.hordes:
		if own_ghosts.has(int(h["id"])):
			h["decoy"] = true


# ------------------------------------------------------------------ rejoin details
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():             # the room server's match host (stage 2)
		if arg == "--dedicated":
			dedicated = true
		elif arg.begins_with("--room="):
			_server_room = arg.substr(7)
		elif arg.begins_with("--secret="):
			_server_secret = arg.substr(9)
		elif arg.begins_with("--idle-close="):         # tests only (a local relay's --host-arg): a short idle limit
			_room_idle = maxf(4.0, float(arg.substr(13)))
	if dedicated:
		Engine.max_fps = DEDICATED_FPS
		_start_dedicated.call_deferred()
		return
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
static func _encode_bin(kind: String, packed: PackedByteArray) -> PackedByteArray:
	## A binary host packet: [kind length][kind][deflated var_to_bytes] (net-5).
	var k := kind.to_utf8_buffer()
	var out := PackedByteArray([k.size()])
	out.append_array(k)
	out.append_array(packed)
	return out


func _encode(kind: String, packed: PackedByteArray) -> String:
	return "{\"kind\":" + JSON.stringify(kind) + ",\"data\":" + JSON.stringify(Marshalls.raw_to_base64(packed)) + "}"


func _send(remote: String, kind: String, data) -> void:
	if bridge == null:
		return
	var packed := var_to_bytes(data).compress(FileAccess.COMPRESSION_DEFLATE)
	if bridge.has_method("send_bin"):                  # RelayBridge: a binary frame, no base64 / JSON envelope
		bridge.send_bin(remote, _encode_bin(kind, packed), kind == "state")
	else:
		bridge.send(remote, _encode(kind, packed))


func _broadcast(kind: String, data) -> void:
	_broadcast_raw(kind, var_to_bytes(data).compress(FileAccess.COMPRESSION_DEFLATE))


func _broadcast_raw(kind: String, packed: PackedByteArray) -> void:
	if bridge == null or not hosting:
		return
	var binary: bool = bridge.has_method("send_bin")
	var envelope = _encode_bin(kind, packed) if binary else _encode(kind, packed)   # one envelope for every guest
	for remote in links:
		if roster.has(links[remote]):
			if binary:
				bridge.send_bin(remote, envelope, kind == "state")
			else:
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
