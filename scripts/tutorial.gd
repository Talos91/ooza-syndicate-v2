class_name TutorialDirector
extends RefCounted
## The interactive tutorial's lesson director (Docs/Game Design/Ooze Syndicate 2.0/01 Rules/TUTORIAL-DESIGN.md
## draft 3, §3 lessons, §6 reveal-as-you-go, §7 progress, §8 shape; TUTORIAL-SCRIPT.md draft 2). A tour of the city
## (L0), eight short lessons and a first match, all played as VEX against EMBER, each a real BRAWL match on a baked
## lesson map: the director STAGES the board (owners, units, tiers),
## SCRIPTS the rival (seat B: plain Sim.send / fire_relay calls - no SeatAI, except the Training AI of the
## first match), walks the player through the lesson's steps and says when a step passed, failed (TRY AGAIN)
## or the lesson is done. Every line the handler says is in LINES (TUTORIAL-SCRIPT.md), every number in them
## comes from Rules at run time, every lesson timing lives in LESSONS.
##
## Pure Sim logic, headless-testable (tests/test_tutorial.gd): no Node, no HUD in here. main.gd drives it:
##   begin(sim, map, seat)        after sim.setup; stages the board (call before the world is built)
##   step(dt)                      every frame, before sim.step(dt * time_scale)
##   on_event(ev)                  every sim.fx_events entry (flings and relay falls live only there)
##   on_action(method, id, args, ok)   every node_action result (the double-tap relay fires included)
##   allow(method, id, args) -> String   "" or the refusal line ("Not yet. Follow the hand.")
##   ui_fraction / ui_inspector / ui_armed   the send fraction, the open inspector's node, the armed dock slot
##   press_button() / skip_step()  the card's GOT IT / SKIP STEP
## and reads back card(), target(), gesture(), time_scale, preview_relay, state, result, reveal_keys().
## Signals: changed (the card / target moved on), completed(result), failed(line).
##
## Progress (static, like ArmyPresets): user://tutorial.cfg [progress] completed / offered / relay_kill /
## version; `saved` false when the browser keeps no storage (the TUTORIAL page says so).

signal changed
signal completed(result: Dictionary)
signal failed(line: String)
signal handler(mood: String)                       # the on-screen handler: "happy" (a step passed) / "droop" (failed)

const HANDLER_NAME := "DR. VESK"                    # the handler on the card (Daniele, 2026-09-27)
const LESSON_COUNT := 9                            # the Graduate vat needs lessons 1..9 (the L0 tour is extra)
const FIRST_ID := 0                                # L0 THE CITY, the tour
const TOTAL_LESSONS := 10                          # 0..9 (the TUTORIAL n/10 count)
const PLAYER_FACTION := "vex"                      # Daniele (0.19.3): VEX for the whole tutorial
const RIVAL_FACTION := "ember"                     # ... and the rival is always EMBER
const L9_NEUTRALS := {1: 10, 2: 15, 3: 25, 4: 40}  # the first match's neutral garrisons (shown), capped there
const PROGRESS_VERSION := 1
const HUMAN := "A"
const RIVAL := "B"
const NOTE_SECONDS := 3.0            # a transient handler line (a refusal, a miss) stays this long on the card
const INTERLUDE := 1.8               # a step's "done" line shows this long before the next step starts
const IDLE_HINT := 20.0              # seconds without an order before the idle hint
const PUSH_SHARE := 0.7              # L9: the scripted push commits at least this share of B's units
const PUSH_KILL := 0.5               # L9: a relay kill = at least this share of the push lost to the fall
const PUSH_LATEST := 150.0           # L9: 2:30 - the push goes even if A does not lead by then
const HALF_SPEED := 0.5
const MIN_STEP := 1.5                # a doing-step shows at least this long, even when it is already done (its line is read)

# ---------------------------------------------------------------- the handler's lines (TUTORIAL-SCRIPT.md draft 2)
# One table, so per-faction voices or translations can replace it without touching the steps. Every line uses the
# script's standard vocabulary (node, your home, neutral node, the rival, units, line, deck, vat, tier, cap, badge,
# SEND panel, inspector, relay, fire, drop, the structure names, skill / dock, Last Stand, danger mark). Placeholders
# ({cost}, {secs}, {garrison}, {cap}, {ls}, {vls}, {hops}, {ult}, {skill1}, {skill2}, {ult_name}, {n}) are filled
# from Rules and the live board by _fmt().
const LINES := {
	"got_it": "GOT IT", "next_step": "NEXT", "skip_step": "SKIP STEP", "restart": "RESTART", "exit": "EXIT",
	"skip_tutorial": "SKIP TUTORIAL",
	"not_yet": "Not yet. Follow the hand.",
	"try_again_title": "TRY AGAIN", "try_again": "That went wrong. Same board, fresh units.",
	"idle_hint": "Still with me? Do what the hand shows.",
	"paused_lessons": "LESSONS",
	"no_storage": "Progress isn't saved on this browser.",
	# L0 THE CITY - what's what
	"L0.title": "THE CITY",
	"L0.hello": "I'm Dr. Vesk, your handler. Quick tour of the city first, then we work.",
	"L0.node": "This is a node. You win by taking nodes.",
	"L0.home": "This one is your home. Your colour means it's yours.",
	"L0.vat": "The tank on it is a vat. It breeds units, up to its cap.",
	"L0.badge": "The badge shows the units on a node and its tier.",
	"L0.neutral": "Grey nodes are neutral. Their badge shows what defends them.",
	"L0.rival": "That colour is the rival - EMBER. Their home is over there.",
	"L0.deck": "Nodes are joined by decks. Units walk the decks.",
	"L0.relay": "This is a relay. It moves a deck - anything on it drops into the void.",
	"L0.send": "The SEND panel sets how much of a node goes when you send.",
	"L0.inspector": "Tap a node and its inspector opens: what it makes, what it can build.",
	"L0.top": "Up top: your strength, the clock and the rival's strength.",
	"L0.dock": "Down here, the dock: your skills. We get to those later.",
	"L0.go": "That's the city. Let's send some units.",
	# L1 SEND
	"L1.title": "SEND",
	"L1.drag": "Drag from your home to the node above it.",
	"L1.label": "The label says what happens: TAKE, how many units, how many seconds.",
	"L1.percent": "You don't have to send everything. Tap 25 % on the SEND panel.",
	"L1.send25": "A quarter of your home is enough for the node below. Send it.",
	"L1.reinforce": "Drag between two of your nodes to move units to the one that needs them.",
	"L1.done1": "Drag from your node to send units.",
	"L1.done2": "The SEND panel sets how much goes.",
	# L2 VATS AND THE MACHINEGOON
	"L2.title": "VATS",
	"L2.inspect": "Tap your home. The inspector shows how fast its vat breeds and its cap.",
	"L2.upgrade": "Double-tap your home to upgrade its vat to T2. Costs {cost} units.",
	"L2.build": "Building takes {secs} s. Watch the bar on the badge.",
	"L2.t3": "A higher tier breeds faster and holds more. Take it to T3 - the highest you can build.",
	"L2.machinegoon": "A node can hold a Machinegoon instead of a vat. Build one on this node.",
	"L2.watch": "A Machinegoon shoots rival lines on its decks, but breeds nothing. Watch.",
	"L2.mg_upgrade": "A Machinegoon has tiers too. Upgrade it.",
	"L2.t4": "That big node holds a T4 vat. Nobody builds T4 - you have to take it.",
	"L2.done1": "Double-tap a node to upgrade its vat, up to T3.",
	"L2.done2": "A Machinegoon swaps breeding for firepower.",
	# L3 THE RIVAL
	"L3.title": "THE RIVAL",
	"L3.neutral": "A neutral node defends with its badge count: {garrison}. Send more units than that.",
	"L3.too_small": "Not enough units. Tap 75 % and send again.",
	"L3.trade": "Each unit that lands kills one defender. Bring more than they have.",
	"L3.defend": "The rival is sending a line at your node. Reinforce it before they land.",
	"L3.held": "Held. Your turn.",
	"L3.attack": "Take the rival's node. A vat you capture drops one tier.",
	"L3.alive": "The rival is out when it has no nodes and no lines left.",
	"L3.done1": "Send more units than a node holds to take it.",
	"L3.done2": "Reinforce before the rival lands.",
	# L4 RELAYS
	"L4.title": "RELAYS",
	"L4.inspect": "Tap the relay. The preview shows where its deck will go.",
	"L4.fire": "Double-tap the relay to fire it. The SWITCH button in the inspector works too.",
	"L4.warning": "Firing gives one second of warning. Then the deck moves - anything on it drops.",
	# not in TUTORIAL-SCRIPT draft 2 (for Daniele's review): the prompt step before the line reaches the deck
	"L4.incoming": "A rival line is coming. Wait until it's on the relay's deck.",
	"L4.prompt": "Their line is on the deck. Fire the relay now!",
	"L4.miss": "Too late - they got across. Here comes another line.",
	"L4.practice": "Timing takes practice. You'll get more chances.",
	"L4.waterfall": "Their vat keeps sending. The rest of the line walks off the edge.",
	"L4.done1": "Fire a relay while the rival's line is on its deck.",
	"L4.done2": "One second of warning, then the drop.",
	# L5 RELAY KINDS
	"L5.title": "RELAY KINDS",
	"L5.retract": "A retract relay pulls its deck in. Fire it while their line is on it.",
	"L5.switch": "A switch relay swaps one deck for another. Fire it while they're on the deck that goes.",
	"L5.remote": "A remote relay moves decks far away - follow the lit wire. Fire it.",
	"L5.own": "Your own lines drop too. Check the preview before you fire.",
	"L5.done1": "Every relay kind drops what's on the deck it moves.",
	"L5.done2": "Read the preview first.",
	# L6 RELAY STRUCTURES
	"L6.title": "RELAY STRUCTURES",
	"L6.inspect": "A relay node holds one structure: Laser tower, Forge or Monster hub. Tap this relay.",
	"L6.laser": "Build the LASER TOWER.",
	"L6.burst": "The Laser tower fires bursts at rival lines in range, then recharges.",
	"L6.forge": "Build a FORGE on the next relay: your units hit harder and your nodes hold better.",
	"L6.hub": "Build a MONSTER HUB on the last relay. You can have one.",
	# 0.19.2's flow (TUTORIAL-SCRIPT L6 "send", trimmed to <= 90 characters)
	"L6.send": "Tap the monster on its hub, then a node up to {hops} decks away. It kicks lines off decks.",
	"L6.take": "The monster takes the node at the end. Only a drop stops it.",
	"L6.fell": "Monsters drop like everything else. Choose the route well.",
	"L6.cooldown": "The hub needs time to grow the next monster. Make each one count.",
	"L6.done1": "One structure per relay: Laser tower, Forge or Monster hub.",
	"L6.done2": "A monster clears its route and takes the node at the end.",
	# L7 LAST STAND
	"L7.title": "LAST STAND",
	"L7.reveal": "It's {ls}: the Last Stand. Nodes fall ring by ring. Watch the danger marks.",
	"L7.evacuate": "Your ring falls first. Move your units to the centre ring.",
	"L7.lost": "Nobody made it out. Move sooner next time.",
	"L7.vls": "It's {vls}: the Very Last Stand. The last nodes fall one by one.",
	"L7.hold": "Whoever holds the last node wins. Be on it.",
	"L7.done1": "Leave a ring before it falls.",
	"L7.done2": "Hold the last node to win.",
	# L8 SKILLS
	"L8.title": "SKILLS",
	"L8.surge": "The dock holds three skills. Tap {skill1}, then one of your lines.",
	"L8.demolish": "{skill2} is a map skill: it drops a deck a moment later. Use it on a busy deck.",
	"L8.ultimate": "{ult_name} is VEX's ultimate. It charges in about {ult} minutes - this one's ready. Use it.",
	"L8.armies": "You choose your skills for each faction in ARMIES, on the main menu.",
	"L8.done1": "Tap a skill in the dock, then its target.",
	"L8.done2": "Choose your skills in ARMIES.",
	# L9 FIRST MATCH
	"L9.title": "FIRST MATCH",
	"L9.start": "A real match now. Take neutral nodes, grow your vats, and hold the relay in the middle.",
	"L9.relay_taken": "The relay is yours. Watch for rival lines on its decks.",
	"L9.push": "Their whole army is on the relay deck. FIRE THE RELAY!",
	"L9.relay_kill": "Straight into the void. That's how VEX works.",
	"L9.miss": "They got across. Finish the match the long way.",
	"L9.win": "Well played, commander. The city is yours.",
	"L9.lose": "They took it this time. The next one's yours.",
	# completion screens
	"lesson_complete": "LESSON COMPLETE", "next": "NEXT LESSON", "replay": "REPLAY", "lessons": "LESSONS",
	"final_title": "TRAINING COMPLETE",
	"final_relay_kill": "RELAY KILL - {n} units into the void.",
	"final_reward": "GRADUATE VAT UNLOCKED",
	"final_reward_line": "Ivory and brass, for commanders who finished training. Put it on in ARMIES.",
	"final_locked": "Finish every lesson to unlock the Graduate vat.",
	"final_armies": "ARMIES", "locked_cosmetic": "Finish the tutorial",
	"final_play": "PLAY YOUR FIRST MATCH", "final_menu": "MAIN MENU",
	# the TUTORIAL page
	"page_title": "TRAINING",
	"page_sub": "A tour of the city, eight short lessons and a first match. Replay any of them.",
	"continue": "CONTINUE", "back": "BACK",
	"L0.goal": "Learn what's what", "L1.goal": "Send units", "L2.goal": "Grow vats, build a Machinegoon",
	"L3.goal": "Take nodes, beat the rival", "L4.goal": "Fire a relay", "L5.goal": "Retract, switch, remote",
	"L6.goal": "Laser tower, Forge, monster", "L7.goal": "Survive the Last Stand", "L8.goal": "Use your skills",
	"L9.goal": "Win your first match",
}

