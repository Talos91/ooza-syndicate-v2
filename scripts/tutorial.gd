class_name TutorialDirector
extends RefCounted
## The interactive tutorial (Docs/Game Design/Ooze Syndicate 2.0/01 Rules/TUTORIAL-REWRITE-DESIGN.md, Daniele 2026-09-30:
## "waay too long and way too messy ... rewrite it all and its logic"). Five tutorials, numbered 1..5 (quick start,
## relays, structures, skills, team play); each is DATA in TUTORIALS - a map, a staged start, reveal stages and a GOAL
## LIST done in any order - run by GoalDirector (goal_director.gd, standalone) with this class as the tutorial layer on
## top: the coach card and its one current hint, the hand / spotlight after idle time, the staged HUD reveal, the
## scripted rival moments (the relay push, the Machinegoon probe, the Last Stand staging), the assists (a short send
## is topped up), progress, rewards and the first-launch rule. Phase 1 builds the QUICK START (1); 2..5 are listed
## (the TRAINING page shows them as SOON) and convert on the same engine later: add the tutorial's row to TUTORIALS,
## its detector ops to _eval(), its hand providers to _hand() and its lines to LINES.
##
## Pure Sim logic, headless-testable (tests/test_tutorial.gd): no Node, no HUD in here. main.gd drives it:
##   begin(sim, map, seat)        after sim.setup; stages the board (call before the world is built)
##   step(dt)                      every frame, before sim.step(dt * time_scale)
##   on_event(ev)                  every sim.fx_events entry (flings and relay falls live only there)
##   on_action(method, id, args, ok)   every node_action result
##   allow(method, id, args) -> String   "" or the refusal line ("Not yet - follow the hand.")
##   ui_fraction / ui_inspector / ui_armed   the send fraction, the open inspector's node, the armed dock slot
##   skip_step()                   the card's SKIP GOAL
## and reads back card(), chips(), target(), gesture(), follow_points(), time_scale, preview_relay, state, stage,
## result, reveal_keys(). Signals: changed, completed(result), handler(mood).
##
## Progress (static, like ArmyPresets): user://tutorial.cfg [progress] completed_v2 / skipped_v2 (the ids "quick",
## "relays", "structures", "skills", "team") / offered / relay_kill / version 2. The old numeric keys are ignored.
## SKIPPING (Daniele, 2026-09-28): a run with a skipped goal (or SKIP TUTORIAL) is `skipped` - it pays no SCRAP and
## counts toward nothing; replaying it without a skip completes it (and pays, once).

signal changed
signal completed(result: Dictionary)
signal handler(mood: String)                       # the on-screen handler: "happy" (a goal ticked) / "droop" (a fail)

const HANDLER_NAME := "DR. VESK"                    # the handler on the card (Daniele, 2026-09-27)
const IDS := ["quick", "relays", "structures", "skills", "team"]   # tutorial n (1..5) -> IDS[n - 1]
const FIRST_ID := 1
const LESSON_COUNT := 5                            # the Graduate vat needs all five
const TOTAL_LESSONS := 5                           # the TUTORIAL n/5 count
const PLAYER_FACTION := "vex"                      # Daniele (0.19.3): VEX for the whole tutorial
const RIVAL_FACTION := "ember"                     # ... and the rival is always EMBER
const PROGRESS_VERSION := 2
const HUMAN := "A"
const RIVAL := "B"
const IDLE_LINE := 20.0                            # seconds without an order before Dr. Vesk asks if you are stuck

# ---------------------------------------------------------------- the handler's lines (TUTORIAL-SCRIPT.md draft 4)
# One table, so per-faction voices or translations can replace it without touching the logic. Every line uses the
# script's standard vocabulary (node, your home, neutral node, the rival, units, line, deck, vat, tier, cap, badge,
# SEND panel, inspector, relay, fire, drop, Machinegoon, Last Stand, danger mark). A line is <= 90 characters, a hint
# about 60-70. Placeholders ({cost}, {garrison}, {ls}, {secs}) are filled from Rules and the live board by _fmt().
const LINES := {
	"got_it": "GOT IT", "next_step": "NEXT", "skip_step": "SKIP GOAL", "restart": "RESTART", "exit": "EXIT",
	"skip_tutorial": "SKIP TUTORIAL",
	"not_yet": "Not yet. Follow the hand - it has a plan, which is more than HR does.",
	"try_again_title": "TRY AGAIN", "try_again": "Well, that happened. Legal says it didn't. Same board, fresh units.",
	"idle_hint": "Still with me? Follow the hand. I bill by the minute.",
	"assist_short": "Not enough units - send again, use 100 %. Accounting rounded down.",   # a short send is topped up, never a TRY AGAIN
	"paused_lessons": "LESSONS",
	"no_storage": "Progress isn't saved on this browser.",
	"skipped": "SKIPPED - replay to complete", "skipped_note": "Skipped a goal: replay it to complete it and earn its SCRAP.",
	"soon": "SOON",
	# titles and one-line goals of the five tutorials (the TRAINING page)
	"T1.title": "QUICK START", "T1.goal": "Take, reinforce, upgrade, Machinegoon, a relay kill, the Last Stand",
	"T2.title": "RELAYS", "T2.goal": "Retract, switch and remote relays",
	"T3.title": "STRUCTURES", "T3.goal": "Laser tower, Forge, Monster hub",
	"T4.title": "SKILLS", "T4.goal": "Surge, Demolish and your ultimate",
	"T5.title": "TEAM PLAY", "T5.goal": "Shared garrison, handover, EJECT",
	# the quick start (TUTORIAL-REWRITE-DESIGN.md §3a): four chapters in order - the goal strip's chips
	"T1.chapter.0": "BASICS", "T1.chapter.1": "YOUR TURN", "T1.chapter.2": "RELAY", "T1.chapter.3": "LAST STAND",
	# chapter 1, guided basics: each card is the instruction, the hand shows it from the start
	"T1.take": "Drag from your home to the grey node. Send more units than its badge: {garrison}.",
	"T1.take_send": "The SEND panel sets how much of a node goes. 50 % is plenty here.",
	"T1.reinforce": "Now drag from your home to your new node. Units move where they're needed.",
	"T1.reinforce_prep": "You need two nodes for this. Take a grey node first.",
	"T1.upgrade": "Double-tap your home to upgrade its vat to T2. Costs {cost} units.",
	"T1.upgrade_pie": "Tap UPGRADE in the menu - or double-tap the node next time. Costs {cost} units.",
	"T1.upgrade_wait": "Building: {secs} s. Watch the bar on the badge. A T2 vat breeds faster.",
	"T1.machinegoon_prep": "Take the grey node the hand shows. A Machinegoon goes there next.",
	"T1.machinegoon": "Tap that node, then MACHINEGOON. It shoots rival lines on its decks.",
	"T1.machinegoon_pie": "Now tap MACHINEGOON in the menu. It shoots rival lines on its decks.",
	"T1.machinegoon_wait": "Building your Machinegoon: {secs} s. Security budget approved.",
	"T1.machinegoon_watch": "Here comes a rival line. Watch it walk into your Machinegoon.",
	# chapter 2, free play
	"T1.free": "Your turn: grow a bit. Take grey nodes, upgrade vats. The rival is napping.",
	"T1.free_nudge": "Still there? Take a grey node or double-tap a vat. The clock is running.",
	# chapter 3, the scripted relay kill
	"T1.relay_take": "Take the relay in the middle. It moves a deck - and whatever is on it.",
	"T1.relay_wait": "Their line is coming. Wait until it's on the relay's deck. Patience pays.",
	"T1.relay_now": "Their line is on the deck. Double-tap the relay now!",
	"T1.relay_miss": "Too late - they got across. Here comes another line. They never learn.",
	"T1.relay_practice": "Timing takes practice. You'll get more chances. The void is very patient.",
	# chapter 4, the Last Stand explained
	"T1.ls_intro": "It's {ls}: the Last Stand. The city now collapses, ring by ring.",
	"T1.ls_marks": "Red danger marks show the nodes that fall next. Anything on them drops.",
	"T1.ls_rings": "The outer ring falls first. The centre ring stays - be on it.",
	"T1.ls_move": "Drag your units off the marked nodes onto the centre ring. Relocation package!",
	"T1.ls_hold": "Hold on. The outer ring falls, the centre stays standing. Tenure!",
	# a step is done (one line, one joke at most, a short moment before the next card)
	"T1.done.take": "Node taken. Acquisitions are going well.",
	"T1.done.reinforce": "Units moved. Restructuring complete.",
	"T1.done.upgrade": "T2. Faster breeding, bigger cap. Growth!",
	"T1.done.machinegoon": "Shredded. That's your Machinegoon on guard.",
	"T1.done.free": "Time's up. Now the fun part: relays.",
	"T1.done.relay_take": "The relay is yours.",
	"T1.done.relay": "Straight into the void. Record quarter. I'm framing this one.",
	"T1.done.ls_hold": "The ring is gone and you are not. Promotion pending.",
	"T1.done1": "Take, reinforce, upgrade - with a Machinegoon on guard.",
	"T1.done2": "Fire a relay under a line. Leave a ring before it falls.",
	# completion screens
	"lesson_complete": "LESSON COMPLETE", "continue_playing": "CONTINUE PLAYING", "main_menu": "MAIN MENU",
	"next": "NEXT LESSON", "replay": "REPLAY", "lessons": "LESSONS",
	"final_title": "TRAINING COMPLETE",
	"final_relay_kill": "RELAY KILL - {n} units into the void.",
	"final_reward": "GRADUATE VAT UNLOCKED",
	"final_reward_line": "Ivory and brass, for commanders who survived training. Put it on in ARMIES.",
	"final_locked": "Finish every tutorial to unlock the Graduate vat.",
	"final_armies": "ARMIES", "locked_cosmetic": "Finish the tutorial",
	"final_play": "PLAY YOUR FIRST MATCH", "final_menu": "MAIN MENU",
	# the TRAINING page
	"page_title": "TRAINING",
	"page_sub": "A quick start, then four short tutorials. Replay any of them.",
	"continue": "CONTINUE", "back": "BACK",
}

