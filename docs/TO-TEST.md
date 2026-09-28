# To test - v0.20.6 "Alpha 20" (Daniele, on the phone and with a second player)

Everything below passed the headless suites and desktop renders only. Nothing was tried on a real phone or across two
networks. Close and reopen the home-screen app after a publish.

Live build: https://talos91.github.io/ooza-syndicate-v2/

## 0.21.12 (domain, taps, loading screen)
- [ ] **https://oozesyndicate.com** on the phone (re-add the home-screen app from the new address); the loading screen.
- [ ] **One tap** opens every menu item; pages open quickly; BACK from LEADERBOARD / PROFILE / HISTORY goes back.
- [ ] **Online** on the new server address (rooms.oozesyndicate.com); Google sign-in on the new domain.
- [ ] **Wardrobe**: skins on their base, monsters in the army's colour.

## 0.21.11 (names online)
- [ ] **Online with your girlfriend**: both names in the lobby, VERSUS, the chips and the results; chat shows names.

## 0.21.10 (emblems v2, final art)
- [ ] **Emblems**: the new marks on every screen and on the in-match badges - nothing old left; readable at badge size on the phone.
- [ ] **HOME / PLAY / VERSUS** art on the phone: headline readable over the bright wallpapers.

## 0.21.9 (sound, callouts, names, co-op AI)
- [ ] **Sound** on the phone: first tap unlocks it; SOUND ON / OFF + VOLUME in SETTINGS and PAUSE work live; nothing too loud / spammy.
- [ ] **Callouts**: monster incoming (and the edge arrow), forge, handover; skill refusal above the slot; Last Stand line pulse.
- [ ] **Your name** on VERSUS and the results.
- [ ] **Co-op**: 2v2 with an AI ally vs AI - does the enemy team feel coordinated but beatable?

## 0.21.8 (telemetry, privacy)
- [ ] **First launch**: the privacy notice (in the EU it starts OFF); SETTINGS > PRIVACY and ACCOUNT > PRIVACY show the switch.
- [ ] **DELETE ACCOUNT** on a throwaway guest: gone from the leaderboard; the device's progress stays.

## 0.21.7 (room limits)
- [ ] **Online**: leave a room idle in the lobby - the 1-minute notice, then it closes at 10 min; a running round never closes.

## 0.21.6 (iPhone fit)
- [ ] **iPhone / notch phone**: nothing under the notch or home bar on HOME, SETUP (DEPLOY), SETTINGS (DONE), results; taps feel >= a fingertip.
- [ ] **A fresh browser (or cleared site data)**: pick a skin on first launch - it shows (the pack downloads).

## 0.21.5 (the UI pass)
- [ ] **Every screen on the phone**: HOME, PLAY -> SETUP -> RIVALS -> VERSUS -> match -> results; ARMIES / wardrobe; CAMPAIGN (city map + CARDS);
      ONLINE -> JOIN ROOM (the code field) -> LOBBY; SETTINGS; ACCOUNT. Anything cut off, too small to tap, or under the notch / home bar?
- [ ] **Pause and results**: pause, win, lose, match details; CONTINUE / RETRY.
- [ ] **Online**: a host that drops - CONNECTION INTERRUPTED with the countdown, then back or LEAVE MATCH.

## 0.21.4 (online hardening, tutorial rotation)
- [ ] **Online**: a server room from a phone on mobile data and a second player - joins, plays, rematch as before.
- [ ] **Tutorial on a phone**: start the first-launch tour holding the phone upright, then turn it - the card fits landscape.

## 0.21.3 (net-5: smaller online updates)
- [ ] **Online on mobile data**: a server room over 4G - as smooth as 0.21.2 or smoother; CONNECTION shows ~20 updates/s.

## 0.21.2 (monster colours)
- [ ] **Monsters**: launch a monster (and a skin alternate) - teal VEX, magenta NULL, green BLOOM, orange EMBER, gold SOLAR, not grey; on the phone too.

