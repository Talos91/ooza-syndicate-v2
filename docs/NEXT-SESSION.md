# Next session - start here

State at the end of the 2026-09-25 sessions: **v0.17.0 "Alpha 17"** (maps 3.0 + debug maps, ring Last Stand, five-level AI; on top of Alpha 16: online rooms, visual pass), source on `main`,
published at https://talos91.github.io/ooza-syndicate-v2/. Read, in order: this file,
`README.md`, the top of `CHANGELOG.md` (0.12.0 to 0.16.0), `PLAYTEST-NOTES.md` notes 26-71, then the
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