# ---------------------------------------------------------------- reveal as you go (staged by goals)
# What the tutorial has not reached yet is not on screen (Hud.reveal). Keys: map / badges / drag / clock (always),
# upgrade_arrow, send_panel, upgrade (the inspector's UPGRADE line, the double-tap), machinegoon, rival_counts,
# strength (your total, RIVALS), notices (toasts), relay (the double-tap fire, SWITCH, the relay line and outcome
# preview, the badge's relay state, ready glow and cue), relay_build (LASER / FORGE / MONSTER HUB), forge_readout,
# monster, monster_icon, status_line, danger (the floating Last Stand symbols), dock, floaters (the rising
# "+ CAPTURED" / "LOST" node text), and - never in a 1v1 tutorial - halos and eject (the team parts).
const REVEAL_BASE := ["map", "badges", "drag", "clock", "topbar"]
const REVEAL_RELAY := 3                           # the quick start's reveal stage for the relay (TUTORIALS[1]["reveal"])
const ALL_KEYS := ["map", "badges", "drag", "clock", "upgrade_arrow", "send_panel", "upgrade", "machinegoon", "rival_counts", "strength",
		"notices", "relay", "relay_build", "forge_readout", "monster", "monster_icon", "status_line", "danger", "dock", "halos", "eject",
		"out_panel", "floaters"]

# ---------------------------------------------------------------- the tutorials (data)
# map: the baked lesson map (its lessonNames name the nodes: H your home, BH the rival's, N1.. neutrals, M the
# Machinegoon node, R the relay); stage: [name, owner, shown units | "home" | "rival_home"]; reveal: keys per stage
# (cumulative: stage A from the start, B when the relay goal opens, C when the Last Stand is announced); goals: the
# list GoalDirector runs - id, chip word, hint line key, stage, ready (a precondition op), the detector `op` and the
# hand provider `hand` (see _eval / _hand). ready false = the tutorial is listed but not built yet (SOON).
const TUTORIALS := {
	# The quick start (§3a, Daniele 2026-09-30: "you cannot have new players just randomly do things without any guidance"):
	# four chapters, the steps IN ORDER. A step: id (its line "T1.<id>", done line "T1.done.<id>"), chapter, reveal (the
	# reveal stage it needs), op (the detector, _eval), read (a GOT IT card), enter (_enter), hand (_hand_now).
	1: {"key": "quick", "ready": true, "map": "T-11-proving-ground", "abilities": false, "ai": "Training",
		"stage": [["H", "A", "home"], ["BH", "B", "rival_home"]],
		"reveal": [["send_panel", "floaters"], ["upgrade", "upgrade_arrow"], ["machinegoon", "rival_counts", "strength", "notices"],
				["relay"], ["status_line", "danger"]],
		"chapters": 4,
		"steps": [
			{"id": "take", "chapter": 0, "reveal": 0, "op": ["took"], "hand": "take"},
			{"id": "reinforce", "chapter": 0, "reveal": 0, "op": ["reinforced"], "hand": "reinforce"},
			{"id": "upgrade", "chapter": 0, "reveal": 1, "op": ["upgraded", 2], "enter": "topup_home", "hand": "upgrade"},
			{"id": "machinegoon", "chapter": 0, "reveal": 2, "op": ["mg_kills"], "hand": "machinegoon"},
			{"id": "free", "chapter": 1, "reveal": 2, "op": ["free_done"], "hand": "free"},
			{"id": "relay_take", "chapter": 2, "reveal": 3, "op": ["relay_owned"], "hand": "relay_take"},
			{"id": "relay", "chapter": 2, "reveal": 3, "op": ["relay_drop"], "hand": "relay"},
			{"id": "ls_intro", "chapter": 3, "reveal": 4, "read": true, "enter": "last_stand"},
			{"id": "ls_marks", "chapter": 3, "reveal": 4, "read": true},
			{"id": "ls_rings", "chapter": 3, "reveal": 4, "read": true},
			{"id": "ls_move", "chapter": 3, "reveal": 4, "op": ["evacuated"], "enter": "ls_move", "hand": "ls_move"},
			{"id": "ls_hold", "chapter": 3, "reveal": 4, "op": ["ring_down"]},
		]},
	2: {"key": "relays", "ready": false, "map": "T-07-switchyard", "abilities": false, "ai": "Training", "stage": [], "reveal": [], "steps": []},
	3: {"key": "structures", "ready": false, "map": "T-08-relay-works", "abilities": false, "ai": "Training", "stage": [], "reveal": [], "steps": []},
	4: {"key": "skills", "ready": false, "map": "T-10-long-decks", "abilities": true, "ai": "Training", "stage": [], "reveal": [], "steps": []},
	5: {"key": "team", "ready": false, "map": "T-12-team-up", "abilities": false, "ai": "Training", "stage": [], "reveal": [], "steps": []},
}


# ================================================================ progress (static, user://tutorial.cfg)
static var path := "user://tutorial.cfg"             # tests point this elsewhere
static var map_dir := "res://maps4"                  # tests may point this at a checkout with the lesson maps
static var completed_ids: Array = []                 # tutorial numbers 1..5 (stored as the string ids)
static var skipped_ids: Array = []                   # finished with a skip, not completed (Daniele, 2026-09-28)
static var offered := false
static var relay_kill_done := false
static var saved := true                             # false: the last save failed (no storage)
static var _loaded := false


static func id_of(n: int) -> String:
	return IDS[n - 1] if n >= 1 and n <= IDS.size() else ""


static func number_of(id: String) -> int:
	return IDS.find(id) + 1


static func tutorial(n: int) -> Dictionary:
	return TUTORIALS.get(n, {})


static func playable(n: int) -> bool:
	return bool(tutorial(n).get("ready", false))


static func load_progress() -> void:
	_loaded = true
	completed_ids = []
	skipped_ids = []
	offered = false
	relay_kill_done = false
	var cf := ConfigFile.new()
	if cf.load(path) != OK:                          # none yet, or no storage at all (private browsing)
		return
	for v in cf.get_value("progress", "completed_v2", []):
		var n := number_of(str(v))
		if n >= 1 and not n in completed_ids:
			completed_ids.append(n)
	completed_ids.sort()
	for v in cf.get_value("progress", "skipped_v2", []):
		var n := number_of(str(v))
		if n >= 1 and not n in completed_ids and not n in skipped_ids:
			skipped_ids.append(n)
	skipped_ids.sort()
	offered = bool(cf.get_value("progress", "offered", false))
	relay_kill_done = bool(cf.get_value("progress", "relay_kill", false))


static func reload_progress() -> void:
	## (not `reload()`: that name is GDScript.reload(), which would reload the script and reset these statics)
	_loaded = false
	load_progress()


static func _ensure() -> void:
	if not _loaded:
		load_progress()


static func save_progress() -> bool:
	var cf := ConfigFile.new()
	cf.load(path)                                    # keeps the old (ignored) numeric keys a v1 file carried
	cf.set_value("progress", "completed_v2", completed_ids.map(func(n): return id_of(int(n))))
	cf.set_value("progress", "skipped_v2", skipped_ids.map(func(n): return id_of(int(n))))
	cf.set_value("progress", "offered", offered)
	cf.set_value("progress", "relay_kill", relay_kill_done)
	cf.set_value("progress", "version", PROGRESS_VERSION)
	saved = cf.save(path) == OK
	return saved


static var last_scrap := 0                           # TUTORIAL + PROGRESSION: what the last mark_complete paid (0 = nothing)


static func scrap_for(n: int) -> int:
	## SCRAP the first completion of tutorial n pays. One helper, so Daniele's answer on the split (TUTORIAL-REWRITE-DESIGN
	## §5: 460 + 4 x 200) is a data change: Rules.PROGRESSION["tutorial_scrap"] = {1: 460, 2: 200, ...}.
	var per = Rules.PROGRESSION.get("tutorial_scrap", {})
	if per is Dictionary and (per as Dictionary).has(n):
		return int(per[n])
	return int(Rules.PROGRESSION["tutorial_lesson"])


static func mark_complete(n: int, relay_kill := false) -> bool:
	_ensure()
	if n >= 1 and n <= LESSON_COUNT and not n in completed_ids:
		completed_ids.append(n)
		completed_ids.sort()
	skipped_ids.erase(n)                             # replayed without a skip: completed now
	offered = true
	relay_kill_done = relay_kill_done or relay_kill
	# TUTORIAL + PROGRESSION: each tutorial pays SCRAP on its first completion (the same "tutorial:N" keys as before, so
	# nobody is paid twice); the Graduate vat is recorded in Progression only when all five are done (Daniele: "Vat only
	# after all of them").
	last_scrap = 0
	if n >= 1 and n <= LESSON_COUNT:
		var amount := scrap_for(n)
		if Progression.grant("tutorial:%d" % n, amount):
			last_scrap = amount
	if all_done():
		Progression.unlock("vat:graduate", "tutorial")
	return save_progress()


static func mark_skipped(n: int) -> bool:
	## A run finished with a skipped goal, or left by SKIP TUTORIAL: not completed - no SCRAP, no step toward the Graduate
	## vat. A completed tutorial stays completed.
	_ensure()
	last_scrap = 0
	if n >= 1 and n <= LESSON_COUNT and not n in completed_ids and not n in skipped_ids:
		skipped_ids.append(n)
		skipped_ids.sort()
	offered = true
	return save_progress()


static func is_skipped(n: int) -> bool:
	_ensure()
	return n in skipped_ids


static func mark_offered() -> bool:
	_ensure()
	offered = true
	return save_progress()


static func is_done(n: int) -> bool:
	_ensure()
	return n in completed_ids


static func done_count() -> int:
	_ensure()
	return completed_ids.size()


static func all_done() -> bool:
	_ensure()
	for n in range(1, LESSON_COUNT + 1):
		if not n in completed_ids:
			return false
	return true


static func first_unfinished() -> int:
	## CONTINUE: the first playable tutorial neither done nor skipped; then the first skipped one (replay to complete it);
	## the quick start when every playable one is done.
	_ensure()
	for n in range(1, LESSON_COUNT + 1):
		if playable(n) and not n in completed_ids and not n in skipped_ids:
			return n
	for n in range(1, LESSON_COUNT + 1):
		if playable(n) and not n in completed_ids:
			return n
	return FIRST_ID