# ---------------------------------------------------------------- reveal as you go (design §6)
# What a lesson has not reached yet is not on screen (Hud.reveal). Keys: map / badges / drag / clock (always, L1),
# send_panel, upgrade (the inspector's UPGRADE line, "Double-tap: N units", the double-tap), machinegoon (MACHINEGOON
# / VAT actions), rival_counts, strength (your total, RIVALS, the strength bar), notices (toasts), relay (the
# double-tap fire, SWITCH, the relay line and outcome preview, the badge's relay state, ready glow and cue),
# relay_build (LASER / FORGE / MONSTER HUB), forge_readout, monster (LAUNCH, the reach ring, the hub line),
# status_line, danger (the floating Last Stand symbols), dock, and - only in L9, never in a 1v1 lesson - halos
# and eject (the team parts).
const REVEAL_BASE := ["map", "badges", "drag", "clock", "topbar"]   # topbar: 0.19.2's centred bar (the clock alone early on)
const ALL_KEYS := ["map", "badges", "drag", "clock", "send_panel", "upgrade", "machinegoon", "rival_counts", "strength",
		"notices", "relay", "relay_build", "forge_readout", "monster", "monster_icon", "status_line", "danger", "dock", "halos", "eject",
		"out_panel"]                                   # (out_panel: the YOU'RE OUT panel - only in the tour and the first match)

