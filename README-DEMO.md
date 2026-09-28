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
| TAB / Shift+TAB | music: select the slot |
| [ / ] | music: the selected slot's track (all 15; BATTLE 2 / 3 and VERY LAST STAND also (off)) |
| P | music: play the selected slot now (preview; P again returns to the match's music) |
| H | music: hold the MENU track |
| N | music on / off |
| , / . | music volume (2 dB steps) |

The match restarts by itself 5 s after it ends (8 s with music on, so the stinger plays out). The overlay (top left) shows the set and alternate and the last 6
sounds as `event  aN -> pack/file.ogg`: name the line you like or dislike (for example "set 4 capture a2").
An event with fewer than 3 files wraps round (the line says which alternate actually played).

## Mix

Every number is in one table, `SOUND`, at the top of `demo/sound_demo.gd` (to copy into rules.gd's SOUND block).
Levels are against the music at 0 dB (Daniele, 2026-09-28: "the sounds are too overpowering vs the background
music"): the frequent sounds (send / fight / hit / machinegoon) at -12 dB, laser / fall / relays -11, skills, builds and
monsters -10, collapse / knock-out -9, capture / node lost / Last Stand / win -8. Every sound fades in over 20 ms and
out over a 250 ms tail (at most 40 % of a short file); a repeat of the same event crossfades the earlier one out
(150 ms) instead of restarting it; 12 voices, and when all are busy a new sound is dropped except win / Last Stand /
Very Last Stand / eliminated / collapse, which fade the oldest one out (100 ms). The same event plays at most every
0.2-0.45 s (alarms 1 s, win 2 s). Long files are cut with the same tail (engineCircular alarms 1.8-2.2 s, digital
lasers 0.6 s, ...). Capture, Last Stand, Very Last Stand and win duck the music -2 dB (0.3 s in, 0.5 s held, 0.8 s out).

## Music

Cyberpunk Music Pack by SmellyCatCafe (smellycatcafe.itch.io), bought by Daniele (free and commercial use, credit
appreciated). 15 tracks, OGG 96 kbps, in `demo_music/`. **Not in git** (this repository is public and the pack is
paid): copy the pack's 15 OGG files into `demo_music/` with their names (`Boss Battle.ogg` ... `Synth Syndicate.ogg`),
then open the project once in the editor (or run `--headless --import`). Without them the demo runs silent of music.

| Slot | Starting pick | When |
|---|---|---|
| MENU | Cyber Sunrise | the first 8 s of every match (a menu preview), or while H holds it |
| BATTLE 1 / 2 / 3 | Drone Patrol, Neon Street, Synth Syndicate | the battle playlist, crossfading (2 s) at each track's end |
| LAST STAND | Midnight Hack | crossfades in (1 s) when Last Stand starts |
| VERY LAST STAND | Boss Battle | the same at Very Last Stand ((off): Last Stand's track goes on) |
| VICTORY | Ending Theme | stinger when seat A (the HUD's seat) wins: the first 7 s, the last 1.5 s fading |
| DEFEAT | Game Over | stinger when anyone else wins, or a draw |

Crossfades (equal power): 0.5 s from silence, 1.5 s MENU -> BATTLE, 1 s into Last Stand, 2 s between playlist
tracks and when a single-track slot loops, 0.8 s for a new pick of the slot that is playing, 0.4 s into a stinger.
The overlay's music panel (top right) shows every slot's pick (`>` the selected slot, `*` the one playing) and the
track playing now with its position. Picks, volume and on / off survive R and the automatic restart.

Verification flags (after `--`): `--demo-log` (print every sound), `--demo-cycle=N` (next set every N s),
`--demo-speed=1..3`, `--demo-ff=S` (silent fast-forward to S s of match time), `--demo-quit=S`,
`--demo-shot=<png>@<s>`, `--demo-map=res://maps4/...json`, `--demo-mode=FFA4|2v2`, `--demo-ai=Standard|Veteran`,
`--demo-track-len=S` (treat every music track as S s long), `--demo-keys=12:Tab,13:BracketRight` (press keys at those
seconds).

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