## 0.21.1 (light models on phones, quality skins, iPhone fullscreen, server host)
- [ ] **iPhone home-screen app**: landscape fills the whole screen (no black band); HUD clear of the notch / home bar.
- [ ] **Phone look**: the light models look right (vats, Machinegoon, monsters, skins); is the phone cooler than 0.21.0?
- [ ] **Desktop**: models sharpen to the full ones a moment after a match starts (the HD packs load once).
- [ ] **Skins**: the new quality skins (plinths, lit caps, neon rings) in ARMIES and in a match; vat drops leave the tanks.
- [ ] **Online**: a server room with a stall - smoother catch-up, CONNECTION shows "buffer".

## 0.21.0 (optimization part 1)
- [ ] **Phone heat / fps**: play a full match; is the phone cooler, is PAUSE's fps steadier (target 45)?
- [ ] **Look**: same as before, sharper on the phone (no blocky edges).
- [ ] **OPTIONS > PERFORMANCE**: try LOW RES on a weak phone; FPS 30 / 60.

## 0.20.13
- [ ] **Last Stand start**: no big centre banner; a short notification top left.
- [ ] **Notifications** are top left and readable.
- [ ] **Co-op**: send troops to your ally's node - a ring in YOUR colour appears on her node and your "+N" is coloured.
- [ ] **Leaderboard** shows your own row; a browser-hosted room says UNRANKED.

## 0.20.12
- [ ] **Last Stand**: drops come ~20 s apart on most maps (a bit faster on big ones); the badge countdowns match.
- [ ] **INSTALL THE GAME** on MAIN in a phone browser (not in the installed app): the steps fit your phone.
- [ ] **Rematch** online: both tap REMATCH; the screen says who is ready; a new round starts (AI fills extra seats).
- [ ] **PAUSE during an online match** shows a CONNECTION line; screenshot it when you feel stutter.

## 0.20.6 (HUD declutter)
- [ ] **No number over moving lines**; node badges still show counts.
- [ ] **Notifications** only top right, small, at most 2; none for your own sends or captures.
- [ ] **Capture feedback**: "+ CAPTURED" / "LOST" rises from the node.
- [ ] **Last Stand** line stays under the top bar and never covers the map.
- [ ] **Dr. Vesk** in the tutorial reads funnier.

## 0.20.5 accounts (guest, email link, leaderboard, match history)
- [ ] **ACCOUNT** (PROFILE > ACCOUNT): it should say GUEST ACCOUNT after a moment online. RENAME yourself.
- [ ] **Add Google** (0.20.8, no email): ACCOUNT > ADD GOOGLE, sign in - you come back SIGNED IN WITH GOOGLE with the same
      progress (while the Google app is in Testing, your account must be a Test user).
- [ ] **Another device**: on a second phone or browser, ACCOUNT > SIGN IN WITH GOOGLE with the same Google account - that
      device should now show your level, SCRAP and unlocks.
- [ ] **LEADERBOARD**: play an online match against another person (server room) and win - you should appear.
- [ ] **MATCH HISTORY** (PROFILE > HISTORY): your recent matches with the right map, mode, time, factions and result;
      online ones tagged ONLINE.

## 0.20.4 campaign preview (VEX, placeholder maps)
- [ ] **MAIN > CAMPAIGN**: the Dockside diorama - 01 open and pulsing, the rest locked. Does the city read? Are the
      mission platforms easy to tap on the phone?
- [ ] **A mission**: tap 01, read the card, PLAY. The briefing waits for START; the objective line under the clock
      moves (e.g. "1 left"), the par clock counts down, the optional objective ticks or crosses as you play.
- [ ] **Stars** ("gotta see if make sense"): win once fast and once slow - do ★ / ★★ / ★★★ feel right? 3 stars + the
      optional objective should count up +150 SCRAP once; a second perfect run says "already taken".
- [ ] **Back on the map**: the new bridge extends to the next mission, the stars pop on the won platform. Win 02 and
      tap the relay beside it: the deck swings over to the side mission Overtime.
- [ ] **District done**: win 03 - Dockside drops ring by ring into the void, the camera moves to The Exchange.
      (Too long? Tap skips it.)
