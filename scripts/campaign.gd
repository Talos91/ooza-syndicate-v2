class_name Campaign
extends RefCounted
## The campaign: its data, progress, stars and rewards (Docs/Game Design/Ooze Syndicate 2.0/01 Rules/CAMPAIGN-DESIGN.md).
## Daniele, 2026-09-27: the sinking city is the campaign map (districts = chapters, missions = nodes, the last chapter
## descends under the city); dark comedy; linear with optional side nodes; one campaign per faction (VEX free, the other
## four paid), finishing one unlocks that faction's vat; stars 1-3 are achievement only; 3 stars + the mission's optional
## objective IN THE SAME RUN pays SCRAP once per mission; solo only.
##
## Static, like ArmyPresets / TutorialDirector: no Node, headless-testable (tests/test_campaign.gd).
##   CAMPAIGNS / missions(faction) / mission(key) / district_of(key)   the data (key = "<faction>:<mission id>")
##   is_open(key) / is_won(key) / next_open(faction) / owned(faction)   what the campaign map shows as playable
##   stars_for(won, time, par, lost_start)                               the three star rules (§5)
##   record(key, run) -> summary                                         a finished run: best stars, reward, unlocks
##   pay_pending()                                                       replay recorded rewards into Progression
##   reward_state(key) / stars_total(faction) / stars_max(faction)       readouts for the page and the result screen
## Progress: user://campaign.cfg; `saved` false when the browser keeps no storage (the page says so).
##
## Rewards go through Progression (the "Leaderboard, progression, and currency" session; CAMPAIGN-DESIGN §5a):
## Progression.grant(source, amount) is idempotent per source ("campaign:vex:04"), unlock(item, source) takes
## "vat:faction:<faction>". A reward that could not be paid (a failed save, a stand-in wallet in tests) stays
## recorded here and pay_pending() pays it later.

const PROGRESS_VERSION := 1
const FACTION_ORDER := ["vex", "null", "bloom", "ember", "solar"]
const FREE := ["vex"]                                # the free campaign (Daniele); the rest are paid, later
const HUMAN := "A"
const RIVAL := "B"
const HANDLER := "DR. VESK"                          # the tutorial's handler (TutorialDirector.HANDLER_NAME)

## The rival executives (CAMPAIGN-DESIGN §1). Names are placeholders until Daniele names them (OPEN-QUESTIONS).
const RIVALS := {
	"foreman": {"name": "THE FOREMAN", "faction": "ember", "title": "EMBER dock foreman"},
	"auditor": {"name": "THE AUDITOR", "faction": "null", "title": "NULL auditor (never seen)"},
	"guru": {"name": "THE GURU", "faction": "bloom", "title": "BLOOM wellness guru"},
	"compliance": {"name": "COMPLIANCE", "faction": "solar", "title": "SOLAR compliance officer"},
	"maw": {"name": "THE MAW", "faction": "ember", "title": "EMBER Maw, chief executive"},
}