static func first_launch_due(user_args: PackedStringArray, net_busy: bool) -> bool:
	## With no `offered` key the game opens straight into the quick start. Never for a launch with a map, scenario, stage,
	## thumbnail, screenshot or test flag, an online room or a pending Net reconnect (`net_busy`).
	_ensure()
	if offered or net_busy:
		return false
	for a in user_args:
		for flag in ["--map=", "--scenario=", "--stage=", "--thumb=", "--shots=", "--demo", "--ff=", "--menu-page=",
				"--menu-shot=", "--tutorial=", "--test"]:
			if a.begins_with(flag):
				return false
	return true


static func map_path_for(n: int) -> String:
	return "%s/%s.json" % [map_dir, str(tutorial(n).get("map", ""))]


static func line(key: String) -> String:
	return str(LINES.get(key, key))


static func title_of(n: int) -> String:
	return line("T%d.title" % n)


static func lesson_rows() -> Array:
	## The TRAINING page's rows: {id, title, goal, done, skipped, soon}.
	_ensure()
	var out := []
	for n in range(1, LESSON_COUNT + 1):
		out.append({"id": n, "title": title_of(n), "goal": line("T%d.goal" % n), "done": n in completed_ids,
				"skipped": n in skipped_ids, "soon": not playable(n)})
	return out


static func reveal_for(n: int, stage := 0) -> Array:
	## Every HUD key tutorial n shows at that stage (cumulative). A tutorial without reveal data shows everything.
	var rv: Array = tutorial(n).get("reveal", [])
	if rv.is_empty():
		return ALL_KEYS.duplicate()
	var keys := REVEAL_BASE.duplicate()
	for s in range(mini(stage, rv.size() - 1) + 1):
		for k in rv[s]:
			if not k in keys:
				keys.append(k)
	return keys


static func final_kill_line(units: int) -> String:
	return line("final_relay_kill").replace("{n}", str(units))


# ================================================================ one run
var lesson_id := 1
var L: Dictionary                                    # the tutorial's row in TUTORIALS
var sim: Sim
var map: Dictionary
var names := {}                                      # lesson name -> node id (the map's lessonNames)
var goals: GoalDirector
var ai: SeatAI                                       # the Training rival (main does not run one for a tutorial)
var first_launch := false                            # the forced first run: the card carries SKIP TUTORIAL
var skipped := false                                 # a goal was skipped in this run: it ends skipped, not completed
var faction := PLAYER_FACTION
var state := "running"                               # running / failed / complete (the screen is up) / released (play on)
var stage := 0                                       # the reveal stage reached (an index into the tutorial's "reveal")
var lesson_t := 0.0
var version := 0                                     # bumped whenever card() / chips() / target() / gesture() change
var time_scale := 1.0                                # main steps the Sim at dt x this (slow motion at the relay moment)
var preview_relay := -1                              # main keeps the relay-outcome preview up for this relay
var result := {}
var fail_line := ""
var ui_fraction := 0.5
var ui_inspector := -1                               # main: the node the inspector is open on (-1: none)
var ui_armed := -1
var ui_monster_from := -1

var _ev_cursor := 0
var _log: Array = []                                 # fx events kept for the detectors (fling, fall, last_stand ...)
var _note := ""
var _note_t := 0.0
var _last_order_t := 0.0
var _idle_shown := false
var _wrong_until := -1.0                             # the hand shows until this match time after a wrong action
var _dt := 0.0
var _hint_key := ""                                  # what the card's hint was built from (it is rebuilt only when this changes)
var _hint_text := ""
var _hmeta := {}                                     # horde id -> {"to_owner", "from", "to"}: what each of your lines was sent at
var _upgraded_tier := 0
var _took := 0
var _reinforced := false
var _mg_kills := 0.0
var _mg_seen := {}                                   # machinegoon node -> the last shot time counted
var _mg_site := -1
var _mg_probe := {"tries": 0, "next": -1.0, "line": -1}
var _relay_drops := 0                                # shown rival units your relay dropped (fling + fall events)
var _push := {"phase": "idle", "tries": 0, "line": -1, "t": 0.0, "slow_t": 0.0, "prompt": false, "units": 0}
var _relay_done_t := -1.0
var _relay_kill_units := 0
var _ls_started := false
var _ls_t0 := 0.0
var _ls_falls := 0.0
var _assist := {}                                    # neutral node id -> {"seen", "frozen", "from", "topped"}
var _assist_added := {}
var _entered := ""                                   # the step whose `enter` ran last
var _enter_t := {}                                   # step id -> the match time it became current
var _base := {}                                      # counters at a step's start (its detector counts from there)
var _pressed := {}                                   # read-only steps whose GOT IT was pressed
var _evac_sent := false                              # the Last Stand move: a send off a falling node onto the kept ring
var _free_shown := -1                                # the free-play countdown the strip shows


func _init(id := 1) -> void:
	lesson_id = clampi(id, FIRST_ID, LESSON_COUNT)
	L = tutorial(lesson_id)


func loadout_for(_player_faction := "", _preset := {}) -> Dictionary:
	## The quick start plays with the skill dock off (abilities are off): no loadout. Never the ARMIES preset: the whole
	## tutorial is VEX (Daniele, 0.19.3).
	faction = PLAYER_FACTION
	return (L.get("loadout", {}) as Dictionary).duplicate()


func fraction_start(current: float) -> float:
	return float(L.get("fraction", current))


# ---------------------------------------------------------------- staging
func begin(s: Sim, m: Dictionary, player_faction := "") -> void:
	## Stage the board right after sim.setup (before the world is built from it).
	sim = s
	map = m
	if player_faction != "":
		faction = player_faction
	names = {}
	var ln = m.get("lessonNames", null)
	if ln is Dictionary:
		for k in ln:
			names[str(k)] = int(ln[k])
	if not names.has("H") and sim.homes.has(HUMAN):
		names["H"] = int(sim.homes[HUMAN])
	if not names.has("BH") and sim.homes.has(RIVAL):
		names["BH"] = int(sim.homes[RIVAL])
	if not names.has("R"):
		for n in sim.nodes:
			if n["relay"] != "":
				names["R"] = int(n["id"])
				break
	sim.abilities_on = bool(L.get("abilities", false))
	sim.vls_enabled = false                          # the Very Last Stand waits until the quick start is over
	sim.match_hard_end = INF                         # ... and so does the 7:00 end (release_pins puts both back)
	for seat in sim.skill_cd:                        # skills stand ready
		sim.skill_cd[seat] = {"active": 0.0, "map": 0.0}
	_stage_board()
	_ev_cursor = sim.events.size()
	ai = SeatAI.new(RIVAL, 2.5, str(L.get("ai", "Training")))
	_build_goals()
	_last_order_t = sim.time
	state = "running"
	stage = 0
	goals.unlock_stage(0)


func _stage_board() -> void:
	var by_id := {}
	for mn in map.get("nodes", []):
		by_id[int(mn["id"])] = mn
	for n in sim.nodes:                              # every node at the map's own start (a legacy dev map included)
		var mn: Dictionary = by_id.get(int(n["id"]), {})
		if n["owner"] == "":
			var neutral = mn.get("neutral", null)
			if neutral is Dictionary and n["node_kind"] != "relay":
				n["tier"] = clampi(int(neutral.get("tier", 1)), 1, 4)
			if n["node_kind"] == "special":
				n["tier"] = 4
			n["units"] = float(Rules.NEUTRAL_UNITS.get(n["tier"], 0)) if Sim.has_vat(n) else n["units"]
	for e in L.get("stage", []):
		var id := _id(str(e[0]))
		if id < 0:
			continue
		var n: Dictionary = sim.nodes[id]
		n["owner"] = str(e[1])
		var v = e[2]
		if v is String:
			v = Rules.QUICK_START["home_shown"] if v == "home" else Rules.QUICK_START["rival_home_shown"]
		n["units"] = float(v) * Rules.SCALE


func _id(name: String) -> int:
	return int(names.get(name, -1))


func _home() -> int:
	return _id("H")


func _relay() -> int:
	return _id("R")


func reveal_keys() -> Array:
	return reveal_for(lesson_id, stage)


# ---------------------------------------------------------------- the goals (GoalDirector + this layer's detectors)
func _build_goals() -> void:
	## The steps become GoalDirector goals, one stage each: step i is live once step i-1 is done (the order of §3a).
	goals = GoalDirector.new(self)
	var steps: Array = L.get("steps", [])
	for i in range(steps.size()):
		var sp: Dictionary = (steps[i] as Dictionary).duplicate()
		var id := str(sp["id"])
		sp["stage"] = i
		if sp.get("read", false):
			sp["check"] = func(_c): return _pressed.has(id)
		else:
			var op: Array = sp["op"]
			sp["check"] = func(_c): return _eval(op)
		match id:                                    # the per-step assists (scripted rival lines, top-ups)
			"machinegoon":
				sp["assist"] = func(_c, _d): _tick_mg_step()
			"relay":
				sp["assist"] = func(_c, _d): _tick_push()
		goals.add_goal(sp)
	goals.goal_completed.connect(_on_goal_done)


func _eval(op: Array):
	## The step detectors - each counts from its own step's start (a later step never passes before its turn).
	match str(op[0]):
		"took":                                      # a neutral node captured since the step began
			return _took > int(_base.get("took", 0))
		"reinforced":                                # a line between two of your nodes landed since the step began
			return _reinforced
		"upgraded":                                  # a vat of yours went up to tier op[1] (an upgrade, never a captured T2)
			return _upgraded_tier >= int(op[1])
		"mg_kills":                                  # you built a Machinegoon and it killed rival units
			return _mg_kills >= float(Rules.QUICK_START["mg_kill_shown"]) * Rules.SCALE
		"free_done":
			return sim.time - float(_enter_t.get("free", sim.time)) >= float(Rules.QUICK_START["free_play"])
		"relay_owned":
			return _relay() >= 0 and sim.nodes[_relay()]["owner"] == HUMAN
		"relay_drop":                                # your relay dropped rival units
			return _relay_drops >= int(Rules.QUICK_START["relay_min_drop"])
		"evacuated":                                 # a send off a falling node onto the kept ring - or nothing left to move
			return _evac_sent or (_ls_started and _evac_move().is_empty())
		"ring_down":                                 # the first ring fell and you still hold a node
			return _ring_down()
	return false


func _mine() -> Array:
	var out := []
	for n in sim.nodes:
		if n["owner"] == HUMAN and not sim.collapsed.get(n["id"], false) and n["node_kind"] != "junction":
			out.append(n["id"])
	return out


