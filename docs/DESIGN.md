# sign_flip: design and findings

Mod id **sign_flip**, published name **Sign Flip**. Target: Noita build "Jan 25 2025" (modding API 12), together with
Entangled Worlds (EW, `quant.ew`, 1.6.6 installed) and Field Imbue (`field_imbue`, 0.3.0+, the release with the
integration in §4). Started 2026-10-24. Field Imbue's `docs/RESEARCH.md` §2 (wand pipeline) and §4 (EW sync) apply here
unchanged.

## 1. Decisions (asked and answered 2026-10-24)

| # | Question | Decision |
|---|---|---|
| 1 | Scope | A Sign flip flips **the next modifier** after it. If that modifier is another Sign flip, the two cancel: `Sign flip → Sign flip → Damage plus` = plain Damage plus, while `Sign flip → Damage plus → Sign flip → Heavy shot` = both negated. It must work for multicasts too. |
| 1b | Next modifier has nothing to flip | Find creative opposites (§3); if there is none, the flip is used up ("wasted"). |
| 1c | Sign flip right in front of a projectile spell | Flip the spell itself: its own damage turns into healing, Black hole ↔ White hole. **Not built yet**: next step after milestone 1. Until then the flip waits for the next modifier in the cast. |
| 2 | Multipliers | Reciprocal: Speed up ×2.5 → ×0.4. |
| 3 | Negative results | **Negative damage heals; no clamps.** The engine has its own limits (§5). |
| 4 | Cast delay, recharge, mana | A **setting** (`wand_numbers`, new-game scope): `bonuses` (default) flips only changes that helped the wand, `all` flips everything, `none` never touches them. |
| 5 | The card | Mid-tier: mana 10, no cast delay, price 150, spawns in levels 2–6 at 0.3/0.4/0.4/0.4/0.3, a 16×16 ± icon. |
| 6 | Creative opposites | All four proposed: Homing ↔ anti homing, converters run backwards, trails eat their material, up ↔ down swaps. |
| 7 | `Sign flip → Field resonance → X` (raised by the review) | A flip **passes over** Field Imbue's Field resonance to the next modifier, so both orders flip X. That includes Random modifier picking Field resonance. |

**From the review, not a user decision.** A flip never *creates* mana beyond what the cast started with. The engine
doesn't cap a wand's mana at its maximum after a shot (verified by disassembly, §6). Without the cap, a flipped Mana to
damage in "Everything" mode would double the wand's mana on every cast.

## 2. How it works

**The card** (`files/actions.lua`) only draws the next card. Everything else happens in `files/gun_append.lua`,
appended to `data/scripts/gun/gun.lua`:
- It runs after every mod's actions exist and before the deck clones them, so always-casts and Random modifier go
  through the wrappers too.
- `SIGN_FLIP`'s wrapper sets `c.sf_pending = 1`, or, if a flip is already pending, cancels it (a flipped Sign flip).
- `FIELD_IMBUE` is not a flip consumer (decision 7).
- Every other `ACTION_TYPE_MODIFIER` is wrapped. When not reflecting and a flip is pending, the wrapper takes it and runs
  the modifier with both draw functions (`draw_actions`, `draw_action`) hooked:
  - **Phase 1 (the modifier draws).** Everything it changed so far is its own, because the next cards are played inside
    that call. The change is flipped, the real draw functions are put back first (so the cards drawn now don't hit the
    hooks), the call is forwarded, and a new snapshot is taken. Then the hooks go back on, in case it draws again.
  - **Phase 2 (the modifier returns).** What it changed after drawing is flipped too. Eight vanilla modifiers change the
    shot *after* drawing: Orbit shot, Spiraling shot, Phasing arc, Fly upwards/downwards, Horizontal arc, Line arc and
    True orbit. A modifier that never draws is measured on return.
  - **Bypass guard.** If cards were drawn past both hooks (`state_cards_drawn` moved since the snapshot, e.g. through a
    draw function the modifier captured itself), their changes are mixed in, so the flip is used up rather than
    flipping someone else's numbers.
  - **Errors.** If the modifier raises, the hooks and `open` are put back and the error is rethrown without flipping
    anything.