## One campaign per faction. Each district: its missions in play order (side missions right after the main
## mission they hang off), a diorama layout for the campaign map (metres, x right / y toward the camera; "decor" =
## platforms without a mission, city dressing) and the order its platforms drop when it is done.
## A mission:
##   id, title, story (one line on the card), type (takeover / relay_puzzle / hold / duel / blind / monster /
##   collapse / mutator / beast), kind (main / side / duel / finale -> Rules.PROGRESSION.campaign_reward), parent (side missions: the main id),
##   map (a baked map path; PLACEHOLDER maps until the new maps land - Game map builder), placeholder,
##   par (seconds, the ★★ / ★★★ time), objective {kind, ...} (what wins), optional {kind, text, ...},
##   ai (Rules.AI_LEVELS), rival (RIVALS key), stage {rival_units: shown units added to the rival's home},
##   brief [[speaker, line], ...] (the briefing card), win_line, lose_line,
##   needs (a system the game doesn't have yet - CAMPAIGN-DESIGN §7b; not playable until it lands), pos (diorama).
const CAMPAIGNS := {
	"vex": {
		"title": "VEX BIOENGINEERS",
		"episode": "GOING UNDER",                  # the episode card's title (Daniele approved all five, 2026-09-29)
		"tagline": "The city is sinking. The vats still turn a profit.",
		"rival": "ember",
		"districts": [
			{
				"id": "dockside", "name": "DOCKSIDE", "blurb": "District 1 - where the city loads its cargo, and loses it.",
				"decor": [Vector2(-34, -14), Vector2(36, -16), Vector2(-40, 12), Vector2(42, 14)],
				"missions": [
					{"id": "01", "title": "HOSTILE TAKEOVER", "type": "takeover", "kind": "main",
						"story": "EMBER is \"restructuring\" the docks with fire. Restructure them back.",
						"map": "res://maps4/A-02-switchback-foundry.json", "placeholder": true, "par": 240.0,
						"objective": {"kind": "conquest"}, "optional": {"kind": "no_vat_lost", "text": "Win without losing a vat"},
						"ai": "Casual", "rival": "foreman", "stage": {},
						"brief": [["handler", "Welcome to Dockside, commander. Our quarterly target: all of it."],
							["rival", "These docks are mine. I've already set most of them on fire."]],
						"win_line": "Docks acquired. I'll log the burnt bits as depreciation.",
						"lose_line": "We've been restructured. Again, from the top.", "pos": Vector2(-22, 2)},
					{"id": "02", "title": "MIND THE GAP", "type": "relay_puzzle", "kind": "main",
						"story": "The loading cranes still work. Mostly as trapdoors.",
						"map": "res://maps4/M-37-switchyard-sprawl.json", "placeholder": true, "par": 200.0,
						"objective": {"kind": "drops", "n": 60, "limit": 300.0},
						"optional": {"kind": "drops_fires", "n": 40, "fires": 3, "text": "Drop 40 units with 3 relay fires or fewer"},
						"ai": "Casual", "rival": "foreman", "stage": {},
						"brief": [["handler", "Relays move decks. Whatever is on the deck goes into the void."],
							["handler", "Drop {n} of their units. HR calls it \"downsizing\"."]],
						"win_line": "Downsizing complete. The void sends its thanks.",
						"lose_line": "Too many of them made it across. Mind the gap next time.", "pos": Vector2(0, -8)},
					{"id": "s1", "title": "OVERTIME", "type": "hold", "kind": "side", "parent": "02",
						"story": "Hold the warehouse till the whistle. Unpaid, naturally.",
						"map": "res://maps4/B-02-switchback-foundry.json", "placeholder": true, "par": 180.0,
						"objective": {"kind": "survive", "t": 180.0},
						"optional": {"kind": "machinegoon_t3", "text": "Have a T3 Machinegoon standing at the whistle"},
						"ai": "Standard", "rival": "foreman", "stage": {"rival_units": 20},
						"brief": [["handler", "EMBER wants the warehouse. Keep your home until {t}."],
							["handler", "Overtime is voluntary. Volunteering is mandatory."]],
						"win_line": "Whistle! Clock out. Clocking out is also unpaid.",
						"lose_line": "The warehouse is EMBER's now. Their problem, frankly.", "pos": Vector2(2, 16)},
					{"id": "03", "title": "THE FOREMAN", "type": "duel", "kind": "duel",
						"story": "EMBER's dock foreman. Very angry. Very flammable.",
						"map": "res://maps4/C-02-vantage-wire.json", "placeholder": true, "par": 300.0,
						"objective": {"kind": "conquest"},
						"optional": {"kind": "before_ultimate", "text": "Win before the Foreman casts his ultimate"},
						"ai": "Standard", "rival": "foreman", "stage": {"rival_units": 15},
						"brief": [["rival", "You took my docks. I'll take your everything. With fire."],
							["handler", "He starts bigger. He also starts angrier. Use both."]],
						"win_line": "The Foreman has been let go. Into the void, specifically.",
						"lose_line": "He's still on fire and still winning. Try again.", "pos": Vector2(24, -2)},
				],
				"collapse": ["01", "s1", "02", "03"],
			},
			{
				"id": "exchange", "name": "THE EXCHANGE", "blurb": "District 2 - the trading floor. It floods at every closing bell.",
				"decor": [Vector2(-36, 16), Vector2(38, -14), Vector2(-8, -18), Vector2(40, 16)],
				"missions": [
					{"id": "04", "title": "MARKET CORRECTION", "type": "mutator", "kind": "main",
						"story": "The trading floor floods at every closing bell. Trade faster.",
						"map": "res://maps4/C-01-meridian-rotunda.json", "placeholder": true, "par": 270.0,
						"objective": {"kind": "conquest"}, "optional": {"kind": "no_tide_loss", "text": "Lose no line to the tide"},
						"ai": "Standard", "rival": "foreman", "stage": {}, "needs": "event deck: flooding tides",
						"brief": [["handler", "Underpasses flood at every bell. Don't be on one."]],
						"win_line": "Market corrected. Upwards, for once.", "lose_line": "Liquidated. Literally.", "pos": Vector2(-24, 4)},
					{"id": "05", "title": "NOBODY SAW ANYTHING", "type": "blind", "kind": "main",
						"story": "The NULL auditor is here. Nobody has ever seen the NULL auditor.",
						"map": "res://maps4/M-25-mirror-moor.json", "placeholder": true, "par": 300.0,
						"objective": {"kind": "conquest"}, "optional": {"kind": "no_skill", "skill": "ghost_line", "text": "Win without casting Ghost Line"},
						"ai": "Standard", "rival": "auditor", "stage": {"hide_counts": true},
						"brief": [["handler", "NULL hides their numbers. Count by eye, or guess confidently."],
							["rival", "..."]],
						"win_line": "Audit passed. Nobody saw anything. Especially them.", "lose_line": "The audit found a problem. It was us.",
						"pos": Vector2(0, -10)},
					{"id": "s2", "title": "SPECIAL DELIVERY", "type": "mutator", "kind": "side", "parent": "05",
						"story": "Supply pods keep landing on the bridges. Finders keepers.",
						"map": "res://maps4/M-22-coral-steps.json", "placeholder": true, "par": 240.0,
						"objective": {"kind": "conquest"}, "optional": {"kind": "all_pods", "text": "Grab every pod"},
						"ai": "Standard", "rival": "auditor", "stage": {}, "needs": "event deck: supply drops",
						"brief": [["handler", "Pods on the decks. Grab them before NULL does."]],
						"win_line": "Signed for. Every one.", "lose_line": "Return to sender.", "pos": Vector2(2, 14)},
					{"id": "06", "title": "AGGRESSIVE GROWTH", "type": "monster", "kind": "main",
						"story": "Break the BLOOM wellness retreat. Bring a monster. It's a retreat.",
						"map": "res://maps4/M-01-meadow-array.json", "placeholder": true, "par": 300.0,
						"objective": {"kind": "monster_take"}, "optional": {"kind": "monster_kicks", "n": 30, "text": "Your monster kicks 30+ units off the decks"},
						"ai": "Standard", "rival": "guru", "stage": {},
						"brief": [["rival", "Breathe in. Breathe out. Leave, please."],
							["handler", "Build a Monster hub and take a node with its monster. Namaste."]],
						"win_line": "Retreat closed. Everyone is very relaxed now. At the bottom.", "lose_line": "We've been composted.",
						"pos": Vector2(24, 0)},
				],
				"collapse": ["04", "s2", "05", "06"],
			},
			{
				"id": "oldtown", "name": "OLD TOWN", "blurb": "District 3 - the oldest platforms. They were never meant to last this long.",
				"decor": [Vector2(-38, -12), Vector2(-6, 18), Vector2(38, 16), Vector2(36, -16)],
				"missions": [
					{"id": "07", "title": "LAST TRAIN OUT", "type": "collapse", "kind": "main",
						"story": "Old Town drops from minute zero. Be on the last ring standing.",
						"map": "res://maps4/C-01-meridian-rotunda.json", "placeholder": true, "par": 240.0,
						"objective": {"kind": "outlast", "collapse_at": 20.0, "n": 40},
						"optional": {"kind": "units_at_end", "n": 60, "text": "End with 60+ units"},
						"ai": "Standard", "rival": "foreman", "stage": {},
						"brief": [["handler", "The district is dropping ring by ring. Get to the last ring."],
							["handler", "Win with {n}+ units still standing. Nobody gets a refund."]],
						"win_line": "Made the train. It's also sinking, but slower.", "lose_line": "Missed the train. And the platform.",
						"pos": Vector2(-24, -2)},
					{"id": "s3", "title": "PET PROJECT", "type": "beast", "kind": "side", "parent": "07",
						"story": "Something big escaped from the VEX labs. It's hungry. It's ours.",
						"map": "res://maps4/M-06-spore-fields.json", "placeholder": true, "par": 300.0,
						"objective": {"kind": "conquest"}, "optional": {"kind": "beast_eats", "n": 3, "text": "The beast eats 3 rival lines"},
						"ai": "Standard", "rival": "guru", "stage": {}, "needs": "wandering neutral beast",
						"brief": [["handler", "Our beast. Their problem. Lure it onto their lines."]],
						"win_line": "Good boy.", "lose_line": "It ate us. We'll call that a feature.", "pos": Vector2(-4, 16)},
					{"id": "08", "title": "COMPLIANCE", "type": "duel", "kind": "duel",
						"story": "The SOLAR compliance officer locks everything. Unlock everything.",
						"map": "res://maps4/M-27-cobalt-commons.json", "placeholder": true, "par": 330.0,
						"objective": {"kind": "conquest"}, "optional": {"kind": "fires", "n": 5, "text": "Fire 5 relays"},
						"ai": "Veteran", "rival": "compliance", "stage": {"rival_units": 15},
						"brief": [["rival", "This takeover has not been approved. Please fill in form 7B."],
							["handler", "Form 7B is on fire. Proceed."]],
						"win_line": "Compliance has been... complied.", "lose_line": "Denied. Stamped. Filed. Us.", "pos": Vector2(22, -6)},
				],
				"collapse": ["07", "s3", "08"],
			},
			{
				"id": "descent", "name": "THE DESCENT", "blurb": "Under the city. The void is closer than it looks.",
				"descent": true,
				"decor": [Vector2(-30, -10), Vector2(30, 10)],
				"missions": [
					{"id": "09", "title": "GOING DOWN", "type": "collapse", "kind": "main",
						"story": "Hanging platforms under the city. Each layer shorter than the last.",
						"map": "res://maps4/C-02-vantage-wire.json", "placeholder": true, "par": 270.0,
						"objective": {"kind": "outlast", "collapse_at": 30.0, "n": 50},
						"optional": {"kind": "no_skill", "skill": "demolish", "text": "Win without casting Demolish"},
						"ai": "Veteran", "rival": "maw", "stage": {},
						"brief": [["handler", "We're under the city now. Mind the gravity."]],
						"win_line": "Still going down. Still winning.", "lose_line": "Went down. All the way.", "pos": Vector2(-14, -6)},
					{"id": "10", "title": "ROOT CAUSE", "type": "duel", "kind": "finale",
						"story": "Why the city sinks. Everyone's product is the problem. Especially ours.",
						"map": "res://maps4/M-27-cobalt-commons.json", "placeholder": true, "par": 360.0,
						"objective": {"kind": "conquest", "collapse_at": 90.0},
						"optional": {"kind": "home_kept", "text": "Win without losing your home"},
						"ai": "Expert", "rival": "maw", "stage": {"rival_units": 25},
						"brief": [["handler", "Bad news: the vats have been eating the city's supports. All of them. Ours too."],
							["rival", "Then there's only one vat left worth owning. Mine."],
							["handler", "Good news: that's a very clear quarterly target."]],
						"win_line": "The city is ours. What's left of it. Please mind the gap.",
						"lose_line": "The Maw keeps the last vat. And the city. Briefly.", "pos": Vector2(14, 6)},
				],
				"collapse": [],
			},
		],
	},
	"null": {"title": "NULL DATA CARTEL", "episode": "OFF THE BOOKS", "tagline": "Coming later.", "rival": "solar", "districts": []},
	"bloom": {"title": "VIRIDIAN BLOOM", "episode": "GROWTH MINDSET", "tagline": "Coming later.", "rival": "ember", "districts": []},
	"ember": {"title": "EMBER MAW", "episode": "SCORCHED EARNINGS", "tagline": "Coming later.", "rival": "vex", "districts": []},
	"solar": {"title": "SOLAR SHELLS", "episode": "TERMS & CONDITIONS", "tagline": "Coming later.", "rival": "null", "districts": []},
}