# ---------------------------------------------------------------- the lessons (design §3)
# stage: [name, owner, units, (tier)] - units in SHOWN numbers, or "garrison" (the tier's neutral garrison,
# Rules.NEUTRAL_UNITS), or "cap" (Rules.CAPS). Every other node keeps the map's own start (neutrals at their
# real garrison). protect: nodes the player may not attack in this lesson (their loss would wreck the staging).
# A step: key (its line is LINES["L<n>.<key>"]), target {nodes, rects, lines}, gesture (alternatives, the first
# main can draw wins: [kind, from, to]; kinds tap / double_tap / drag / press), reveal (keys it adds), pass /
# fail / enter (ops, see _check_pass / _check_fail / _enter), read_only (a GOT IT card), budget (seconds the
# headless test allows), catch (a scripted rival line the player drops with a relay, see _tick_catch).
const LESSONS := [
	{"id": 0, "key": "L0", "map": "T-06-pivot", "abilities": true, "vls": false, "tour": true,
		"loadout": {"active": "surge", "map": "demolish"},   # the dock shows what L8 will teach
		"stage": [["H", "A", 20], ["BH", "B", 20]], "protect": ["BH"],
		"reveal": [],
		"steps": [
			{"key": "hello", "target": {"rects": ["handler"]}, "read_only": true},
			{"key": "node", "target": {"nodes": ["A2"]}, "gesture": [["tap", "A2"]], "read_only": true},
			{"key": "home", "target": {"nodes": ["H"]}, "gesture": [["tap", "H"]], "read_only": true},
			{"key": "vat", "target": {"nodes": ["H"], "radius": 0.55}, "gesture": [["tap", "H"]], "read_only": true},
			{"key": "badge", "target": {"rects": ["badge:H"]}, "gesture": [["press", "badge:H"]], "read_only": true},
			{"key": "neutral", "target": {"rects": ["badge:T"]}, "gesture": [["press", "badge:T"]], "read_only": true},
			{"key": "rival", "target": {"nodes": ["BH"]}, "gesture": [["tap", "BH"]], "read_only": true},
			{"key": "deck", "target": {"decks": [["H", "U"]]}, "read_only": true},
			{"key": "relay", "target": {"nodes": ["R"]}, "gesture": [["tap", "R"]], "read_only": true},
			{"key": "send", "target": {"rects": ["send_panel"]}, "gesture": [["press", "send:0.5"]], "read_only": true},
			{"key": "inspector", "inspect": "H", "target": {"rects": ["inspector"]}, "read_only": true},
			{"key": "top", "target": {"rects": ["top_bar"]}, "gesture": [["press", "top_bar"]], "read_only": true},
			{"key": "dock", "target": {"rects": ["dock"]}, "gesture": [["press", "dock"]], "read_only": true},
			{"key": "go", "read_only": true},
		],
		"done": []},
	{"id": 1, "key": "L1", "map": "T-03-first-batch", "abilities": false, "vls": false, "fraction": 1.0,
		"stage": [["H", "A", 30], ["BH", "B", 30]], "protect": ["BH"],
		"reveal": ["map", "badges", "drag", "clock"],
		"steps": [
			{"key": "drag", "target": {"nodes": ["H", "N1"]}, "gesture": [["drag", "H", "N1"]], "pass": ["send", "H", "N1"], "budget": 30.0},
			{"key": "label", "target": {"nodes": ["N1"], "label": ["H", "N1"]}, "pass": ["owner", "N1", "A"], "budget": 30.0},
			{"key": "percent", "reveal": ["send_panel"], "enter": ["topup", "H", "N2", 0.25], "target": {"rects": ["send:0.25"]},
				"gesture": [["press", "send:0.25"]], "pass": ["fraction", 0.25], "budget": 10.0},
			{"key": "send25", "target": {"nodes": ["H", "N2"]}, "gesture": [["drag", "H", "N2"]], "pass": ["owner", "N2", "A"], "budget": 30.0},
			{"key": "reinforce", "target": {"nodes": ["N1", "H"]}, "gesture": [["drag", "N1", "H"]], "pass": ["send_own"], "budget": 15.0},
		],
		"done": ["L1.done1", "L1.done2"]},
	{"id": 2, "key": "L2", "map": "T-04-vat-row", "abilities": false, "vls": false,
		"stage": [["H", "A", 30], ["N1", "A", 45], ["N2", "A", 15], ["BH", "B", 30], ["B1", "B", 8]], "protect": ["BH", "B1", "B2"],
		"reveal": ["upgrade", "machinegoon"],
		"steps": [
			{"key": "inspect", "target": {"nodes": ["H"]}, "gesture": [["tap", "H"]], "pass": ["inspect", "H"], "budget": 10.0},
			{"key": "upgrade", "target": {"nodes": ["H"], "rects": ["action:UPGRADE"]}, "gesture": [["double_tap", "H"]],
				"pass": ["build_started", "H"], "budget": 10.0},
			{"key": "build", "target": {"nodes": ["H"]}, "pass": ["tier", "H", 2], "budget": 15.0},
			{"key": "t3", "target": {"nodes": ["H"]}, "gesture": [["double_tap", "H"]], "pass": ["tier", "H", 3], "budget": 40.0},
			{"key": "machinegoon", "target": {"nodes": ["N1"], "rects": ["action:MACHINEGOON"]},
				"gesture": [["press", "action:MACHINEGOON"], ["tap", "N1"]], "pass": ["built", "N1", "machinegoon"], "budget": 20.0},
			{"key": "watch", "enter": ["b_send", "B1", "N1", 8], "target": {"nodes": ["N1"], "lines": "B"},
				"pass": ["custom", "line_spent", "N1"], "fail": ["lost", "N1"], "budget": 30.0},
			{"key": "mg_upgrade", "target": {"nodes": ["N1"], "rects": ["action:UPGRADE"]},
				"gesture": [["press", "action:UPGRADE"], ["double_tap", "N1"]], "pass": ["build_started", "N1"], "budget": 10.0},
			{"key": "t4", "target": {"nodes": ["SP"]}, "read_only": true},
		],
		"done": ["L2.done1", "L2.done2"]},
	{"id": 3, "key": "L3", "map": "T-05-border-run", "abilities": false, "vls": false,
		"stage": [["H", "A", 25], ["N1", "A", 25], ["B1", "B", 5], ["BH", "B", 30]], "protect": ["BH"],
		"reveal": ["rival_counts", "strength", "notices"],
		"steps": [
			{"key": "neutral", "target": {"nodes": ["N2"]}, "gesture": [["drag", "H", "N2"]], "pass": ["owner", "N2", "A"],
				"hint": ["too_small", "N2", "L3.too_small"], "budget": 60.0},
			{"key": "trade", "read_only": true},
			{"key": "defend", "enter": ["b_attack", "B1", "N1", 6], "target": {"nodes": ["N1"], "lines": "B"},
				"gesture": [["drag", "H", "N1"]], "pass": ["custom", "line_spent", "N1"], "fail": ["lost", "N1"],
				"done_line": "L3.held", "budget": 40.0},
			{"key": "attack", "target": {"nodes": ["B1"]}, "gesture": [["drag", "N1", "B1"]], "pass": ["owner", "B1", "A"], "budget": 60.0},
			{"key": "alive", "read_only": true},
		],
		"done": ["L3.done1", "L3.done2"]},
	{"id": 4, "key": "L4", "map": "T-06-pivot", "abilities": false, "vls": false,
		"stage": [["H", "A", 30], ["A2", "A", 20], ["R", "A", 40], ["B2", "B", 60], ["BH", "B", 30]], "protect": ["BH", "B2"],
		"reveal": ["relay"], "preview": "R",
		"steps": [
			{"key": "inspect", "target": {"nodes": ["R"]}, "gesture": [["tap", "R"]], "pass": ["inspect", "R"], "budget": 10.0},
			{"key": "fire", "target": {"nodes": ["R"], "rects": ["action:SWITCH"]}, "gesture": [["double_tap", "R"]],
				"pass": ["fired", "R"], "budget": 10.0},
			{"key": "warning", "target": {"nodes": ["R"]}, "read_only": true, "restore": "R"},
			{"key": "prompt", "target": {"nodes": ["R"], "lines": "B"}, "before": "L4.incoming",
				"catch": {"relay": "R", "from": "B2", "to": "R", "shown": 20, "kind": "fling", "min": 5, "tries": 3, "half": true,
					"miss": "L4.miss", "practice": "L4.practice"}, "budget": 90.0},
			{"key": "waterfall", "target": {"nodes": ["R"]}, "pass": ["fall_or_time", 4.0], "min": 3.0, "budget": 6.0},
		],
		"done": ["L4.done1", "L4.done2"]},
	{"id": 5, "key": "L5", "map": "T-07-switchyard", "abilities": false, "vls": false,
		"stage": [["H", "A", 30], ["RT", "A", 40], ["SW", "A", 40], ["RC", "A", 40], ["T1", "B", 30], ["S1", "B", 30], ["BH", "B", 30]],
		"protect": ["BH", "S1", "T1"],
		"reveal": [],
		"steps": [
			{"key": "retract", "target": {"nodes": ["RT"], "decks": [["RT", "T1"]]},
				"catch": {"relay": "RT", "from": "T1", "to": "RT", "shown": 12, "kind": "fall", "min": 1, "tries": 3, "half": false}, "budget": 60.0},
			{"key": "switch", "target": {"nodes": ["SW"], "decks": [["SW", "S1"]]},
				"catch": {"relay": "SW", "from": "S1", "to": "SW", "shown": 12, "kind": "fall", "min": 1, "tries": 3, "half": false}, "budget": 60.0},
			{"key": "remote", "target": {"nodes": ["RC"], "decks": [["S1", "BH"]]},
				"catch": {"relay": "RC", "from": "BH", "to": "S1", "shown": 12, "kind": "fall", "min": 1, "tries": 3, "half": false}, "budget": 60.0},
			{"key": "own", "target": {"nodes": ["SW"]}, "read_only": true},
		],
		"done": ["L5.done1", "L5.done2"]},
	{"id": 6, "key": "L6", "map": "T-08-relay-works", "abilities": false, "vls": false,
		"stage": [["H", "A", 30], ["R1", "A", 60], ["R2", "A", 30], ["R3", "A", 60], ["L1", "B", 20], ["F1", "B", 20],
				["M1", "B", 15], ["M2", "B", 30], ["BH", "B", 30]], "protect": ["BH", "L1", "F1", "M1"],
		"reveal": ["relay_build", "forge_readout", "monster", "monster_icon"],
		"steps": [
			{"key": "inspect", "target": {"nodes": ["R1"]}, "gesture": [["tap", "R1"]], "pass": ["inspect", "R1"], "budget": 10.0},
			{"key": "laser", "target": {"nodes": ["R1"], "rects": ["action:LASER"]}, "gesture": [["press", "action:LASER"], ["tap", "R1"]],
				"pass": ["built", "R1", "laser"], "budget": 20.0},
			{"key": "burst", "enter": ["b_send", "L1", "R1", 10], "target": {"nodes": ["R1"], "lines": "B"},
				"pass": ["custom", "burst_spent", "R1"], "fail": ["lost", "R1"], "budget": 30.0},
			{"key": "forge", "target": {"nodes": ["R2"], "rects": ["action:FORGE"]}, "gesture": [["press", "action:FORGE"], ["tap", "R2"]],
				"pass": ["built", "R2", "forge"], "budget": 20.0},
			{"key": "hub", "target": {"nodes": ["R3"], "rects": ["action:MONSTER HUB"]},
				"gesture": [["press", "action:MONSTER HUB"], ["tap", "R3"]], "pass": ["built", "R3", "monster_hub"], "budget": 20.0},
			{"key": "send", "enter": ["charge_hub", "R3"], "target": {"nodes": ["R3", "M2"], "rects": ["monster_icon:R3"]},
				"gesture": [["monster", "R3", "M2"]], "pass": ["launched", "M2"], "only_launch": "M2", "budget": 10.0},
			{"key": "take", "enter": ["b_send", "M2", "R3", 8], "target": {"nodes": ["M2"], "lines": "B"},
				"pass": ["custom", "monster_done", "M2"], "budget": 45.0},
			{"key": "cooldown", "target": {"nodes": ["R3"]}, "read_only": true},
		],
		"done": ["L6.done1", "L6.done2"]},
	# the Last Stand starts with the lesson (the clock jumps to {ls}, as the first line says); its first wave's
	# countdown holds while that line is on screen ("hold_ls": the reveal step), then the ring falls
	{"id": 7, "key": "L7", "map": "T-09-collapse-ring", "abilities": false, "vls": false, "last_stand_at": 0.0, "hold_ls": "reveal",
		# the design's 4 s Very Last Stand gap leaves no time to move a garrison off a warned node (a 100-unit
		# garrison needs ~10 s just to leave its door): the lesson uses the Last Stand's own warning + drop gap
		"vls_gap": "warning+gap",
		"stage": [["H", "A", 30], ["A1", "A", 30], ["A2", "A", 30], ["BH", "B", 8], ["B1", "B", 8], ["B2", "B", 8]],
		"protect_rival_until": "hold",
		"reveal": ["status_line", "danger"],
		"steps": [
			{"key": "reveal", "read_only": true},
			{"key": "evacuate", "target": {"nodes": ["I1", "I2"]}, "gesture": [["drag", "H", "I1"]],
				"pass": ["custom", "ring_down"], "fail": ["custom", "ring_lost"], "budget": 60.0},
			{"key": "vls", "enter": ["vls"], "target": {"nodes": ["I1", "I2", "I3"]}, "read_only": true, "pass": ["won"]},
			{"key": "hold", "target": {"nodes": ["I1", "I2", "I3"]}, "gesture": [["vls_move"]], "pass": ["won"], "fail": ["lost_match"], "budget": 60.0},
		],
		"done": ["L7.done1", "L7.done2"]},
	{"id": 8, "key": "L8", "map": "T-10-long-decks", "abilities": true, "vls": false,
		"loadout": {"active": "surge", "map": "demolish"},
		"stage": [["H", "A", 30], ["A1", "A", 20], ["A2", "A", 20], ["BH", "B", 30], ["B1", "B", 20], ["B2", "B", 20]],
		"protect": ["BH", "B1", "B2"],
		"reveal": ["dock"],
		"steps": [
			{"key": "surge", "keep_a_line": true, "target": {"rects": ["dock:0"], "lines": "A"},
				"gesture": [["tap_line", "A"], ["press", "dock:0"]], "armed": 0, "pass": ["cast", "active"], "budget": 30.0},
			{"key": "demolish", "b_stream": ["BH", "C", 10], "target": {"rects": ["dock:1"], "lines": "B"},
				"gesture": [["tap_deck", "B"], ["press", "dock:1"]], "armed": 1, "pass": ["custom", "demolish_busy"], "budget": 60.0},
			{"key": "ultimate", "enter": ["fill_ultimate"], "keep_a_line": true, "target": {"rects": ["dock:2"]},
				"gesture": [["tap_ult", "A"], ["press", "dock:2"]], "armed": 2, "pass": ["cast", "ultimate"], "budget": 60.0},
			{"key": "armies", "read_only": true},
		],
		"done": ["L8.done1", "L8.done2"]},
	{"id": 9, "key": "L9", "map": "T-02-turning-tide", "abilities": true, "vls": true, "match": true, "ai": "Training",
		"loadout": {"active": "surge", "map": "demolish"},   # the skills L8 just taught (VEX's ultimate: Rewire)
		"stage": [], "neutrals": L9_NEUTRALS, "reveal": [],
		"steps": [{"key": "start", "read_only": true}],
		"done": []},
]


