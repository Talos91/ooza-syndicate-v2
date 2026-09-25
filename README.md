# Ooze Syndicate 2.0 - Alpha 18 (v0.18.4)

Godot 4.6 project (GL Compatibility - browser and phone first) for the 2.0 bridge-network game.
Design authority: `Docs/Game Design/Ooze Syndicate 2.0/` in the project folder
(`H:\My Drive\PROJECTS\Ooze Syndicate`). Alpha 11 lives separately in `Game/Alpha 11`.

**Start here next session:** `docs/NEXT-SESSION.md` (state, open work, the standing rules).

## What Alpha 17 is

Two modes that look and play differently, picked on the setup page (MODE / SIEGE or BRAWL):

- **SIEGE** - goo hordes. A send streams out as one long blob (length = count). Hordes fight
  wherever they touch, to the death, and the front slides toward the weaker side (tug-of-war).
  Tap your own line to RECALL it. Goo corridors join any two adjacent nodes you own; enemies on
  your goo are slower and push weaker. Passing through an enemy node fights its garrison; only an
  arrival captures. Arrivals besiege the platform and fight the garrison there.
- **BRAWL** - Alpha 11's core rules. Columns of the approved creature models, three across. Each
  unit is resolved the moment it reaches the target node (Alpha 11 `land()`, one-for-one at
  baseline). Waypoints are free, lines pass each other. Alpha 11's movement and animation: 8.9 m/s on
  decks and platforms, 9.6 units/s out and in, the Alpha 11 hop. No recall. Half-bridge neon and round count badges
  with faction emblems, as in Alpha 11.

Shared by both:

- **Front menu = Alpha 11's** (MAIN -> 01 FACTION -> 02 BATTLEFIELD -> 03 SETUP -> DEPLOY; OPTIONS).
  Setup: rival faction, difficulty (Casual / Standard / Veteran), PLAYERS (1v1 / 2v2 / 3v3 /
  FFA 3-5, whatever the map offers), YOUR COLOUR (palette or FACTION), MODE, LAST STAND on/off.
- **Maps 3.0**: 100 maps (tutorial, core, brawl, siege, crazy) + 9 debug maps, in the approved
  Blender layout baked per map (`maps3/`, `assets/maps3/`, see BUILD-LOG). Plazas, rim exits, angled
  piers, decks at 0 / +4 / -4 / +8 m (lines only meet on the same height), honest deck time.