- **Random modifier** calls the picked modifier's function directly, before anything draws. A modifier entered while a
  flipped one hasn't drawn a card yet takes over the flip (`open`), so the *picked* modifier is flipped and recorded.
  A picked Sign flip cancels; a picked Field resonance hands the flip on.
- **Numbers.** Additive shot fields: `before − (now − before)`. Multiplied fields (`speed_multiplier`,
  `child_speed_multiplier`, `dampening`): `before² / now`; a factor of 0 can't be inverted and stays.
  - Damage a flip takes away goes to `damage_healing_add` instead, for the projectile, melee, electricity, fire, ice,
    slice, curse and drill types (§5).
  - Never flipped: cosmetics (screenshake, gore, blood, light), counts (`lightning_count`, trail and material amounts),
    the `damage_null_all` flag, and the cards' own mana costs.
- **Cast delay, recharge, mana** follow the setting.
  - Add mana's bonus is its negative card cost, paid by `draw_action` *before* the action runs, so it is flipped from
    `current_action.mana`: −30 cost → drains 30.
  - A drain never takes the wand below 0. A spend turned into a gain is capped at the mana `_start_shot` got (the
    wrapper remembers it).
  - `ModSettingGet` is read on every flip; it works in the wand's Lua state (probe E1–E4 switch the setting mid-run).
- **Record.** `c.sf_negated` lists the modifiers whose projectile numbers or parts were flipped (not cast delay,
  recharge, mana or recoil). Field Imbue's `register_action` wrapper reads it. Nothing ever clears it: `c` is a fresh
  table per shot, and keys the engine doesn't know never reach it.
- **Pass-through** while `reflecting` (spell tooltips, EW's `action_fix`, Field Imbue's recipe builder) and when no flip
  is pending.

**Shots and triggers.** `c` is one shot. A trigger's payload is a new shot with its own `c`, so a flip pending in the
outer shot doesn't enter the payload; it waits for a later modifier of the outer shot. A Sign flip inside the payload
flips there.

**Copy spells** follow from the rules. Divide by, Duplicate, Mu and Omega replay cards one at a time, and every replay
is a play: `Sign flip → Divide by 2 → Damage plus` flips the first of its Damage plus plays. A replayed Sign flip card
cancels the pending flip.

**Entangled Worlds.**
- **Replay:** EW replays each player's cast on every peer with the same seeds. The wrappers only depend on the shot (no
  `Random()`, frame numbers or entity ids), so every peer computes the same flipped shot.
- **Generated files:** the opposites are generated at mod init from the loaded mods, with sorted output, so they are the
  same on every peer with the same mods.
- **Settings:** EW doesn't compare mod lists or settings, so every player needs the same version and the same
  `wand_numbers` setting.

## 3. Opposites: what a flipped modifier adds

