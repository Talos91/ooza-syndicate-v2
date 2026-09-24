# Ooze Syndicate 2.0

Fresh Godot 4.6 project (GL Compatibility - browser and phone first) for the 2.0 bridge-network
game. Design authority: `Docs/Game Design/Ooze Syndicate 2.0/` in the project folder
(`H:\My Drive\PROJECTS\Ooze Syndicate`). Alpha 11 lives separately in `Game/Alpha 11`.

## First slice: Two Piers (starter map 1)

- Map built from `maps/004-two-piers.json` with the Blender kit, at honest lengths
  (1 deck module = 4 m = 2 s; piers count as part of the platform).
- Drag from one of your nodes to any node to send; side buttons set 25 / 50 / 75 / 100 %.
- Hordes are chains of patches (goo + creatures, one patch per 60 units) that leave from the tank
  bottoms, flow along the decks, curve AROUND the centre structure of every node they pass and
  squeeze in through the destination's door.
- Neutral and enemy nodes: the garrison is beaten down, then the node flips. Own nodes: reinforce.
- Opposing hordes meeting on a deck stop at a frontline and fight.
- Owned vats produce up to their cap. Seat B is a simple AI.
- Ownership = material: seat-colour lights, vat ooze, goo; creature body hue = seat, race = accent.
- Per-match telemetry JSON in `user://telemetry/`.

All tunable numbers are in `scripts/rules.gd`; army numbers there are PROVISIONAL placeholders.
Not in this slice yet: relays, vat upgrades, cannons/forges in play, abilities, Last Stand,
multiplayer, pinch-zoom on touch.

## Run

```
Godot_v4.6.1-stable_win64.exe --path .                          # play
Godot_v4.6.1-stable_win64.exe --path . -- --demo                # AI vs AI
Godot_v4.6.1-stable_win64.exe --path . -- --demo --shots=9,24 --out=C:/tmp
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/test_sim.gd
```

Godot is in `Tools/Godot` of the project folder.

## Layout

| Path | What |
|---|---|
| `scripts/rules.gd` | every number: kit sizes, speeds, caps, production, combat, colours |
| `scripts/sim.gd` | rules and state, no visuals (routes, paths, production, capture, frontlines) |
| `scripts/map_builder.gd` | honest layout from map JSON, kit placement, ownership materials |
| `scripts/horde_view.gd` | hordes as patch chains |
| `scripts/mats.gd`, `shaders/creature.gdshader` | seat materials, creature hue shift + race rim |
| `scripts/seat_ai.gd`, `scripts/telemetry.gd` | opponent, match log |
| `scripts/main.gd` | world, camera, input, HUD, demo/screenshot mode |
| `assets/kit`, `assets/horde` | GLBs exported from `Models/2.0/OozeKit-2.0.blend` and `OozeHordePatches-2.0.blend` |
| `maps/` | the starter seven (copies of the roster JSON) |
| `tests/test_sim.gd` | headless rules checks |