func _open_stage(n: int) -> void:
	## Reveal stage n (and everything before it); the relay stage also arms the relay-outcome preview.
	if n <= stage:
		return
	stage = n
	if n >= REVEAL_RELAY:
		preview_relay = _relay()
	_bump()


func current_id() -> String:
	return str(goals.current().get("id", "")) if goals else ""


func current_step() -> Dictionary:
	return goals.current() if goals else {}


func _step_index(id: String) -> int:
	for i in range(goals.goals.size()):
		if goals.goals[i]["id"] == id:
			return i
	return -1


func _enter_current() -> void:
	## The step that just became current: its reveal, its staging (`enter`), its clocks.
	var g := goals.current()
	if g.is_empty() or str(g["id"]) == _entered:
		return
	var id := str(g["id"])
	_entered = id
	_enter_t[id] = sim.time
	_open_stage(int(g.get("reveal", 0)))
	match id:
		"take":
			_base["took"] = _took
		"reinforce":
			_reinforced = false
		"relay":
			_push["phase"] = "idle"
	match str(g.get("enter", "")):
		"topup_home":                                # the upgrade can always be paid
			var h := _home()
			if h >= 0 and sim.nodes[h]["owner"] == HUMAN:
				var need := float(sim.upgrade_cost(sim.nodes[h])) + 5.0 * Rules.SCALE
				sim.nodes[h]["units"] = maxf(float(sim.nodes[h]["units"]), need)
		"last_stand":
			_stage_last_stand()
		"ls_move":
			_evac_sent = false
	_last_order_t = sim.time                         # a fresh card: the idle clock starts again
	_idle_shown = false
	_bump()


func _on_goal_done(id: String, was_skipped: bool) -> void:
	if was_skipped:
		skipped = true
	elif LINES.has("T1.done.%s" % id):
		say(line("T1.done.%s" % id), float(Rules.QUICK_START["tick_note"]))
		handler.emit("happy")
	if id == "relay":
		_relay_done_t = sim.time
		_push["prompt"] = false
		_push["phase"] = "done"
	goals.unlock_stage(_step_index(id) + 1)          # the next step goes live now
	_enter_current()
	_bump()


func _tick_mg_step() -> void:
	## The Machinegoon step: once M is yours it can always pay for the build (staging), then the probe walks at it.
	var site := _mg_site_id()
	if site >= 0 and sim.nodes[site]["owner"] == HUMAN and sim.nodes[site]["structure"] == "vat" and sim.nodes[site]["build_kind"] == "":
		var need := float(Rules.MACHINEGOON_COST[1]) + 5.0 * Rules.SCALE
		if float(sim.nodes[site]["units"]) < need:
			sim.nodes[site]["units"] = need
	_tick_probe()


# ---------------------------------------------------------------- the frame
func step(dt: float) -> void:
	if sim == null:
		return
	if state == "released":                          # CONTINUE PLAYING: the Training AI plays the rest of the match
		if ai != null:
			ai.think(sim, dt)
		return
	if state != "running":
		return
	_dt = dt
	lesson_t += dt
	time_scale = 1.0
	if _note_t > 0.0:
		_note_t -= dt
		if _note_t <= 0.0:
			_note = ""
			_bump()
	_scan_events()
	_track_hordes()
	_scan_machinegoons()
	_scan_reinforce()
	_tick_short_sends()
	_enter_current()
	goals.tick(dt, sim.time)                         # (the rival stays passive: no AI until the quick start is done)
	if state != "running":
		return
	_hold_last_stand()
	_cap_rival()
	if goals.all_done():
		_complete()
		return
	var why := _check_fail()
	if why != "":
		_fail(why)
		return
	if state != "running":
		return
	_refresh_hint()
	_tick_countdown()
	var cur := current_id()
	var read := bool(current_step().get("read", false))
	var idle_after := float(Rules.QUICK_START["free_nudge"]) if cur == "free" else IDLE_LINE
	if not _idle_shown and not read and sim.time - _last_order_t > idle_after and str(_push["phase"]) != "out":
		_idle_shown = true
		say(line("T1.free_nudge") if cur == "free" else line("idle_hint"))


func _tick_countdown() -> void:
	## Free play: the strip's chip counts the seconds down.
	if current_id() != "free":
		return
	var left := free_left()
	if left != _free_shown:
		_free_shown = left
		_bump()


func free_left() -> int:
	## Whole seconds of free play left (the strip shows it).
	if current_id() != "free":
		return 0
	var t := sim.time - float(_enter_t.get("free", sim.time))
	return maxi(0, ceili(float(Rules.QUICK_START["free_play"]) - t))


func on_event(ev: Dictionary) -> void:
	## main: every sim.fx_events entry (and the headless test does the same after each sim.step).
	match str(ev.get("type", "")):
		"fling", "fall", "last_stand", "collapse", "build_done", "monster_kick":
			var e := ev.duplicate()
			e.erase("pts")
			e["t"] = sim.time if sim else 0.0
			_log.append(e)
			if str(ev.get("seat", "")) == RIVAL:
				var relay := _relay()
				if str(ev["type"]) == "fling" and int(ev.get("node", -1)) == relay and relay >= 0:
					_relay_drops += int(ev.get("units", 0))
					_relay_kill_units += int(ev.get("units", 0))
				elif str(ev["type"]) == "fall" and int(ev.get("relay", -1)) == relay and relay >= 0:
					_relay_drops += int(ev.get("shown", 0))
					_relay_kill_units += int(ev.get("shown", 0))


func on_action(method: String, _id_arg: int, _args := {}, ok := true) -> void:
	## main: every node_action result. An accepted order resets the idle clock (the hand hides); a refused one is a
	## wrong action (the hand shows).
	if sim == null:
		return
	if ok and method != "":
		_last_order_t = sim.time
		_idle_shown = false
	elif not ok:
		_wrong_until = sim.time + float(Rules.QUICK_START["wrong_hand"])
		_bump()


func allow(method: String, _id_arg: int, args := {}) -> String:
	## "" or the line that refuses an order which would wreck the staging: an attack on the rival's home before the goals
	## are done (the match would end under the tutorial).
	if sim == null or state != "running":
		return ""
	if method == "send":
		var to := int(args.get("to", -1))
		if to >= 0 and to == _id("BH") and not goals.all_done():
			_wrong_until = sim.time + float(Rules.QUICK_START["wrong_hand"])
			return line("not_yet")
	return ""


func press_button() -> void:
	## The card's GOT IT on a read-only step (the Last Stand explanations).
	if state != "running" or goals == null:
		return
	_enter_current()
	var g := goals.current()
	if not g.is_empty() and g.get("read", false):
		_pressed[str(g["id"])] = true
		goals.complete(str(g["id"]))


func skip_step() -> void:
	## SKIP GOAL: the current step counts as done for the flow (the next one starts) but the run ends skipped.
	if state != "running" or goals == null:
		return
	_enter_current()                                 # (its staging runs even when it is skipped at once)
	var g := goals.current()
	if g.is_empty():
		return
	skipped = true
	if str(g["id"]) == "relay":
		_push["phase"] = "done"
		_push["prompt"] = false
	goals.skip(str(g["id"]))
	_bump()


func say(text: String, secs := -1.0) -> void:
	## A transient handler line on the card (a refusal, a goal ticking, a miss).
	if text == "":
		return
	_note = text
	_note_t = secs if secs > 0.0 else float(Rules.QUICK_START["note"])
	_bump()


func _bump() -> void:
	version += 1
	changed.emit()


# ---------------------------------------------------------------- reading the Sim
func _scan_events() -> void:
	while _ev_cursor < sim.events.size():
		var ev: Dictionary = sim.events[_ev_cursor]
		_ev_cursor += 1
		var seat := str(ev.get("seat", ""))
		match str(ev.get("type", "")):
			"build_done":
				if seat == HUMAN and str(ev.get("kind", "")) == "vat":
					var nd: Dictionary = sim.nodes[int(ev["node"])]
					_upgraded_tier = maxi(_upgraded_tier, int(nd["tier"]))
			"capture":
				if seat == HUMAN and str(ev.get("from", "x")) == "":
					_took += 1
			"send", "build_start", "relay_fired", "skill", "monster_launch":
				if seat == HUMAN:
					_last_order_t = sim.time
					_idle_shown = false
					if str(ev["type"]) == "send" and _ls_started and _doomed(int(ev.get("from", -1))) \
							and sim.last_stand_keep.has(int(ev.get("to", -1))):
						_evac_sent = true              # off a falling node, onto the kept ring


func _track_hordes() -> void:
	## What each of your lines was sent at (the target's owner at the first frame it is seen): a capture that pours in
	## after the node changed hands is not a reinforcement.
	var alive := {}
	for h in sim.hordes:
		if h["owner"] != HUMAN or h.get("decoy", false):
			continue
		alive[h["id"]] = true
		if not _hmeta.has(h["id"]):
			var t := int(h["target"])
			_hmeta[h["id"]] = {"to_owner": str(sim.nodes[t]["owner"]), "from": int(h["route"][0]), "to": t}
	for hid in _hmeta.keys():
		if not alive.has(hid):
			_hmeta[hid]["gone"] = true
	for hid in _hmeta.keys():                        # forget the gone ones after the assist has looked (one frame)
		if _hmeta[hid].get("gone", false) and _hmeta[hid].get("gone_seen", false):
			_hmeta.erase(hid)
		elif _hmeta[hid].get("gone", false):
			_hmeta[hid]["gone_seen"] = true


func _scan_reinforce() -> void:
	if _reinforced:
		return
	for h in sim.hordes:
		if h["owner"] != HUMAN or h["state"] != "absorb" or not _hmeta.has(h["id"]):
			continue
		var m: Dictionary = _hmeta[h["id"]]
		if str(m["to_owner"]) == HUMAN and int(m["from"]) != int(m["to"]) and sim.nodes[int(m["to"])]["owner"] == HUMAN \
				and sim.nodes[int(m["from"])]["owner"] == HUMAN:
			_reinforced = true
			return


func _scan_machinegoons() -> void:
	_mg_site = -1
	for n in sim.nodes:
		if n["owner"] == HUMAN and n["structure"] == "machinegoon" and n["build_kind"] == "":
			_mg_site = n["id"]
			var shot: Dictionary = n["shot"]
			if not shot.is_empty():
				var st := float(shot.get("t", -1.0))
				if st > float(_mg_seen.get(n["id"], -1.0)):
					_mg_seen[n["id"]] = st
					_mg_kills += float(shot.get("kills", 0.0))