# ================================================================ progress (static, user://tutorial.cfg)
static var path := "user://tutorial.cfg"             # tests point this elsewhere
static var map_dir := "res://maps4"                  # tests may point this at a checkout with the lesson maps
static var completed_ids: Array = []
static var offered := false
static var relay_kill_done := false
static var saved := true                             # false: the last save failed (no storage)
static var _loaded := false


static func load_progress() -> void:
	_loaded = true
	completed_ids = []
	offered = false
	relay_kill_done = false
	var cf := ConfigFile.new()
	if cf.load(path) != OK:                          # none yet, or no storage at all (private browsing)
		return
	for v in cf.get_value("progress", "completed", []):
		var id := int(v)
		if id >= FIRST_ID and id <= LESSON_COUNT and not id in completed_ids:
			completed_ids.append(id)
	completed_ids.sort()
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
	cf.set_value("progress", "completed", completed_ids.duplicate())
	cf.set_value("progress", "offered", offered)
	cf.set_value("progress", "relay_kill", relay_kill_done)
	cf.set_value("progress", "version", PROGRESS_VERSION)
	saved = cf.save(path) == OK
	return saved


static var last_scrap := 0                           # TUTORIAL + PROGRESSION: what the last mark_complete paid (0 = nothing)


static func mark_complete(id: int, relay_kill := false) -> bool:
	_ensure()
	if id >= FIRST_ID and id <= LESSON_COUNT and not id in completed_ids:
		completed_ids.append(id)
		completed_ids.sort()
	offered = true
	relay_kill_done = relay_kill_done or relay_kill
	# TUTORIAL + PROGRESSION (Daniele, 2026-09-27): lessons 1-9 pay SCRAP on their first completion (enough for a 3rd
	# skill by the end); the tour pays nothing. The Graduate vat is recorded in Progression once all are done.
	last_scrap = 0
	if id >= 1 and id <= LESSON_COUNT:                   # 1..9: FIRST_ID is the tour (0), which pays nothing
		var amount: int = Rules.PROGRESSION["tutorial_lesson"]
		if Progression.grant("tutorial:%d" % id, amount):
			last_scrap = amount
	if all_done():
		Progression.unlock("vat:graduate", "tutorial")
	return save_progress()


static func mark_offered() -> bool:
	_ensure()
	offered = true
	return save_progress()


static func is_done(id: int) -> bool:
	_ensure()
	return id in completed_ids


static func done_count() -> int:
	_ensure()
	return completed_ids.size()


static func all_done() -> bool:
	## Lessons 1-9 complete (the L0 tour is not needed): the Graduate vat unlocks (ArmyPresets.is_unlocked).
	_ensure()
	for i in range(1, LESSON_COUNT + 1):
		if not i in completed_ids:
			return false
	return true


static func first_unfinished() -> int:
	## CONTINUE: the first lesson not done yet, the tour included (L1 when every one is).
	_ensure()
	for i in range(FIRST_ID, LESSON_COUNT + 1):
		if not i in completed_ids:
			return i
	return 1


static func first_launch_due(user_args: PackedStringArray, net_busy: bool) -> bool:
	## §7: with no `offered` key the game opens straight into the tour (L0), then L1. Never for a launch with a map, scenario, stage,
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


static func lesson(id: int) -> Dictionary:
	for l in LESSONS:
		if int(l["id"]) == id:
			return l
	return {}


static func map_path_for(id: int) -> String:
	return "%s/%s.json" % [map_dir, str(lesson(id).get("map", ""))]


static func line(key: String) -> String:
	return str(LINES.get(key, key))


static func title_of(id: int) -> String:
	return line("L%d.title" % id)


static func lesson_rows() -> Array:
	## The TUTORIAL page's rows: {id, title, goal, done}.
	_ensure()
	var out := []
	for l in LESSONS:
		var id := int(l["id"])
		out.append({"id": id, "title": title_of(id), "goal": line("L%d.goal" % id), "done": id in completed_ids})
	return out


static func reveal_for(id: int, step_index := 0) -> Array:
	## Every HUD key a lesson shows at that step: all of the lessons before it, then this lesson's own keys up
	## to the step (a lesson replayed out of order reveals everything up to it, §7). The tour (L0) and the first
	## match show everything; the tour is not part of the chain, so L1 hides it all again.
	if id == FIRST_ID or id == LESSON_COUNT:
		return ALL_KEYS.duplicate()
	var keys := REVEAL_BASE.duplicate()
	for l in LESSONS:
		var lid := int(l["id"])
		if lid == FIRST_ID:
			continue
		if lid > id:
			break
		for k in l.get("reveal", []):
			if not k in keys:
				keys.append(k)
		var steps: Array = l["steps"]
		for i in range(steps.size()):
			if lid == id and i > step_index:
				break
			for k in (steps[i] as Dictionary).get("reveal", []):
				if not k in keys:
					keys.append(k)
	return keys


# ================================================================ one lesson run
var lesson_id := 1
var L: Dictionary                                    # the lesson's row in LESSONS
var sim: Sim
var map: Dictionary
var names := {}                                      # lesson name -> node id (the map's lessonNames)
var first_launch := false                            # the forced first run: the card carries SKIP TUTORIAL
var faction := PLAYER_FACTION                        # the player's faction (VEX in the tutorial)
var state := "running"                               # running / interlude / failed / complete
var step_i := 0
var step_t := 0.0
var lesson_t := 0.0
var version := 0                                     # bumped whenever card() / target() / gesture() change
var time_scale := 1.0                                # main steps the Sim at dt x this (half speed at a relay prompt)
var preview_relay := -1                              # main keeps the relay-outcome preview up for this relay
var result := {}                                     # completed(): {id, title, lines, time, relay_kill, final, graduate}
var fail_line := ""
var ui_fraction := 0.5                               # main: the send panel's fraction
var ui_inspector := -1                               # main: the node the inspector is open on (-1: none)
var ui_armed := -1                                   # main: the armed dock slot (-1: none)
var ui_monster_from := -1                            # main: the hub whose launch is armed (the monster icon / LAUNCH)
var ai: SeatAI                                       # L9 only: the Training rival

var _log: Array = []                                 # sim.events (and fx events from on_event) since the lesson began
var _ev_cursor := 0
var _step_started := 0.0                             # sim time the current step began
var _note := ""
var _note_t := 0.0
var _interlude_t := 0.0
var _interlude_next := ""                            # "advance" / "complete"
var _last_order_t := 0.0
var _idle_shown := false
var _catch := {}                                     # the current catch step's state (see _tick_catch)
var _hint_seen := {}                                 # horde ids already judged by a "too_small" hint
var _tracked := []                                   # horde ids of the step's scripted rival line(s)
var _burst_seen := false
var _demolish_tries := 0
var _ls_started := false
var _ls_strength := 0.0
var _ls_falls := 0.0
var _match := {}                                     # L9: {phase, muster, push, falls0, push_units, t, relay_taken}


func _init(id := 1) -> void:
	lesson_id = clampi(id, FIRST_ID, LESSON_COUNT)
	L = lesson(lesson_id)


func loadout_for(_player_faction := "", _preset := {}) -> Dictionary:
	## The skill loadout the lesson plays with: L8's and L9's fixed Surge + Demolish (+ VEX's Rewire), else VEX's
	## default. Never the player's ARMIES preset: the whole tutorial is VEX (Daniele, 0.19.3).
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
	if not names.has("H") and sim.homes.has(HUMAN):  # T-02 (the first match) has no lesson names: its homes
		names["H"] = int(sim.homes[HUMAN])            # and first relay stand in
	if not names.has("BH") and sim.homes.has(RIVAL):
		names["BH"] = int(sim.homes[RIVAL])
	if not names.has("R"):
		for n in sim.nodes:
			if n["relay"] != "":
				names["R"] = int(n["id"])
				break
	sim.abilities_on = bool(L.get("abilities", false))
	sim.vls_enabled = bool(L.get("vls", true))
	if not L.get("match", false):
		sim.match_hard_end = INF                     # a lesson is never cut short by the 7:00 end
		for seat in sim.skill_cd:                     # skills stand ready in a lesson (0.19.2: Rules.SKILLS_START_ON_COOLDOWN);
			sim.skill_cd[seat] = {"active": 0.0, "map": 0.0}   # the first match keeps the normal start for both seats
	_stage()
	_ev_cursor = sim.events.size()
	if L.get("match", false):
		ai = SeatAI.new(RIVAL, 2.5, str(L.get("ai", "Training")))
		_match = {"phase": "idle", "relay_taken": false}
	preview_relay = _id(str(L.get("preview", "")))
	state = "running"
	step_i = 0
	_enter(_step())


func _stage() -> void:
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
		if (e as Array).size() > 3:
			n["tier"] = int(e[3])
		n["owner"] = str(e[1])
		n["units"] = _units(e[2], n["tier"])
	var low: Dictionary = L.get("neutrals", {})        # L9: T-02's neutrals start (and stay) low, so a match ends
	if not low.is_empty():
		for n in sim.nodes:
			if n["owner"] == "" and Sim.has_vat(n) and low.has(int(n["tier"])):
				n["units"] = float(low[int(n["tier"])]) * Rules.SCALE
				n["regen_cap"] = n["units"]


func _units(v, tier: int) -> float:
	if v is String:
		match v:
			"garrison":
				return float(Rules.NEUTRAL_UNITS.get(tier, 0))
			"cap":
				return float(Rules.CAPS.get(tier, 0))
	return float(v) * Rules.SCALE


