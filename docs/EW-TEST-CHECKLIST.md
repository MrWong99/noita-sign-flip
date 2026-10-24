# sign_flip: two-player Entangled Worlds checklist

**A** = the host, who casts. **B** = the second player. Sign flip is deterministic and runs inside the wand code, which
Entangled Worlds replays on every peer, so both screens must show the same thing. The automated probe can't check
this: in the two-peer harness, scripted shots don't reach the other peer.

## Setup (both players)
1. Both players install the same version of **Sign Flip** (0.1.0) and, for part B, **Field Imbue** (0.3.0 or newer).
   Use the Steam Workshop, or extract the release zips into `Noita/mods/` so that you get
   `Noita/mods/sign_flip/mod.xml` and `Noita/mods/field_imbue/mod.xml` (not a folder named after the zip).
2. Mods menu:
   - enable **Sign Flip**, **Field Imbue** and **Cheatgui** (A at least);
   - keep **quant.ew** enabled;
   - never enable `sign_flip_probe` (test-only).
3. Sign Flip's mod setting **Flip cast delay, recharge and mana** must match for both players. Leave it on
   **Bonuses only**; it applies from the next new run.
4. Start EW as usual (proxy, lobby, New Game). Leave EW friendly fire **off** unless a step says otherwise.

## Wands (A builds these with Cheatgui → spells; use non-shuffle wands, cards left to right)
| Wand | Cards | What it should do |
|---|---|---|
| **W1 heal** | Sign flip → Damage plus → Spark bolt | each hit **heals** 7 instead of dealing 13 |
| **W2 slow** | Sign flip → Speed up → Spark bolt | bolt flies at ~40 % speed |
| **W3 anti-homing** | Sign flip → Homing → Spark bolt | bolt veers **away** from enemies |
| **W4 anti-gravity** | Sign flip → Gravity → Spark bolt | bolt curves **upwards** |
| **W5 fire eater** | Sign flip → Fire trail → Spark bolt | puts out fire along its path, leaves no fire |
| **W6 cancel** | Sign flip → Sign flip → Damage plus → Spark bolt | a plain Damage plus bolt |
| **W7 drain** | Sign flip → Add mana → Spark bolt | wand mana drops ~45 per cast (Sign flip 10, Spark bolt 5, the drain 30) instead of rising |
| **W9 white hole** | Sign flip → Black hole | a White hole (pushes things away) |
| **W10 implosion** | Sign flip → Explosive projectile → Spark bolt | where the bolt dies, things are pulled in for a moment, then a small, strong blast |
| **W8 reverse** | Sign flip → Water to poison → Spark bolt | turns poison back into water around the bolt |
| **Fire / poison** | Fire trail → Spark bolt; Water to poison → Spark bolt | to make fire and poison for W5 / W8 |

## Part A: Sign flip alone. Each step: both players report what they saw.
| # | Do | Expected on **both** screens |
|---|---|---|
| 1 | A fires W2 and W4 across open space. | Same slow bolts (W2) and the same upward curve (W4) for both. |
| 2 | A fires W3 past a few enemies (Mines entrance). | The bolts bend away from the enemies, the same way on both screens. |
| 3 | A sets grass or wood alight with the Fire trail wand, then fires W5 low through the flames. | Within about 12 px of the bolt's path the flames go out and the grass/wood stops burning, on both screens. Nothing new catches fire. (Never watched in game before: report what you see.) |
| 4 | A turns a water pool into poison (Water to poison wand), then fires W8 over it. | The poison turns back into water along the path, the same pixels on both screens. |
| 5 | Turn EW friendly fire **on**. A first hits B 3–4 times with a plain Damage plus → Spark bolt (13 each), so B is below full health. Then A hits B with W1 a few times while B watches their health. | B's health goes **up** by about 7 per W1 hit (3 damage, 10 healing), never above full. A sees the same. Turn friendly fire off again. |
| 6 | A fires W6 at an enemy. | It takes damage like a normal Damage plus bolt: the two Sign flips cancel. |
| 7 | A casts W7 a few times (A watches the wand's mana bar). | The mana bar drops each cast instead of filling. No error text. |
| 7b | A casts W9 near enemies. | The same White hole on both screens, pushing things away. |
| 7c | A fires W10 into a group of enemies on the ground. | On both screens: enemies get pulled together, then one small blast; the crater looks the same for both players. |

## Part B: with Field Imbue
Field wands, cards left to right; B shoots a plain Spark bolt through **A's** circle.
| Wand | Cards |
|---|---|
| **F1 slow field** | Field resonance → Sign flip → Speed up → Circle of fervour |
| **F2 anti-homing field** | Field resonance → Sign flip → Homing → Circle of fervour |
| **F3 healing field** | Field resonance → Sign flip → Damage plus → Circle of fervour |

| # | Do | Expected on **both** screens |
|---|---|---|
| 8 | A casts F1; A and B fire Spark bolts through it. | Every bolt slows to ~40 % as it crosses the circle, for A's and B's bolts alike. |
| 9 | A casts F2 near enemies; both shoot through it. | Bolts leaving the circle veer away from enemies. |
| 10 | Friendly fire **on**: B first hurts A a little with a plain Spark bolt. Then A casts F3, and B shoots through it at A. | A's health goes up when hit (never above full). Friendly fire off again. |
| 10b | A casts **Sign flip → Field resonance → Damage plus → Circle of fervour** (Sign flip first). | Behaves like F3: the flip passes over Field resonance. |
| 11 | Note when the circles disappear. | At the same moment for both players. |

## Report back
- **Any mismatch between screens.** For example: a bolt slow or curving on only one screen, fire put out for one player
  only, or poison that changes back on one screen only.
- **Red error text or a crash.** Send both players' `Noita/logger.txt` (with EW's default settings it contains the Lua
  messages).
- **Feel.** Is Sign flip fun? Too strong? One combo to watch: Sign flip → Explosive tiny on a Spark bolt. The engine
  gives it 13 explosion damage (~325) in a radius of 5; it hit that hard once in the probe but not reliably (see
  docs/DESIGN.md §5). Does it one-shot enemies for you?