func _any_alive(hid: int) -> bool:
	return not sim._horde(hid).is_empty()


# ---------------------------------------------------------------- short sends never break the quick start
# Daniele (0.20.2): "since sometimes order might be short of a few troops or the user might be mistake amount sent it can
# somewhat break the tutorial". When a line of yours lands on a neutral node and it is still not yours, the director
# tops up your best sender to win with a margin, freezes the target's count until it is taken, says so once and points
# the hand at the retry. A short send is never a TRY AGAIN.
func _tick_short_sends() -> void:
	for hid in _hmeta.keys():
		var m: Dictionary = _hmeta[hid]
		if str(m["to_owner"]) != "" or m.get("counted", false):
			continue
		var t := int(m["to"])
		if sim.collapsed.get(t, false):
			continue
		var a: Dictionary = _assist.get(t, {"seen": {}, "frozen": -1.0, "from": -1, "topped": false})
		_assist[t] = a
		if not m.get("gone", false):
			a["seen"][hid] = true
		elif a["seen"].has(hid):
			a["seen"].erase(hid)
			m["counted"] = true
			a["short"] = true
	for t in _assist.keys():
		var a: Dictionary = _assist[t]
		var tn: Dictionary = sim.nodes[t]
		if tn["owner"] != "" or sim.collapsed.get(t, false):
			_assist.erase(t)
			continue
		if float(a["frozen"]) >= 0.0:
			tn["units"] = minf(float(tn["units"]), float(a["frozen"]))
		if not (a["seen"] as Dictionary).is_empty() or not a.get("short", false):
			continue
		a["short"] = false
		var need := float(tn["units"]) * 1.1 + float(Rules.QUICK_START["assist_margin"]) * Rules.SCALE
		var best := -1
		var best_doomed := true
		for n in sim.nodes:
			if n["owner"] != HUMAN or sim.collapsed.get(n["id"], false) or sim.find_route(n["id"], t).size() < 2:
				continue
			var doomed := _doomed(n["id"])
			if best < 0 or (best_doomed and not doomed) or (doomed == best_doomed and n["units"] > sim.nodes[best]["units"]):
				best = n["id"]
				best_doomed = doomed
		if best < 0:
			continue
		var bn: Dictionary = sim.nodes[best]
		_assist_added[best] = float(_assist_added.get(best, 0.0)) + maxf(need - float(bn["units"]), 0.0)
		bn["units"] = maxf(float(bn["units"]), need)
		a["frozen"] = float(tn["units"])
		a["from"] = best
		a["topped"] = true
		say(line("assist_short"))
		_wrong_until = sim.time + float(Rules.QUICK_START["wrong_hand"])
		handler.emit("droop")


func assist_retry() -> Array:
	## [from, to] of the retry the hand points at after a top-up (no line of yours on the way), else [].
	for t in _assist:
		var a: Dictionary = _assist[t]
		if int(a.get("from", -1)) >= 0 and sim.nodes[t]["owner"] == "" and (a["seen"] as Dictionary).is_empty():
			return [int(a["from"]), int(t)]
	return []


func _doomed(id: int) -> bool:
	## Warned by a collapse, or in the ring the Last Stand is taking now.
	if sim.is_warned(id):
		return true
	return sim.last_stand_active and id in _ring_nodes()


# ---------------------------------------------------------------- the Machinegoon probe
func _tick_probe() -> void:
	## Once a Machinegoon of yours stands, a small scripted rival line walks at it so it has something to shoot (the
	## Training AI may take a minute to come). Tries again if nothing was killed.
	if _mg_site < 0 or _mg_kills >= float(Rules.QUICK_START["mg_kill_shown"]) * Rules.SCALE:
		return
	if float(_mg_probe["next"]) < 0.0:
		_mg_probe["next"] = sim.time + float(Rules.QUICK_START["probe_delay"])
	if sim.time < float(_mg_probe["next"]) or int(_mg_probe["tries"]) >= int(Rules.QUICK_START["probe_tries"]):
		return
	if _rival_bound_for(_mg_site):
		return
	var from := _nearest_rival(_mg_site)
	if from < 0:
		return
	var h := _rival_send(from, _mg_site, float(Rules.QUICK_START["probe_shown"]))
	if h.is_empty():
		return
	_mg_probe["line"] = h["id"]
	_mg_probe["tries"] = int(_mg_probe["tries"]) + 1
	_mg_probe["next"] = sim.time + float(Rules.QUICK_START["probe_gap"])
	_bump()


func _nearest_rival(to: int) -> int:
	var best := -1
	var best_len := 99999
	for n in sim.nodes:
		if n["owner"] != RIVAL or sim.collapsed.get(n["id"], false) or n["node_kind"] == "relay":
			continue
		var r := sim.find_route(n["id"], to)
		if r.size() >= 2 and (r.size() < best_len or (r.size() == best_len and n["units"] > sim.nodes[best]["units"])):
			best_len = r.size()
			best = n["id"]
	return best


func _rival_send(from: int, to: int, shown: float) -> Dictionary:
	## One scripted rival order of about `shown` units (the source is topped up if it has fewer - staging).
	if from < 0 or to < 0 or sim.collapsed.get(from, false):
		return {}
	var n: Dictionary = sim.nodes[from]
	if n["owner"] != RIVAL:
		return {}
	var want := shown * Rules.SCALE
	if float(n["units"]) < want + 1.0:
		n["units"] = want + 1.0
	return sim.send(from, to, clampf((want + 0.5) / float(n["units"]), 0.01, 1.0))


func _rival_bound_for(node: int) -> bool:
	for h in sim.hordes:
		if h["owner"] == RIVAL and int(h["target"]) == node:
			return true
	return false


# ---------------------------------------------------------------- the relay moment
# Once the relay goal is open and the relay is yours (at 2:00 the stage opens whatever you did), a scripted rival line
# walks onto the relay's open deck. The game drops to slow motion from ~2 s before the line is on the deck and holds
# until the relay moves (the drop) or the line is past, at most `slow_max` real seconds so the window always ends. A
# miss sends the next line after `relay_retry` s, up to `relay_tries`, then "timing takes practice" passes the goal.
func _tick_push() -> void:
	var relay := _relay()
	if str(_push["phase"]) == "done":
		return
	if relay < 0 or sim.collapsed.get(relay, false):     # no relay left to fire (or none on this map)
		_pass_relay_by_practice()
		return
	var rn: Dictionary = sim.nodes[relay]
	match str(_push["phase"]):
		"idle":
			if _push_due(relay):
				_launch_push(relay)
		"out":
			var hid := int(_push["line"])
			_relay_window(hid, relay)
			if not _any_alive(hid) or _landed(hid):
				_push["prompt"] = false
				_push["tries"] = int(_push["tries"]) + 1
				_push["phase"] = "cool"
				_push["t"] = sim.time
				if int(_push["tries"]) >= int(Rules.QUICK_START["relay_tries"]):
					_pass_relay_by_practice()
				else:
					say(line("T1.relay_miss"))
		"cool":
			if sim.time - float(_push["t"]) >= float(Rules.QUICK_START["relay_retry"]) and rn["owner"] == HUMAN:
				_push["phase"] = "idle"


func _pass_relay_by_practice() -> void:
	_push["phase"] = "done"
	_push["prompt"] = false
	goals.complete("relay")
	say(line("T1.relay_practice"))


func _push_due(relay: int) -> bool:
	var rn: Dictionary = sim.nodes[relay]
	if current_id() != "relay" or rn["owner"] != HUMAN or rn["relay_phase"] != "" or rn["relay_cd"] > 0.0:
		return false
	return true                                      # (the scripted line tops its source up: no strength needed)


func _relay_deck(relay: int) -> Dictionary:
	## The relay's deck open now, as {edge, near, far}: near = the end the rival reaches first.
	for ei in sim.controlled_edges(relay):
		if not sim.is_edge_open(ei):
			continue
		var e: Dictionary = sim.edges[ei]
		var a: int = e["a"]
		var b: int = e["b"]
		var home := int(sim.homes.get(RIVAL, -1))
		var ra := sim.find_route(home, a, {ei: true}) if home >= 0 else []
		var rb := sim.find_route(home, b, {ei: true}) if home >= 0 else []
		var near := a if (not ra.is_empty() and (rb.is_empty() or ra.size() <= rb.size())) else b
		return {"edge": ei, "near": near, "far": b if near == a else a}
	return {}


func _launch_push(relay: int) -> void:
	var deck := _relay_deck(relay)
	if deck.is_empty():
		return
	var m := -1
	var best_len := 99999
	for n in sim.nodes:
		if n["owner"] != RIVAL or sim.collapsed.get(n["id"], false):
			continue
		var r := sim.find_route(n["id"], deck["near"], {deck["edge"]: true}) if n["id"] != deck["near"] else [n["id"]]
		if r.is_empty():
			continue
		if r.size() < best_len or (r.size() == best_len and n["units"] > sim.nodes[m]["units"]):
			best_len = r.size()
			m = n["id"]
	if m < 0:
		return
	# the push's target: your node nearest the deck's far end (the far end itself if it is yours)
	var target := int(deck["far"])
	if sim.nodes[target]["owner"] != HUMAN:
		var tl := 99999
		for n in sim.nodes:
			if n["owner"] != HUMAN or sim.collapsed.get(n["id"], false):
				continue
			var r2 := sim.find_route(deck["far"], n["id"])
			if not r2.is_empty() and r2.size() < tl:
				tl = r2.size()
				target = n["id"]
	var route: Array = [m] if m == int(deck["near"]) else sim.find_route(m, deck["near"], {deck["edge"]: true})
	if route.is_empty():
		return
	route.append(deck["far"])
	if target != int(deck["far"]):
		var tail := sim.find_route(deck["far"], target, {deck["edge"]: true})
		if tail.size() >= 2:
			route.append_array(tail.slice(1))
		else:
			target = int(deck["far"])
	if route.size() < 2 or route.count(route[-1]) > 1:
		return
	var shown := float(Rules.QUICK_START["push_shown"])
	var tn: Dictionary = sim.nodes[target]
	if tn["owner"] == HUMAN:                         # a miss never takes the node
		tn["units"] = maxf(float(tn["units"]), (shown + 10.0) * Rules.SCALE)
	var h := _rival_send(m, target, shown)
	if h.is_empty():
		return
	sim._set_route(h, route)                         # the scripted line crosses the relay deck, whatever is fastest
	h["speed"] = float(Rules.QUICK_START["line_speed"])
	_push["phase"] = "out"
	_push["line"] = h["id"]
	_push["t"] = sim.time
	_push["slow_t"] = 0.0
	_push["prompt"] = false
	_push["units"] = shown
	_relay_kill_units = 0
	_bump()