func _id(name: String) -> int:
	return int(names.get(name, -1))


func _node(name: String) -> Dictionary:
	var id := _id(name)
	return sim.nodes[id] if id >= 0 else {}


func _step() -> Dictionary:
	var steps: Array = L["steps"]
	return steps[clampi(step_i, 0, steps.size() - 1)]


func reveal_keys() -> Array:
	return reveal_for(lesson_id, step_i)


# ---------------------------------------------------------------- the frame
func step(dt: float) -> void:
	if state in ["complete", "failed"] or sim == null:
		return
	lesson_t += dt
	step_t += dt
	if _note_t > 0.0:
		_note_t -= dt
		if _note_t <= 0.0:
			_note = ""
			_bump()
	_scan_events()
	if L.get("match", false):
		_tick_match(dt)
		return
	if state == "interlude":
		_interlude_t -= dt
		if _interlude_t <= 0.0:
			state = "running"
			if _interlude_next == "complete":
				_complete()
			else:
				_advance()
		return
	var st := _step()
	_tick_lesson(dt)
	_tick_step(st, dt)
	if state != "running":
		return
	var why := _check_fail(st)
	if why != "":
		_fail(why)
		return
	if (st.get("read_only", false) or step_t >= MIN_STEP) and _check_pass(st):
		_pass_step(st)
		return
	if sim.is_out(HUMAN) and not sim.over:            # out (lines keep you alive): TRY AGAIN - main keeps the YOU'RE OUT
		_fail(line("L7.lost") if lesson_id == 7 else line("try_again"))   # panel off in lessons (show_out_panel)
		return
	if sim.over:                                     # the match ended off-script
		if sim.winner != "" and sim.allied(sim.winner, HUMAN):
			_complete()
		else:
			_fail(line("try_again"))
		return
	if not st.get("read_only", false) and not _idle_shown and sim.time - _last_order_t > IDLE_HINT:
		_idle_shown = true
		say(line("idle_hint"))


func on_event(ev: Dictionary) -> void:
	## main: every sim.fx_events entry (and the headless test does the same after each sim.step).
	match str(ev.get("type", "")):
		"fling", "fall", "monster_kick", "last_stand", "collapse", "build_done", "monster_take", "monster_fall":
			var e := ev.duplicate()
			e.erase("pts")
			e["t"] = sim.time if sim else 0.0
			e["fx"] = true
			_log.append(e)


func on_action(method: String, _id_arg: int, _args := {}, ok := true) -> void:
	## main: every node_action result. Only the timing of the player's orders matters here (the idle hint); what
	## they did is read from the Sim's own events.
	if ok and method != "":
		_last_order_t = sim.time if sim else 0.0
		_idle_shown = false


func allow(method: String, id: int, args := {}) -> String:
	## "" or the line that refuses an order which would wreck the lesson's staging (design §6).
	if sim == null or state == "complete":
		return ""
	if method == "send":
		var to := int(args.get("to", -1))
		if to >= 0 and to < sim.nodes.size() and not sim.allied(sim.nodes[to]["owner"], HUMAN):
			for p in L.get("protect", []):
				if _id(str(p)) == to:
					return line("not_yet")
			var until := str(L.get("protect_rival_until", ""))
			if until != "" and sim.nodes[to]["owner"] == RIVAL and _step_index_of(until) > step_i:
				return line("not_yet")
	if method == "launch_monster" and _step().has("only_launch"):
		if int(args.get("to", -1)) != _id(str(_step()["only_launch"])):
			return line("not_yet")
	return ""


func _step_index_of(key: String) -> int:
	var steps: Array = L["steps"]
	for i in range(steps.size()):
		if str(steps[i]["key"]) == key:
			return i
	return steps.size()


func press_button() -> void:
	## The card's one button: GOT IT on a read-only step.
	if state == "running" and _step().get("read_only", false):
		_pass_step(_step())


func skip_step() -> void:
	if state == "interlude":
		_interlude_t = 0.0
		return
	if state != "running":
		return
	if L.get("match", false):
		_match["card_done"] = true
		_bump()
		return
	_advance()


func say(text: String) -> void:
	## A transient handler line on the card (a refusal, a hint, a miss).
	if text == "":
		return
	_note = text
	_note_t = NOTE_SECONDS
	_bump()


func _bump() -> void:
	version += 1
	changed.emit()


# ---------------------------------------------------------------- events
func _scan_events() -> void:
	while _ev_cursor < sim.events.size():
		var ev: Dictionary = sim.events[_ev_cursor]
		_ev_cursor += 1
		var t := str(ev.get("type", ""))
		if t in ["send", "build_start", "build_done", "relay_fired", "skill", "monster_launch", "capture", "cannon_burst",
				"horde_destroyed", "handover", "eliminated"]:
			_log.append(ev)
			if str(ev.get("seat", "")) == HUMAN and t in ["send", "build_start", "relay_fired", "skill", "monster_launch"]:
				_last_order_t = sim.time
				_idle_shown = false


func _since(t0: float, type: String, filter := {}) -> Array:
	var out := []
	for ev in _log:
		if float(ev.get("t", 0.0)) + 0.0001 < t0 or str(ev.get("type", "")) != type:
			continue
		var ok := true
		for k in filter:
			if not ev.has(k) or ev[k] != filter[k]:
				ok = false
				break
		if ok:
			out.append(ev)
	return out


# ---------------------------------------------------------------- steps: enter / pass / fail
func _enter(st: Dictionary) -> void:
	step_t = 0.0
	_step_started = sim.time
	_catch = {}
	_tracked = []
	_idle_shown = false
	_last_order_t = sim.time
	var op: Array = st.get("enter", [])
	if not op.is_empty():
		match str(op[0]):
			"topup":                                  # the vat gets enough for `fraction` of it to beat the target
				var n := _node(str(op[1]))
				var target := _node(str(op[2]))
				if not n.is_empty() and not target.is_empty():
					var need: float = (float(target["units"]) + 3.0 * Rules.SCALE) / float(op[3])
					n["units"] = maxf(float(n["units"]), ceilf(need))
			"b_send":
				var h := _b_send(str(op[1]), str(op[2]), float(op[3]))
				if not h.is_empty():
					_tracked.append(h["id"])
			"b_attack":                              # a line the target can't hold alone: its garrison + op[3]
				var target := _node(str(op[2]))
				var shown := float(Rules.shown(float(target["units"]))) + float(op[3]) if not target.is_empty() else float(op[3])
				var h := _b_send(str(op[1]), str(op[2]), shown)
				if not h.is_empty():
					_tracked.append(h["id"])
			"charge_hub":                             # the director fills the hub's charge, as L8 fills the ultimate
				var n := _node(str(op[1]))
				if not n.is_empty():
					n["monster_ready_t"] = sim.time
			"fill_ultimate":
				sim.ult_charge[HUMAN] = 1.0
				sim.ult_since[HUMAN] = Rules.ULT_MIN_TIME
			"vls":
				_jump_clock(Rules.VERY_LAST_STAND_TIME)   # the clock reads {vls}
				var gap = L.get("vls_gap", -1.0)
				sim.start_very_last_stand_now(vls_gap())
	_bump()


func _check_pass(st: Dictionary) -> bool:
	if st.has("catch"):
		return _catch.get("done", false)
	var op: Array = st.get("pass", [])
	if op.is_empty():
		return false
	match str(op[0]):
		"send":
			for ev in _since(0.0, "send", {"seat": HUMAN}):
				if (str(op[1]) == "" or int(ev["from"]) == _id(str(op[1]))) and int(ev["to"]) == _id(str(op[2])):
					return true
		"send_own":
			for ev in _since(_step_started, "send", {"seat": HUMAN}):
				if str(ev.get("target_owner", "")) == HUMAN:
					return true
		"owner":
			return _node(str(op[1])).get("owner", "") == str(op[2])
		"fraction":
			return absf(ui_fraction - float(op[1])) < 0.001
		"inspect":
			return ui_inspector == _id(str(op[1]))
		"build_started":
			var n := _node(str(op[1]))
			return not _since(_step_started, "build_start", {"node": _id(str(op[1])), "seat": HUMAN}).is_empty() \
					or (not n.is_empty() and n["build_kind"] == n["structure"] and n["build_kind"] != "")
		"tier":
			var n := _node(str(op[1]))
			return not n.is_empty() and int(n["tier"]) >= int(op[2]) and n["build_kind"] == ""
		"built":
			var n := _node(str(op[1]))
			return not n.is_empty() and n["owner"] == HUMAN and n["structure"] == str(op[2]) and n["build_kind"] == ""
		"fired":
			var n := _node(str(op[1]))
			return not _since(0.0, "relay_fired", {"node": _id(str(op[1])), "seat": HUMAN}).is_empty() \
					or (not n.is_empty() and n["relay_phase"] != "")
		"cast":
			return not _since(_step_started, "skill", {"seat": HUMAN, "slot": str(op[1])}).is_empty()
		"launched":
			return not _since(_step_started, "monster_launch", {"seat": HUMAN, "target": _id(str(op[1]))}).is_empty()
		"fall_or_time":
			if step_t < float(_step().get("min", 0.0)):
				return false
			for ev in _since(_step_started, "fall"):
				if str(ev.get("seat", "")) == RIVAL:
					return true
			return step_t >= float(op[1])
		"won":
			return sim.over and sim.winner != "" and sim.allied(sim.winner, HUMAN)
		"custom":
			return _custom_pass(str(op[1]), op)
	return false


func _check_fail(st: Dictionary) -> String:
	var op: Array = st.get("fail", [])
	if op.is_empty():
		return ""
	match str(op[0]):
		"lost":
			return line("try_again") if _node(str(op[1])).get("owner", "") != HUMAN else ""
		"lost_match":
			return line("try_again") if sim.over and not (sim.winner != "" and sim.allied(sim.winner, HUMAN)) else ""
		"custom":
			if str(op[1]) == "ring_lost":
				return _ring_lost()
	return ""