static var path := "user://campaign.cfg"             # tests point this elsewhere
static var saved := true                             # false: the last save failed (no storage)
static var all_open := false                         # --campaign-all / tests: every playable mission open
static var progress := {}                            # key -> {stars, objective, won, best_time, plays, reward: "" / "earned" / "paid"}
static var unlocks_pending := {}                     # item -> source, recorded until Progression exists
static var seen := {}                                # "collapse:<district>" -> true once its drop has played
static var _loaded := false
static var _loaded_path := ""                        # the file `progress` came from (a new `path` loads afresh)
static var _prog_script: Script = null
static var _prog_checked := false


# ------------------------------------------------------------------ data
static func key_of(faction: String, id: String) -> String:
	return "%s:%s" % [faction, id]


static func faction_of(key: String) -> String:
	return key.get_slice(":", 0)


static func source_of(key: String) -> String:
	## The one-off grant source (CAMPAIGN-DESIGN §5a): "campaign:vex:04".
	return "campaign:" + key


static func has_content(faction: String) -> bool:
	return CAMPAIGNS.has(faction) and not (CAMPAIGNS[faction]["districts"] as Array).is_empty()


static func episodes() -> Array:
	## The CAMPAIGN MENU's cards (Alpha 21 "choose an episode", Architect's shared EpisodeCard), one per faction in
	## FACTION_ORDER: {faction, title (the episode), faction_title, tagline, art, state, stars, stars_max, next}.
	## state: "open" (content, owned), "locked" (content, a paid campaign not owned - UNLOCK), "coming" (no content yet).
	var out := []
	for f in FACTION_ORDER:
		var c: Dictionary = CAMPAIGNS.get(f, {})
		var state := "coming"
		if has_content(f):
			state = "open" if owned(f) else "locked"
		out.append({"faction": f, "title": str(c.get("episode", c.get("title", f.to_upper()))),
			"faction_title": str(c.get("title", "")), "tagline": str(c.get("tagline", "")),
			"art": "res://assets/art/%s.png" % f, "state": state,
			"stars": stars_total(f), "stars_max": stars_max(f), "next": next_open(f) if state == "open" else ""})
	return out