func _relay_window(hid: int, relay: int) -> void:
	## The slow-motion window and the prompt: a fire NOW would still drop at least the counted units - the line is where
	## the deck is when the relay's warning runs out.
	var rn: Dictionary = sim.nodes[relay]
	var eta := _deck_eta(hid, relay)
	var moving: bool = rn["relay_phase"] == "moving"
	var fired: bool = rn["relay_phase"] != ""
	var slow_on := eta >= 0.0 and eta <= float(Rules.QUICK_START["slow_lead"]) and not moving \
			and float(_push["slow_t"]) < float(Rules.QUICK_START["slow_max"])
	if slow_on:
		_push["slow_t"] = float(_push["slow_t"]) + _dt
		time_scale = float(Rules.QUICK_START["slow"])
	var prompt := not fired and _drop_if_fired(hid, relay) >= float(Rules.QUICK_START["relay_min_drop"]) * Rules.SCALE
	if prompt != bool(_push["prompt"]):
		_push["prompt"] = prompt
		_bump()


func _deck_eta(hid: int, relay: int) -> float:
	## Seconds (match time) until line `hid` reaches the relay's open deck: 0 while on it, -1 once past or off route.
	var h := sim._horde(hid)
	if h.is_empty():
		return -1.0
	var head: float = h["s"]
	var tail: float = head - Sim.chain_length(h)
	var v := maxf(Rules.move_speed() * float(h.get("speed", 1.0)) * sim.stat(h["owner"], "speed"), 0.1)
	for sp in h["spans"]:
		if not (sp["edge"] in sim.controlled_edges(relay)) or not sim.is_edge_open(sp["edge"]):
			continue
		if head >= sp["s0"] and tail <= sp["s1"]:
			return 0.0
		if head < sp["s0"]:
			return (float(sp["s0"]) - head) / v
	return -1.0


func _drop_if_fired(hid: int, relay: int) -> float:
	## Units (sim) of line `hid` on the relay's open deck when a fire now takes effect (after Rules.RELAY_WARNING).
	var h := sim._horde(hid)
	if h.is_empty():
		return 0.0
	var v := Rules.move_speed() * float(h.get("speed", 1.0)) * sim.stat(h["owner"], "speed")
	var head: float = float(h["s"]) + v * Rules.RELAY_WARNING
	var total: float = float(h["ordered"]) if h["streaming"] else float(h["units"])
	var tail: float = head - minf(Sim.full_length(total), head)
	var best := 0.0
	for sp in h["spans"]:
		if sp["edge"] in sim.controlled_edges(relay) and sim.is_edge_open(sp["edge"]):
			best = maxf(best, minf(head, sp["s1"]) - maxf(tail, sp["s0"]))
	return maxf(best, 0.0) / Rules.metres_per_unit()


func _landed(hid: int) -> bool:
	var h := sim._horde(hid)
	return not h.is_empty() and h["state"] == "absorb" and not h["streaming"]


func catch_prompt() -> bool:
	## The push's line is on the relay's deck right now (the prompt, the hand, the slow motion).
	return bool(_push["prompt"]) and str(_push["phase"]) == "out"


func catch_line() -> int:
	return int(_push["line"]) if str(_push["phase"]) == "out" else -1


# ---------------------------------------------------------------- the Last Stand
func _stage_last_stand() -> void:
	## The collapse is announced: the clock jumps to {ls}, the drops are pinned short, the rival is capped weak so the
	## collapse can be won, the kept ring's neutral nodes are made cheap to take.
	if _ls_started:
		return
	_ls_started = true
	_note = ""                                       # the announcement is the hint now
	_note_t = 0.0
	_jump_clock(Rules.LAST_STAND_TIME)
	_ls_t0 = sim.time
	_ls_falls = float(sim.fall_losses.get(HUMAN, 0.0))
	sim.ls_drop_gap_override = Rules.LAST_STAND_DROP_GAP
	sim.start_last_stand_now()
	for n in sim.nodes:
		if n["owner"] == "" and Sim.has_vat(n) and sim.last_stand_keep.has(n["id"]):
			var cap := float(Rules.QUICK_START["ls_neutral_cap_shown"]) * Rules.SCALE
			n["units"] = minf(float(n["units"]), cap)
			n["regen_cap"] = n["units"]
	_give_rival_a_kept_node()
	_bump()


func _give_rival_a_kept_node() -> void:
	## The rival keeps a node on the kept ring (the one nearest its home that you do not hold), so the collapse takes its
	## outer nodes and the match still goes on when you CONTINUE PLAYING - instead of ending under the tutorial.
	var home := int(sim.homes.get(RIVAL, -1))
	if home < 0 or sim.last_stand_keep.is_empty():
		return
	for n in sim.nodes:
		if n["owner"] == RIVAL and sim.last_stand_keep.has(n["id"]):
			return
	var best := -1
	var best_len := 99999
	for id in sim.last_stand_keep.keys():
		var n: Dictionary = sim.nodes[id]
		if n["owner"] == HUMAN or n["node_kind"] in ["junction", "relay"] or not Sim.has_vat(n):
			continue
		var r := sim.find_route(home, id)
		if r.size() >= 2 and r.size() < best_len:
			best_len = r.size()
			best = id
	if best >= 0:
		sim.nodes[best]["owner"] = RIVAL
		sim.nodes[best]["units"] = minf(float(sim.nodes[best]["units"]), float(Rules.QUICK_START["ls_rival_cap_shown"]) * Rules.SCALE)
		sim.nodes[best]["regen_cap"] = sim.nodes[best]["units"]


func _jump_clock(to: float) -> void:
	## The match clock jumps to the collapse's own time (so the HUD clock and the line agree); every time the director
	## measures from moves with it.
	var d := to - sim.time
	if d <= 0.0:
		return
	sim.time = to
	_last_order_t += d
	if _wrong_until > 0.0:
		_wrong_until += d
	if float(_mg_probe["next"]) > 0.0:
		_mg_probe["next"] = float(_mg_probe["next"]) + d
	_push["t"] = float(_push["t"]) + d
	if _relay_done_t >= 0.0:
		_relay_done_t += d
	for k in _mg_seen.keys():
		_mg_seen[k] = float(_mg_seen[k]) + d
	for k in _enter_t.keys():                        # the step clocks move with it
		_enter_t[k] = float(_enter_t[k]) + d


func _hold_last_stand() -> void:
	## The first ring's countdown waits while the explanation cards are read, and a few seconds into the move.
	if not _ls_started or sim.last_stand_queue.is_empty() or goals.goal_done("ls_hold"):
		return
	var cur := current_id()
	var hold := cur in ["ls_intro", "ls_marks", "ls_rings"]
	if cur == "ls_move" and sim.time - float(_enter_t.get("ls_move", sim.time)) < float(Rules.QUICK_START["ls_grace"]):
		hold = true
	if hold:
		sim.last_stand_warn_t = maxf(sim.last_stand_warn_t, Rules.LAST_STAND_WARNING)


func _cap_rival() -> void:
	## From the announcement to the end of the quick start the rival's nodes hold at most a few units: whatever the
	## collapse leaves it, an attack of yours can take.
	if not _ls_started or goals.goal_done("ls_hold"):
		return
	var cap := float(Rules.QUICK_START["ls_rival_cap_shown"]) * Rules.SCALE
	for n in sim.nodes:
		if n["owner"] == RIVAL:
			n["units"] = minf(float(n["units"]), cap)


func _ring_nodes() -> Array:
	return (sim.last_stand_waves[0] as Array) if not sim.last_stand_waves.is_empty() else []


func _holds_node() -> bool:
	for n in sim.nodes:
		if n["owner"] == HUMAN and not sim.collapsed.get(n["id"], false):
			return true
	return false


func _ring_down() -> bool:
	if not _ls_started:
		return false
	if sim.over and sim.winner != "" and sim.allied(sim.winner, HUMAN):
		return true                                  # the collapse itself took the rival's last node: you stood, you won
	if not sim.last_stand_active:
		return false
	var ring := _ring_nodes()
	if ring.is_empty():                              # a map without rings (a test board): nothing to wait for
		return _holds_node()
	for id in ring:
		if not sim.collapsed.get(id, false):
			return false
	return _holds_node()


func _release_pins() -> void:
	## The quick start is over: the match goes on to its normal end (the Very Last Stand and the 7:00 end are back, the
	## rival is free).
	sim.vls_enabled = true
	sim.match_hard_end = Rules.MATCH_HARD_END


# ---------------------------------------------------------------- endings
func _check_fail() -> String:
	if sim.is_out(HUMAN) and not sim.over:
		return line("try_again")
	var home := _home()
	if home >= 0 and not sim.collapsed.get(home, false) and sim.nodes[home]["owner"] == RIVAL:
		return line("try_again")
	if sim.over:                                     # the match ended off-script
		if sim.winner != "" and sim.allied(sim.winner, HUMAN):
			skipped = skipped or not goals.all_done()
			_complete()
			return ""
		return line("try_again")
	return ""


func _fail(text: String) -> void:
	state = "failed"
	time_scale = 1.0
	fail_line = text
	_bump()
	handler.emit("droop")


func _complete() -> void:
	if state == "complete" or state == "released":
		return
	state = "complete"
	time_scale = 1.0
	_release_pins()
	var kill := _relay_kill_units > 0
	if skipped:
		mark_skipped(lesson_id)
	else:
		mark_complete(lesson_id, kill)
	result = {"id": lesson_id, "title": title_of(lesson_id), "lines": [line("T1.done1"), line("T1.done2")], "time": lesson_t,
			"relay_kill": kill, "kill_units": _relay_kill_units, "scrap": last_scrap, "skipped": skipped,
			"final": all_done(), "graduate": all_done(), "next": -1, "continue": true,
			"won": sim.over and sim.allied(sim.winner, HUMAN)}
	_bump()
	completed.emit(result)


func release() -> void:
	## CONTINUE PLAYING: the coach goes away, the match plays on to its end.
	if state != "complete":
		return
	state = "released"
	_release_pins()
	_bump()