func _custom_pass(what: String, op: Array) -> bool:
	match what:
		"line_spent":                                # the step's rival line is gone and the node held
			if _node(str(op[2])).get("owner", "") != HUMAN or _tracked.is_empty():
				return false
			return not _any_alive(_tracked) and not _rival_bound_for(_id(str(op[2])))
		"burst_spent":                               # the laser fired at the line, which is gone
			if not _since(_step_started, "cannon_burst", {"node": _id(str(op[2]))}).is_empty():
				_burst_seen = true
			return _burst_seen and _node(str(op[2])).get("owner", "") == HUMAN and not _any_alive(_tracked) \
					and not _rival_bound_for(_id(str(op[2])))
		"monster_done":                              # the monster took the lane's end - or fell (the step passes)
			for ev in _since(_step_started, "monster_take"):
				if str(ev.get("seat", "")) == HUMAN and int(ev.get("node", -1)) == _id(str(op[2])):
					return true
			for ev in _since(_step_started, "monster_fall"):
				if str(ev.get("seat", "")) == HUMAN:
					if not _catch.get("fell_said", false):
						_catch["fell_said"] = true
						say(line("L6.fell"))
					return true
		"ring_down":
			return _ring_down()
		"demolish_busy":
			for ev in _since(_step_started, "skill", {"seat": HUMAN, "slot": "map"}):
				if ev.get("judged", false):
					continue
				ev["judged"] = true
				if _rival_on_edge(int(ev.get("target", -1))):
					return true
				_demolish_tries += 1
				if _demolish_tries >= 2:
					return true
				sim.skill_cd[HUMAN]["map"] = 0.0      # the director hands the skill back for another try
	return false


func _pass_step(st: Dictionary) -> void:
	if not st.get("read_only", false):
		handler.emit("happy")
	var dl := str(st.get("done_line", ""))
	var last := step_i >= (L["steps"] as Array).size() - 1
	if dl != "":
		_note = line(dl)
		_note_t = INTERLUDE
		state = "interlude"
		_interlude_t = INTERLUDE
		_interlude_next = "complete" if last else "advance"
		_bump()
		return
	if last:
		_complete()
	else:
		_advance()


func _advance() -> void:
	step_i += 1
	time_scale = 1.0
	if step_i >= (L["steps"] as Array).size():
		step_i = (L["steps"] as Array).size() - 1
		_complete()
		return
	_enter(_step())


func _fail(text: String) -> void:
	state = "failed"
	time_scale = 1.0
	fail_line = text
	_bump()
	handler.emit("droop")
	failed.emit(text)


func _complete(relay_kill := false, kill_units := 0) -> void:
	if state == "complete":
		return
	state = "complete"
	time_scale = 1.0
	mark_complete(lesson_id, relay_kill)
	var lines := []
	for k in L.get("done", []):
		lines.append(line(str(k)))
	result = {"id": lesson_id, "title": title_of(lesson_id), "lines": lines, "time": lesson_t, "relay_kill": relay_kill,
			"scrap": last_scrap,                        # TUTORIAL + PROGRESSION
			"kill_units": kill_units, "final": lesson_id == LESSON_COUNT, "graduate": all_done(), "tour": L.get("tour", false),
			"next": lesson_id + 1 if lesson_id < LESSON_COUNT else -1, "won": sim.over and sim.allied(sim.winner, HUMAN)}
	_bump()
	completed.emit(result)


# ---------------------------------------------------------------- per-frame lesson behaviour
func _tick_lesson(_dt: float) -> void:
	var at := float(L.get("last_stand_at", -1.0))
	if at >= 0.0 and not _ls_started and lesson_t >= at:
		_ls_started = true
		_jump_clock(Rules.LAST_STAND_TIME)            # the clock reads {ls} as the line says
		_ls_strength = sim.seat_strength(HUMAN)
		_ls_falls = float(sim.fall_losses.get(HUMAN, 0.0))
		sim.start_last_stand_now()
		_b_evacuate()
		_bump()
	if _ls_started and str(L.get("hold_ls", "")) == str(_step().get("key", "")) and not sim.last_stand_queue.is_empty():
		sim.last_stand_warn_t = maxf(sim.last_stand_warn_t, Rules.LAST_STAND_WARNING)   # the countdown waits for GOT IT


func _jump_clock(to: float) -> void:
	## L7: the match clock jumps to the collapse's own time (so the HUD clock and the line agree); every time
	## the director measures from moves with it.
	var d := to - sim.time
	if d <= 0.0:
		return
	sim.time = to
	_last_order_t += d
	_step_started += d
	for ev in _log:
		ev["t"] = float(ev.get("t", 0.0)) + d
	if _catch.has("t0"):
		_catch["t0"] = float(_catch["t0"]) + d


func _tick_step(st: Dictionary, _dt: float) -> void:
	time_scale = 1.0
	var restore := str(st.get("restore", ""))
	if restore != "":
		_restore_relay(_id(restore))
	if st.has("catch"):
		_tick_catch(st["catch"])
	if st.get("keep_a_line", false):
		_keep_a_line()
	if st.has("b_stream"):
		var bs: Array = st["b_stream"]
		if not _rival_moving():
			var h := _b_send(str(bs[0]), str(bs[1]), float(bs[2]))
			if not h.is_empty():
				_tracked.append(h["id"])
	if st.has("hint"):
		_tick_hint(st["hint"])


func _tick_hint(h: Array) -> void:
	## L3's "too small": a line of yours reached the neutral and it held.
	var target := _id(str(h[1]))
	if target < 0 or sim.nodes[target]["owner"] == HUMAN:
		return
	for ev in _since(_step_started, "send", {"seat": HUMAN}):
		if int(ev["to"]) != target or _hint_seen.has(ev.get("t")):
			continue
		var alive := false
		for x in sim.hordes:
			if x["owner"] == HUMAN and int(x["target"]) == target:
				alive = true
		if not alive:
			_hint_seen[ev.get("t")] = true
			say(line(str(h[2])))


# ---------------------------------------------------------------- the relay catch (L4, L5)
# A scripted rival line walks onto the relay's deck; the player fires the relay while it is on it. Before every
# line the relay is set back to its starting state (fired again once its cooldown allows - "the director turns
# the deck back"), and the node the line attacks is topped up so a miss never takes it. A catch: a fling
# (rotation) or a relay fall of at least `min` shown rival units. A miss: the line is spent without one - the
# next line comes, up to `tries`, then the step passes anyway ("Timing takes practice").
func _tick_catch(c: Dictionary) -> void:
	var relay := _id(str(c["relay"]))
	if relay < 0:
		_catch["done"] = true
		return
	var rn: Dictionary = sim.nodes[relay]
	if _catch.get("done", false):
		return
	if not _catch.has("tries"):
		_catch = {"tries": 0, "line": -1, "t0": sim.time, "prompt": false}
	# was the line caught?
	var hid := int(_catch["line"])
	if hid >= 0:
		var caught := 0
		for ev in _since(float(_catch["t0"]), "fling"):
			if str(ev.get("seat", "")) == RIVAL and int(ev.get("node", -1)) == relay:
				caught += int(ev.get("units", 0))
		for ev in _since(float(_catch["t0"]), "fall"):
			if str(ev.get("seat", "")) == RIVAL and int(ev.get("relay", -1)) == relay:
				caught += int(ev.get("shown", 0))
		if caught >= int(c["min"]):
			_catch["done"] = true
			_catch["caught"] = caught
			return
		var on := _on_relay_deck(hid, relay)
		if on != bool(_catch.get("prompt", false)):
			_catch["prompt"] = on
			_bump()
		if on and c.get("half", false):
			time_scale = HALF_SPEED
		if not _any_alive([hid]) or _landed(hid):
			_catch["tries"] = int(_catch["tries"]) + 1
			_catch["line"] = -1
			_catch["prompt"] = false
			if int(_catch["tries"]) >= int(c["tries"]):
				say(line(str(c.get("practice", "L4.practice"))))
				_catch["done"] = true
				return
			if c.has("miss"):
				say(line(str(c["miss"])))
			_bump()
		return
	# no line out: set the relay back, then send the next one
	if rn["relay_index"] != 0 or rn["relay_phase"] != "":
		_restore_relay(relay)
		return
	if rn["relay_cd"] > 0.0 or rn["owner"] != HUMAN:
		return
	var to := _node(str(c["to"]))
	if not to.is_empty() and to["owner"] == HUMAN:
		to["units"] = maxf(float(to["units"]), (float(c["shown"]) + 10.0) * Rules.SCALE)
	var h := _b_send(str(c["from"]), str(c["to"]), float(c["shown"]))
	if not h.is_empty():
		_catch["line"] = h["id"]
		_catch["t0"] = sim.time
		_tracked.append(h["id"])
		_bump()


func _restore_relay(relay: int) -> void:
	## Back to the relay's starting state (index 0) once it may fire again.
	if relay < 0:
		return
	var rn: Dictionary = sim.nodes[relay]
	if rn["relay_index"] != 0 and rn["relay_phase"] == "" and rn["relay_cd"] <= 0.0 and rn["owner"] != "":
		sim.fire_relay(relay)


func catch_prompt() -> bool:
	## The catch step's line is on the relay's deck right now (the prompt, the hand, the half speed).
	return bool(_catch.get("prompt", false)) or bool(_match.get("prompt", false))


func catch_line() -> int:
	return int(_catch.get("line", -1)) if not _catch.is_empty() else int(_match.get("push_line", -1))


func _on_relay_deck(hid: int, relay: int) -> bool:
	## Does line `hid` have bodies on one of the relay's decks that is open now (the deck a fire would drop)?
	var h := sim._horde(hid)
	if h.is_empty():
		return false
	var edges := sim.controlled_edges(relay)
	var head: float = h["s"]
	var tail: float = head - Sim.chain_length(h)
	for sp in h["spans"]:
		if sp["edge"] in edges and sim.is_edge_open(sp["edge"]):
			if minf(head, sp["s1"]) - maxf(tail, sp["s0"]) > 0.3:
				return true
	return false


func _landed(hid: int) -> bool:
	var h := sim._horde(hid)
	return not h.is_empty() and h["state"] == "absorb" and not h["streaming"]