static func hub(faction: String, district_index := -1) -> Dictionary:
	## The CAMPAIGN HUB page (Alpha 21, the UI helper's mockup): one district's header and its mission cards.
	## district_index -1 = the district of the next mission (the first one when nothing is left).
	## {faction, faction_title, district_index, district_count, district_name, district_blurb, stars, stars_max,
	##  missions: [{key, number ("01" / "S1"), title, kind, state, stars, stars_max, unlock_hint, backdrop, needs}]}
	## state: "next" (CONTINUE), "won", "open", "locked", "dev" (IN DEVELOPMENT - needs a system not built yet).
	var ds := districts(faction)
	if ds.is_empty():
		return {}
	var nxt := next_open(faction)
	if district_index < 0:
		district_index = 0
		for i in range(ds.size()):
			for m in ds[i]["missions"]:
				if key_of(faction, str(m["id"])) == nxt:
					district_index = i
	district_index = clampi(district_index, 0, ds.size() - 1)
	var d: Dictionary = ds[district_index]
	var cards := []
	var got := 0
	for m in d["missions"]:
		var key := key_of(faction, str(m["id"]))
		var mm := mission(key)
		var state := "locked"
		if not playable(mm):
			state = "dev"
		elif is_won(key):
			state = "won"
		elif key == nxt:
			state = "next"
		elif is_open(key):
			state = "open"
		got += stars_of(key)
		cards.append({"key": key, "number": str(m["id"]).to_upper(), "title": str(m["title"]), "kind": str(m["kind"]),
			"state": state, "stars": stars_of(key), "stars_max": 3,
			"unlock_hint": unlock_hint(key) if state == "locked" else "", "backdrop": backdrop_of(key),
			"needs": str(m.get("needs", ""))})
	return {"faction": faction, "faction_title": str(CAMPAIGNS[faction].get("title", "")), "district_index": district_index,
		"district_count": ds.size(), "district_name": str(d["name"]), "district_blurb": str(d.get("blurb", "")),
		"stars": got, "stars_max": cards.size() * 3, "missions": cards}