`files/scripts/opposites_build.lua` runs from `OnModPostInit`. It evaluates every modifier in reflection mode (the way
Field Imbue's recipe builder does, restoring `_G` and the `dofile_once` caches afterwards). It collects the extra
entities and trail materials each modifier adds and writes `gen/opposites.lua` plus the generated entity files:

| Kind | Rule | Vanilla result |
|---|---|---|
| Homing | `HomingComponent.homing_targeting_coeff` negated | Homing +130 → −130, which is vanilla's own Anti homing. Short-range, Accelerating, Boomerang (`target_who_shot`: flies away from you) and Homing-to-wand get the same; Anti homing → Homing. Rotate homing only turns (no strength to flip); Auto-aim and Cursor homing are scripts: no opposite. |
| Converters | `from_material` ↔ `to_material`. A converter that can't run backwards (a material group via `from_material_tag`, or one waiting for a script) stays as it is; later converters from the same new source are dropped | Water to poison → poison to water, Blood to acid → acid to blood, Lava to blood → blood to **lava**, Toxic sludge to acid → acid to toxic sludge, Freeze charge's water → static ice becomes static ice → water. Static to sand (`[solid]`), Liquid to explosion (`[liquid_common]`) and Transmutation have no opposite. |
| Trails | trail material removed, a small converter "material → air" rides on the projectile instead, and the modifier's on-hit effect is dropped. Fire eaters also carry vanilla's `extinguish_fire` converter (as Ice ball does), because burning grass or wood stays its own material | Fire, Water, Oil, Acid, Poison, Gunpowder and Rainbow trail |
| Poured material | an extra entity whose particle emitter makes real material is replaced by the same eater, on-hit effect dropped | Burning trail (`burn.xml`, real fire) → eats fire |
| Pairs | swapped by file | Fly upwards ↔ Fly downwards, Larpa upwards ↔ Larpa downwards |
| Includes | `<Base file="...">` pointing at a file with something to flip is pointed at that file's flipped version (up to 4 levels) | none in vanilla; for modded entities |

At cast time the wrapper replaces whatever the flipped modifier appended to `extra_entities` and `trail_material`, in
the same phases as the numbers. A cancelled flip (`Sign flip → Sign flip → Homing`) leaves Homing alone.

**Everything else is used up:** curses, critical-on-X hit effects, orbits, rays, arcs, Light, Matter eater, and so on.
The colour modifiers' only number is a cast-delay bonus, which does flip. Per-modifier list:
[modifier-flips.md](modifier-flips.md).

## 4. Field Imbue integration (Field Imbue 0.3.0)

- **Markers.** Field Imbue's `register_action` wrapper counts `state.sf_negated` per id. For each flipped occurrence it
  emits the marker `gen/mod/<ID>.neg.xml` (`value_string="-<ID>"`) instead of the plain one, so a shot can carry `DAMAGE`
  and `-DAMAGE` at once. `recipes_build.lua` writes a `.neg` marker for every recipe.
- **Stripping.** An imbuing circle carries none of its modifiers' own pieces. For a flipped one those pieces are the
  flipped ones: anti homing, a reversed converter, a trail's eater. Field Imbue looks them up in Sign Flip's
  `gen/opposites.lua`.
- **Negated recipes.** `fi_lib.recipe("-<ID>")` builds them lazily:
  - numbers are negated, with taken-away damage turned into healing, and the speed factor inverted;
  - extras and converters are mapped through Sign Flip's table when Sign Flip is loaded;
  - a trail becomes an eater, both on bolts and as a converter over the circle, and on-hit effects are dropped.
  - A negation that changes nothing for a projectile collapses back to the plain id.
- **Duplicates.** `already_has` never matches a negated recipe: its numbers can't be read back from a projectile.
  Matching is by whole entry, because Sign Flip's flipped files (`mods/sign_flip/files/gen/flip/data/...`) contain the
  vanilla path.
  - Converters shared by `X` and `-X` are loaded once.
  - A circle with both `X` and `-X` of a converter runs both directions, which undo each other.
- **Independence.** Each mod works alone, in either load order. Field Imbue only records ids, Sign Flip only flips.
  Field Imbue's recipe builder sees Sign flip as "nothing that works on a flying projectile" and skips it.

## 5. In-game findings (probe, 2026-10-24)

`tools/probe-run.sh main` sweeps every vanilla modifier with projectile numbers as `[Sign flip, X, Spark bolt]`
against `[X, Spark bolt]` and `[Spark bolt]`. It compares both the wand code's final shot (logged by the probe's own
`register_action` hook) and the bolt's components against a model of what the engine does with a shot.

**Passed in game:**
- the wand side for all 50 numeric modifiers;
- cancelling, only the next modifier, multicast (both bolts), trigger payload in both directions, always-cast (alone
  and cancelled), and "nothing to flip";
- Random modifier with a forced pick: numbers, anti homing, and a picked Sign flip cancelling;
- the opposites: anti homing turns away from a target that plain homing turns towards, Water to poison runs backwards,
  fire eaters, Fly upwards flies down;
- the wand economy under all three settings, including the mana cap;
- with Field Imbue in both load orders: flipped and mixed circles, a clean circle centre, Field resonance passing a flip
  on.

**Engine behaviour:**
- **Negative damage of any normal type is ignored** (a sheep stayed at 1.0 HP). Healing-type damage heals:
  - Sign flip → Damage plus → Spark bolt: 1.0 → **1.28** (+7 HP);
  - Sign flip → Heavy shot: 1.0 → 2.63.
- **Negative explosion damage does nothing** (neither heals nor hurts).
- **Lifetime ≤ 0 kills the projectile at once.** Vanilla's double Reduce lifetime does the same; it does *not* mean
  "never dies". This hits flipped Increase lifetime, Spiraling shot, Phasing arc, True orbit and Null shot on a Spark
  bolt.