# ---------------------------------------------------------------- scripted rival and helper lines
func _b_send(from_name: String, to_name: String, shown: float) -> Dictionary:
	## One scripted rival order of about `shown` units (the source is topped up if it has fewer - staging).
	var from := _id(from_name)
	var to := _id(to_name)
	if from < 0 or to < 0 or sim.collapsed.get(from, false):
		return {}
	var n: Dictionary = sim.nodes[from]
	if n["owner"] != RIVAL:
		return {}
	var want := shown * Rules.SCALE
	if float(n["units"]) < want + 1.0:
		n["units"] = want + 1.0
	return sim.send(from, to, clampf((want + 0.5) / float(n["units"]), 0.01, 1.0))


func _b_evacuate() -> void:
	## L7: the weak rival pulls every line of units off its falling ring onto the centre's far end (it never attacks).
	var dest := _id("I3")
	if dest < 0:
		return
	for n in sim.nodes:
		if n["owner"] == RIVAL and n["id"] != dest and float(n["units"]) >= Rules.SCALE:
			sim.send(n["id"], dest, 1.0)


func _keep_a_line() -> void:
	## L8: keep one of your lines on the move (a Surge / ultimate target): half a garrison at the centre.
	for h in sim.hordes:
		if h["owner"] == HUMAN and h["state"] == "move" and not h.get("decoy", false):
			return
	var best := -1
	for n in sim.nodes:
		if n["owner"] == HUMAN and not sim.collapsed.get(n["id"], false) and (best < 0 or n["units"] > sim.nodes[best]["units"]):
			best = n["id"]
	var target := _id("C")
	if target < 0 or best < 0 or sim.nodes[best]["units"] < 4.0 * Rules.SCALE:
		return
	if sim.allied(sim.nodes[target]["owner"], HUMAN):
		target = _id("BH")
	sim.send(best, target, 0.5)


func _any_alive(ids: Array) -> bool:
	for h in sim.hordes:
		if h["id"] in ids:
			return true
	return false


func _rival_bound_for(node: int) -> bool:
	for h in sim.hordes:
		if h["owner"] == RIVAL and int(h["target"]) == node:
			return true
	return false


func _rival_moving() -> bool:
	for h in sim.hordes:
		if h["owner"] == RIVAL and h["state"] == "move":
			return true
	return false


func _rival_on_edge(ei: int) -> bool:
	for h in sim.hordes:
		if h["owner"] != RIVAL:
			continue
		var head: float = h["s"]
		var tail: float = head - Sim.chain_length(h)
		for sp in h["spans"]:
			if int(sp["edge"]) == ei and minf(head, sp["s1"]) - maxf(tail, sp["s0"]) > -1.0:
				return true
	return false


# ---------------------------------------------------------------- L7: the collapse
func _ring_nodes() -> Array:
	return (sim.last_stand_waves[0] as Array) if not sim.last_stand_waves.is_empty() else []


func _ring_down() -> bool:
	if not _ls_started or not sim.last_stand_active:
		return false
	var ring := _ring_nodes()
	if ring.is_empty():
		return false
	for id in ring:
		if not sim.collapsed.get(id, false):
			return false
	return _holds_node() and _ring_lost() == ""


func _ring_lost() -> String:
	## Out, or the ring is down and more than half of what you had went with it (the vats you left kept
	## breeding until they fell, so "what you had" is what fell plus what is still standing).
	if sim.eliminated.has(HUMAN) or (sim.over and not sim.allied(sim.winner, HUMAN)):
		return line("L7.lost")
	if not _ls_started:
		return ""
	var ring := _ring_nodes()
	var down := not ring.is_empty() and ring.all(func(id): return sim.collapsed.get(id, false))
	if not down:
		return ""
	var fell := float(sim.fall_losses.get(HUMAN, 0.0)) - _ls_falls
	if not _holds_node() or fell >= 0.5 * maxf(fell + sim.seat_strength(HUMAN), 1.0):
		return line("L7.lost")
	return ""


func _holds_node() -> bool:
	for n in sim.nodes:
		if n["owner"] == HUMAN and not sim.collapsed.get(n["id"], false):
			return true
	return false


# ---------------------------------------------------------------- L9: the first match
# A normal 1v1 against the Training AI with one scripted moment (§3): once you hold the relay and lead (at 2:30 at
# the latest) the rival MUSTERS its units on the node nearest the relay deck's near end, then commits one big PUSH
# (>= 70 % of its units) across that deck. While the push is on the deck the game runs at half speed and the relay
# is spotlit; losing >= 50 % of the push to the fall (the fling and the waterfall behind it) ends the tutorial on
# the spot. A miss hands the match back to the AI; win or lose, the lesson completes.
func _tick_match(dt: float) -> void:
	time_scale = 1.0
	var relay := _id("R")
	if state == "interlude":
		_interlude_t -= dt
		if _interlude_t <= 0.0:
			state = "running"
			_complete(bool(_match.get("kill", false)), int(_match.get("kill_units", 0)))
		return
	if sim.over:
		var won := sim.winner != "" and sim.allied(sim.winner, HUMAN)
		_finish_in(line("L9.win") if won else line("L9.lose"))
		return
	var phase := str(_match.get("phase", "idle"))
	if phase in ["idle", "done"]:
		ai.think(sim, dt)
	if relay >= 0 and sim.nodes[relay]["owner"] == HUMAN and not _match.get("relay_taken", false):
		_match["relay_taken"] = true
		say(line("L9.relay_taken"))
	if not _match.get("card_done", false) and sim.time > 12.0:
		_match["card_done"] = true
		_bump()
	if phase in ["idle", "done"] and sim.time - _last_order_t > IDLE_HINT and not _idle_shown:
		_idle_shown = true
		say(line("idle_hint"))
	match phase:
		"idle":
			if relay >= 0 and _push_due(relay):
				_start_muster(relay)
		"muster":
			if sim.nodes[relay]["owner"] != HUMAN:
				_match["phase"] = "done"
			elif not _rival_moving() or sim.time - float(_match["t"]) > 25.0:
				_launch_push(relay)
		"push":
			_tick_push(relay)


func _push_due(relay: int) -> bool:
	var rn: Dictionary = sim.nodes[relay]
	if rn["owner"] != HUMAN or rn["relay_phase"] != "" or rn["relay_cd"] > 0.0:
		return false
	var b := sim.seat_strength(RIVAL)
	if b < 20.0 * Rules.SCALE:
		return false
	return sim.seat_strength(HUMAN) > b or sim.time >= PUSH_LATEST


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


func _start_muster(relay: int) -> void:
	var deck := _relay_deck(relay)
	if deck.is_empty():
		return
	var best := -1
	var best_len := 99999
	for n in sim.nodes:
		if n["owner"] != RIVAL or sim.collapsed.get(n["id"], false):
			continue
		var r := sim.find_route(n["id"], deck["near"], {deck["edge"]: true}) if n["id"] != deck["near"] else [n["id"]]
		if r.is_empty():
			continue
		if r.size() < best_len or (r.size() == best_len and n["units"] > sim.nodes[best]["units"]):
			best_len = r.size()
			best = n["id"]
	if best < 0:
		return
	for n in sim.nodes:                              # every other rival garrison gathers there
		if n["owner"] == RIVAL and n["id"] != best and float(n["units"]) >= 3.0 * Rules.SCALE:
			sim.send(n["id"], best, 1.0)
	_match["phase"] = "muster"
	_match["muster"] = best
	_match["t"] = sim.time


func _launch_push(relay: int) -> void:
	var m := int(_match.get("muster", -1))
	var deck := _relay_deck(relay)
	var rn: Dictionary = sim.nodes[relay]
	if m < 0 or deck.is_empty() or sim.nodes[m]["owner"] != RIVAL or rn["owner"] != HUMAN or rn["relay_cd"] > 0.0 \
			or rn["relay_phase"] != "":
		if sim.time - float(_match["t"]) > 40.0:
			_match["phase"] = "done"
		return
	# the push's target: your node nearest the deck's far end (the far end itself if it is yours)
	var target := int(deck["far"])
	if sim.nodes[target]["owner"] != HUMAN:
		var best_len := 99999
		for n in sim.nodes:
			if n["owner"] != HUMAN or sim.collapsed.get(n["id"], false):
				continue
			var r := sim.find_route(deck["far"], n["id"])
			if not r.is_empty() and r.size() < best_len:
				best_len = r.size()
				target = n["id"]
	var route: Array = [m] if m == int(deck["near"]) else sim.find_route(m, deck["near"], {deck["edge"]: true})
	if route.is_empty():
		_match["phase"] = "done"
		return
	route.append(deck["far"])
	if target != int(deck["far"]):
		var tail := sim.find_route(deck["far"], target, {deck["edge"]: true})
		if tail.size() >= 2:
			route.append_array(tail.slice(1))
		else:
			target = int(deck["far"])
	if route.size() < 2 or route.count(route[-1]) > 1:
		_match["phase"] = "done"
		return
	var h := sim.send(m, target, 1.0)
	if h.is_empty():
		_match["phase"] = "done"
		return
	sim._set_route(h, route)                         # the scripted push crosses the relay deck, whatever is fastest
	_match["phase"] = "push"
	_match["push_line"] = h["id"]
	_match["push_units"] = float(h["ordered"])
	_match["falls0"] = float(sim.fall_losses.get(RIVAL, 0.0))
	_match["t"] = sim.time
	_match["prompt"] = false


func _tick_push(relay: int) -> void:
	var hid := int(_match["push_line"])
	var lost := float(sim.fall_losses.get(RIVAL, 0.0)) - float(_match["falls0"])
	var units := maxf(float(_match["push_units"]), 1.0)
	if lost >= PUSH_KILL * units:
		_match["kill"] = true
		_match["kill_units"] = Rules.shown(lost)
		_match["prompt"] = false
		_match["phase"] = "done"
		handler.emit("happy")
		_finish_in(line("L9.relay_kill"))
		return
	var on := _on_relay_deck(hid, relay)
	if on != bool(_match.get("prompt", false)):
		_match["prompt"] = on
		_bump()
	if on:
		time_scale = HALF_SPEED
	var gone := true
	for h in sim.hordes:
		if h["owner"] == RIVAL:
			gone = false
	if (gone or sim.time - float(_match["t"]) > 45.0) and lost < PUSH_KILL * units:
		_match["phase"] = "done"
		_match["prompt"] = false
		say(line("L9.miss"))


