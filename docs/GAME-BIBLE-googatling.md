# Googatling (was Machinegoon) - lines for the Release worker (2026-11-06, branch `googatling`)

## GAME-BIBLE (replace the Machinegoon paragraph in the structures section)
**Googatling** (internal id `machinegoon`; Daniele 2026-11-06: "machinegoon should be called googatling should produce units till
its cap at 0.5 speed per tier and shoots goo until it finish it and then each time its produced so fundamentally the default fire
rate should be higher than the production rate of it"). Built on a common node in place of its vat (cost 15, upgrades 20 / 30
shown, tier kept on a swap, back to a vat 15). It makes its own **goo stock** - its ammo, not garrison - at **0.5 x the same-tier
vat rate** (x the faction's production stat; an Echo jam stops it): 0.43 / 0.68 / 1.02 shown per second, up to **30 / 60 / 120**
shown (the tier's cap). An enemy line within 10 m is shot at 1.6 / 2.8 / 4 kills per second, one stock unit per kill, until the
stock is empty; then each unit is fired as soon as it is made (fire > production, so a long fight is production-bound). The node
grows no garrison. A new or captured Googatling starts empty; a tier drop clamps the stock; an upgrade raises the cap.
Readout: the inspector line "stock n/cap · +x/s · fires y/s" (EMPTY while it trickles); on the board a ring of 10 pips round the
gun fills with the stock (pulses when full, dark when empty); an empty gun's stream sputters thin.
(Proto-r / round R: a map-placed neutral Googatling starts full, refills at the plain tier rate and shoots every seat.)

## CHANGELOG (player-facing)
- The Machinegoon is now the **Googatling**: it fills a goo stock (half a vat's speed, up to its tier's cap) and fires it at
  enemy lines; when the stock runs dry it fires each new drop as it is made. It no longer fires forever. A ring of lights round
  the gun shows the stock; the node card shows "stock n/cap · +x/s".

## Knobs (rules.gd, balance keys)
`GOOGATLING_PROD` 0.5, `GOOGATLING_VAT_PROD` 0.0 (1.0 = it also produces garrison like a vat; Desk option), `GOOGATLING_CAP`
{1: 150, 2: 300, 3: 600}, fire rate = `MACHINEGOON_RATE` {8, 14, 20}, range `MACHINEGOON_RANGE` 10.