# ================================================================ what the coach shows
func header() -> String:
	return "%s · %s" % [HANDLER_NAME, title_of(lesson_id)]


func chips() -> Array:
	## The goal strip: one chip per chapter, the current one outlined with its progress ("BASICS 2/4", "YOUR TURN 0:32"),
	## ticked when done, the later ones dimmed.
	var cur := current_step()
	var cur_ch := int(cur.get("chapter", 99)) if not cur.is_empty() else 99
	var out := []
	for ch in range(int(L.get("chapters", 0))):
		var all := goals.goals.filter(func(g): return int(g["chapter"]) == ch)
		var done := all.filter(func(g): return g["done"]).size()
		var text := line("T%d.chapter.%d" % [lesson_id, ch])
		if ch == cur_ch:
			if str(cur["id"]) == "free":
				text += " %s" % _mmss(float(free_left()))
			elif all.size() > 1:
				text += " %d/%d" % [done, all.size()]
		out.append({"id": ch, "text": text, "done": done == all.size() and all.size() > 0,
				"skipped": all.any(func(g): return g["skipped"]), "current": ch == cur_ch, "locked": ch > cur_ch})
	return out


func _phase(g: Dictionary) -> String:
	## Which of a step's lines applies now: "main", "prep" (something must come first), "wait" (building / waiting),
	## "watch", "now" (the moment), "send" (the take card's second line).
	match str(g.get("id", "")):
		"take":
			return "send" if sim.time - float(_enter_t.get("take", sim.time)) > float(Rules.QUICK_START["take_send_after"]) \
					and _hmeta.is_empty() else "main"
		"reinforce":
			return "main" if _mine().size() >= 2 else "prep"
		"upgrade":
			var s := _upgrade_site()
			if s >= 0 and sim.nodes[s]["build_kind"] != "":
				return "wait"
			return "pie" if s >= 0 and ui_inspector == s else "main"
		"machinegoon":
			if _mg_site >= 0:
				return "watch"
			var site := _mg_site_id()
			if site >= 0 and sim.nodes[site]["owner"] == HUMAN:
				if sim.nodes[site]["build_kind"] != "":
					return "wait"
				return "pie" if ui_inspector == site else "main"
			return "prep"
		"relay":
			return "now" if catch_prompt() else "wait"
	return "main"


func _hint_line() -> String:
	var g := goals.current()
	if g.is_empty():
		return ""
	var id := str(g["id"])
	var ph := _phase(g)
	var key := "T1.%s" % id if ph == "main" else "T1.%s_%s" % [id, ph]
	if not LINES.has(key):
		key = "T1.%s" % id
	return line(key)


func _refresh_hint() -> void:
	## Rebuild the card's hint only when what it says changes (the number in it is frozen at that moment, so the typed line
	## is never retyped).
	var g := goals.current()
	var k := "%s|%s|%d" % [str(g.get("id", "")), _phase(g) if not g.is_empty() else "", _upgrade_site() if current_id() == "upgrade" else -1]
	if k != _hint_key:
		_hint_key = k
		_hint_text = _fmt(_hint_line())
		_bump()


func card() -> Dictionary:
	## The coach card now: {visible, header, text, dots, dot, button, compact}. GOT IT on the read-only steps.
	if state == "failed":
		return {"visible": true, "header": "%s · %s" % [header(), line("try_again_title")], "text": fail_line,
				"dots": 0, "dot": 0, "button": line("try_again_title")}
	var read := bool(current_step().get("read", false))
	var text := _hint_text if read or _note == "" else _note   # a read-only card is never hidden by a passing line
	return {"visible": state == "running" and text != "", "header": header(), "text": text, "dots": 0, "dot": 0,
			"button": line("got_it") if read and state == "running" else "",
			"compact": catch_prompt()}                # the relay prompt: no button row, the card covers less of the map


func is_tour() -> bool:
	return false


func uses_inspector() -> bool:
	## Does the current step work in the inspector (an action button)? If not, main closes an inspector left open.
	if state != "running":
		return false
	return current_id() in ["machinegoon", "upgrade"] and _phase(current_step()) in ["main", "pie"]


func inspect_request() -> int:
	return -1


func _hand_armed() -> bool:
	## The guided steps show the hand from the start; free play only after idle time or a wrong action.
	if current_id() != "free":
		return true
	return sim.time - _last_order_t >= float(Rules.QUICK_START["idle_hand"]) or sim.time < _wrong_until


func target() -> Dictionary:
	## What the spotlight rings: {nodes: [ids], rects: [keys], lines: [horde ids], open, ...}. `open`: a watch moment - no
	## dim, nothing fogged, at most one soft ring.
	var out := {"nodes": [], "rects": [], "lines": [], "decks": [], "open": false, "radius": 1.0, "monsters": false, "relay_decks": -1}
	if state != "running" or goals == null:
		return out
	if catch_prompt() or str(_push["phase"]) == "out":   # the relay moment: the relay and the line, undimmed
		out["nodes"] = [_relay()]
		out["lines"] = [int(_push["line"])]
		out["relay_decks"] = _relay()
		out["open"] = true
		return out
	var g := goals.current()
	if g.is_empty():
		return out
	match str(g["id"]):
		"machinegoon":
			if _mg_site >= 0:                        # built: watch the probe walk into it
				out["open"] = true
				out["nodes"] = [_mg_site]
				if _any_alive(int(_mg_probe["line"])):
					out["lines"] = [int(_mg_probe["line"])]
				return out
		"ls_intro", "ls_hold":                       # the Last Stand is never fogged over
			out["open"] = true
			return out
		"ls_marks":                                  # the danger marks: the nodes that fall next
			out["open"] = true
			out["nodes"] = sim.last_stand_warn.keys().filter(func(id): return not sim.collapsed.get(id, false)).slice(0, 8)
			return out
		"ls_rings":                                  # the centre ring that stays
			out["open"] = true
			out["nodes"] = sim.last_stand_keep.keys().slice(0, 8)
			return out
		"relay":                                     # waiting for the push: the relay
			out["nodes"] = [_relay()] if _relay() >= 0 else []
			out["relay_decks"] = _relay()
			out["open"] = true
			return out
	if not _hand_armed():
		return out
	var h := _hand(g)
	out["nodes"] = h.get("nodes", [])
	out["rects"] = (h.get("rects", []) as Array).duplicate()
	var gs := _inspector_aware(h.get("gesture", []))
	if not gs.is_empty() and str(gs[0][0]) == "press" and not str(gs[0][1]) in out["rects"]:
		out["rects"].append(str(gs[0][1]))           # the pie slice the hand presses is lit
	out["lines"] = _moving_lines()
	out["open"] = str(g["id"]) == "ls_move"
	return out


func gesture() -> Array:
	## The pointing hand's alternatives, resolved to ids: [[kind, a, b], ...] - main draws the first it can. kinds: tap /
	## double_tap (node id), drag (node id -> node id), press (a rect key).
	if state != "running" or goals == null:
		return []
	if catch_prompt():                               # (the inspector open on the relay: its SWITCH slice, never the hub)
		return [["press", "action:SWITCH", -1]] if ui_inspector == _relay() else [["double_tap", _relay(), -1]]
	var g := goals.current()
	if g.is_empty() or g.get("read", false) or not _hand_armed():
		return []
	var out: Array = _hand(g).get("gesture", [])
	return _inspector_aware(out)


func _inspector_aware(gs: Array) -> Array:
	## 0.23.9's inspector is a pie beside the node with its close hub ON the node centre: while it is open, a hand on the
	## node would close it. So: the step's own action there -> its slice; anything else -> tap the hub to close it first.
	if ui_inspector < 0 or gs.is_empty() or str(gs[0][0]) == "press":
		return gs
	if str(gs[0][0]) == "double_tap" and int(gs[0][1]) == ui_inspector:
		return [["press", "action:UPGRADE", -1]]      # (the double-tap's action in the pie)
	return [["tap", ui_inspector, -1]]                # close the inspector, then the move


func _moving_lines() -> Array:
	## The lines on the move the spotlight keeps lit while it dims (a few: up to 2 of yours, 3 of the rival's).
	var out := []
	var mine := 0
	var theirs := 0
	for h in sim.hordes:
		if h["state"] != "move" or h.get("decoy", false):
			continue
		if h["owner"] == HUMAN and mine < 2:
			mine += 1
			out.append(h["id"])
		elif h["owner"] == RIVAL and theirs < 3:
			theirs += 1
			out.append(h["id"])
	return out


# ---------------------------------------------------------------- the hand providers (per step)
var _hand_cache := {}
var _hand_cache_key := ""


func _hand(g: Dictionary) -> Dictionary:
	## {nodes, rects, gesture} for the step's hint now - worked out once per frame (target() and gesture() both ask), from
	## the cached routes: no route search per frame.
	var key := "%s|%.3f|%d|%d" % [str(g.get("id", "")), sim.time, ui_inspector, version]
	if key != _hand_cache_key:
		_hand_cache_key = key
		_hand_cache = _hand_now(g)
	return _hand_cache


func _hand_now(g: Dictionary) -> Dictionary:
	var retry := assist_retry()
	if not retry.is_empty():                          # after a short send: the hand shows the retry, 100 % from there
		return {"nodes": [int(retry[0]), int(retry[1])], "rects": [], "gesture": [["drag", int(retry[0]), int(retry[1])]]}
	match str(g.get("hand", "")):
		"take":
			var t := _take_target()
			var h := _capture_hand(t)
			if not h.is_empty():
				h["rects"] = ["send_panel"]         # the card talks about the SEND panel
			return h
		"reinforce":
			var p := _reinforce_pair()
			if p.is_empty():
				return _capture_hand(_neutral_target())
			return {"nodes": p, "rects": [], "gesture": [["drag", int(p[0]), int(p[1])]]}
		"upgrade":
			var s := _upgrade_site()
			if s < 0:
				return {}
			if sim.nodes[s]["build_kind"] != "":     # building: the badge's bar, no hand
				return {"nodes": [s], "rects": [], "gesture": []}
			return {"nodes": [s], "rects": [], "gesture": [["double_tap", s, -1]]}
		"machinegoon":
			var site := _mg_site_id()
			if site < 0:
				return _capture_hand(_neutral_target())
			if sim.nodes[site]["owner"] != HUMAN:
				return _capture_hand(site)
			if _mg_site >= 0 or sim.nodes[site]["build_kind"] != "":
				return {"nodes": [site], "rects": [], "gesture": []}
			if ui_inspector == site:                # the inspector's MACHINEGOON card (main._inspector_target: its centre)
				return {"nodes": [site], "rects": ["action:MACHINEGOON"], "gesture": [["press", "action:MACHINEGOON", -1]]}
			return {"nodes": [site], "rects": [], "gesture": [["tap", site, -1]]}
		"free":                                      # after idle time: something to do - a grey node, else a vat
			var t2 := _neutral_target()
			if t2 >= 0 and _best_sender(t2) >= 0:
				return _capture_hand(t2)
			var s2 := _upgrade_site()
			return {"nodes": [s2], "rects": [], "gesture": [["double_tap", s2, -1]]} if s2 >= 0 else {}
		"relay_take":
			var r := _relay()
			if r >= 0 and sim.nodes[r]["owner"] != HUMAN:
				return _capture_hand(r)
			return {}
		"ls_move":
			var mv := _evac_move()
			if mv.is_empty():
				return {}
			return {"nodes": mv, "rects": [], "gesture": [["drag", int(mv[0]), int(mv[1])]]}
	return {}