func _finish_in(text: String) -> void:
	if state == "interlude":
		return
	state = "interlude"
	_interlude_t = INTERLUDE
	_note = text
	_note_t = INTERLUDE + 1.0
	time_scale = 1.0
	_bump()


# ================================================================ what the coach shows
func header() -> String:
	if lesson_id == FIRST_ID:
		return "%s · %s" % [HANDLER_NAME, title_of(FIRST_ID)]
	if lesson_id == LESSON_COUNT:
		return "%s · FIRST MATCH" % HANDLER_NAME
	return "%s · LESSON %d / %d · %s" % [HANDLER_NAME, lesson_id, LESSON_COUNT - 1, title_of(lesson_id)]


func card() -> Dictionary:
	## The coach card now: {visible, header, text, dots, dot, button}. button "" = a doing-step.
	if state == "failed":
		return {"visible": true, "header": "%s · %s" % [header(), line("try_again_title")], "text": fail_line,
				"dots": 0, "dot": 0, "button": line("try_again_title")}
	var steps: Array = L["steps"]
	if L.get("match", false):
		var show: bool = not _match.get("card_done", false) or _note != "" or catch_prompt()
		var text := line("L9.push") if catch_prompt() else (_note if _note != "" else line("L9.start"))
		return {"visible": show and state != "complete", "header": header(), "text": text, "dots": 0, "dot": 0,
				"button": line("got_it") if not _match.get("card_done", false) and _note == "" and not catch_prompt() else ""}
	var st := _step()
	var text := _note if _note != "" else _fmt(line("%s.%s" % [L["key"], st["key"]]))
	if st.has("before") and not catch_prompt() and _note == "":
		text = line(str(st["before"]))              # the catch before its line reaches the deck
	var button := ""
	if st.get("read_only", false) and state == "running":
		button = line("next_step") if L.get("tour", false) else line("got_it")
	return {"visible": state != "complete", "header": header(), "text": text, "dots": steps.size(), "dot": step_i,
			"button": button}


func is_tour() -> bool:
	return bool(L.get("tour", false)) and state == "running"


func uses_inspector() -> bool:
	## Does the current step work in the inspector (an action button, the inspector itself)? If not, main closes
	## an inspector left open from an earlier step, so it never lingers over the next one.
	if state != "running":
		return false
	var st := _step()
	for k in (st.get("target", {}) as Dictionary).get("rects", []):
		if str(k).begins_with("action:") or str(k) == "inspector":
			return true
	var op: Array = st.get("pass", [])
	return st.has("inspect") or (not op.is_empty() and str(op[0]) == "inspect")


func inspect_request() -> int:
	## The node the step wants the inspector open on (the tour's inspector step), -1 for none.
	if state != "running":
		return -1
	return _id(str(_step().get("inspect", "")))


func target() -> Dictionary:
	## What the spotlight rings: {nodes: [ids], rects: [keys], lines: [horde ids]}. Rect keys: "send:0.25",
	## "action:<NAME>" (Hud.action_rect), "dock:<slot>".
	var out := {"nodes": [], "rects": [], "lines": []}
	if state != "running":
		return out
	if L.get("match", false):
		if catch_prompt():
			out["nodes"] = [_id("R")]
			out["lines"] = [int(_match.get("push_line", -1))]
		return out
	var t: Dictionary = _step().get("target", {})
	for nm in t.get("nodes", []):
		var id := _id(str(nm))
		if id >= 0 and not sim.collapsed.get(id, false):
			out["nodes"].append(id)
	out["radius"] = float(t.get("radius", 1.0))
	if t.has("label"):                                # the walking line's own TAKE · units · seconds label
		out["label"] = [_id(str(t["label"][0])), _id(str(t["label"][1]))]
	out["decks"] = []
	for pair in t.get("decks", []):
		var ei := sim._edge_index(_id(str(pair[0])), _id(str(pair[1])))
		if ei >= 0:
			out["decks"].append(ei)
	for key in t.get("rects", []):                    # "badge:<name>" -> "badge:<node id>"
		var k := str(key)
		out["rects"].append(_rect_key(k))
	var who := str(t.get("lines", ""))
	if who != "":
		for h in sim.hordes:
			if h["owner"] == who and not h.get("decoy", false) and (who == HUMAN or _tracked.is_empty() or h["id"] in _tracked):
				out["lines"].append(h["id"])
	return out


func gesture() -> Array:
	## The pointing hand's alternatives, resolved to ids: [[kind, a, b], ...] - main draws the first it can.
	## kinds: tap / double_tap (node id), drag (node id -> node id), press (a rect key), tap_line (horde id),
	## tap_deck (edge index).
	if state != "running":
		return []
	if L.get("match", false):
		return [["double_tap", _id("R"), -1]] if catch_prompt() else []
	var st := _step()
	if st.has("catch"):
		return [["double_tap", _id(str(st["catch"]["relay"])), -1]] if catch_prompt() else []
	var out := []
	for g in st.get("gesture", []):
		var kind := str(g[0])
		match kind:
			"tap", "double_tap":
				out.append([kind, _id(str(g[1])), -1])
			"drag":
				out.append([kind, _id(str(g[1])), _id(str(g[2]))])
			"vls_move":                               # L7: off your warned node, onto the one that stays
				var mv := _vls_move()
				if not mv.is_empty():
					out.append(["drag", mv[0], mv[1]])
			"press":
				var k := str(g[1])
				out.append([kind, _rect_key(k), -1])
			"monster":                                # 0.19.2: tap the monster over its hub, then the end node
				var hub := _id(str(g[1]))
				if ui_monster_from == hub:
					out.append(["tap", _id(str(g[2])), -1])
				else:
					out.append(["press", "monster_icon:%d" % hub, -1])
					out.append(["press", "action:LAUNCH", -1])   # the second way, while the inspector is open
					out.append(["tap", hub, -1])
			"tap_line":                               # only once the dock slot is armed
				if ui_armed == int(st.get("armed", -1)):
					var hid := _a_line()
					if hid >= 0:
						out.append(["tap_line", hid, -1])
			"tap_deck":
				if ui_armed == int(st.get("armed", -1)):
					var ei := _busy_deck()
					if ei >= 0:
						out.append(["tap_deck", ei, -1])
			"tap_ult":
				if ui_armed == int(st.get("armed", -1)):
					var kind_t := str(Rules.SKILLS.get(sim.skill_id(HUMAN, "ultimate"), {}).get("target", "none"))
					if kind_t == "own_line" and _a_line() >= 0:
						out.append(["tap_line", _a_line(), -1])
					elif kind_t in ["own_node", "own_vat"]:
						out.append(["tap", _id("H"), -1])
	return out


func vls_gap() -> float:
	var gap = L.get("vls_gap", -1.0)
	if str(gap) == "warning+gap":
		return Rules.LAST_STAND_WARNING + Rules.LAST_STAND_DROP_GAP
	return float(gap)


func _vls_move() -> Array:
	## [from, to]: your warned node with units and the nearest survivor that is not warned (yours first).
	var from := -1
	for n in sim.nodes:
		if n["owner"] == HUMAN and sim.is_warned(n["id"]) and n["units"] >= Rules.SCALE and not sim.collapsed.get(n["id"], false):
			from = n["id"]
	if from < 0:
		return []
	var best := -1
	var best_score := INF
	for n in sim.nodes:
		if n["id"] == from or sim.collapsed.get(n["id"], false) or sim.is_warned(n["id"]):
			continue
		var r := sim.find_route(from, n["id"])
		if r.size() < 2:
			continue
		var score := float(r.size()) - (10.0 if n["owner"] == HUMAN else 0.0)
		if score < best_score:
			best_score = score
			best = n["id"]
	return [from, best] if best >= 0 else []


func _rect_key(k: String) -> String:
	## "badge:<name>" / "monster_icon:<name>" -> the node id main's rect getters take.
	for pre in ["badge:", "monster_icon:"]:
		if k.begins_with(pre):
			return "%s%d" % [pre, _id(k.substr(pre.length()))]
	return k


func _a_line() -> int:
	for h in sim.hordes:
		if h["owner"] == HUMAN and h["state"] == "move" and not h.get("decoy", false):
			return h["id"]
	return -1


func _busy_deck() -> int:
	for h in sim.hordes:
		if h["owner"] != RIVAL:
			continue
		var head: float = h["s"]
		for sp in h["spans"]:
			if head >= sp["s0"] and head <= sp["s1"]:
				return int(sp["edge"])
	return -1


func _fmt(text: String) -> String:
	if not "{" in text:
		return text
	var st := _step()
	var first := -1
	for nm in (st.get("target", {}) as Dictionary).get("nodes", []):
		first = _id(str(nm))
		break
	var vals := {
		"secs": str(int(Rules.BUILD_SECONDS)),
		"ls": _mmss(Rules.LAST_STAND_TIME), "vls": _mmss(Rules.VERY_LAST_STAND_TIME),
		"hops": str(Rules.MONSTER_REACH),
		"ult": str(roundi(Rules.ULT_CHARGE_TIME / 60.0)),
		"cap": str(Rules.shown(Rules.CAPS[1])),
		"faction": str(Rules.FACTION_NAMES.get(faction, [faction.to_upper()])[0]),
		"skill1": ArmyPresets.skill_name(sim.skill_id(HUMAN, "active")),
		"skill2": ArmyPresets.skill_name(sim.skill_id(HUMAN, "map")),
		"ult_name": ArmyPresets.skill_name(sim.skill_id(HUMAN, "ultimate")),
		"n": str(lesson_id),
	}
	if first >= 0:
		vals["cost"] = str(Rules.shown(sim.upgrade_cost(sim.nodes[first])))
		vals["garrison"] = str(Rules.shown(sim.nodes[first]["units"]))
	for k in vals:
		text = text.replace("{%s}" % k, str(vals[k]))
	return text


static func _mmss(secs: float) -> String:
	return "%d:%02d" % [int(secs) / 60, int(secs) % 60]


static func final_kill_line(units: int) -> String:
	return line("final_relay_kill").replace("{n}", str(units))
