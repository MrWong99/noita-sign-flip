# What Sign flip does to each vanilla modifier

Generated with `SIM_TABLE=md luajit tools/sim.lua <unpacked data.wak> | sed '/^-- opposites/,$d' > docs/modifier-flips.md`
(default setting "Bonuses only"). Each entry reads *what the modifier does → what the flipped modifier does*, relative to
a plain Spark bolt.
- `healing`: damage moved to the healing type, because the engine ignores negative damage.
- `parts`: the extra entities the flipped cast carries. `flipped X` is X with its homing reversed or its converters run
  backwards; `eater of M` takes material M away around the projectile.
- `implode marker`: the explosion turns into an implosion (pull for 0.25 s, then 3x the damage in 1/3 of the radius).
- Cast delay and recharge only flip when they were a bonus; `mana` is Add mana's gain.

Not in the table: Sign flip itself, Random modifier (its pick is flipped), Random damage and Mana to damage (their
numbers depend on the frame and on the wand's mana; they flip like any other).

| Modifier | Flipped |
|---|---|
| `SPREAD_REDUCE` | `spread_degrees -60 → +60` |
| `HEAVY_SPREAD` | `spread_degrees +720 → -720` · `cast_delay -7 → +7` · `recharge -15 → +15` |
| `RECHARGE` | `cast_delay -10 → +10` · `recharge -20 → +20` |
| `LIFETIME` | `lifetime_add +75 → -75` · `cast_delay +13 → +13` |
| `LIFETIME_DOWN` | `lifetime_add -42 → +42` · `cast_delay -15 → +15` |
| `NOLLA` | `cast_delay -15 → +15` |
| `SLOW_BUT_STEADY` | `recharge +70 → +70` · `recoil -80 → +80` |
| `EXPLOSION_REMOVE` | `damage_explosion_add -0.8 → +0.8` · `explosion_radius -30 → +30` · `cast_delay -15 → +15` |
| `EXPLOSION_TINY` | `damage_explosion_add +0.8 → -0.8` · `explosion_radius -30 → +30` · `cast_delay +15 → +15` |
| `LASER_EMITTER_WIDER` | nothing to flip (wasted) |
| `MANA_REDUCE` | `cast_delay +10 → +10` · `mana +30 → -30` |
| `QUANTUM_SPLIT` | `cast_delay +5 → +5` |
| `GRAVITY` | `gravity +600 → -600` |
| `GRAVITY_ANTI` | `gravity -600 → +600` |
| `SINEWAVE` | `speed_multiplier x2 → x0.5` |
| `CHAOTIC_ARC` | `speed_multiplier x2 → x0.5` |
| `PINGPONG_PATH` | `lifetime_add +25 → -25` |
| `AVOIDING_ARC` | `cast_delay +10 → +10` |
| `FLOATING_ARC` | `cast_delay +10 → +10` |
| `FLY_DOWNWARDS` | `speed_multiplier x1.2 → x0.8333` · `cast_delay -8 → +8` · `parts=fly_upwards.xml` |
| `FLY_UPWARDS` | `speed_multiplier x1.2 → x0.8333` · `cast_delay -8 → +8` · `parts=fly_downwards.xml` |
| `HORIZONTAL_ARC` | `damage_projectile_add +0.3 → +0` · `healing -0.3` · `cast_delay -6 → +6` |
| `LINE_ARC` | `damage_projectile_add +0.2 → +0` · `healing -0.2` · `cast_delay -4 → +4` |
| `ORBIT_SHOT` | `damage_projectile_add +0.1 → +0` · `lifetime_add +25 → -25` · `healing -0.1` · `cast_delay -6 → +6` |
| `SPIRALING_SHOT` | `damage_projectile_add +0.1 → +0` · `lifetime_add +50 → -50` · `healing -0.1` · `cast_delay -6 → +6` |
| `PHASING_ARC` | `lifetime_add +80 → -80` · `speed_multiplier x0.33 → x3.03` · `child_speed_multiplier x0.33 → x3.03` · `cast_delay -12 → +12` |
| `TRUE_ORBIT` | `damage_projectile_add +0.1 → +0` · `lifetime_add +80 → -80` · `healing -0.1` · `cast_delay -20 → +20` |
| `BOUNCE` | `bounces +10 → -10` |
| `REMOVE_BOUNCE` | nothing to flip (wasted) |
| `HOMING` | `parts=flipped homing.xml, tinyspark_white.xml` |
| `ANTI_HOMING` | `cast_delay -20 → +20` · `parts=flipped anti_homing.xml, tinyspark_white.xml` |
| `HOMING_WAND` | `parts=flipped homing_wand.xml, tinyspark_white.xml` |
| `HOMING_SHORT` | `parts=flipped homing_short.xml, tinyspark_white_weak.xml` |
| `HOMING_ROTATE` | nothing to flip (wasted) |
| `HOMING_SHOOTER` | `parts=flipped homing_shooter.xml, tinyspark_white.xml` |
| `AUTOAIM` | nothing to flip (wasted) |
| `HOMING_ACCELERATING` | `parts=flipped homing_accelerating.xml, tinyspark_white_small.xml` |
| `HOMING_CURSOR` | nothing to flip (wasted) |
| `HOMING_AREA` | `spread_degrees +6 → -6` · `speed_multiplier x0.75 → x1.333` · `cast_delay +8 → +8` |
| `PIERCING_SHOT` | `damage_projectile_add -0.6 → +0.6` |
| `CLIPPING_SHOT` | `cast_delay +50 → +50` · `recharge +40 → +40` |
| `DAMAGE` | `damage_projectile_add +0.4 → +0` · `healing -0.4` · `cast_delay +5 → +5` · `recoil +10 → -10` |
| `BLOODLUST` | `damage_projectile_add +1.3 → +0` · `spread_degrees +6 → -6` · `healing -1.3` · `cast_delay +8 → +8` · `recoil +30 → -30` |
| `CRITICAL_HIT` | `damage_critical_chance +15 → -15` |
| `AREA_DAMAGE` | nothing to flip (wasted) |
| `SPELLS_TO_POWER` | `cast_delay +40 → +40` |
| `ESSENCE_TO_POWER` | `cast_delay +20 → +20` |
| `ZERO_DAMAGE` | `lifetime_add +280 → -280` · `cast_delay -5 → +5` · `recoil -10 → +10` |
| `HEAVY_SHOT` | `damage_projectile_add +1.75 → +0` · `healing -1.75` · `speed_multiplier x0.3 → x3.333` · `cast_delay +10 → +10` · `recoil +50 → -50` |
| `LIGHT_SHOT` | `damage_projectile_add -1 → +1` · `spread_degrees -6 → +6` · `speed_multiplier x7.5 → x0.1333` · `cast_delay -3 → +3` · `recoil -10 → +10` |
| `KNOCKBACK` | `knockback_force +5 → -5` |
| `RECOIL` | `recoil +200 → -200` |
| `RECOIL_DAMPER` | `recoil -200 → +200` |
| `SPEED` | `speed_multiplier x2.5 → x0.4` |
| `ACCELERATING_SHOT` | `speed_multiplier x0.32 → x3.125` · `cast_delay +8 → +8` · `recoil +10 → -10` |
| `DECELERATING_SHOT` | `speed_multiplier x1.68 → x0.5952` · `cast_delay -8 → +8` · `recoil -10 → +10` |
| `EXPLOSIVE_PROJECTILE` | `damage_explosion_add +0.2 → +0.2` · `explosion_radius +15 → +15` · `speed_multiplier x0.75 → x1.333` · `cast_delay +40 → +40` · `recoil +30 → -30` · `parts=implode marker` |
| `CLUSTERMOD` | `damage_explosion_add +0.2 → +0.2` · `explosion_radius +4 → +4` · `cast_delay +20 → +20` · `recoil +10 → -10` · `parts=clusterbomb.xml, implode marker` |
| `WATER_TO_POISON` | `cast_delay +10 → +10` · `parts=flipped water_to_poison.xml, tinyspark_purple.xml` |
| `BLOOD_TO_ACID` | `cast_delay +10 → +10` · `parts=flipped blood_to_acid.xml, tinyspark_red.xml` |
| `LAVA_TO_BLOOD` | `cast_delay +10 → +10` · `parts=flipped lava_to_blood.xml, tinyspark_orange.xml` |
| `LIQUID_TO_EXPLOSION` | `cast_delay +20 → +20` |
| `TOXIC_TO_ACID` | `cast_delay +10 → +10` · `parts=flipped toxic_to_acid.xml, tinyspark_green.xml` |
| `STATIC_TO_SAND` | `cast_delay +60 → +60` |
| `TRANSMUTATION` | `cast_delay +20 → +20` |
| `RANDOM_EXPLOSION` | `cast_delay +40 → +40` |
| `NECROMANCY` | `cast_delay +10 → +10` |
| `LIGHT` | nothing to flip (wasted) |
| `ELECTRIC_CHARGE` | `damage_electricity_add +0.1 → +0` · `healing -0.1` |
| `MATTER_EATER` | nothing to flip (wasted) |
| `FREEZE` | `damage_ice_add +0.2 → +0` · `healing -0.2` · `parts=flipped freeze_charge.xml` |
| `HITFX_BURNING_CRITICAL_HIT` | nothing to flip (wasted) |
| `HITFX_CRITICAL_WATER` | nothing to flip (wasted) |
| `HITFX_CRITICAL_OIL` | nothing to flip (wasted) |
| `HITFX_CRITICAL_BLOOD` | nothing to flip (wasted) |
| `HITFX_TOXIC_CHARM` | nothing to flip (wasted) |
| `HITFX_EXPLOSION_SLIME` | nothing to flip (wasted) |
| `HITFX_EXPLOSION_SLIME_GIGA` | nothing to flip (wasted) |
| `HITFX_EXPLOSION_ALCOHOL` | nothing to flip (wasted) |
| `HITFX_EXPLOSION_ALCOHOL_GIGA` | nothing to flip (wasted) |
| `HITFX_PETRIFY` | nothing to flip (wasted) |
| `ROCKET_DOWNWARDS` | `cast_delay +25 → +25` |
| `ROCKET_OCTAGON` | `cast_delay +20 → +20` |
| `FIZZLE` | `speed_multiplier x1.2 → x0.8333` · `cast_delay -10 → +10` |
| `BOUNCE_EXPLOSION` | `bounces +1 → -1` · `cast_delay +25 → +25` · `recoil +20 → -20` |
| `BOUNCE_SPARK` | `bounces +1 → -1` · `cast_delay +8 → +8` · `recoil +5 → -5` |
| `BOUNCE_LASER` | `bounces +1 → -1` · `cast_delay +12 → +12` · `recoil +5 → -5` |
| `BOUNCE_LASER_EMITTER` | `bounces +1 → -1` · `cast_delay +12 → +12` · `recoil +5 → -5` |
| `BOUNCE_LARPA` | `bounces +1 → -1` · `cast_delay +32 → +32` · `recoil +10 → -10` |
| `BOUNCE_SMALL_EXPLOSION` | `bounces +1 → -1` · `cast_delay +9 → +9` · `recoil +10 → -10` |
| `BOUNCE_LIGHTNING` | `bounces +1 → -1` · `cast_delay +25 → +25` · `recoil +10 → -10` |
| `BOUNCE_HOLE` | `bounces +1 → -1` · `cast_delay +40 → +40` · `recoil +10 → -10` |
| `FIREBALL_RAY` | nothing to flip (wasted) |
| `LIGHTNING_RAY` | nothing to flip (wasted) |
| `TENTACLE_RAY` | nothing to flip (wasted) |
| `LASER_EMITTER_RAY` | nothing to flip (wasted) |
| `FIREBALL_RAY_LINE` | nothing to flip (wasted) |
| `FIREBALL_RAY_ENEMY` | nothing to flip (wasted) |
| `LIGHTNING_RAY_ENEMY` | nothing to flip (wasted) |
| `TENTACLE_RAY_ENEMY` | nothing to flip (wasted) |
| `GRAVITY_FIELD_ENEMY` | nothing to flip (wasted) |
| `CURSE` | nothing to flip (wasted) |
| `CURSE_WITHER_PROJECTILE` | nothing to flip (wasted) |
| `CURSE_WITHER_EXPLOSION` | nothing to flip (wasted) |
| `CURSE_WITHER_MELEE` | nothing to flip (wasted) |
| `CURSE_WITHER_ELECTRICITY` | nothing to flip (wasted) |
| `ORBIT_DISCS` | nothing to flip (wasted) |
| `ORBIT_FIREBALLS` | nothing to flip (wasted) |
| `ORBIT_NUKES` | nothing to flip (wasted) |
| `ORBIT_LASERS` | nothing to flip (wasted) |
| `ORBIT_LARPA` | nothing to flip (wasted) |
| `CHAIN_SHOT` | `damage_projectile_add -0.2 → +0.2` · `lifetime_add -30 → +30` · `spread_degrees +10 → -10` |
| `ARC_ELECTRIC` | nothing to flip (wasted) |
| `ARC_FIRE` | nothing to flip (wasted) |
| `ARC_GUNPOWDER` | nothing to flip (wasted) |
| `ARC_POISON` | nothing to flip (wasted) |
| `CRUMBLING_EARTH_PROJECTILE` | nothing to flip (wasted) |
| `UNSTABLE_GUNPOWDER` | nothing to flip (wasted) |
| `ACID_TRAIL` | `parts=eater of acid.xml` · `no trail` |
| `POISON_TRAIL` | `parts=eater of poison.xml` · `no trail` · `no on-hit effect` |
| `OIL_TRAIL` | `parts=eater of oil.xml` · `no trail` · `no on-hit effect` |
| `WATER_TRAIL` | `parts=eater of water.xml` · `no trail` · `no on-hit effect` |
| `GUNPOWDER_TRAIL` | `parts=eater of gunpowder.xml` · `no trail` |
| `FIRE_TRAIL` | `parts=eater of fire.xml` · `no trail` · `no on-hit effect` |
| `BURN_TRAIL` | `parts=eater of fire.xml` · `no on-hit effect` |
| `ENERGY_SHIELD_SHOT` | `speed_multiplier x0.4 → x2.5` |
| `LARPA_CHAOS` | `cast_delay +15 → +15` |
| `LARPA_DOWNWARDS` | `cast_delay +15 → +15` · `parts=larpa_upwards.xml` |
| `LARPA_UPWARDS` | `cast_delay +15 → +15` · `parts=larpa_downwards.xml` |
| `LARPA_CHAOS_2` | `cast_delay +20 → +20` |
| `LARPA_DEATH` | `cast_delay +15 → +15` |
| `COLOUR_RED` | `cast_delay -8 → +8` |
| `COLOUR_ORANGE` | `cast_delay -8 → +8` |
| `COLOUR_GREEN` | `cast_delay -8 → +8` |
| `COLOUR_YELLOW` | `cast_delay -8 → +8` |
| `COLOUR_PURPLE` | `cast_delay -8 → +8` |
| `COLOUR_BLUE` | `cast_delay -8 → +8` |
| `COLOUR_RAINBOW` | `cast_delay -8 → +8` |
| `COLOUR_INVIS` | `cast_delay -8 → +8` |
| `RAINBOW_TRAIL` | `parts=eater of material_rainbow.xml` · `no trail` · `no on-hit effect` |