static func unlock_hint(key: String) -> String:
	## Why a mission is locked: "Complete HOSTILE TAKEOVER to unlock." (the main mission before it; a side mission:
	## its parent). "" when it is open.
	var m := mission(key)
	if m.is_empty() or is_open(key):
		return ""
	if str(m["kind"]) == "side":
		return "Complete %s to unlock." % str(mission(key_of(faction_of(key), str(m.get("parent", "")))).get("title", ""))
	var prev := ""
	for mm in main_missions(faction_of(key)):
		if str(mm["key"]) == key:
			break
		if playable(mm):
			prev = str(mm["title"])
	return "Complete %s to unlock." % prev if prev != "" else ""


static func backdrop_of(key: String) -> String:
	## The mission's own background (CAMPAIGN-BACKGROUNDS-PROMPTS.md): a "backdrop" field, else
	## res://assets/art/campaign/<faction>-<id>.png when that file exists; "" until the art is in (callers fall back).
	var m := mission(key)
	if m.has("backdrop"):
		return str(m["backdrop"]) if ResourceLoader.exists(str(m["backdrop"])) else ""
	for ext in ["jpg", "png"]:                       # UI: tools/ui_art.py writes .jpg (a smaller web download)
		var p := "res://assets/art/campaign/%s-%s.%s" % [faction_of(key), str(m.get("id", "")), ext]
		if ResourceLoader.exists(p):
			return p
	return ""


static func progress_total() -> Vector2i:
	## "CAMPAIGN PROGRESS ★ x / y" under the cards: every episode with content, owned or not.
	var got := 0
	var most := 0
	for f in FACTION_ORDER:
		if has_content(f):
			got += stars_total(f)
			most += stars_max(f)
	return Vector2i(got, most)


static func districts(faction: String) -> Array:
	return CAMPAIGNS[faction]["districts"] if CAMPAIGNS.has(faction) else []


static func missions(faction: String) -> Array:
	## Every mission of a campaign in play order, each a copy with "key", "faction", "district" added.
	var out := []
	for d in districts(faction):
		for m in d["missions"]:
			var c: Dictionary = (m as Dictionary).duplicate(true)
			c["key"] = key_of(faction, str(m["id"]))
			c["faction"] = faction
			c["district"] = str(d["id"])
			out.append(c)
	return out