- [ ] **Mind the Gap** (relay puzzle) and **Overtime** (hold until 3:00): fun? too hard / easy vs the AI levels set?
- [ ] **Tone**: the handler and rival lines - funny, or too much?
- [ ] Missions marked IN DEVELOPMENT (04, s2, s3) can't be played; CONTINUE skips them.

## 0.20.3 (first online playtest fixes)
- [ ] **Online movement is smooth** in a server room (you + a second phone, one on mobile data): no stutter or jumps.
- [ ] **Monster launch:** when your hub's monster is ready, tap the hub (or the monster / icon) -> the reach lights up -> tap a
      lit node -> it goes. Tap elsewhere to cancel. A charging hub still opens its inspector.
- [ ] **Machinegoon** looks as big as a T2 vat and its goo arcs onto the enemy line; Spitter and Pepperbox skins (ARMIES >
      COSMETICS) the same size.
- [ ] **Menu on her phone** (0.20.2 fix): open the app upright, then rotate - the buttons stay normal size.

## Carried over

## 0.20.1 progression (SCRAP, SYNDICATE CHIPS, levels, challenges, unlocks)
- [ ] **After a match** (vs Veteran or Expert): the results screen shows MATCH FINISHED · WIN · FIRST WIN OF THE DAY,
      the SCRAP counting up, and the XP bar filling (a LEVEL UP flash when you cross a level). Vs Casual / Training it
      should say "XP only".
- [ ] **MAIN**: the card top right (LEVEL, XP bar, SCRAP, CHIPS) opens PROFILE; CHALLENGES under it says how many are
      ready to claim.
- [ ] **PROFILE**: your level, both balances, and each faction's PLAYED / WON with the vat bar (x / 25 wins).
- [ ] **CHALLENGES**: play a few matches, watch the bars move, CLAIM one (the SCRAP counts up on the card), try one
      REROLL on a daily. Do the challenges feel doable in a day / a week?
- [ ] **Tutorial**: replay a lesson you haven't finished - LESSON COMPLETE should count up +140 SCRAP (a lesson
      already finished pays nothing again).
- [ ] **Locks preview**: OPTIONS > TEST SWITCH · LOCKS: ON, then ARMIES - locked skills show LOCKED and 1 250 SCRAP;
      tap one for the UNLOCK sheet and buy it if you have the SCRAP. COSMETICS shows UNLOCK on locked looks. Switch it
      back (or reload) and everything is open again. Tell us when the locks should go live for everyone.
- [ ] **Numbers**: a skill costs 1 250 SCRAP; ~5 matches a day plus the dailies pays ~400. Does that pace feel right?

## 0.19.2 fixes (from your 0.19.1 playtest)
- [ ] **D-11..D-16**: play each and tell us the largest map that still plays well on your phone.
- [ ] **Monster launch**: a pulsing icon appears over a ready hub; tap it, its reach (nodes within 3 decks)
      lights up, tap a lit node to launch - check it reads clearly and the old LAUNCH-from-inspector way
      still works too.
- [ ] **Machinegoon look**: smaller, and its muzzle now sits above the deck so the stream arcs down onto the
      line instead of firing up through the enemy from below.
- [ ] **Skills**: every active/map skill starts a match already on cooldown (no free first cast); Demolish's
      deck now falls 1.5 s after the cast; Surge should feel noticeably faster (speed + door rate) both
      moving down a bridge and pouring into a node.
- [ ] **Skill dock**: the three slots are now bordered/labelled by type (blue/green/orange); on your phone the
      1/2/3 shortcut badges should be gone.
- [ ] **SETUP**: pick a rival faction per seat (not one for the whole match); the DIFFICULTY row should look
      evenly spaced; the FACTION colour chip should now show an emblem and a caption while picked.
- [ ] **Top bar**: should stay fixed and centred through a match (clock in the middle, your chip first, out
      seats greyed, teammates grouped) - tell us if it still moves or feels wrong for multiplayer.
- [ ] **YOU'RE OUT panel**: lose your last node/line/monster/stored troops and you should get SPECTATE / MAIN
      MENU instead of being dropped straight out.