- **Bounces and critical chance stop at 0.** A negative `explosion_radius` sum is ignored, so vanilla's Remove explosion
  −30 has no effect there either.
- **Explosion damage.** From `explosion_radius` +30 on, the engine sets the explosion damage itself: **13**, for
  vanilla's two Explosive projectiles too.
  - Flipped Remove explosion gets radius 32 and damage 13, but its own script switches the explosion off.
  - Flipped Explosive tiny gets damage 13 and then its script shrinks the radius to 5. One run, a sheep hit by it lost
    13.1; a later run lost only the bolt's 0.12, and the vanilla double Explosive projectile control never hit. **Not
    reproducible yet**: a possible strong combo to watch.
- **Speed:** Speed up ×2.5 → ×0.4 measured 328 px/s against a 758 px/s base; Light shot ×7.5 → ×0.133 measured 107.

## 6. Review (2026-10-24)

An independent review was followed by a verification workflow: each claim checked by an adversarial verifier, plus
gap-finders for packaging, docs and tooling.

**Found and fixed:**
- **Field Imbue `already_has`.** A substring match made a bolt with Sign Flip's flipped Homing count as already
  carrying plain Homing; now it matches whole entries.
- **Error path.** It flipped a second time against a stale snapshot; now it rethrows first.
- **Hook bypass.** It was possible through `draw_action` or a captured draw function; now both are hooked, plus the
  card-count guard.
- **Unbounded mana** in "Everything" mode. The engine writes the wand's mana back from the gun script with no cap
  (checked in the disassembly of `noita.exe`), and regeneration only stops below the maximum. Now capped at the cast's
  starting mana.
- **Converters.** An irreversible converter in a flipped file was dropped; now it is kept as it is. `<Base>` includes
  are followed.
- **Fire eaters didn't put out burning material**; they now extinguish.
- **Tooling:**
  - `probe-run.sh` reported success on FAIL or ABORT, could be pointed at Steam's prefix, tested whatever was installed
    under `mods/`, and left the probe mod linked. All four are fixed; it also stops early when Noita dies.
  - The Random-modifier probe couldn't fail; the pick is now forced.
  - `tools/sim.lua` didn't run Field Imbue's builder; it does now.

## 7. Testing

- **`luajit tools/sim.lua <unpacked data.wak> [order]`** runs vanilla's real `gun.lua` offline. It covers:
  - every modifier in all three settings, the semantics, and the opposites;
  - with Field Imbue loaded, its negated recipes against the cast-time flips, its markers and stripping;
  - modded modifiers that bypass the hooks, the error path, and the builder's edge cases.

  All orders pass (`sf`, `ew,fi,sf`, `sf,fi,ew`, `fi,sf`). It caught a real bug before the game did: "all" mode flipped
  Add mana's drain back.
- **`tools/probe-run.sh main|fi|fi-first`** is the in-game probe, in an isolated prefix with Field Imbue loaded
  after/before. Harness rules (all from Field Imbue): absolute `noita.exe` path, run outside the sandbox, copied
  `config.xml` with `application_pause_when_unfocused="0"` and `vsync="0"`, `save00` trashed before each run.
  - Proton sets `WINEPREFIX=<prefix>/pfx/` **with a trailing slash**; the kill matcher has to allow it.
  - Under zsh, `kill $pids` doesn't word-split; the script is bash.
- **`docs/EW-TEST-CHECKLIST.md`** is for two players. Scripted shots don't replicate in the two-peer harness.

## 8. Open

- **Spell flip** (decision 1c): Sign flip right in front of a projectile flips the spell's own damage, and Black hole ↔
  White hole.
  - The shot's numbers are shared by the whole cast, so it needs per-spell entity variants generated at init.
  - EW position-syncs a few projectiles by filename.
- Balance: Explosive tiny (§5); "Everything" mode is deliberately strong.
- Not flipped: `lightning_count` (Electric charge's arcs), Firecrackers' `material`.
- Not watched in game yet: burning material being put out (the component is vanilla's, and the probe checks it is
  there). It is on the two-player checklist.