- **Factions** play differently (Alpha 11's stat profiles). **Numbers on screen are Alpha 11's**
  (caps 30/40/80/160, upgrades 10/20/30, cannon 15/25/35, forge 20); the sim runs at x5 (`Rules.SCALE`).
- **Structures**: vat T1-T4, cannon T1-T3 (2 s beam burst), forge (+50 % attack). Tap a node for
  the ring inspector; double-tap your own node to upgrade. **Conquest drops a vat or cannon one tier.**
- **Relays** (rotation / retract / switch / remote): tap yours, SWITCH. 3 s warning, the deck
  moves, 5 s cooldown. Rotation: troops ride. Retract: carried into the node. Switch / remote: fall.
  Anything ordered across a deck that is gone walks off into the void.
- **Last Stand** at 2:00 (toggle), ring logic (Alpha 17): hidden method (inward / outward / chaos from
  the map's ring orders) revealed with the waves on the badges; each wave drops a whole ring after a
  10 s warning, the last ring never falls, relays fall only after all their rings, and nothing is ever
  left cut off. Everything on a falling node dies. 7:00 safety net. Tutorials have none.
- **Teams and FFA**: allies never fight, reinforce each other, win together.
- **Fixed camera** (no zoom/pan, 42 degrees), fitted so the HUD never covers the map; every
  structure faces the viewer. **Phones play fullscreen** (Android button / iPhone Add to Home Screen).
- Deck and platform speed 5 m/s, door 48 units/s.
- **Online rooms** (Alpha 16, browser build): MAIN -> ONLINE -> CREATE ROOM or JOIN ROOM (four-character
  code). Alpha 11's PeerJS peer-to-peer rooms: 2-5 player FFA or 2v2, a lobby where the host picks map,
  PLAYERS, SIEGE/BRAWL, Last Stand and EMPTY SEATS (AI), host-authoritative play (guests' orders are validated by the
  host, state streams back ~10 Hz), rematch in the same room, RECONNECT into your seat, chat. Keep the host's tab in front.

Not in yet: accounts / room list / stats (Vercel + Neon, later), a relay server for strict networks, abilities
(skill pools unapproved), team "eject", textures and the blob-model readability redo.

## Play

**https://talos91.github.io/ooza-syndicate-v2/** - published from `main` to `gh-pages`. Phone: open
in Chrome (Android: PLAY FULLSCREEN) or Safari (Share -> Add to Home Screen), landscape. **After a
publish, reload twice**; if an old version sticks, clear the site data (PWA cache).

## Run and test

```
Godot_v4.6.1-stable_win64.exe --path .                               # front menu
Godot_v4.6.1-stable_win64.exe --path . -- --map=res://maps3/C-05-karth-carousel.json --brawl
Godot_v4.6.1-stable_win64.exe --path . -- --demo --seed=3 --shots=10 --out=C:/tmp
Godot_v4.6.1-stable_win64.exe --path . -- --menu-page=setup --menu-shot=C:/tmp/setup.png
Godot_v4.6.1-stable_win64.exe --path . -- --map=res://maps3/T-01-first-steps.json --thumb=C:/tmp/T-01.png
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_sim.gd
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_map_pool.gd
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_maps3.gd
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_ai_curve.gd
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_net.gd
```

Flags: `--brawl` (or `--classic`), `--mode=1v1|2v2|3v3|FFA3|FFA4|FFA5`, `--ai=Casual|Standard|Veteran`,
`--seed=N`, `--perf`, `--scenario=fight|rear|queue|build|inspect|switch|rotate`, `--mobile`, `--window=WxH`.
Godot is in `Tools/Godot` of the project folder. Publishing steps: `docs/BUILD-LOG.md` §10.

## Layout

| Path | What |
|---|---|
| `scripts/rules.gd` | every number and switch (mode, Last Stand, speeds, costs, colours, camera) |
| `scripts/sim.gd` | rules and state: routes, production, contacts, tug-of-war, recall, corridors, Brawl landing, relays, Last Stand, structures, teams |
| `scripts/seat_ai.gd` | AI levels; relay use; retreats; cost-aware building; team-aware |
| `scripts/map_builder.gd` | layout, kit placement, overpass detection, relay ledges |
| `scripts/map_pool.gd` | the maps 3.0 pool (100 + 9 debug); `maps/` = the archived 2.0 roster, rules tests only |
| `maps3/`, `assets/maps3/` | baked maps 3.0 (JSON + plaza GLBs, thumbnails) from `Models/2.0/export_maps_3_0_game.py` |
| `scripts/horde_view.gd` | Siege goo lines, fight look, rivers, corridors |
| `scripts/unit_view.gd` | Brawl creature columns |
| `scripts/fx.gd` | construction, cannon beams, relay motion, Last Stand, falls, Brawl half-bridge neon |
| `scripts/hud.gd` | match HUD: top bar, send panel, badges, inspector, pause, results, debug |
| `scripts/menu.gd`, `neon_panel.gd`, `ui_skin.gd` | Alpha 11's front menu and kit |
| `scripts/fullscreen_gate.gd` | phone fullscreen requirement |
| `scripts/main.gd` | world, camera fit, input, orchestration, command-line flags |
| `scripts/net.gd` | online rooms (autoload `Net`): lobby, seats, host validation, snapshots, rematch, chat |
| `scripts/scenery.gd` | sky backdrop, vat liquid levels and tank residents (Alpha 16 visual pass) |
| `web/` | PeerJS, transport shim, room-code field, chat panel - copied into `build/web` at publish |
| `tests/test_sim.gd`, `test_map_pool.gd`, `test_net.gd`, `test_maps3.gd`, `test_ai_curve.gd` | rules; every map plays to the end (each combat mode); rooms / netcode; maps 3.0 layout, seats and Last Stand; AI fairness and difficulty curve |
