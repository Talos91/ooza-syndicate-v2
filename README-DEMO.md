# Ooze Syndicate 2.0 - SOUND DEMO (branch `sound-demo`, never shipped)

Spectate an AI-vs-AI BRAWL match (M-30 Sporefall Plain, FFA4, Veteran AI, skills on, the normal play camera)
and compare candidate sound sets by ear. Nothing in `scripts/` is changed: `demo/sound_demo.gd` boots `main.tscn`
with every seat on the AI (like `tests/perf_check.gd`) and reads the match read-only each frame (the Sim's
telemetry list `sim.events`, lines pouring into hostile nodes, machinegoon `shot` stamps).

**Run:** double-click `RUN-SOUND-DEMO.bat` (windowed Godot 4.6.1, 1600x900). Or:
`Godot_v4.6.1-stable_win64.exe --path <this folder> --resolution 1600x900 res://demo/sound_demo.tscn`

## Keys

| Key | Does |
|---|---|
| 1 / 2 / 3 / 4 | sound set (also the buttons on the overlay) |
| A | next alternate (alt 1 -> 2 -> 3) for every event of the set |
| M | mute |
| + / - | master volume (3 dB steps) |
| S | speed 1x / 2x / 3x (to reach Last Stand sooner) |
| R | restart the match with a new seed |
| SPACE | pause / resume |

The match restarts by itself 5 s after it ends. The overlay (top left) shows the set and alternate and the last 6
sounds as `event  aN -> pack/file.ogg`: name the line you like or dislike (for example "set 4 capture a2").
An event with fewer than 3 files wraps round (the line says which alternate actually played).

Throttle: the same event at most every 0.2-0.45 s (alarms 1 s, win 2 s), 12 voices; when all are busy a new
sound is dropped, except win / Last Stand / Very Last Stand / eliminated / collapse, which take the oldest voice.
Long files are cut with a short fade (engineCircular alarms 1.8-2.2 s, digital lasers 0.6 s, ...).

Verification flags (after `--`): `--demo-log` (print every sound), `--demo-cycle=N` (next set every N s),
`--demo-speed=1..3`, `--demo-ff=S` (silent fast-forward to S s of match time), `--demo-quit=S`,
`--demo-shot=<png>@<s>`, `--demo-map=res://maps4/...json`, `--demo-mode=FFA4|2v2`, `--demo-ai=Standard|Veteran`.

## Events

