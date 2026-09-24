# Ooze Syndicate 2.0 - changelog

Versioned from **2026-09-25** (Daniele: "start versioning and have it in the interface and a
changelog"). The version shows bottom-right in the HUD and on the title screen. Numbering is
retroactive for the same-day passes before this file existed - each one bumps the minor number.
See `docs/BUILD-LOG.md` for the full narrative record and design rationale behind every change.

## 0.7.0 - 2026-09-25

- **Relay housings, for real.** Relay nodes now show their actual modelled tower per kind
  (`Relay_Rotation_Tower`, `Relay_Retract`, `Relay_Switch_Hub`, `Relay_Remote`) on a rim-mounted
  ledge (`Relay_Mount`), with `Socket_Attachment` in the middle instead of a vat (GAME-RULES sec6:
  a relay node has no vat) - previously every node, including relays, rendered as a plain platform
  with a placeholder T1 vat. Rotation hubs also use `Platform_Rotation` instead of the standard
  platform. `retracts` and remote-state (`m1`/`m2`) decks use their own `Deck_Retract`/`Deck_Remote`
  models instead of the generic deck module.
- **Toast feedback on every tap** (Alpha 11 convention): tapping an owned node always says
  something - what got built, why an upgrade can't happen yet, or that there's nothing to build
  here - instead of silently doing nothing. Fixes the "I click and nothing happens" report, which
  was two real gaps: relay nodes had no attachment socket to click at all, and a tap that found
  nothing eligible gave no feedback either way.
- The build popup is now styled as a ring (rounded panel, cyan border) closer to Alpha 11's
  circular inspector, instead of a plain rectangle.
- Versioning: this file, plus the version number in the HUD and the title screen.

## 0.6.0 - 2026-09-25

- Transit fighting (an order passing through a node that isn't its target) now only triggers at an
  ENEMY-owned node - a neutral one is a free glide-through.
- The shield: every owned node has a shield worth 20% of its current garrison, regenerating from
  "excess minions" over time. A transiting force fights the shield, never the real garrison -
  only an actual arrival ever touches that. If the shield breaks, the specific deck the attacker
  used is destroyed for good ("the bond with the other node disappears").

## 0.5.0 - 2026-09-25

- A relay-controlled or retracting deck now visibly disappears while closed and reappears while
  open - relay cycling is something you can see, not just a routing change.
- Replaced the unreliable engine double-click with a manual tap timer and the Alpha 11 convention:
  single-tap an empty attachment slot to choose Cannon or Forge; double-tap upgrades whatever's
  already there (vat, or a cannon's tier).
- A transiting fight at an intermediate node gets the same goo meniscus/splash as an arrival siege,
  anchored to the platform's rim, so it reads as combat AT the platform.
- A deck between two of your own adjacent nodes is covered in your goo.
- Last Stand moved to 2:00 (was 3:00).

## 0.4.0 - 2026-09-25

- All seven starter maps playable from a title screen; every map verified fully connected with
  AI vs AI finishing.
- Rudimentary relay cycling (every relay's states cycle together every 18 s; retract decks toggle
  open/closed the same way) and rudimentary Last Stand (starts 3:00, always inward, one rim node
  every 14 s, centre never dropped; a 7:00 safety net decides by strength if still undecided) - so
  no map turtles forever.
- Fixed a stalemate bug: a node whose garrison fell under simultaneous arrival sieges from both
  seats used to stay captureless forever; now the stronger side takes it.
- Implemented the modelled structures: vat upgrade (T1-T4), a single-tier cannon (bursts enemy
  hordes in range, bypassing fight math) and forge (owner takes less damage everywhere).
- Debug panel ranges widened a lot; platform speed can go below deck speed.

## 0.3.0 - 2026-09-25

- "The whole platform is the node": arriving hordes spread onto the platform from whichever pier
  they came by; a besieged platform splits into a goo river per attacker, seamed at the fight.
- "An order passing through a node always counts as passing through that node": every waypoint on
  a route fights whoever's transiting it, at siege rates; only an arrival can capture, though.
- Units leave the vat only as the door reveals them; a new send re-spends the vat's current total.

## 0.2.0 - 2026-09-25

- Blob fight pass: the drawn line recedes smoothly with its losses; a goo meniscus with a hot seam
  merges two lines where they meet; the contact patch squashes and the front shoves and ripples;
  goo splashes off the seam with the loss rate.

## 0.1.0 - 2026-09-24

- First playable slice: Two Piers. Drag-to-send, long hordes, capture, frontline combat, a simple
  AI opponent, phone profile and web export.