static func main_missions(faction: String) -> Array:
	return missions(faction).filter(func(m): return str(m["kind"]) != "side")


static func mission(key: String) -> Dictionary:
	for m in missions(faction_of(key)):
		if str(m["key"]) == key:
			return m
	return {}


static func district_of(key: String) -> Dictionary:
	var id := str(mission(key).get("district", ""))
	for d in districts(faction_of(key)):
		if str(d["id"]) == id:
			return d
	return {}


static func reward_for(m: Dictionary) -> int:
	var rewards: Dictionary = Rules.PROGRESSION["campaign_reward"]
	return int(rewards.get(str(m.get("kind", "main")), rewards["main"]))


static func playable(m: Dictionary) -> bool:
	## A mission needing a system the game doesn't have yet (CAMPAIGN-DESIGN §7b) shows as IN DEVELOPMENT.
	return str(m.get("needs", "")) == "" and ResourceLoader.exists(str(m.get("map", "")))


static func rival_of(m: Dictionary) -> Dictionary:
	return RIVALS.get(str(m.get("rival", "")), {"name": "THE RIVAL", "faction": "ember", "title": ""})


static func fill(line: String, m: Dictionary) -> String:
	## A brief line's placeholders: {n} (objective / optional count), {t} (a clock time), {par}.
	var o: Dictionary = m.get("objective", {})
	var t := float(o.get("t", 0.0))
	return line.replace("{n}", str(int(o.get("n", 0)))).replace("{t}", "%d:%02d" % [int(t) / 60, int(t) % 60]) \
		.replace("{par}", "%d:%02d" % [int(m.get("par", 0.0)) / 60, int(m.get("par", 0.0)) % 60])


static func objective_text(m: Dictionary) -> String:
	## The objective line on the mission card and under the match clock.
	var o: Dictionary = m.get("objective", {})
	match str(o.get("kind", "conquest")):
		"conquest":
			return "Take every rival node"
		"drops":
			return "Drop %d rival units into the void - or take every rival node" % int(o.get("n", 0))
		"survive":
			var t := float(o.get("t", 0.0))
			return "Keep your home until %d:%02d" % [int(t) / 60, int(t) % 60]
		"monster_take":
			return "Take a node with your monster"
		"outlast":
			return "Win the collapse with %d+ units" % int(o.get("n", 0))
	return "Win"


# ------------------------------------------------------------------ progress
static func load_all() -> void:
	## Reads `path`. A file that won't load (no storage: private browsing) keeps this session's progress when it was
	## already loaded from the same path (AUDIT FIX, 2026-09-28: the campaign page's reload used to wipe mission 01's
	## win before mission 02 could open).
	var cf := ConfigFile.new()
	var ok := cf.load(path) == OK
	if not ok and _loaded and _loaded_path == path:
		return
	progress = {}
	unlocks_pending = {}
	seen = {}
	_loaded = true
	_loaded_path = path
	if not ok:
		return
	for k in cf.get_section_keys("progress") if cf.has_section("progress") else []:
		var v = cf.get_value("progress", k, {})
		if v is Dictionary:
			progress[str(k).replace("_", ":")] = v
	for k in cf.get_section_keys("unlocks") if cf.has_section("unlocks") else []:
		unlocks_pending[str(k).replace("|", ":")] = str(cf.get_value("unlocks", k, ""))
	for k in cf.get_section_keys("seen") if cf.has_section("seen") else []:
		seen[str(k).replace("|", ":")] = true


static func reload_all() -> void:
	## Read the file again (tests; a failed read keeps the session's progress, see load_all).
	load_all()


static func load_if_needed() -> void:
	## The campaign page: load once per path - the session's progress is the truth after that (every change saves).
	if not _loaded or _loaded_path != path:
		load_all()


static func save_all() -> bool:
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", PROGRESS_VERSION)
	for k in progress:
		cf.set_value("progress", str(k).replace(":", "_"), progress[k])
	for k in unlocks_pending:
		cf.set_value("unlocks", str(k).replace(":", "|"), unlocks_pending[k])
	for k in seen:
		cf.set_value("seen", str(k).replace(":", "|"), true)
	saved = cf.save(path) == OK
	return saved


static func _ensure() -> void:
	if not _loaded or _loaded_path != path:
		load_all()


static func record_of(key: String) -> Dictionary:
	_ensure()
	return progress.get(key, {})


static func is_won(key: String) -> bool:
	return bool(record_of(key).get("won", false))


static func stars_of(key: String) -> int:
	return int(record_of(key).get("stars", 0))


static func owned(faction: String) -> bool:
	## The free campaign, or a paid one bought (Progression unlock "campaign:<faction>", later) / testing.
	if faction in FREE or all_open:
		return true
	var p := _progression()
	return p != null and bool(p.call("is_unlocked", "campaign:" + faction))


