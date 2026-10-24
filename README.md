# Sign Flip

A Noita mod that adds **Sign flip**, a modifier card that negates the next modifier.

| Cast | What happens |
|---|---|
| Sign flip → Damage plus → Spark bolt | instead of +10 damage the bolt **heals** 10 (it still deals its own 3) |
| Sign flip → Speed up → Spark bolt | ×2.5 becomes ×0.4: a slow bolt |
| Sign flip → Gravity → … | anti-gravity |
| Sign flip → Increase lifetime → … | lifetime −75 (a Spark bolt dies at once, like vanilla's double Reduce lifetime) |
| Sign flip → Reduce spread → … | +60° spread |
| Sign flip → Homing → … | the bolt steers **away** from enemies (exactly vanilla's Anti homing) |
| Sign flip → Water to poison → … | poison turns into water |
| Sign flip → Fire trail → … | the bolt takes fire away along its path and puts out what burns, instead of leaving fire |
| Sign flip → Fly upwards → … | flies downwards |
| Sign flip → Sign flip → Damage plus | a plain Damage plus: a flipped Sign flip cancels |

## Install
- **Steam Workshop:** subscribe to [Sign Flip](https://steamcommunity.com/sharedfiles/filedetails/?id=3826087249).
- **Manual:** download `sign_flip-<version>.zip` from
  [Releases](https://github.com/MrWong99/noita-sign-flip/releases) and extract it into `Noita/mods/`, so that you
  get `Noita/mods/sign_flip/mod.xml`. Then enable **Sign Flip** in the Mods menu.

## Rules
- **Scope.** A Sign flip flips the **next modifier** played in the same cast. That also works:
  - through multicasts;
  - as an always-cast;
  - when Random modifier is the next modifier: the modifier it picks is flipped.
- **Triggers.** A flip stays in its own cast. It doesn't reach into a trigger's payload, and a flip left unused there
  waits for a later modifier of the same cast.
- **Field resonance** ([Field Imbue](https://github.com/MrWong99/noita-field-imbue)) doesn't take a flip; it passes on
  to the next modifier. Both `Sign flip → Field resonance → X` and `Field resonance → Sign flip → X` flip X.
- **Copy spells** (Divide by, Duplicate, Mu, Omega, …) replay cards one by one, and every replay counts:
  - `Sign flip → Divide by 2 → Damage plus` flips only the first of its Damage plus plays;
  - a copy spell that replays the Sign flip card itself cancels the flip.
- **Nothing to flip.** A next modifier with nothing to flip (curses, orbits, Light, …) uses the flip up.
- **Numbers.** Numbers a modifier adds are negated. Numbers it multiplies get the reciprocal factor.
- **Healing.** Damage that a flip takes away **heals** instead. The engine ignores negative damage, so it goes to the
  healing type, like vanilla's Healing bolt. It heals what the bolt hits; explosion damage can't heal (a negative
  explosion damage does nothing).
- **No clamps on projectile numbers.** The engine itself stops bounces and critical chance at 0, ignores a negative
  explosion radius, and kills a projectile with lifetime ≤ 0 at once. Mana is the exception:
  - a flipped drain never takes the wand below 0;
  - a flip never gives back more mana than the cast started with.
- **Parts flip too.** What a modifier adds to the projectile is flipped as well:
  - **Homing ↔ anti homing:** the sign of the homing strength. Covers Homing, Short-range, Accelerating, Boomerang and
    Homing to wands. Rotate, Auto-aim and Cursor homing have no strength to flip.
  - **Converters run backwards** when they turn one material into another: Water to poison, Blood to acid, Lava to
    blood, Toxic sludge to acid, Freeze charge's freezing. Converters of whole material groups (Static to sand, Liquid
    to explosion) and Transmutation can't.
  - **Trails:** material trails and Burning trail take their material away instead of leaving it, and lose their
    on-hit effect.
  - **Pairs:** Fly upwards ↔ Fly downwards, Larpa upwards ↔ Larpa downwards.
- The full table for every vanilla modifier: [docs/modifier-flips.md](docs/modifier-flips.md).

## Setting
**Flip cast delay, recharge and mana** (applies from the next new run):
- **Bonuses only** (default). Only a bonus flips: Reduce recharge time slows you down, Add mana drains 30 mana. A
  modifier's price stays, so a flipped Heavy shot still adds its cast delay.
- **Everything.** Prices flip too, so a flipped Static to sand casts 60 frames faster. Very strong.
- **Never.** Cast delay, recharge and mana never flip. Everything else still does: projectile numbers, recoil and
  parts.

## Compatibility
- **Entangled Worlds**: everything happens in the wand code, which every peer replays deterministically. Every player
  needs the same version and the same setting.
- **[Field Imbue](https://github.com/MrWong99/noita-field-imbue)** ([Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3825663162)),
  0.3.0 or newer. A circle cast with Field resonance hands out the flipped modifier:
  - a Sign flip → Damage plus circle heals the bolts' targets;
  - a Sign flip → Homing circle makes bolts flee enemies;
  - a Sign flip → Fire trail circle puts out fire over its area.
- **Modifiers from other mods** are flipped too: numbers at cast time, their homing and converters at mod load.

## Development
- [docs/DESIGN.md](docs/DESIGN.md): decisions, how it works, in-game findings.
- `luajit tools/sim.lua <unpacked data.wak> [ew,fi,sf]` runs vanilla's real wand code offline with the engine stubbed,
  together with Entangled Worlds' and Field Imbue's wrappers in any order. Unpack with
  `python3 -I tools/unwak.py <Noita>/data/data.wak <dir>`.
- `tools/probe-run.sh [main|fi|fi-first]` runs the in-game probe (`probe/`, mod `sign_flip_probe`) in an isolated Proton
  prefix and copies the results to `~/noita-dev/signflip-probe.txt`.
- [docs/EW-TEST-CHECKLIST.md](docs/EW-TEST-CHECKLIST.md): the two-player test.

MIT licensed.