func _take_target() -> int:
	## The take step's grey node: the map's N1 (a T1 next to your home) while it is still grey, else the nearest one.
	var n1 := _id("N1")
	if n1 >= 0 and sim.nodes[n1]["owner"] == "" and not sim.collapsed.get(n1, false):
		return n1
	return _neutral_target()


func _capture_hand(t: int) -> Dictionary:
	var f := _best_sender(t)
	if t < 0 or f < 0:
		return {}
	return {"nodes": [f, t], "rects": [], "gesture": [["drag", f, t]]}


func _upgrade_site() -> int:
	## The vat the hint points at: one of yours below T2 that can go up now, else the richest one below T2, else your home.
	for id in _mine():                               # a vat going up right now: that one (the card watches its bar)
		if sim.nodes[id]["structure"] == "vat" and sim.nodes[id]["build_kind"] == "vat":
			return id
	var h := _home()                                 # the card says "your home": the home, whenever it can go up
	if h >= 0 and sim.nodes[h]["owner"] == HUMAN and sim.nodes[h]["structure"] == "vat" and int(sim.nodes[h]["tier"]) < 2 			and sim.can_upgrade(h, HUMAN) == "":
		return h
	var best := -1
	var best_ok := false
	for id in _mine():
		var n: Dictionary = sim.nodes[id]
		if n["structure"] != "vat" or int(n["tier"]) >= 2:
			continue
		var ok := sim.can_upgrade(id, HUMAN) == ""
		if best < 0 or (ok and not best_ok) or (ok == best_ok and float(n["units"]) > float(sim.nodes[best]["units"])):
			best = id
			best_ok = ok
	return best if best >= 0 else _home()


func _neutral_target() -> int:
	## The grey node the take hint points at: the nearest vat node nobody owns (by decks from your nodes), the weakest first.
	var best := -1
	var best_key := INF
	for n in sim.nodes:
		if n["owner"] != "" or sim.collapsed.get(n["id"], false) or not Sim.has_vat(n) or n["node_kind"] == "relay" \
				or n["node_kind"] == "junction":
			continue
		var f := _best_sender(n["id"])
		if f < 0:
			continue
		var key := float(route(f, n["id"]).size()) * 1000.0 + float(n["units"])
		if key < best_key:
			best_key = key
			best = n["id"]
	return best


func _best_sender(to: int) -> int:
	## Your richest node (not `to`) with a route to `to`; a node the collapse is about to take last.
	var best := -1
	var best_doomed := true
	for id in _mine():
		if id == to or route(id, to).size() < 2:
			continue
		var doomed := _doomed(id)
		if best < 0 or (best_doomed and not doomed) or (doomed == best_doomed and sim.nodes[id]["units"] > sim.nodes[best]["units"]):
			best = id
			best_doomed = doomed
	return best


func _reinforce_pair() -> Array:
	var mine := _mine()
	if mine.size() < 2:
		return []
	var from := -1
	for id in mine:
		if from < 0 or sim.nodes[id]["units"] > sim.nodes[from]["units"]:
			from = id
	var to := -1
	for id in mine:
		if id == from or route(from, id).size() < 2:
			continue
		if to < 0 or float(sim.nodes[id]["units"]) < float(sim.nodes[to]["units"]):
			to = id
	return [from, to] if to >= 0 else []


func _mg_site_id() -> int:
	## Where the Machinegoon goes: a built one of yours; else the map's M node; else another node of yours that can hold it
	## (not your home if you have a second); else -1 (take a node first).
	if _mg_site >= 0:
		return _mg_site
	var m := _id("M")
	if m >= 0 and not sim.collapsed.get(m, false) and sim.nodes[m]["owner"] != RIVAL:
		if sim.nodes[m]["owner"] == HUMAN:
			return m if "machinegoon" in sim.nodes[m]["buildable"] else -1
		return m
	var mine := _mine()
	var pick := -1
	for id in mine:
		if not "machinegoon" in sim.nodes[id]["buildable"] or sim.nodes[id]["structure"] != "vat":
			continue
		if pick < 0 or (pick == _home() and id != _home()):
			pick = id
	if pick >= 0 and (pick != _home() or mine.size() == 1):
		return pick
	return -1


func _evac_move() -> Array:
	## [from, to]: your doomed node with units, and the safest node to move them to (yours first, a kept-ring node).
	var from := -1
	for id in _mine():
		if _doomed(id) and float(sim.nodes[id]["units"]) >= Rules.SCALE:
			if from < 0 or sim.nodes[id]["units"] > sim.nodes[from]["units"]:
				from = id
	if from < 0:
		return []
	var best := -1
	var best_score := INF
	for n in sim.nodes:
		var id: int = n["id"]
		if id == from or sim.collapsed.get(id, false) or _doomed(id) or n["node_kind"] == "junction":
			continue
		var r := route(from, id)
		if r.size() < 2:
			continue
		var score := float(r.size()) - (6.0 if n["owner"] == HUMAN else 0.0) - (4.0 if sim.last_stand_keep.has(id) else 0.0)
		if n["owner"] == RIVAL:
			score += 3.0
		if score < best_score:
			best_score = score
			best = id
	return [from, best] if best >= 0 else []


const FOLLOW_STEP := 8.0            # metres between the circles along a line (a circle is ~R x 1.35 across)
const FOLLOW_MAX := 5                # circles per line at most
var _deck_pts := {}                  # edge index -> its 3 world points (ends + middle): decks never move in place


func follow_points(tg: Dictionary = {}) -> Array:
	## World points the spotlight must light this frame (Daniele, 0.22.1: "never have the area necessary to look at covered
	## in fog of war"): each followed line from tail to head every FOLLOW_STEP m, the relay's decks. Light only - no
	## ring of their own. A few samples per frame: no route searches, no scene lookups.
	if tg.is_empty():
		tg = target()
	var out := []
	for hid in tg.get("lines", []):
		var h := sim._horde(int(hid))
		if h.is_empty():
			continue
		var head: float = h["s"]
		var len := Sim.chain_length(h)
		var k := clampi(ceili(len / FOLLOW_STEP), 1, FOLLOW_MAX - 1)
		for i in range(k + 1):
			out.append(Sim.sample(h, head - len * float(i) / float(k))[0])
	var edges: Array = (tg.get("decks", []) as Array).duplicate()
	var r := int(tg.get("relay_decks", -1))
	if r >= 0:
		for ei in sim.controlled_edges(r):
			if not ei in edges:
				edges.append(ei)
	for ei in edges:
		if not _deck_pts.has(ei):
			var dl := sim.deck_line(int(ei))
			_deck_pts[ei] = [] if dl.size() < 2 else [dl[0], ((dl[0] as Vector3) + (dl[-1] as Vector3)) / 2.0, dl[-1]]
		out.append_array(_deck_pts[ei])
	out.append_array(goals.follow_points())
	return out


# ROUTE CACHE (audit-tutorial-campaign B1): the hand's drag path and the evacuation pick ask for the same routes every
# frame; they are cached per (from, to) until the board's routes can have changed (_route_stamp).
var _routes := {}                                    # "from:to" -> [route, path points or null]
var _routes_stamp := ""
var _stamp_t := -1.0


func _route_stamp() -> String:
	## What invalidates the cached routes: a collapse, a demolished deck, a relay's state or motion.
	var relays := 0
	for n in sim.nodes:
		if n["relay"] != "":
			relays = relays * 7 + int(n["relay_index"]) * 2 + (1 if n["relay_phase"] == "moving" else 0)
	return "%d|%d|%d" % [sim.collapsed.size(), sim.demolished.size(), relays]


func route(from: int, to: int) -> Array:
	## sim.find_route(from, to), cached for as long as the routes stand.
	if sim.time != _stamp_t:
		_stamp_t = sim.time
		var st := _route_stamp()
		if st != _routes_stamp:
			_routes_stamp = st
			_routes = {}
	var k := "%d:%d" % [from, to]
	if not _routes.has(k):
		_routes[k] = [sim.find_route(from, to), null]
	return _routes[k][0]


func route_points(from: int, to: int) -> PackedVector3Array:
	## The drawn path of route(from, to) (main's drag hand), built once per cached route.
	var r := route(from, to)
	var entry: Array = _routes["%d:%d" % [from, to]]
	if entry[1] == null:
		entry[1] = sim.build_path(r)["pts"] if r.size() >= 2 else PackedVector3Array()
	return entry[1]


func _fmt(text: String) -> String:
	if not "{" in text:
		return text
	var site := _upgrade_site()
	var vals := {
		"secs": str(int(Rules.BUILD_SECONDS)),
		"ls": _mmss(Rules.LAST_STAND_TIME),
		"cost": str(Rules.shown(sim.upgrade_cost(sim.nodes[site]))) if site >= 0 else str(Rules.shown(Rules.VAT_COST[1])),
	}
	var t := _take_target()
	vals["garrison"] = str(Rules.shown(sim.nodes[t]["units"])) if t >= 0 else "0"
	for k in vals:
		text = text.replace("{%s}" % k, str(vals[k]))
	return text


static func _mmss(secs: float) -> String:
	return "%d:%02d" % [int(secs) / 60, int(secs) % 60]
