class_name MatchReport
extends RefCounted
## The server's match result report (0.20.5 "accounts", PROGRESSION-DESIGN §7a): what the room server's match host
## POSTs to the Supabase edge function `match-result` when a round of a server-hosted room ends. Pure functions over a
## finished Sim, so the payload and the signature can be tested without a network. Net sends it (Net._report_round);
## the counting is Progression's (seat_stats / placements), shared with the device's local rewards.

const V := 1


static func payload(sim: Sim, info: Dictionary, users: Dictionary, left: Dictionary, room: String, round_no: int,
		started_at: int) -> Dictionary:
	## info = Net.match_info (map, mode, rules, players, ai); users = seat -> verified user id; left = seat -> true
	## for a player who was gone at the end (dropped, the AI finishing the seat).
	var strength := {}
	for seat in sim.factions:
		strength[seat] = sim.seat_strength(seat)
	var placed := Progression.placements(sim, strength)
	var seats := []
	var ai: Dictionary = info.get("ai", {})
	var seat_list: Array = sim.factions.keys()
	seat_list.sort()
	for seat in seat_list:
		var nodes_held := 0
		for n in sim.nodes:
			if n["owner"] == seat and not sim.collapsed.get(n["id"], false):
				nodes_held += 1
		seats.append({"seat": seat, "team": sim.teams.get(seat, null), "faction": str(sim.factions[seat]),
				"user_id": users.get(seat, null), "ai_level": ai.get(seat, null), "left_early": bool(left.get(seat, false)),
				"won": sim.winner != "" and (seat == sim.winner or sim.allied(seat, sim.winner)),
				"placed": int(placed.get(seat, seat_list.size())), "final_strength": Rules.shown(float(strength[seat])),
				"final_nodes": nodes_held, "stats": Progression.seat_stats(sim, seat)})
	var rules: Dictionary = info.get("rules", {})
	return {"v": V, "match_id": "%s-%d-%d" % [room, round_no, started_at], "build": Rules.VERSION,
			"map": map_code(str(info.get("map", ""))), "mode": str(info.get("mode", "")).to_lower(),
			"rules": {"last_stand": bool(rules.get("last_stand", true)), "abilities": bool(rules.get("abilities_on", true))},
			"started_at": started_at, "duration_s": snappedf(sim.time, 0.1), "outcome": outcome(sim), "seats": seats}


static func outcome(sim: Sim) -> Dictionary:
	## win (a side took the map), vls (it came down to the Very Last Stand), forced (the 7:00 end), draw.
	var last := {}
	for e in sim.events:
		if e.get("type") == "end":
			last = e
	var draw := sim.winner == ""
	var end := "draw" if draw else ("forced" if bool(last.get("forced", false)) else ("vls" if sim.very_last_stand_active else "win"))
	var team = sim.teams.get(sim.winner, null) if not draw else null
	return {"winner_seat": null if draw else sim.winner, "winner_team": team, "draw": draw, "end": end}


static func map_code(path: String) -> String:
	## "res://maps4/M-07-twin-docks.json" -> "M-07"
	var parts := path.get_file().get_basename().split("-")
	return "%s-%s" % [parts[0], parts[1]] if parts.size() >= 2 else path.get_file().get_basename()


static func sign(secret: String, ts: int, body: String) -> String:
	## x-ooze-sig = hex HMAC-SHA256(secret, ts + "." + raw body)
	var ctx := HMACContext.new()
	ctx.start(HashingContext.HASH_SHA256, secret.to_utf8_buffer())
	ctx.update(("%d.%s" % [ts, body]).to_utf8_buffer())
	return ctx.finish().hex_encode()