| Event | When |
|---|---|
| `send` | a line leaves a node (every send order) |
| `fight` | a line starts pouring into an enemy / neutral node (BRAWL's fight at the door) |
| `hit` | a line is wiped out (horde destroyed) |
| `capture` | a neutral node is taken |
| `node_lost` | a player's node is taken by someone else |
| `upgrade` | a vat / machinegoon tier-up completes |
| `build` | a structure build or swap completes (laser, forge, hub, machinegoon, vat restore) |
| `laser` | a laser tower starts a burst |
| `machinegoon` | a machinegoon fires (stream, throttled to ~2 per s) |
| `monster_launch` | a hub launches a monster |
| `monster_stomp` | a monster kicks units off a deck |
| `monster_take` | a monster takes a node |
| `monster_fall` | a monster falls off the map |
| `skill` | any skill / ultimate cast |
| `relay_warning` | a relay is fired (its warning starts) |
| `relay_switch` | a relay deck switches |
| `fall` | units fall off a deck (relay switch, Last Stand drop, monster) |
| `collapse_warning` | a node is marked to drop (Last Stand) |
| `collapse` | a platform drops (Last Stand) |
| `last_stand` | LAST STAND starts (alarm) |
| `very_last_stand` | VERY LAST STAND starts (alarm) |
| `eliminated` | a seat is knocked out |
| `win` | the match ends with a winner (win jingle) |

## Set 1 - Kenney mix

UI = Kenney interface, captures / hits = Kenney impact, lasers / alarms / relays = Kenney sci-fi, goo = slime pack.

| Event | alt 1 | alt 2 | alt 3 |
|---|---|---|---|
| `send` | `slime/slime_12.ogg` | `slime/slime_06.ogg` | `slime/slime_11.ogg` |
| `fight` | `slime/slime_02.ogg` | `slime/slime_07.ogg` | `slime/splash_09.ogg` |
| `hit` | `impact/impactSoft_medium_000.ogg` | `impact/impactSoft_medium_002.ogg` | `impact/impactGeneric_light_001.ogg` |
| `capture` | `impact/impactGlass_light_000.ogg` | `impact/impactGlass_light_002.ogg` | `impact/impactBell_heavy_004.ogg` |
| `node_lost` | `impact/impactPunch_medium_001.ogg` | `impact/impactPlate_light_002.ogg` | `impact/impactGlass_heavy_000.ogg` |
| `upgrade` | `interface/confirmation_001.ogg` | `interface/maximize_006.ogg` | `interface/confirmation_003.ogg` |
| `build` | `interface/maximize_003.ogg` | `interface/maximize_008.ogg` | `interface/drop_002.ogg` |
| `laser` | `scifi/laserSmall_000.ogg` | `scifi/laserSmall_002.ogg` | `scifi/laserRetro_002.ogg` |
| `machinegoon` | `scifi/laserRetro_000.ogg` | `scifi/laserRetro_004.ogg` | `scifi/laserSmall_004.ogg` |
| `monster_launch` | `slime/splash_06.ogg` | `slime/slime_03.ogg` | `scifi/slime_000.ogg` |
| `monster_stomp` | `slime/slime_09.ogg` | `impact/impactSoft_heavy_000.ogg` | `impact/impactPunch_heavy_002.ogg` |
| `monster_take` | `slime/slime_13.ogg` | `slime/slime_10.ogg` | `slime/splash_14.ogg` |
| `monster_fall` | `slime/splash_02.ogg` | `slime/splash_08.ogg` | `slime/splash_12.ogg` |
| `skill` | `scifi/forceField_000.ogg` | `scifi/forceField_002.ogg` | `scifi/doorOpen_002.ogg` |
| `relay_warning` | `scifi/doorClose_000.ogg` | `scifi/impactMetal_004.ogg` | `scifi/doorClose_002.ogg` |
| `relay_switch` | `scifi/doorOpen_000.ogg` | `scifi/doorOpen_001.ogg` | `scifi/impactMetal_002.ogg` |
| `fall` | `slime/splash_10.ogg` | `slime/splash_15.ogg` | `slime/splash_06.ogg` |
| `collapse_warning` | `interface/error_004.ogg` | `interface/error_008.ogg` | `interface/tick_004.ogg` |
| `collapse` | `scifi/explosionCrunch_000.ogg` | `scifi/lowFrequency_explosion_001.ogg` | `scifi/impactMetal_003.ogg` |
| `last_stand` | `scifi/engineCircular_000.ogg` | `scifi/engineCircular_003.ogg` | `scifi/forceField_004.ogg` |
| `very_last_stand` | `scifi/engineCircular_002.ogg` | `scifi/engineCircular_004.ogg` | `scifi/lowFrequency_explosion_000.ogg` |
| `eliminated` | `interface/minimize_005.ogg` | `interface/minimize_006.ogg` | `interface/error_005.ogg` |
| `win` | `interface/confirmation_002.ogg` | `interface/confirmation_004.ogg` | `interface/maximize_005.ogg` |

## Set 2 - Sci-fi + goo

UI = Kenney interface, lasers / beeps = OpenGameArt 60 CC0 sci-fi (unnamed files, picked by length and group), impacts = Kenney impact, goo = slime pack.

| Event | alt 1 | alt 2 | alt 3 |
|---|---|---|---|
| `send` | `slime/slime_05.ogg` | `slime/slime_16.ogg` | `slime/splash_09.ogg` |
| `fight` | `slime/slime_14.ogg` | `slime/slime_10.ogg` | `slime/slime_07.ogg` |
| `hit` | `impact/impactGeneric_light_000.ogg` | `impact/impactGeneric_light_002.ogg` | `impact/impactGeneric_light_004.ogg` |
| `capture` | `interface/confirmation_003.ogg` | `scifi60/sfx_04a.ogg` | `scifi60/sfx_05a.ogg` |
| `node_lost` | `interface/error_007.ogg` | `scifi60/sfx_03a.ogg` | `interface/error_002.ogg` |
| `upgrade` | `scifi60/sfx_14a.ogg` | `scifi60/sfx_14b.ogg` | `scifi60/sfx_15a.ogg` |
| `build` | `interface/maximize_007.ogg` | `scifi60/sfx_10a.ogg` | `scifi60/sfx_17a.ogg` |
| `laser` | `scifi60/sfx_07a.ogg` | `scifi60/sfx_07b.ogg` | `scifi60/sfx_07c.ogg` |
| `machinegoon` | `scifi60/sfx_09a.ogg` | `scifi60/sfx_09b.ogg` | `scifi60/sfx_20b.ogg` |
| `monster_launch` | `slime/slime_03.ogg` | `slime/splash_12.ogg` | `slime/slime_13.ogg` |
| `monster_stomp` | `impact/impactPunch_heavy_002.ogg` | `impact/impactPunch_heavy_000.ogg` | `impact/impactSoft_heavy_001.ogg` |
| `monster_take` | `slime/slime_08.ogg` | `slime/slime_15.ogg` | `slime/slime_06.ogg` |
| `monster_fall` | `slime/splash_14.ogg` | `slime/splash_13.ogg` | `slime/splash_03.ogg` |
| `skill` | `scifi60/sfx_13a.ogg` | `scifi60/sfx_13b.ogg` | `scifi60/sfx_21a.ogg` |
| `relay_warning` | `scifi60/sfx_20a.ogg` | `scifi60/sfx_20c.ogg` | `scifi60/sfx_22a.ogg` |
| `relay_switch` | `scifi60/sfx_12a.ogg` | `scifi60/sfx_12b.ogg` | `scifi60/sfx_10b.ogg` |
| `fall` | `slime/splash_15.ogg` | `slime/splash_10.ogg` | `slime/splash_06.ogg` |
| `collapse_warning` | `scifi60/sfx_02a.ogg` | `scifi60/sfx_02b.ogg` | `scifi60/sfx_02c.ogg` |
| `collapse` | `impact/impactPlate_heavy_000.ogg` | `impact/impactPlate_heavy_002.ogg` | `scifi60/sfx_08a.ogg` |
| `last_stand` | `scifi60/sfx_18b.ogg` | `scifi60/sfx_16a.ogg` | `scifi60/sfx_01a.ogg` |
| `very_last_stand` | `scifi60/sfx_18a.ogg` | `scifi60/sfx_16b.ogg` | `scifi60/sfx_06b.ogg` |
| `eliminated` | `interface/minimize_004.ogg` | `scifi60/sfx_05c.ogg` | `scifi60/sfx_03b.ogg` |
| `win` | `scifi60/sfx_06.ogg` | `scifi60/sfx_01b.ogg` | `interface/maximize_004.ogg` |

## Set 3 - Digital bleeps

Kenney digital-audio for most events, Kenney impact for hits, slime pack for goo.

| Event | alt 1 | alt 2 | alt 3 |
|---|---|---|---|
| `send` | `slime/bubble_02.ogg` | `slime/bubble_03.ogg` | `slime/slime_16.ogg` |
| `fight` | `slime/slime_01.ogg` | `slime/slime_04.ogg` | `slime/slime_11.ogg` |
| `hit` | `impact/impactSoft_medium_001.ogg` | `impact/impactSoft_medium_003.ogg` | `impact/impactSoft_medium_004.ogg` |
| `capture` | `digital/powerUp5.ogg` | `digital/powerUp6.ogg` | `digital/powerUp9.ogg` |
| `node_lost` | `digital/phaserDown2.ogg` | `digital/phaserDown1.ogg` | `digital/phaserDown3.ogg` |
| `upgrade` | `digital/powerUp2.ogg` | `digital/powerUp7.ogg` | `digital/powerUp10.ogg` |
| `build` | `digital/highUp.ogg` | `digital/powerUp4.ogg` | `digital/twoTone2.ogg` |
| `laser` | `digital/laser5.ogg` | `digital/laser3.ogg` | `digital/zap1.ogg` |
| `machinegoon` | `digital/pepSound3.ogg` | `digital/phaserUp5.ogg` | `digital/phaserUp6.ogg` |
| `monster_launch` | `slime/splash_09.ogg` | `digital/phaseJump1.ogg` | `slime/splash_06.ogg` |
| `monster_stomp` | `impact/impactSoft_heavy_002.ogg` | `impact/impactSoft_heavy_004.ogg` | `digital/lowRandom.ogg` |
| `monster_take` | `slime/slime_15.ogg` | `slime/slime_08.ogg` | `digital/powerUp11.ogg` |
| `monster_fall` | `slime/splash_06.ogg` | `slime/splash_08.ogg` | `digital/spaceTrash1.ogg` |
| `skill` | `digital/phaseJump2.ogg` | `digital/phaseJump4.ogg` | `digital/phaserUp3.ogg` |
| `relay_warning` | `digital/tone1.ogg` | `digital/pepSound2.ogg` | `digital/pepSound4.ogg` |
| `relay_switch` | `digital/twoTone1.ogg` | `digital/threeTone1.ogg` | `digital/zapTwoTone.ogg` |
| `fall` | `slime/bubble_01.ogg` | `slime/splash_10.ogg` | `slime/slime_12.ogg` |
| `collapse_warning` | `digital/pepSound1.ogg` | `digital/pepSound5.ogg` | `digital/highDown.ogg` |
| `collapse` | `digital/lowDown.ogg` | `digital/spaceTrash2.ogg` | `impact/impactSoft_heavy_000.ogg` |
| `last_stand` | `digital/lowThreeTone.ogg` | `digital/zapThreeToneUp.ogg` | `digital/threeTone2.ogg` |
| `very_last_stand` | `digital/zapThreeToneDown.ogg` | `digital/zapTwoTone2.ogg` | `digital/lowThreeTone.ogg` |
| `eliminated` | `digital/highDown.ogg` | `digital/lowRandom.ogg` | `digital/spaceTrash3.ogg` |
| `win` | `digital/powerUp1.ogg` | `digital/powerUp3.ogg` | `digital/powerUp12.ogg` |

## Set 4 - Mix 2+3

Daniele (2026-09-28, "2 and 3 are my fav so far", after "set 1 and 3 are best so far"): Set 3's digital bleeps for UI / relays / skills, Set 2's sci-fi lasers / beeps plus its impacts and slime for combat; collapse warning, collapse, alarms, knock-out and the win offer both sets' files as alternates.

| Event | alt 1 | alt 2 | alt 3 |
|---|---|---|---|
| `send` | `slime/slime_05.ogg` | `slime/slime_16.ogg` | `slime/splash_09.ogg` |
| `fight` | `slime/slime_14.ogg` | `slime/slime_10.ogg` | `slime/slime_07.ogg` |
| `hit` | `impact/impactGeneric_light_000.ogg` | `impact/impactGeneric_light_002.ogg` | `impact/impactGeneric_light_004.ogg` |
| `capture` | `digital/powerUp5.ogg` | `digital/powerUp6.ogg` | `digital/powerUp9.ogg` |
| `node_lost` | `digital/phaserDown2.ogg` | `digital/phaserDown1.ogg` | `digital/phaserDown3.ogg` |
| `upgrade` | `digital/powerUp2.ogg` | `digital/powerUp7.ogg` | `digital/powerUp10.ogg` |
| `build` | `digital/highUp.ogg` | `digital/powerUp4.ogg` | `digital/twoTone2.ogg` |
| `laser` | `scifi60/sfx_07a.ogg` | `scifi60/sfx_07b.ogg` | `scifi60/sfx_07c.ogg` |
| `machinegoon` | `scifi60/sfx_09a.ogg` | `scifi60/sfx_09b.ogg` | `scifi60/sfx_20b.ogg` |
| `monster_launch` | `slime/slime_03.ogg` | `slime/splash_12.ogg` | `slime/slime_13.ogg` |
| `monster_stomp` | `impact/impactPunch_heavy_002.ogg` | `impact/impactPunch_heavy_000.ogg` | `impact/impactSoft_heavy_001.ogg` |
| `monster_take` | `slime/slime_08.ogg` | `slime/slime_15.ogg` | `slime/slime_06.ogg` |
| `monster_fall` | `slime/splash_14.ogg` | `slime/splash_13.ogg` | `slime/splash_03.ogg` |
| `skill` | `digital/phaseJump2.ogg` | `digital/phaseJump4.ogg` | `digital/phaserUp3.ogg` |
| `relay_warning` | `digital/tone1.ogg` | `digital/pepSound2.ogg` | `digital/pepSound4.ogg` |
| `relay_switch` | `digital/twoTone1.ogg` | `digital/threeTone1.ogg` | `digital/zapTwoTone.ogg` |
| `fall` | `slime/splash_15.ogg` | `slime/splash_10.ogg` | `slime/splash_06.ogg` |
| `collapse_warning` | `scifi60/sfx_02a.ogg` | `digital/pepSound1.ogg` | `digital/pepSound5.ogg` |
| `collapse` | `impact/impactPlate_heavy_000.ogg` | `impact/impactPlate_heavy_002.ogg` | `digital/lowDown.ogg` |
| `last_stand` | `digital/lowThreeTone.ogg` | `scifi60/sfx_18b.ogg` | `digital/zapThreeToneUp.ogg` |
| `very_last_stand` | `digital/zapThreeToneDown.ogg` | `scifi60/sfx_18a.ogg` | `digital/zapTwoTone2.ogg` |
| `eliminated` | `digital/highDown.ogg` | `interface/minimize_004.ogg` | `digital/lowRandom.ogg` |
| `win` | `digital/powerUp1.ogg` | `scifi60/sfx_06.ogg` | `digital/powerUp3.ogg` |

## Files and credits

`demo_sounds/<pack>/` holds only the files the sets use, with their original names; `demo_sounds/CREDITS.txt`
lists each pack, its URL and licence (all CC0). Packs: `interface` Kenney Interface Sounds, `impact` Kenney Impact
Sounds, `scifi` Kenney Sci-Fi Sounds, `digital` Kenney Digital Audio, `scifi60` OpenGameArt 60 CC0 Sci-Fi SFX,
`slime` OpenGameArt 40 CC0 water / splash / slime SFX.

Not for release: the Web preset exports all resources, so merging this branch as-is would ship `demo/` and
`demo_sounds/`; exclude them (or pick the final files into the game's own folder) when sound goes in for real.