static func is_open(key: String) -> bool:
	## Linear (Daniele): a main mission opens when the main before it is won; a side mission when its parent is.
	var m := mission(key)
	if m.is_empty() or not owned(faction_of(key)):
		return false
	if all_open:
		return true
	if str(m["kind"]) == "side":
		return is_won(key_of(faction_of(key), str(m.get("parent", ""))))
	var prev := ""
	for mm in main_missions(faction_of(key)):
		if str(mm["key"]) == key:
			return prev == "" or is_won(prev)
		if playable(mm):                             # an IN DEVELOPMENT mission never blocks the chain
			prev = str(mm["key"])
	return false


static func next_open(faction: String) -> String:
	## The first open, unwon, playable main mission (the campaign's CONTINUE); "" when none is left.
	for m in main_missions(faction):
		if playable(m) and is_open(str(m["key"])) and not is_won(str(m["key"])):
			return str(m["key"])
	return ""


static func district_done(faction: String, district_id: String) -> bool:
	for d in districts(faction):
		if str(d["id"]) == district_id:
			for m in d["missions"]:
				if str(m["kind"]) != "side" and not is_won(key_of(faction, str(m["id"]))):
					return false
			return true
	return false


static func campaign_done(faction: String) -> bool:
	var mains := main_missions(faction)
	return not mains.is_empty() and is_won(str(mains[-1]["key"]))


static func stars_total(faction: String) -> int:
	var s := 0
	for m in missions(faction):
		s += stars_of(str(m["key"]))
	return s


static func stars_max(faction: String) -> int:
	return missions(faction).size() * 3


# ------------------------------------------------------------------ stars and rewards (§5)
static func stars_for(won: bool, time: float, par: float, lost_start: bool) -> int:
	## ★ win; ★★ win within par; ★★★ win within par without losing a node you started with.
	if not won:
		return 0
	if time > par:
		return 1
	return 2 if lost_start else 3


static func reward_state(key: String) -> String:
	## "" (not earned), "earned" (3 stars + objective in one run, waiting for Progression), "paid".
	var r := str(record_of(key).get("reward", ""))
	if r == "earned":
		var p := _progression()
		if p != null and bool(p.call("has_granted", source_of(key))):
			return "paid"
	return r


static func record(key: String, run: Dictionary) -> Dictionary:
	## A finished run: {won: bool, time: float, stars: int, objective: bool}. Keeps the best stars / time, marks the
	## one-off reward when THIS run had 3 stars and the optional objective (Daniele: same run), pays it through
	## Progression when it is there, unlocks the faction vat when the campaign's last main mission is won.
	## Returns {stars, best_stars, new_best, objective, reward: {amount, state: "paid" / "earned" / "taken" /
	## "none"}, unlocked: [items], district_done: bool, campaign_done: bool, next: key or ""}.
	_ensure()
	var m := mission(key)
	var rec: Dictionary = progress.get(key, {"stars": 0, "objective": false, "won": false, "best_time": 0.0,
			"plays": 0, "reward": ""}).duplicate()
	var won := bool(run.get("won", false))
	var stars := int(run.get("stars", 0)) if won else 0
	var obj := bool(run.get("objective", false)) and won
	var old_stars := int(rec.get("stars", 0))
	var was_won := bool(rec.get("won", false))
	rec["plays"] = int(rec.get("plays", 0)) + 1
	if won:
		rec["won"] = true
		var t := float(run.get("time", 0.0))
		if float(rec.get("best_time", 0.0)) <= 0.0 or t < float(rec["best_time"]):
			rec["best_time"] = t
	rec["stars"] = maxi(old_stars, stars)
	rec["objective"] = bool(rec.get("objective", false)) or obj
	var amount := reward_for(m)
	var reward := {"amount": amount, "state": "none"}
	if stars == 3 and obj:
		if str(rec.get("reward", "")) == "paid":
			reward["state"] = "taken"                  # one-off (Daniele): a second perfect run pays nothing
		else:
			rec["reward"] = "earned"
			reward["state"] = "earned"
			if _grant(key, amount):
				rec["reward"] = "paid"
				reward["state"] = "paid"
			else:                                      # AUDIT FIX: the wallet already had it (paid on another device,
				var p := _progression()                # a lost local record): taken, not "earned" again
				if p != null and bool(p.call("has_granted", source_of(key))):
					rec["reward"] = "paid"
					reward["state"] = "taken"
	progress[key] = rec
	var f := faction_of(key)
	var unlocked := []
	var done := campaign_done(f)
	if won and done and not was_won and str(m.get("kind", "")) != "side":
		var item := "vat:faction:" + f
		unlocked.append(item)
		if not _unlock(item, "campaign:" + f):
			unlocks_pending[item] = "campaign:" + f
	save_all()
	return {"stars": stars, "best_stars": int(rec["stars"]), "new_best": stars > old_stars, "objective": obj,
		"reward": reward, "unlocked": unlocked, "district_done": won and district_done(f, str(m.get("district", ""))),
		"first_win": won and not was_won, "campaign_done": done, "next": next_open(f)}


