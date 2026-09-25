# Ooze Syndicate 2.0 - Alpha 15 (v0.15.0)

Godot 4.6 project (GL Compatibility - browser and phone first) for the 2.0 bridge-network game.
Design authority: `Docs/Game Design/Ooze Syndicate 2.0/` in the project folder
(`H:\My Drive\PROJECTS\Ooze Syndicate`). Alpha 11 lives separately in `Game/Alpha 11`.

**Start here next session:** `docs/NEXT-SESSION.md` (state, open work, the standing rules).

## What Alpha 15 is

Two modes that look and play differently, picked on the setup page (MODE / SIEGE or BRAWL):

- **SIEGE** - goo hordes. A send streams out as one long blob (length = count). Hordes fight
  wherever they touch, to the death, and the front slides toward the weaker side (tug-of-war).
  Tap your own line to RECALL it. Goo corridors join any two adjacent nodes you own; enemies on
  your goo are slower and push weaker. Passing through an enemy node fights its garrison; only an
  arrival captures. Arrivals besiege the platform and fight the garrison there.
- **BRAWL** - Alpha 11's core rules. Columns of the approved creature models, three across. Each
  unit is resolved the moment it reaches the target node (Alpha 11 `land()`, one-for-one at
  baseline). Waypoints are free, lines pass each other. Half-bridge neon and round count badges
  with faction emblems, as in Alpha 11.

Shared by both:

- **Front menu = Alpha 11's** (MAIN -> 01 FACTION -> 02 BATTLEFIELD -> 03 SETUP -> DEPLOY; OPTIONS).
  Setup: rival faction, difficulty (Casual / Standard / Veteran), PLAYERS (1v1 / 2v2 / 3v3 /
  FFA 3-5, whatever the map offers), YOUR COLOUR (palette or FACTION), MODE, LAST STAND on/off.
- **99 maps** (the whole roster but 030, whose data is broken). Crossing decks are overpasses;
  hordes on an overpass only meet hordes on the same deck.
- **Factions** play differently (Alpha 11's stat profiles). **Numbers on screen are Alpha 11's**
  (caps 30/40/80/160, upgrades 10/20/30, cannon 15/25/35, forge 20); the sim runs at x5 (`Rules.SCALE`).
- **Structures**: vat T1-T4, cannon T1-T3 (2 s beam burst), forge (+50 % attack). Tap a node for
  the ring inspector; double-tap your own node to upgrade. **Conquest drops a vat or cannon one tier.**
- **Relays** (rotation / retract / switch / remote): tap yours, SWITCH. 3 s warning, the deck
  moves, 5 s cooldown. Rotation: troops ride. Retract: carried into the node. Switch / remote: fall.
  Anything ordered across a deck that is gone walks off into the void.
- **Last Stand** at 2:00 (toggle): hidden method (inward / outward / chaos from the map), order
  revealed on badges, 10 s warnings, everything on a falling node dies, never isolates a node;
  same-ring nodes shuffle so the first drop varies. 7:00 safety net.
- **Teams and FFA**: allies never fight, reinforce each other, win together.
- **Fixed camera** (no zoom/pan, 42 degrees), fitted so the HUD never covers the map; every
  structure faces the viewer. **Phones play fullscreen** (Android button / iPhone Add to Home Screen).
- Deck and platform speed 5 m/s, door 48 units/s.

Not in yet: **multiplayer** (PeerJS transport is in `web/`, the Godot side is next), abilities
(skill pools unapproved), team "eject", textures and the blob-model readability redo.

## Play

**https://talos91.github.io/ooza-syndicate-v2/** - published from `main` to `gh-pages`. Phone: open
in Chrome (Android: PLAY FULLSCREEN) or Safari (Share -> Add to Home Screen), landscape. **After a
publish, reload twice**; if an old version sticks, clear the site data (PWA cache).

## Run and test

```
Godot_v4.6.1-stable_win64.exe --path .                               # front menu
Godot_v4.6.1-stable_win64.exe --path . -- --map=res://maps/008-strait.json --brawl --mode=2v2
Godot_v4.6.1-stable_win64.exe --path . -- --demo --seed=3 --shots=10 --out=C:/tmp
Godot_v4.6.1-stable_win64.exe --path . -- --menu-page=setup --menu-shot=C:/tmp/setup.png
Godot_v4.6.1-stable_win64.exe --path . -- --map=res://maps/004-two-piers.json --thumb=C:/tmp/004.png
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_sim.gd
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_map_pool.gd
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
| `scripts/map_pool.gd` | the 99 playable maps |
| `scripts/horde_view.gd` | Siege goo lines, fight look, rivers, corridors |
| `scripts/unit_view.gd` | Brawl creature columns |
| `scripts/fx.gd` | construction, cannon beams, relay motion, Last Stand, falls, Brawl half-bridge neon |
| `scripts/hud.gd` | match HUD: top bar, send panel, badges, inspector, pause, results, debug |
| `scripts/menu.gd`, `neon_panel.gd`, `ui_skin.gd` | Alpha 11's front menu and kit |
| `scripts/fullscreen_gate.gd` | phone fullscreen requirement |
| `scripts/main.gd` | world, camera fit, input, orchestration, command-line flags |
| `web/` | PeerJS + transport shim, copied into `build/web` at publish |
| `tests/test_sim.gd`, `tests/test_map_pool.gd` | 200+ rules checks; every map plays to the end |
