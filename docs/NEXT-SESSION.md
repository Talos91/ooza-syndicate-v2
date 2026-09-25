# Next session - start here

State at the end of the 2026-09-25 sessions: **v0.18.1 "Alpha 18"** (maps 4.1 at the kit's sizes - 18 maps of a partial pack -, per-map camera, optimization pass; on top of Alpha 17: ring Last Stand, five-level AI; Alpha 16: online rooms, visual pass), source on `main`,
published at https://talos91.github.io/ooza-syndicate-v2/. Read, in order: `GAME-BIBLE.md` (project root - the whole game as built), this file,
`README.md`, the top of `CHANGELOG.md` (0.17.0 to 0.18.0), `PLAYTEST-NOTES.md` notes 90-100, then the
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

## Maps 4.1 (partial) - built in 0.18.1; waiting for the rest of the pack

- `References/Ooze Syndicate maps 4.1 (partial)`: 18 maps drawn in metres at the kit's sizes. Baked by
  `Models/2.0/export_maps_4_1_game.py` (builder `build_maps_4_1_review.py`, K 1.0, plaza templates read off
  the maps) into `maps4/` + `assets/maps4/` (the folder keeps its 4.x name; maps 4.0 are in git history).
  Files are named by code only (`maps4/T-01.json`). Decks 4.1 / 8.3 / 12.4 m median (honest 4 / 8 / 12).
- Still to come from the pack: B-06, B-08 (generator: "no embedding"), the whole core (C) and siege (S)
  groups, more FFA / team maps (only X-01 offers FFA 4 / 2v2), any debug maps beyond D-01/02/05/07. B-02,
  B-03 and T-05 came out without geometric symmetry (status.log `sym=False`) - ask whether that is fair.
- When the rest arrives: drop it into the same folder (or a new one and point the builder's PACK and the
  exporter's PACK_DIR at it), bake, `--import`, set LODs / shadow meshes off in the new `.glb.import`
  files, `test_maps4` (now also checks honest deck lengths), the phone-fit probe (rule: from 58 degrees,
  lowest angle with every tap >= 44 pt, no overflow, no badge collision) -> `scripts/map_camera.gd`, the
  full suites, publish.
- `MapPool.WITHHELD` and `PHONE_UNFIT` are empty on 4.1 (every map passes). `MapPool.dir` is a static
  var so `tests/test_net.gd` can point the pool at the legacy roster.

## Alpha 18 (2026-09-25): maps 4.0, per-map camera, optimization pass - built

- **Maps 4.0** (`References/Ooze Syndicate maps 4.0`, 160 x 80 frame): `Models/2.0/build_maps_4_0_review.py`
  (the 3.0 builder with the 4.0 frame, gen4 plaza templates and K 1.7) + `export_maps_4_0_game.py` (adds
  docks) -> `maps4/`, `assets/maps4/`. After a bake: `Godot --headless --import`, re-apply
  `generate_lods=false` / `create_shadow_meshes=false` in the new `assets/maps4/*.glb.import` (then
  reimport), `tests/test_maps4.gd`, `test_map_pool`, and the phone-fit probe (below).
- **K sweep** (`clashes / over-platform`, 109 maps): 1.4: 67/110, 1.5: 61/31, 1.6: 35/23, 1.7: 25/13
  (only B-30 and D-04), 1.8+: B-19 gains clashes. Steep piers (> 80 degrees) persist even at 3.0 on the
  ring maps: a layout property, clamped by the kit.
- **Pool**: `MapPool.WITHHELD` = B-30 (24 clashes), D-08 (not phone-fit); `MapPool.PHONE_UNFIT` = the
  3v3 / 2v2v2 maps, hidden when `MapPool.phone` (phone profile + short screen side < 600 CSS px).
- **Camera**: `scripts/map_camera.gd` (generated table, per-map pitch), `main.cam_pitch`,
  `--pitch=N` (sets `pitch_forced`). **Phone-fit probe**: run windowed as a scene (the Net autoload is
  needed): `Godot_v4.6.1-stable_win64_console.exe --path . --resolution 1266x585 res://tests/phone_fit.tscn -- out=<file> pitches=auto`
  (or `pitches=50,54,...` to sweep; `maps=C-05,...` to filter). Rule used: lowest pitch with the
  smallest tap >= 33 pt (844 pt wide phone), no badge over the HUD / screen edge, no badge collisions,
  then fewest badges touching a neighbour's platform. Final: 107 maps, 0 overflow, 0 collisions, min tap
  33.0 pt, 34 badge-touches-platform (FFA 5 / 3v3).
- **Optimization pass**: audit + fixes by two workflows (8 reviewers + skeptics; 7 file-disjoint fix
  groups, an integrator, 7 reviewers). Audit table and every applied change: CHANGELOG 0.18.0. Deferred
  (need Daniele or a measured pass): MultiMesh for moving horde patches (perf-05), AI route caching
  (ai-04), menu map-summary cache (main-06), host signalling reconnect (net-02), shadows (the sun's
  100 m shadow range is still out of reach at 1.7 m per unit; if a future pack brings the camera closer,
  goo should stop casting), phone lighting (sun.shadow_enabled off on phones changes the look slightly).
- Frame cost now (desktop, 1280x720, `--perf`, pitch 42 for comparison): C-05 SIEGE ~1,125 draw calls,
  D-09 3v3 ~1,147 (were 1,875 and 3,525 on maps 4.0 before the pass).
- The other session's uncommitted kit pieces (`assets/kit/Park_*`, `Plaza_*`, `Pier_Park*`,
  `Pier_Plaza_*`) are still untracked: add them to `exclude_filter` for the export only (as every
  publish since 0.17.0 has), never commit them for that session.

## Alpha 17 (2026-09-25): maps 3.0 (superseded by 4.0), ring Last Stand, five-level AI - built

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