static func pay_pending() -> int:
	## Replays recorded rewards and unlocks into Progression once it exists (idempotent sources: safe to repeat).
	## Returns how many were paid now.
	_ensure()
	if _progression() == null:
		return 0
	var n := 0
	for key in progress:
		if str(progress[key].get("reward", "")) == "earned":
			if _grant(str(key), reward_for(mission(str(key)))) or bool(_progression().call("has_granted", source_of(str(key)))):
				progress[key]["reward"] = "paid"
				n += 1
	for item in unlocks_pending.keys():
		# owns(), not is_unlocked(): Progression's testing switch opens everything but records nothing
		var p := _progression()
		if _unlock(str(item), str(unlocks_pending[item])) or bool(p.call("owns" if _has_static(p, "owns") else "is_unlocked", str(item))):
			unlocks_pending.erase(item)
	if n > 0 or unlocks_pending.is_empty():
		save_all()
	return n


static func mark_seen(what: String) -> void:
	_ensure()
	seen[what] = true
	save_all()


static func was_seen(what: String) -> bool:
	_ensure()
	return seen.has(what)


static func to_dict() -> Dictionary:
	## The whole campaign state as plain data, for the account's cloud save (Progression session, 0.20.5):
	## {version, progress: {key: record}, unlocks_pending: {item: source}, seen: {flag: true}}.
	_ensure()
	return {"version": PROGRESS_VERSION, "progress": progress.duplicate(true),
		"unlocks_pending": unlocks_pending.duplicate(), "seen": seen.duplicate()}


static func from_dict(d: Dictionary) -> void:
	## Replaces this device's campaign state with a cloud copy (the account wins) and saves it.
	progress = {}
	for k in d.get("progress", {}):
		if d["progress"][k] is Dictionary:
			progress[str(k)] = (d["progress"][k] as Dictionary).duplicate(true)
	unlocks_pending = {}
	for k in d.get("unlocks_pending", {}):
		unlocks_pending[str(k)] = str(d["unlocks_pending"][k])
	seen = {}
	for k in d.get("seen", {}):
		seen[str(k)] = true
	_loaded = true
	_loaded_path = path
	save_all()


static func reset_progress() -> void:
	## Debug / tests: forget every campaign record on this device (Progression's wallet is not touched).
	progress = {}
	unlocks_pending = {}
	seen = {}
	_loaded = true
	_loaded_path = path
	save_all()


# ------------------------------------------------------------------ Progression (0.20.1, scripts/progression.gd)
static func _progression() -> Script:
	## The wallet: Progression, or the tests' stand-in (use_progression) so a test never touches the player's
	## progress.cfg.
	return _prog_script if _prog_checked else Progression


static func use_progression(script: Script) -> void:
	## Tests: point the bridge at a stand-in wallet (or null: no wallet, rewards are only recorded).
	_prog_script = script
	_prog_checked = true


static func _grant(key: String, amount: int) -> bool:
	var p := _progression()
	return p != null and bool(p.call("grant", source_of(key), amount))


static func _unlock(item: String, source: String) -> bool:
	var p := _progression()
	return p != null and bool(p.call("unlock", item, source))


# ------------------------------------------------------------------ hand-over between a match and the campaign page
static var last_run := {}                            # main.gd sets {key, summary} after a mission; the page plays it once


# ------------------------------------------------------------------ CAMPAIGN in-match additions (mission_director.gd / main.gd)
static func progress_match(sim, seat: String, ai_level: String) -> Dictionary:
	## A mission also counts as a match for XP and challenges (no per-match SCRAP, no faction-vat win: the
	## Progression session's contract). {} with the tests' stand-in or no wallet.
	## The result may carry lines, xp_before / xp_after, challenges (the result screen shows an XP line if any).
	var p := _progression()
	if p == null or not _has_static(p, "record_match") or not _has_static(p, "result_from_sim"):
		return {}
	var r = p.call("record_match", p.call("result_from_sim", sim, seat, {"campaign": true, "ai_level": ai_level}))
	return r if r is Dictionary else {}


static func _has_static(s: Script, method: String) -> bool:
	for mm in s.get_script_method_list():
		if str(mm.get("name", "")) == method:
			return true
	return false
