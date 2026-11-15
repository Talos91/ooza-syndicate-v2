# DECK KNOB for Tools/MapBuilder (map-shrink, 2026-11-15)

Daniele, 2026-11-15: the maps are too big on his phone. The limit is a start-view platform of at least ~60 pt on the 840 x 360
fold profile (HX ladder: HX-4 at 59.7 pt passed, HX-5 at 54.5 pt failed). Bridges go from 4 / 8 / 12 m to 2 / 4 / 6 m, and units
keep full speed (option A).

These files replace their twins in `H:/My Drive/PROJECTS/Ooze Syndicate/Tools/MapBuilder` (the Drive copy is not in git).
After this branch is merged, copy them over that folder with the same relative paths. Nothing else in the builder changes.

| file | change |
|---|---|
| `mb/kit.py` | **the knob**: `DECK_K` (env `OOZE_DECK_K`, default 1 = 4 / 8 / 12 m; 0.5 = 2 / 4 / 6 m), `deck_m(tier)`, `CENTRE` from it; env `OOZE_ROOT` / `OOZE_RULES_GD` let a copy run against a clone |
| `mb/planner.py` | G05 honest length = the deck's `modules`, else its tier x `DECK_K` |
| `mb/junctions.py` | `honest_m`, `centre_for`, `deck_tier` through the knob |
| `mb/sketch.py` | deck lengths through `kit.deck_m` |
| `mb/shrink.py` | **new**: re-bakes a map drawn at the default tiers at `k`: same nodes, edges, tiers and symmetry; node positions re-solved so every deck loses (1 - k) of its honest length (rulebook G02 / G03 / G04 / J01 / J02 as constraints, rotor decks keep their headings). Where fixed pieces make an exact k impossible, the deck keeps the length it got and writes it into `modules`: the game walks the real length. k = 1 returns the map unchanged |
| `packs/shrink_pool.py` | **new**: the pool re-bake runner (`--src=<maps4 at 4/8/12> --game=<clone> --deck-k=0.5 --write`), rulebook before / after, planner verify |
| `packs/r_maps.py`, `r_new_r13.py`, `r_new_r14.py`, `exp_chain.py` | literal 19.2 / 23.2 / 27.2 / 4.0 / 7.6 m replaced by `kit.CENTRE` / `kit.deck_m` / `kit.S x DECK_K` (identical at K 1; not re-run at K 0.5: the pool was baked by `shrink_pool.py`) |

Game side: `tests/test_maps4.gd` reads the knob from the map (each deck's `modules`, or the map's `deckK` x its tier).
Bake of 2026-11-15: `python packs/shrink_pool.py --src=<main 8d50c11 maps4> --game=<clone> --deck-k=0.5 --write`
(numpy + scipy; R-09 uses `PER_MAP` RELAY_HEAD 0.4). Results: `References/Map size 2026-11/SHRINK-36.md`.