- [ ] **ARMIES > COSMETICS**: skins should show a turning 3D preview; BACK should return properly; check the
      new CORE · ALL FACTIONS row for TERRITORY NEON / GOO (moved out of OPTIONS).
- [ ] **Skins on the web build**: should now actually download and apply (the gzip bug is fixed) instead of
      failing silently.
- [ ] **Graduate vat v2**: ivory / brass look with a bigger crown and a star-and-laurel crest - does it read
      well now?
- [ ] Spelling: everything should now read **Machinegoon**, not Machingoon.

## Carried over from 0.19.0 (still not confirmed)

### Structures 2.1
- [ ] **Laser tower** (relay nodes, replaces the three cannon tiers): one tier, a 2 s burst then 2 s recharge
      - check it no longer out-kills a full door of reinforcements.
- [ ] **Monster hub**: once launched (see the new icon flow above) it should reach 3 bridges, kick every line
      off the decks and platforms it crosses (friend or foe), take an empty end node or drop a tier off a
      friendly one, and only die to a fall.
- [ ] **Fortify's Anchor** halves both a Laser tower's and a Machinegoon's kills; an Echo Split jam stops
      either.
- [ ] **Relay controls**: double-tapping an owned relay fires its SWITCH directly; the SWITCH button, relay
      badges and relay towers should all read more clearly when ready, cooling down or under warning.
- [ ] **Relay-outcome preview**: hovering or holding SWITCH, or any relay warning, should show which decks are
      about to vanish (dashed red) and which are about to appear (ghosted), plus a turn arrow on a rotation.

### Teams
- [ ] **Shared garrisons**: allied troops sent to a node count toward its cap alongside the owner's; an
      attacker fights the whole shared garrison at once.
- [ ] **Handover**: when the owner's own troops on a shared node hit zero, the ally with the largest garrison
      takes over (ties go to whoever arrived first) - the node keeps its tier and structure but the old
      owner's construction is cancelled.
- [ ] **EJECT** sends every ally's stored troops back out to their own nearest node.
- [ ] **Halo tiers**: an ally's ring round a shared node should brighten as its share of the cap grows past
      25 % and 75 %.

### Skills
- [ ] **ARMIES** menu: pick an active + map skill per faction; the pick is saved after closing the game.
- [ ] **Dock** in a match: tap a slot, valid targets light up, tap one; tap the slot again to cancel; the
      ultimate charges (~120 s). Every skill's effect shows on screen.
- [ ] **ABILITIES ON / OFF** in SETUP and the lobby.
- [ ] The AI casts skills and it feels fair; Veteran / Expert should now play harder against a forge.
- [ ] **Ghost Line** looks translucent to you, real to the opponent (online).

### Online (two phones)
- [ ] **Room server**: creating or joining a room should connect through the room relay server (the only
      transport; the PeerJS rooms are gone since Alpha 21) - check it still works on a strict/mobile
      network that failed before.
- [ ] Both players see the **same colours**; each picks their own in the lobby, plus their ARMIES cosmetics
      (including the new per-faction rival picks and TERRITORY skin).
- [ ] **JOIN TEAM** works: you and your girlfriend on one team in 2v2, AI filling the rest; try the team rules
      (shared garrison, handover, EJECT) online.
- [ ] Skills, Machinegoon/Laser/Monster hub builds and monster launches by a guest all work; enemy-cast toasts
      appear.
- [ ] The host tab still needs to stay in front - background it and confirm the match still freezes (stage 2
      of the server work fixes this, not built yet).

### Look
- [ ] **New models**: Machinegoon (three tiers, now at the smaller scale), Laser tower, Monster hub and
      monster (one look per faction).
- [ ] **Minions**: the new full-colour models should read clearly at a distance, not just up close.
- [ ] Glow effects (relay towers, laser, skills) don't tank the frame rate on the phone.

### Phone UI
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
- The tutorial itself: still "veeeeery unpolished and messy" - a dedicated tutorial session is next (0.19.3).
