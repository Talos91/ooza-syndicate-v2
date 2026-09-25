# Next session - start here

State at the end of the 2026-09-25 sessions: **v0.17.1 "Alpha 17"** (maps 3.0 + debug maps, ring Last Stand, five-level AI, constant unit speed; on top of Alpha 16: online rooms, visual pass), source on `main`,
published at https://talos91.github.io/ooza-syndicate-v2/. Read, in order: `GAME-BIBLE.md` (project root - the whole game as built), this file,
`README.md`, the top of `CHANGELOG.md` (0.16.0 to 0.17.1), `PLAYTEST-NOTES.md` notes 72-95, then the
design package `Docs/Game Design/Ooze Syndicate 2.0/00 README.md` and `05 Handoff/AGENT-BRIEF.md`.

## Standing rules (Daniele)

- **Publish after every pass** that changes play or looks: commit + push `main`, export Web, copy
  `web/*.js` (PeerJS, transport, room-ui, chat-ui) into `build/web`, replace the `gh-pages` branch (recipe in `docs/BUILD-LOG.md` §10),
  verify the live `index.pck` size matches, hand back the link. Bump `Rules.VERSION` every publish.
- **Every mechanic ships with its animation, HUD readout and control** in the same pass. Only
  textures and better models may wait.
- **Start numbers from Alpha 11's logic**, shown to the player at Alpha 11 scale (`Rules.shown`).
- **BRAWL must be exactly Alpha 11's core rules**; SIEGE is where 2.0 experiments live.
- Ask before assuming what to work on; Daniele drives from his own playtests.
- Reference the design package; never hand-edit roster geometry (`maps-100.json`).

## Queued, in this order (Daniele, 2026-09-25)

1. **Alpha 18 - new map pack.** Daniele: "the maps are waaaay too big for mobile". He is generating
   a new pack to replace maps 3.0; wait for it, then bake and implement it the same way (builder ->
   `export_maps_3_0_game.py` -> `maps3/`, `test_maps3`, `test_map_pool`). Measured sizes (fitted
   span = the larger of width and height scaled to 836x470, platforms R 6 m):

   | Set | Maps | Fitted span (median / min / max) | Platform width on screen |
   |---|---|---|---|
   | maps 3.0 (`maps3`, K 3 m/unit) | 109 | 401 / 179 / 502 m | 2.4-4.9 % (median ~2.9 %, ~24 px of 836) |
   | older 2.0 roster (`maps`, before maps 3.0) | 100 | 134 / 21 / 186 m | median ~9 % (~75 px) |

   So maps 3.0 are about 3x the older roster. Plaza sockets sit ~5.2 units (15.6 m) apart, so
   simply lowering K would overlap platforms (diameter 12 m): the size has to come from the layout.
   At constant speed, bigger maps also mean longer marches.
2. **Optimization pass** (after Alpha 18): stray code, stale comments, errors, smoothness - keep
   the look. Findings so far:
   - Bug: `Rules.TEAM_FAMILIES` has two families; 2v2v2 has three teams, so two teams share the
     warm family. Add a third family (e.g. violet/magenta/lilac) and a `test_sim` check.
   - Dead or stale: shield code (Rules `SHIELD_*`, `fx._shield`, hud shield bar - check whether any
     rule still sets `shield_up`), `Rules.OVERPASS_H` / `_deck_points` legacy overpass path,
     `MODULE_SECONDS` (legacy routing only), `UNITS_PER_PATCH`, `main.STARTER_MAPS` / `PROVES`,
     `Net.NODE_SKIP` "center", "Alpha 12" headers in main/fx/hud/mats/sim.
   - The other session's uncommitted kit pieces (`assets/kit/Park_*`, `Plaza_*`, `Pier_Park*`,
     `Pier_Plaza_*`) still sit untracked; keep them out of the export (temporary exclude_filter)
     or ask Daniele whether to delete them.
   - Frame cost (`--perf`, desktop, 1280x720, `--demo`): C-05 1v1 60 fps, ~1,700 draw calls,
     1.2 M primitives, ~1,000 nodes; D-09 stress 3v3 55-59 fps, ~6,550 draw calls, 2.2 M
     primitives, ~3,700 nodes. Draw calls are the target for phones (mesh merging / MultiMesh for
     repeated kit pieces, residents and badges; check the vat liquid transparency and detail
     textures on the mobile profile). No errors or warnings in either run.
   - Command: `Godot_v4.6.1-stable_win64_console.exe --path . -- --map=res://maps3/D-09-stress-test.json --mode=3v3 --demo --seed=3 --shots=60 --out=<dir> --perf --window=1280x720`
   Then tests, version bump, publish.

