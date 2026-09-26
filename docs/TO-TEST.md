# To test - v0.19.0 "Alpha 19" (Daniele, on the phone and with a second player)

Everything below passed the headless suites and desktop / phone-emulation renders only. Nothing was tried on a
real phone or across two networks. Tick what works, note what doesn't; the next session starts from this file.

Live build: https://talos91.github.io/ooza-syndicate-v2/ (reload twice - PWA cache).

## Core rules
- [ ] **New vat caps** 30/60/120/200; homes start at T1 with 1 unit; neutrals start at half their tier's cap
      and regrow to it.
- [ ] **Owned vats stop at T3** (no T3 -> T4 upgrade); a **special node is always T4**; conquest never
      downgrades a T4; conquering a vat or Machingoon still drops it one tier.
- [ ] **Forge** now protects too: the owner's garrisons take 20 % less damage on top of the +50 % attack.
- [ ] **"Lines keep you alive"** - losing your last node no longer eliminates you if you still have a line, a
      monster or stored allied troops out.
- [ ] **7:00 follows the Very Last Stand**: the owner of the last standing platform wins; a still-neutral
      last platform is a DRAW with a call-out line; the Very Last Stand still runs at 6:00 with LAST STAND
      OFF.
- [ ] A **remote console** that falls in the Last Stand freezes its decks instead of snapping to the first
      state.
- [ ] **Last Stand danger triangle** - the fall warning is now a symbol over the platform's rim, not a red
      badge; it shouldn't cover play.
- [ ] **Last Stand camera** has no zoom limit any more - it should keep closing in on the winner.

## Structures 2.1
- [ ] **Machingoon** (common nodes, in place of the vat): builds T1-T3, streams goo at the nearest enemy line
      on its decks, produces nothing while it holds one; swapping to/from a vat keeps the tier.
- [ ] **Laser tower** (relay nodes, replaces the three cannon tiers): one tier, a 2 s burst then 2 s recharge
      - check it no longer out-kills a full door of reinforcements.
- [ ] **Monster hub** (relay nodes, one per player): launch a monster by dragging from the hub; it should
      reach 3 bridges, kick every line off the decks and platforms it crosses (friend or foe), take an empty
      end node or drop a tier off a friendly one, and only die to a fall.
- [ ] **Fortify's Anchor** halves both a Laser tower's and a Machingoon's kills; an Echo Split jam stops
      either.
- [ ] **Relay controls**: double-tapping an owned relay fires its SWITCH directly (no more opening the
      inspector first); the SWITCH button, relay badges and relay towers should all read more clearly when
      ready, cooling down or under warning.
- [ ] **Relay-outcome preview**: hovering or holding SWITCH, or any relay warning, should show which decks are
      about to vanish (dashed red) and which are about to appear (ghosted), plus a turn arrow on a rotation.

## Teams
- [ ] **Shared garrisons**: allied troops sent to a node count toward its cap alongside the owner's; an
      attacker fights the whole shared garrison at once.
- [ ] **Handover**: when the owner's own troops on a shared node hit zero, the ally with the largest garrison
      takes over (ties go to whoever arrived first) - the node keeps its tier and structure but the old
      owner's construction is cancelled.
- [ ] **EJECT** sends every ally's stored troops back out to their own nearest node.
- [ ] **Halo tiers**: an ally's ring round a shared node should brighten as its share of the cap grows past
      25 % and 75 %.

## Skills
- [ ] **ARMIES** menu: pick an active + map skill per faction; the pick is saved after closing the game.
- [ ] **Dock** in a match: tap a slot, valid targets light up, tap one; tap the slot again to cancel; the
      ultimate charges (~120 s). Every skill's effect shows on screen.
- [ ] **ABILITIES ON / OFF** in SETUP and the lobby.
- [ ] The AI casts skills and it feels fair; Veteran / Expert should now play harder against a forge.
- [ ] **Ghost Line** looks translucent to you, real to the opponent (online).

## Online (two phones)
- [ ] **Room server**: creating or joining a room should connect through the new room relay server by
      default (no PeerJS peer-to-peer unless the URL has `?relay=peerjs`) - check it still works on a
      strict/mobile network that failed before.
- [ ] Both players see the **same colours**; each picks their own in the lobby, plus their ARMIES cosmetics.
- [ ] **JOIN TEAM** works: you and your girlfriend on one team in 2v2, AI filling the rest; try the new team
      rules (shared garrison, handover, EJECT) online.
- [ ] Skills, Machingoon/Laser/Monster hub builds and monster launches by a guest all work; enemy-cast toasts
      appear.
- [ ] The host tab still needs to stay in front - background it and confirm the match still freezes (stage 2
      of the server work fixes this, not built yet).

## Look
- [ ] **New models**: Machingoon (three tiers), Laser tower, Monster hub and monster (one look per faction).
- [ ] **Cosmetics** (ARMIES > COSMETICS): pick a skin per structure family per faction; check it shows in
      your own match and to other players online.
- [ ] **Skins on the web build**: the first time a skin is actually needed it should download its own
      `skins.pck` in the background (default look shown meanwhile) rather than stalling the match.
- [ ] **Minions**: the new full-colour models should read clearly at a distance, not just up close.
- [ ] **YOUR COLOUR** chips (SETUP and lobby): solid hexagon chips, no text; FACTION is a 5-colour wedge; the
      pick gets a white ring and grows; hover/long-press for the colour's name.
- [ ] Glow effects (relay towers, laser, skills) don't tank the frame rate on the phone.

## Phone UI
- [ ] Every button easy to tap (44 pt); nothing cut off; tall pages scroll; the Debug panel scrolls.
- [ ] Map filter TYPE now reads FAST / FORTRESS / STANDARD - check the labels make sense at a glance.
- [ ] **MAIN MENU** remembers the last map played; after a match, **REMATCH** offers a random other map that
      still fits every human player.

## Decisions still open (OPEN-QUESTIONS)
- Cosmetics: per faction or global unlocks; unlock rules beyond "wins with a race" and "finish the tutorial".
- The game's name: Ooze Syndicate, or Ooze Downfall.
- Resetting a guest's online settings (mode, Last Stand, enemy counts, tuning) on leaving a room.
- More Alpha 11 maps beyond the four classics; asymmetric maps; a map revision pass (Daniele: "all current
  maps needs revision") - M-01's relay housing blocking its hub's gate is part of that.
- A lighter kit, phone lighting and a telemetry cap - proposed, not approved.
- Monetisation stays parked.
