# To test - v0.18.9 (Daniele, on the phone and with a second player)

Everything below passed the headless suites and desktop / phone-emulation renders only. Nothing was tried on a
real phone or across two networks. Tick what works, note what doesn't; the next session starts from this file.

Live build: https://talos91.github.io/ooza-syndicate-v2/ (reload twice - PWA cache).

## Core rules
- [ ] **Relay fall rule** - every relay kind: the 1 s warning leaves the bridge walkable; when it moves, everything
      on it falls (retract no longer pulls units in); the rest of the order pours off the edge; a line straddling it
      splits and its front walks on.
- [ ] **Waterfall pour** - no stop at the lip, one continuous fall, not visibly more bodies than units lost.
- [ ] **Last Stand from 3:00** - drops start at a random player's corner, then the opposite one, then the others.
- [ ] **Very Last Stand at 6:00** - platforms fall one by one, evenly spaced, last one at 7:00; only 1-2-connection
      platforms; never an island. Faster check: Debug tools on, or wait from 6:00.
- [ ] **Neutral villages regrow** at their vat's speed after being chipped.
- [ ] **Balance** - neutrals feel costlier (12/16/32/64); Ember / Bloom less dominant. Debug > Balance LEGACY to compare.
- [ ] **Cannon** kills the front of an incoming line; the beam may reach a bit past range to finish a burst.
- [ ] **Tapping an enemy or neutral node** does nothing (no empty ring).

## Skills
- [ ] **ARMIES** menu: pick an active + map skill per faction; the pick is saved after closing the game.
- [ ] **Dock** in a match: tap a slot, valid targets light up, tap one; tap the slot again to cancel; the ultimate
      charges (~120 s). Every skill's effect shows on screen.
- [ ] **ABILITIES ON / OFF** in SETUP and the lobby.
- [ ] The AI casts skills and it feels fair.
- [ ] **Ghost Line** looks translucent to you, real to the opponent (online).

## Online (two phones)
- [ ] Both players see the **same colours**; each picks their own in the lobby.
- [ ] **JOIN TEAM** works: you and your girlfriend on one team in 2v2, AI filling the rest.
- [ ] Skills cast by a guest work; enemy-cast toasts appear.

## Look
- [ ] **Vats** read at a glance (owner ring, glass tanks, tier by shape); structures look like one family.
- [ ] **Abyss fog** - pillars sink into it; falling units and platforms fade instead of vanishing.
- [ ] **Units drop out of the vat tanks** and join the line.
- [ ] **Forge surge** plays when a forge finishes.
- [ ] **TERRITORY: GOO** (OPTIONS) - goo on owned ground, units in race colour; check the frame rate on the phone.
- [ ] Glow effects (laser, skills, fog) don't tank the frame rate on the phone.

## Phone UI
- [ ] Every button easy to tap (44 pt); nothing cut off; tall pages scroll; the Debug panel scrolls.
- [ ] Known small spots: ARMIES card text; the CHANGE button on the SETUP / lobby card.

## Decisions still open (OPEN-QUESTIONS)
- Map filter TYPE labels BRAWL / SIEGE / CORE (pack group names) - relabel FAST / FORTRESS / STANDARD?
- AI keeps 6 units on relay nodes; every new forge plays the surge; two rings on rotation platforms.