## Alpha 17 (2026-09-25): maps 3.0, ring Last Stand, five-level AI - built

- Maps: `Models/2.0/export_maps_3_0_game.py` bakes the approved layout (run it headless in Blender
  5.2 after any change to the pack or to `build_maps_3_0_review.py`; BUILD-LOG sec10), then
  `tests/test_maps3.gd` must pass. The game never re-plans: `MapBuilder.build3` only places pieces,
  `Sim._build_path3` / `_deck_points3` follow the baked exits and heights.
- Last Stand: `Sim._start_rings` / `_plan_waves` / `_islands` / `_step_rings`.
- AI: `scripts/seat_ai.gd` (Alpha 11 loop) + `Rules.AI_LEVELS`; `tests/test_ai_curve.gd`.
- Open (maps handoff): homes start T2 (game) vs T1 (pack); The Knot has two levels in the data (README
  says three); plaza sockets ~0.5 module apart; retract housings / switch emitters are radial pieces on
  angled exits; D-04 keeps one planner clash. The big maps render small at 3 m per unit - check on a
  phone. Last Stand starts at 2:00 (pack README says 3:00).

## Multiplayer: built in Alpha 16 (PeerJS peer-to-peer, Alpha 11's approach)

`scripts/net.gd` (autoload `Net`) + `web/peer-transport.js`, `web/room-ui.js` (code field),
`web/chat-ui.js` (chat panel). MAIN -> ONLINE -> CREATE / JOIN -> lobby -> DEPLOY by host. The host's
`Sim` is the only simulation: guests call `main.node_action` -> `Net.order` -> host `Net._execute` ->
`main.perform(seat, ...)` (the same checks and feedback lines as offline); the host streams
`Net.snapshot()` ~10 Hz and `Net.push_effects()`; guests `Net.apply_snapshot()` (fires `captured` /
`finished` like a local Sim) and `Net.predict()` between updates. Tests: `tests/test_net.gd`; two
players on one PC: `tests/duo.html` (BUILD-LOG sec10). Main's `HUMAN` is now a variable (your seat).

Still open on multiplayer:
- Real separate-network and phone tests (Daniele). No relay (TURN) server: strict networks fail.
- A host tab in the background freezes the match; 10 s later guests drop (they can RECONNECT).
- Built in 0.16.1: EMPTY SEATS (AI), RECONNECT into a held seat, 10 s host grace, REMATCH.
- Not built: seat swapping in the lobby, spectators.
- Later: Vercel (site, room list, sign-in functions) + Neon Postgres (accounts, match history,
  leaderboards, telemetry). Vercel cannot relay a live match itself (no long-lived WebSockets).

## Other open work

- **Blob readability redo** (SIEGE): enemy attacks are hard to scan (PLAYTEST-NOTES 49) - Blender
  patch generator `Models/2.0/build_horde_patches_2_0.py`.
- **Badges** now sit outside platforms in the widest gap; on dense maps some still touch a deck.
- **Abilities / Ooze Factory**: waiting on SKILLS-2.0-DRAFT approval; the dock is hidden meanwhile.
- **Team eject, halo tiers** (GAME-RULES sec11) not built.
- **Open questions for Daniele** are listed at the end of `05 Handoff/OPEN-QUESTIONS.md` (bond as
  mechanic, forge defence, cannon numbers, Last Stand 2:00 vs 3:00, speed 5 m/s vs 2 s modules,
  relay cooldown 5 s vs 15 s, chaos vs homes, map 030).
- Real-phone touch and frame rate are still unmeasured (only browser emulation).

## Gotchas

- New `class_name` scripts need `Godot --headless --import --path .` before they resolve.
- Since 0.16.2 `web/update.js` swaps in a new build by itself. If an old one still sticks, in the in-app browser clear it with
  `navigator.serviceWorker.getRegistrations()` + `caches.keys()` via the JS tool.
- `git branch -D gh-pages` locally before recreating the orphan branch (see BUILD-LOG §10).
- No system Python on this PC; use Godot headless scripts for data work.
- Files merged from other sessions may have CRLF endings - normalise before perl/sed edits.
- Autoloads are not global names inside `--script` test files: tests reach `Net` through an instance
  (`load("res://scripts/net.gd").new()`), never the `Net` identifier.
- In the in-app browser only the front tab runs its game loop; test two players with `tests/duo.html`
  (both iframes visible), and hover before clicking - Godot buttons need a mouse move first.
