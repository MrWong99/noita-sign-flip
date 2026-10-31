-- sign_flip probes: in-game checks for Sign flip, run automatically after the player spawns. Every result is an
-- "SFPROBE" line in logger.txt. Meant for an isolated prefix (tools/probe-run.sh): it rewrites the player's held
-- starting wand, pins the player in the air and fires by driving ControlsComponent. The harness (pinning, firing,
-- rewriting the wand, calibration) comes from Field Imbue's probe, which found out what works.

local MOD = "mods/sign_flip_probe/"

-- suite.txt (written by tools/probe-run.sh): line 1 suite ("main", "fi", "fi-first"), line 2 optional sweep ids, line 3
-- the run's token. Without it this is not a probe run: do nothing at all (the probe rewrites the held wand).
local ok_suite, SUITE_TEXT = pcall(ModTextFileGetContent, MOD .. "suite.txt")
if not ok_suite or not SUITE_TEXT or SUITE_TEXT == "" then
	print("sign_flip_probe: no suite.txt, not a probe run (tools/probe-run.sh): disabled")
	return
end

ModMagicNumbersFileAdd(MOD .. "files/magic_numbers.xml") -- makes Lua print() reach logger.txt
ModLuaFileAppend("data/scripts/gun/gun.lua", MOD .. "files/gun_append.lua")
local LINES = {}
for line in (SUITE_TEXT .. "\n"):gmatch("([^\n]*)\n") do
	LINES[#LINES + 1] = line
end
local SUITE = (LINES[1] or ""):match("[%w%-]+") or "main"
local ONLY = {}
for id in (LINES[2] or ""):gmatch("[%w_]+") do
	ONLY[id] = true
end
local TOKEN = LINES[3] or ""
ModSettingSet("sign_flip.wand_numbers", "bonuses")

-- state -----------------------------------------------------------------------------------------------------------

local player, ctrl
local PX, PY -- pinned player position (in the air)
local pins = {} -- entity -> {x, y}
local runner -- the probe coroutine
local current_wand
local n_pass, n_fail = 0, 0

local function log(...)
	local parts = { "SFPROBE" }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	print(table.concat(parts, " "))
end

local function result(tag, ok, ...)
	if ok then
		n_pass = n_pass + 1
	else
		n_fail = n_fail + 1
	end
	log(tag, ok and "PASS" or "FAIL", ...)
	return ok
end

local function wait(frames)
	for _ = 1, frames do
		coroutine.yield()
	end
end

local function pin(e, x, y)
	pins[e] = { x, y }
end

local function apply_pins()
	if ctrl then
		ComponentSetValue2(ctrl, "enabled", false)
	end
	for e, p in pairs(pins) do
		if EntityGetIsAlive(e) then
			EntitySetTransform(e, p[1], p[2])
			local cd = EntityGetFirstComponentIncludingDisabled(e, "CharacterDataComponent")
			if cd then
				ComponentSetValue2(cd, "mVelocity", 0, 0)
			end
		else
			pins[e] = nil
		end
	end
end

local function kill(...)
	for i = 1, select("#", ...) do
		local e = select(i, ...)
		if e and e ~= 0 and EntityGetIsAlive(e) then
			pins[e] = nil
			EntityKill(e)
		end
	end
end

local function aim(dx, dy)
	local d = math.sqrt(dx * dx + dy * dy)
	ComponentSetValue2(ctrl, "mAimingVector", dx, dy)
	ComponentSetValue2(ctrl, "mAimingVectorNormalized", dx / d, dy / d)
	ComponentSetValue2(ctrl, "mAimingVectorNonZeroLatest", dx, dy)
	ComponentSetValue2(ctrl, "mMousePosition", PX + dx, PY + dy)
end

local FIRE_MODE = "hold" -- chosen by calibrate_fire()

local function ability()
	return EntityGetFirstComponentIncludingDisabled(current_wand, "AbilityComponent")
end

local function shots_fired()
	return ComponentGetValue2(ability(), "stat_times_player_has_shot")
end

-- returns true if the wand's shot counter went up
local function fire(dx, dy, mode)
	mode = mode or FIRE_MODE
	aim(dx, dy)
	wait(2) -- let the wand rotate
	local ab = ability()
	for _ = 1, 200 do -- wait out cast delay / recharge from the previous shot
		local ready = math.max(ComponentGetValue2(ab, "mNextFrameUsable"), ComponentGetValue2(ab, "mReloadNextFrameUsable"))
		if GameGetFrameNum() >= ready then
			break
		end
		wait(1)
	end
	local before = shots_fired()
	if mode == "force" then
		local psc = EntityGetFirstComponentIncludingDisabled(player, "PlatformShooterPlayerComponent")
		ComponentSetValue2(psc, "mForceFireOnNextUpdate", true)
		wait(2)
	else
		for i = 1, 8 do
			local f = GameGetFrameNum()
			ComponentSetValue2(ctrl, "mButtonDownFire", true)
			ComponentSetValue2(ctrl, "mButtonDownFire2", true)
			if i == 1 then
				ComponentSetValue2(ctrl, "mButtonFrameFire", f + 1)
			end
			ComponentSetValue2(ctrl, "mButtonLastFrameFire", f)
			wait(1)
			if shots_fired() > before then
				break
			end
		end
		ComponentSetValue2(ctrl, "mButtonDownFire", false)
		ComponentSetValue2(ctrl, "mButtonDownFire2", false)
	end
	return shots_fired() > before
end

-- Rewrites the held starting wand's cards and stats. Swapping in a different wand entity and writing
-- Inventory2Component.mActiveItem leaves it unable to fire; this is vanilla's perk pattern instead.
local WAND_DELAY = 30
local function equip(cards, opts)
	opts = opts or {}
	local w = current_wand
	for _, card in ipairs(EntityGetAllChildren(w) or {}) do
		if EntityGetFirstComponentIncludingDisabled(card, "ItemActionComponent") then
			EntityRemoveFromParent(card)
			EntityKill(card)
		end
	end
	local n = 0
	local function add(id, permanent)
		local card = CreateItemActionEntity(id, PX, PY)
		EntityAddChild(w, card)
		EntitySetComponentsWithTagEnabled(card, "enabled_in_world", false)
		if permanent then
			ComponentSetValue2(EntityGetFirstComponentIncludingDisabled(card, "ItemComponent"), "permanently_attached", true)
		end
		n = n + 1
	end
	for _, id in ipairs(opts.always or {}) do
		add(id, true)
	end
	for _, id in ipairs(cards) do
		add(id, false)
	end
	local ab = ability()
	ComponentObjectSetValue2(ab, "gun_config", "deck_capacity", n + 1)
	ComponentObjectSetValue2(ab, "gun_config", "actions_per_round", opts.per_round or 1)
	ComponentObjectSetValue2(ab, "gun_config", "reload_time", 0)
	ComponentObjectSetValue2(ab, "gun_config", "shuffle_deck_when_empty", false)
	ComponentObjectSetValue2(ab, "gunaction_config", "fire_rate_wait", WAND_DELAY)
	ComponentSetValue2(ab, "mana_max", 10000)
	ComponentSetValue2(ab, "mana_charge_speed", opts.charge or 10000)
	ComponentSetValue2(ab, "mana", opts.mana or 10000)
	local inv = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
	ComponentSetValue2(inv, "mActualActiveItem", 0) -- makes the held wand rebuild its deck
	wait(5)
	return ComponentGetValue2(inv, "mActualActiveItem") == w
end

local PROJ_TAGS = { "projectile", "projectile_player" }
local function snapshot()
	local s = {}
	for _, tag in ipairs(PROJ_TAGS) do
		for _, e in ipairs(EntityGetWithTag(tag)) do
			s[e] = true
		end
	end
	return s
end

-- new spark bolts shot by the player itself (not children of an earlier projectile), up to `n`, waiting a few frames
local function own_bolts(snap, n, max_frames)
	local found = {}
	for _ = 1, max_frames or 10 do
		for _, p in ipairs(EntityGetWithTag("projectile") or {}) do
			if not snap[p] and (EntityGetFilename(p) or ""):find("light_bullet", 1, true) then
				snap[p] = true
				local pc = EntityGetFirstComponentIncludingDisabled(p, "ProjectileComponent")
				local parent = pc and ComponentGetValue2(pc, "mEntityThatShot") or 0
				if pc and ComponentGetValue2(pc, "mWhoShot") == player and (parent == 0 or not EntityHasTag(parent, "projectile")) then
					found[#found + 1] = p
				end
			end
		end
		if #found >= n then
			break
		end
		wait(1)
	end
	return found
end

-- every projectile near the test spot goes, without explosions (twice: some spawn children when removed)
local function quiet_cleanup()
	for _ = 1, 2 do
		for _, p in ipairs(EntityGetInRadiusWithTag(PX, PY, 1200, "projectile") or {}) do
			for _, pc in ipairs(EntityGetComponentIncludingDisabled(p, "ProjectileComponent") or {}) do
				ComponentSetValue2(pc, "on_death_explode", false)
				ComponentSetValue2(pc, "on_lifetime_out_explode", false)
			end
			EntityKill(p)
		end
		wait(8)
	end
end

local function bolt_stats(e)
	local pc = e and EntityGetIsAlive(e) and EntityGetFirstComponentIncludingDisabled(e, "ProjectileComponent")
	if not pc then
		return nil
	end
	local s = {
		damage = ComponentGetValue2(pc, "damage"),
		lifetime = ComponentGetValue2(pc, "lifetime"),
		bounces = ComponentGetValue2(pc, "bounces_left"),
		knockback = ComponentGetValue2(pc, "knockback_force"),
		expl_radius = ComponentObjectGetValue2(pc, "config_explosion", "explosion_radius"),
		expl_damage = ComponentObjectGetValue2(pc, "config_explosion", "damage"),
		crit = ComponentObjectGetValue2(pc, "damage_critical", "chance"),
		ice = ComponentObjectGetValue2(pc, "damage_by_type", "ice"),
		elec = ComponentObjectGetValue2(pc, "damage_by_type", "electricity"),
		heal = ComponentObjectGetValue2(pc, "damage_by_type", "healing"),
		cfg_speed = ComponentObjectGetValue2(pc, "config", "speed_multiplier"),
	}
	local vc = EntityGetFirstComponentIncludingDisabled(e, "VelocityComponent")
	if vc then
		s.gravity = ComponentGetValue2(vc, "gravity_y")
		local vx, vy = ComponentGetValue2(vc, "mVelocity")
		s.speed = math.sqrt(vx * vx + vy * vy)
	end
	return s
end

-- the wand code's final shot states for the last cast (probe/files/gun_append.lua)
local function shot_states()
	local out = {}
	for line in (GlobalsGetValue("sfprobe_shots", "") or ""):gmatch("[^\n]+") do
		local s = {}
		for k, v in line:gmatch("([%w_]+)=(%S*)") do
			if v ~= "nil" then
				s[k] = tonumber(v) or v
			end
		end
		out[#out + 1] = s
	end
	return out
end

-- equips `cards`, fires once and returns the shot states plus the stats of the player's spark bolts on their first frame
local function cast(cards, opts)
	opts = opts or {}
	equip(cards, opts)
	GlobalsSetValue("sfprobe_shots", "")
	local snap = snapshot()
	local fired = fire(opts.dx or 1, opts.dy or 0)
	local frame = GameGetFrameNum()
	local bolts = own_bolts(snap, opts.bolts or 1)
	local r = { fired = fired, shots = shot_states(), bolts = bolts, stats = {} }
	for i, b in ipairs(bolts) do
		r.stats[i] = bolt_stats(b)
	end
	r.root = r.shots[#r.shots] or {}
	local ab = ability()
	r.mana_after = ComponentGetValue2(ab, "mana")
	r.cast_delay = ComponentGetValue2(ab, "mNextFrameUsable") - frame
	r.recharge = ComponentGetValue2(ab, "mReloadNextFrameUsable") - frame
	return r
end

local function spawn_sheep(x, y, hp)
	local s = EntityLoad("data/entities/animals/sheep.xml", x, y)
	local dm = EntityGetFirstComponentIncludingDisabled(s, "DamageModelComponent")
	if dm then
		ComponentSetValue2(dm, "max_hp", 40)
		ComponentSetValue2(dm, "hp", hp or 40)
	end
	pin(s, x, y)
	return s
end

local function hp(e)
	local dm = e and EntityGetIsAlive(e) and EntityGetFirstComponentIncludingDisabled(e, "DamageModelComponent")
	return dm and ComponentGetValue2(dm, "hp") or -1
end

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (tol or 1e-4) * math.max(1, math.abs(b))
end

local function fmt(v)
	if type(v) ~= "number" then
		return tostring(v)
	end
	return ("%.4g"):format(v)
end

-- sweep -------------------------------------------------------------------------------------------------------------

-- vanilla modifiers whose projectile numbers flip with the default setting (tools/sim.lua's table)
local NUMERIC = {
	"SPREAD_REDUCE", "HEAVY_SPREAD", "LIFETIME", "LIFETIME_DOWN", "SLOW_BUT_STEADY", "EXPLOSION_REMOVE", "EXPLOSION_TINY",
	"GRAVITY", "GRAVITY_ANTI", "SINEWAVE", "CHAOTIC_ARC", "PINGPONG_PATH", "FLY_DOWNWARDS", "FLY_UPWARDS",
	"HORIZONTAL_ARC", "LINE_ARC", "ORBIT_SHOT", "SPIRALING_SHOT", "PHASING_ARC", "TRUE_ORBIT", "BOUNCE", "HOMING_AREA",
	"PIERCING_SHOT", "DAMAGE", "BLOODLUST", "CRITICAL_HIT", "ZERO_DAMAGE", "HEAVY_SHOT", "LIGHT_SHOT", "KNOCKBACK",
	"RECOIL", "RECOIL_DAMPER", "SPEED", "ACCELERATING_SHOT", "DECELERATING_SHOT", "EXPLOSIVE_PROJECTILE", "CLUSTERMOD",
	"ELECTRIC_CHARGE", "FREEZE", "FIZZLE", "BOUNCE_EXPLOSION", "BOUNCE_SPARK", "BOUNCE_LASER", "BOUNCE_LASER_EMITTER",
	"BOUNCE_LARPA", "BOUNCE_SMALL_EXPLOSION", "BOUNCE_LIGHTNING", "BOUNCE_HOLE", "CHAIN_SHOT", "ENERGY_SHIELD_SHOT",
}
local SHOT_ADD = { "damage_projectile_add", "damage_electricity_add", "damage_explosion_add", "damage_ice_add",
	"damage_critical_chance", "explosion_radius", "knockback_force", "lifetime_add", "bounces", "gravity",
	"spread_degrees", "recoil" }
-- a flip that takes damage of these types away heals instead (files/gun_append.lua, DAMAGE)
local SHOT_DAMAGE = { damage_projectile_add = true, damage_electricity_add = true, damage_ice_add = true }
-- bolt stat -> shot field the engine adds to it, and how the engine treats the sum (measured in the first run:
-- bounces and crit chance stop at 0, a negative explosion_radius sum is ignored, lifetime <= 0 kills the bolt at once)
local BOLT_FROM_SHOT = {
	{ "damage", "damage_projectile_add" }, { "ice", "damage_ice_add" }, { "elec", "damage_electricity_add" },
	{ "heal", "damage_healing_add" }, { "expl_damage", "damage_explosion_add" }, { "knockback", "knockback_force" },
	{ "gravity", "gravity" }, { "crit", "damage_critical_chance", "floor0" }, { "bounces", "bounces", "floor0" },
	{ "expl_radius", "explosion_radius", "add_floor0" },
}
local SPARK_LIFETIME = 40 -- light_bullet.xml, +-7 at random

-- what the engine should make of `shot` on a spark bolt, given the plain spark's bolt `sb` and shot `b`
local function engine_bolt(sb, b, shot, stat, field, rule)
	local d = shot[field] - b[field]
	if rule == "floor0" then
		return math.max(0, sb[stat] + d)
	elseif rule == "add_floor0" then
		return sb[stat] - math.max(0, b[field]) + math.max(0, shot[field])
	end
	return sb[stat] + d
end
-- speed changes that show on the bolt's first frame (no script steering it), checked against its config multiplier
local SPEED_CHECK = { SPEED = true, LIGHT_SHOT = true, ENERGY_SHIELD_SHOT = true, EXPLOSIVE_PROJECTILE = true, FIZZLE = true,
	HOMING_AREA = true }

local sweep = {} -- id -> { plain, flip } shot states, for the Random modifier check
-- swept modifiers whose parts also have an opposite (files/scripts/opposites_build.lua)
local OPPOSITE_IDS = { FLY_UPWARDS = true, FLY_DOWNWARDS = true, FREEZE = true }

local function sweep_one(id, base)
	local plain = cast({ id, "LIGHT_BULLET" })
	quiet_cleanup()
	local flip = cast({ "SIGN_FLIP", id, "LIGHT_BULLET" })
	quiet_cleanup()
	sweep[id] = { plain = plain.root, flip = flip.root }
	local bad = {}
	local b, p, f = base.root, plain.root, flip.root
	local heal = 0
	-- recorded for Field Imbue when a projectile number or part flipped (not for recoil, cast delay, recharge, mana)
	local recorded = OPPOSITE_IDS[id] or false
	local dr, dd = p.explosion_radius - b.explosion_radius, p.damage_explosion_add - b.damage_explosion_add
	local implosion = dr > 0 or (dr == 0 and dd > 0)
	for _, k in ipairs(SHOT_ADD) do
		if k ~= "recoil" and not near(p[k], b[k]) then
			recorded = true
		end
		if not near(p[k], b[k]) then
			local want = 2 * b[k] - p[k]
			if implosion and (k == "explosion_radius" or k == "damage_explosion_add") then
				want = p[k]
			elseif SHOT_DAMAGE[k] and p[k] > b[k] then
				heal, want = heal + (b[k] - p[k]), b[k]
			end
			if not near(f[k], want) then
				bad[#bad + 1] = ("shot.%s=%s(want %s)"):format(k, fmt(f[k]), fmt(want))
			end
		end
	end
	if not near(f.damage_healing_add, b.damage_healing_add + heal) then
		bad[#bad + 1] = ("shot.damage_healing_add=%s(want %s)"):format(fmt(f.damage_healing_add), fmt(b.damage_healing_add + heal))
	end
	for _, k in ipairs({ "speed_multiplier", "child_speed_multiplier" }) do
		if not near(p[k], b[k]) and p[k] ~= 0 then
			recorded = true
			if not near(f[k], b[k] * b[k] / p[k]) then
				bad[#bad + 1] = ("shot.%s=%s(want %s)"):format(k, fmt(f[k]), fmt(b[k] * b[k] / p[k]))
			end
		end
	end
	for _, k in ipairs({ "fire_rate_wait", "reload" }) do
		local d = p[k] - b[k]
		local want = b[k] + (d < 0 and -d or d) -- default setting: only a bonus flips
		if d ~= 0 and not near(f[k], want) then
			bad[#bad + 1] = ("shot.%s=%s(want %s)"):format(k, fmt(f[k]), fmt(want))
		end
	end
	if not result("SWEEP-SHOT " .. id, #bad == 0 and f.sf_negated == (recorded and id .. "," or nil),
		"sf_negated=" .. tostring(f.sf_negated), table.concat(bad, " ")) then
		return
	end
	-- The engine's view: does each bolt carry what the engine makes of its shot (the plain cast's bolt is checked the same
	-- way, so a wrong engine model shows up there too)? A lifetime <= 0 kills the bolt before it can be seen.
	local sb, sp, sf = base.stats[1], plain.stats[1], flip.stats[1]
	local function seen_ok(stats, shot)
		local d = shot.lifetime_add - b.lifetime_add
		if SPARK_LIFETIME - 7 + d > 0 then
			return stats ~= nil
		elseif SPARK_LIFETIME + 7 + d <= 0 then
			return stats == nil
		end
		return true -- depends on the spark's random lifetime
	end
	if not sb or not seen_ok(sp, p) or not seen_ok(sf, f) then
		result("SWEEP-BOLT " .. id, false, "bolt seen: base/plain/flipped", tostring(sb ~= nil), tostring(sp ~= nil),
			tostring(sf ~= nil), "lifetime_add", fmt(p.lifetime_add), fmt(f.lifetime_add))
		return
	end
	if not (sp and sf) then
		result("SWEEP-BOLT " .. id, true, "lifetime <= 0 kills the bolt at once (as vanilla): lifetime_add", fmt(p.lifetime_add),
			fmt(f.lifetime_add))
		return
	end
	bad = {}
	local notes = {}
	for _, m in ipairs(BOLT_FROM_SHOT) do
		local stat, field, rule = m[1], m[2], m[3]
		-- From explosion_radius +30 on, the engine sets the explosion damage itself (13, also for vanilla's two Explosive
		-- projectiles; behaviour B4/B5)
		if (stat == "expl_damage" or stat == "expl_radius") and implosion then
			goto next_stat -- the implode marker neutered the bolt's own explosion (checked by I2)
		end
		if stat == "expl_damage" and math.max(p.explosion_radius, f.explosion_radius) >= 30 then
			notes[#notes + 1] = ("expl_damage %s/%s/%s (engine: radius-based)"):format(fmt(sb[stat]), fmt(sp[stat]), fmt(sf[stat]))
			goto next_stat
		end
		local want_p = engine_bolt(sb, b, p, stat, field, rule)
		local want_f = engine_bolt(sb, b, f, stat, field, rule)
		if not near(sp[stat], sb[stat]) or not near(sf[stat], sb[stat]) then
			notes[#notes + 1] = ("%s %s/%s/%s"):format(stat, fmt(sb[stat]), fmt(sp[stat]), fmt(sf[stat]))
		end
		if not near(sp[stat], want_p) then
			bad[#bad + 1] = ("plain.%s=%s(engine model %s)"):format(stat, fmt(sp[stat]), fmt(want_p))
		end
		if not near(sf[stat], want_f) then
			bad[#bad + 1] = ("%s=%s(want %s)"):format(stat, fmt(sf[stat]), fmt(want_f))
		end
		::next_stat::
	end
	for _, pair in ipairs({ { sp, p, "plain." }, { sf, f, "" } }) do
		local want = SPARK_LIFETIME + pair[2].lifetime_add - b.lifetime_add
		if math.abs(pair[1].lifetime - want) > 8 then
			bad[#bad + 1] = ("%slifetime=%d(want %d+-7)"):format(pair[3], pair[1].lifetime, want)
		end
	end
	if SPEED_CHECK[id] then
		local want = sb.speed * sf.cfg_speed / sb.cfg_speed
		notes[#notes + 1] = ("speed %.0f/%.0f/%.0f cfg x%.3g"):format(sb.speed, sp.speed, sf.speed, sf.cfg_speed)
		if want < 950 and math.abs(sf.speed - want) > 0.2 * want then
			bad[#bad + 1] = ("speed=%.0f(want ~%.0f)"):format(sf.speed, want)
		end
	end
	result("SWEEP-BOLT " .. id, #bad == 0, table.concat(bad, " "), "| base/plain/flipped:", table.concat(notes, "; "))
end

local function run_sweep()
	local base = cast({ "LIGHT_BULLET" })
	quiet_cleanup()
	log("SWEEP base", "damage=" .. fmt(base.stats[1] and base.stats[1].damage), "shot.fire_rate_wait=" .. fmt(base.root.fire_rate_wait))
	for _, id in ipairs(NUMERIC) do
		if next(ONLY) == nil or ONLY[id] then
			sweep_one(id, base)
		end
	end
end

-- semantics ---------------------------------------------------------------------------------------------------------

-- damage net of healing (a flip that takes damage away heals instead)
local function damage_of(r, i)
	local s = r.shots[i or #r.shots]
	return s and s.damage_projectile_add + s.damage_healing_add
end
local function bolt_net(st)
	return st and st.damage + st.heal
end

local function run_semantics()
	local function want(tag, got, expected, extra)
		return result(tag, near(got, expected), "got " .. fmt(got), "want " .. fmt(expected), extra or "")
	end
	local r = cast({ "SIGN_FLIP", "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET" })
	want("S1 two Sign flips cancel", damage_of(r), 0.4)
	quiet_cleanup()
	r = cast({ "SIGN_FLIP", "DAMAGE", "SIGN_FLIP", "HEAVY_SHOT", "LIGHT_BULLET" })
	want("S2 each flips its next modifier", damage_of(r), -0.4 - 1.75, "speed x" .. fmt(r.root.speed_multiplier))
	quiet_cleanup()
	r = cast({ "SIGN_FLIP", "DAMAGE", "HEAVY_SHOT", "LIGHT_BULLET" })
	want("S4 only the next modifier", damage_of(r), -0.4 + 1.75)
	quiet_cleanup()
	r = cast({ "SIGN_FLIP", "BURST_2", "DAMAGE", "LIGHT_BULLET", "LIGHT_BULLET" }, { bolts = 2 })
	local d1 = bolt_net(r.stats[1])
	local d2 = bolt_net(r.stats[2])
	want("S5 multicast: shot", damage_of(r), -0.4)
	result("S5 multicast: both bolts", #r.bolts == 2 and near(d1, 0.12 - 0.4) and near(d2, 0.12 - 0.4),
		"bolts=" .. #r.bolts, "damage " .. fmt(d1) .. " " .. fmt(d2), "want " .. fmt(0.12 - 0.4))
	quiet_cleanup()
	r = cast({ "LIGHT_BULLET_TRIGGER", "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET" })
	want("S6 flip inside a trigger payload", damage_of(r, 1), -0.4, "shots=" .. #r.shots)
	quiet_cleanup()
	r = cast({ "SIGN_FLIP", "LIGHT_BULLET_TRIGGER", "DAMAGE", "LIGHT_BULLET" })
	want("S6b flip does not enter the payload", damage_of(r, 1), 0.4, "outer sf_pending=" .. tostring(r.root.sf_pending))
	quiet_cleanup()
	r = cast({ "DAMAGE", "LIGHT_BULLET" }, { always = { "SIGN_FLIP" } })
	want("S7 always-cast Sign flip", damage_of(r), -0.4)
	quiet_cleanup()
	r = cast({ "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET" }, { always = { "SIGN_FLIP" } })
	want("S7b always-cast + deck Sign flip cancel", damage_of(r), 0.4)
	quiet_cleanup()
	r = cast({ "SIGN_FLIP", "LIGHT", "DAMAGE", "LIGHT_BULLET" })
	want("S10 the flip goes to Light (darkness), not Damage plus", damage_of(r), 0.4)
	quiet_cleanup()
end

local function vsc_str(e, name)
	for _, v in ipairs(EntityGetComponentIncludingDisabled(e, "VariableStorageComponent") or {}) do
		if ComponentGetValue2(v, "name") == name then
			return ComponentGetValue2(v, "value_string")
		end
	end
	return nil -- explicit: tostring() with zero arguments throws
end

local function wait_new(snap, pattern, max_frames)
	for _ = 1, max_frames do
		for _, tag in ipairs(PROJ_TAGS) do
			for _, e in ipairs(EntityGetWithTag(tag)) do
				if not snap[e] then
					snap[e] = true
					if (EntityGetFilename(e) or ""):find(pattern, 1, true) then
						return e
					end
				end
			end
		end
		wait(1)
	end
	return nil
end

-- opposites: what flipped modifiers add (files/scripts/opposites_build.lua) -----------------------------------------

local function homing_coeffs(e)
	local out = {}
	for _, h in ipairs(EntityGetComponentIncludingDisabled(e, "HomingComponent") or {}) do
		out[#out + 1] = ComponentGetValue2(h, "homing_targeting_coeff")
	end
	return out
end

-- material converters on an entity, as "from>to" material names (not the ones that only put out fire)
local function converters(e)
	local out = {}
	for _, comp in ipairs(EntityGetComponentIncludingDisabled(e, "MagicConvertMaterialComponent") or {}) do
		if not ComponentGetValue2(comp, "extinguish_fire") then
			out[#out + 1] = CellFactory_GetName(ComponentGetValue2(comp, "from_material")) .. ">"
				.. CellFactory_GetName(ComponentGetValue2(comp, "to_material"))
		end
	end
	table.sort(out)
	return table.concat(out, ",")
end

-- does it put out burning material around it (vanilla Ice ball's extinguish_fire converter)?
local function extinguishes(e)
	for _, comp in ipairs(EntityGetComponentIncludingDisabled(e, "MagicConvertMaterialComponent") or {}) do
		if ComponentGetValue2(comp, "extinguish_fire") then
			return true
		end
	end
	return false
end

local function run_opposites()
	local r = cast({ "SIGN_FLIP", "HOMING", "LIGHT_BULLET" })
	local h = r.bolts[1] and homing_coeffs(r.bolts[1]) or {}
	result("O1 flipped Homing steers away", #h == 1 and near(h[1], -130), "homing_targeting_coeff=" .. table.concat(h, ","),
		"sf_negated=" .. tostring(r.root.sf_negated))
	quiet_cleanup()
	r = cast({ "SIGN_FLIP", "ANTI_HOMING", "LIGHT_BULLET" })
	h = r.bolts[1] and homing_coeffs(r.bolts[1]) or {}
	result("O2 flipped Anti homing homes", #h == 1 and near(h[1], 130), "homing_targeting_coeff=" .. table.concat(h, ","))
	quiet_cleanup()
	-- behaviour: a sheep above the bolt's path; homing turns towards it, anti homing away
	for _, cards in ipairs({ { "HOMING", "LIGHT_BULLET" }, { "SIGN_FLIP", "HOMING", "LIGHT_BULLET" } }) do
		local sheep = spawn_sheep(PX + 170, PY - 60)
		wait(3)
		r = cast(cards)
		local vy
		for _ = 1, 15 do
			wait(1)
			local vc = r.bolts[1] and EntityGetIsAlive(r.bolts[1]) and EntityGetFirstComponentIncludingDisabled(r.bolts[1], "VelocityComponent")
			if vc then
				vy = select(2, ComponentGetValue2(vc, "mVelocity"))
			end
		end
		log("O1b " .. table.concat(cards, ","), "vertical speed after 15 frames=" .. fmt(vy), "(sheep is above: < 0 towards it)")
		kill(sheep)
		quiet_cleanup()
	end
	r = cast({ "SIGN_FLIP", "WATER_TO_POISON", "LIGHT_BULLET" })
	local conv = r.bolts[1] and converters(r.bolts[1]) or ""
	result("O3 flipped Water to poison runs backwards", conv == "poison>water", "converters=" .. conv)
	quiet_cleanup()
	for _, id in ipairs({ "FIRE_TRAIL", "BURN_TRAIL" }) do
		local plain = cast({ id, "LIGHT_BULLET" })
		local pe = plain.bolts[1] and ComponentGetValue2(EntityGetFirstComponentIncludingDisabled(plain.bolts[1], "ProjectileComponent"),
			"damage_game_effect_entities") or "?"
		quiet_cleanup()
		r = cast({ "SIGN_FLIP", id, "LIGHT_BULLET" })
		local b = r.bolts[1]
		conv = b and converters(b) or ""
		local fe = b and ComponentGetValue2(EntityGetFirstComponentIncludingDisabled(b, "ProjectileComponent"), "damage_game_effect_entities") or "?"
		local ext = b and extinguishes(b) or false
		result("O4 flipped " .. id .. " eats fire", conv == "fire>air" and ext and not fe:find("on_fire", 1, true)
			and pe:find("on_fire", 1, true) ~= nil, "converters=" .. conv, "extinguishes=" .. tostring(ext), "on-hit plain=" .. pe,
			"flipped=" .. fe)
		quiet_cleanup()
	end
	-- Fly upwards: its script turns the bolt on frame 20; flipped it turns down (and soon hits the ground)
	local vys = {}
	for i, cards in ipairs({ { "FLY_UPWARDS", "LIGHT_BULLET" }, { "SIGN_FLIP", "FLY_UPWARDS", "LIGHT_BULLET" } }) do
		r = cast(cards)
		local b = r.bolts[1]
		for _ = 1, 24 do
			wait(1)
			local vc = b and EntityGetIsAlive(b) and EntityGetFirstComponentIncludingDisabled(b, "VelocityComponent")
			if vc then
				vys[i] = select(2, ComponentGetValue2(vc, "mVelocity"))
			end
		end
		quiet_cleanup()
	end
	-- the scripts set the vertical speed to twice the bolt's speed: far beyond what gravity adds in 24 frames (~80)
	result("O6 flipped Fly upwards flies down", vys[1] and vys[2] and vys[1] < -300 and vys[2] > 300,
		"vertical speed after 24 frames: plain " .. fmt(vys[1]), "flipped " .. fmt(vys[2]), "(< 0 is up)")
end

-- this mod's own opposites (PAIRS in files/scripts/opposites_build.lua): each replacement file is on the bolt, and what it
-- does where that can be checked without luck

local SF = "mods/sign_flip/files/"

local function has_script(e, file)
	for _, lc in ipairs(e and EntityGetIsAlive(e) and EntityGetComponentIncludingDisabled(e, "LuaComponent") or {}) do
		if ComponentGetValue2(lc, "script_source_file") == SF .. "scripts/" .. file then
			return true
		end
	end
	return false
end

-- the value_string of every HitEffectComponent on the bolt, comma-separated
local function hit_effects(e)
	local out = {}
	for _, h in ipairs(e and EntityGetIsAlive(e) and EntityGetComponentIncludingDisabled(e, "HitEffectComponent") or {}) do
		out[#out + 1] = ComponentGetValue2(h, "value_string")
	end
	return table.concat(out, ",")
end

-- a pinned sheep in the bolt path (PX + 150) and a bolt shot at it; returns the sheep, the bolt and the frame it was shot
local function shoot_sheep(cards, hp_now, prepare)
	local sheep = spawn_sheep(PX + 150, PY, hp_now)
	if prepare then
		prepare(sheep)
	end
	wait(3)
	local r = cast(cards, { dx = 150, dy = 0 })
	return sheep, r.bolts[1]
end

local function run_parts()
	-- O7 Light -> darkness
	local r = cast({ "SIGN_FLIP", "LIGHT", "LIGHT_BULLET" })
	local dark = false
	for _, sc in ipairs(r.bolts[1] and EntityGetComponentIncludingDisabled(r.bolts[1], "SpriteComponent") or {}) do
		dark = dark or ComponentGetValue2(sc, "image_file") == SF .. "particles/darkness.xml"
	end
	local lights = r.bolts[1] and #(EntityGetComponentIncludingDisabled(r.bolts[1], "LightComponent") or {}) or -1
	result("O7 flipped Light carries darkness", dark, "darkness sprite=" .. tostring(dark), "LightComponents=" .. lights)
	quiet_cleanup()

	-- O8 Boomerang -> veers away from players: the script instead of a homing on the shooter
	r = cast({ "SIGN_FLIP", "HOMING_SHOOTER", "LIGHT_BULLET" })
	local b = r.bolts[1]
	local h = b and homing_coeffs(b) or {}
	result("O8 flipped Boomerang repels players", has_script(b, "repel_players.lua") and #h == 0,
		"repel script=" .. tostring(has_script(b, "repel_players.lua")), "HomingComponents=" .. #h)
	quiet_cleanup()

	-- O9 colours: complementary colour_name, cosmetic sparks recoloured, cast delay -8 -> +8
	for _, t in ipairs({ { "RED", "green", "spark_green" }, { "PURPLE", "yellow", "spark_yellow" }, { "RAINBOW", "invis" },
		{ "INVIS", "rainbow" } }) do
		local plain = cast({ "COLOUR_" .. t[1], "LIGHT_BULLET" })
		quiet_cleanup()
		r = cast({ "SIGN_FLIP", "COLOUR_" .. t[1], "LIGHT_BULLET" })
		b = r.bolts[1]
		local name = b and vsc_str(b, "colour_name")
		wait(2)
		local mats, emitting = {}, 0
		for _, pe in ipairs(b and EntityGetIsAlive(b) and EntityGetComponentIncludingDisabled(b, "ParticleEmitterComponent") or {}) do
			if ComponentGetValue2(pe, "emit_cosmetic_particles") then
				mats[#mats + 1] = ComponentGetValue2(pe, "emitted_material_name")
				emitting = emitting + (ComponentGetValue2(pe, "is_emitting") and 1 or 0)
			end
		end
		local mat_list = "," .. table.concat(mats, ",") .. ","
		local looks = (t[3] and mat_list:find("," .. t[3] .. ",", 1, true) ~= nil) or (t[2] == "invis" and emitting == 0)
			or t[2] == "rainbow"
		result("O9 flipped Colour " .. t[1] .. " is " .. t[2], name == t[2] and looks
			and near(r.root.fire_rate_wait, plain.root.fire_rate_wait + 16), "colour_name=" .. tostring(name),
			"cosmetic emitters=" .. table.concat(mats, ","), "emitting=" .. emitting,
			"cast delay " .. fmt(plain.root.fire_rate_wait) .. " -> " .. fmt(r.root.fire_rate_wait))
		quiet_cleanup()
	end

	-- O10 Rocket downwards -> rockets up: shot straight up, the bolt bursts into five rockets that rise
	r = cast({ "SIGN_FLIP", "ROCKET_DOWNWARDS", "LIGHT_BULLET" }, { dx = 0, dy = -1 })
	b = r.bolts[1]
	local script = has_script(b, "rocket_upwards.lua")
	local rockets = {}
	for _ = 1, 12 do
		wait(1)
		for _, tag in ipairs(PROJ_TAGS) do
			for _, p in ipairs(EntityGetWithTag(tag) or {}) do
				if (EntityGetFilename(p) or ""):find("rocket_upwards_shot", 1, true) then
					rockets[p] = true
				end
			end
		end
		if next(rockets) then
			wait(2)
			break
		end
	end
	local n, up, sum_vx = 0, 0, 0
	for p in pairs(rockets) do
		local vc = EntityGetIsAlive(p) and EntityGetFirstComponentIncludingDisabled(p, "VelocityComponent")
		if vc then
			n = n + 1
			local vx, vy = ComponentGetValue2(vc, "mVelocity")
			sum_vx = sum_vx + vx
			up = up + (vy < 0 and ComponentGetValue2(vc, "gravity_y") < 0 and 1 or 0)
		end
	end
	result("O10 flipped Rocket downwards fires rockets up", script and n == 5 and up == 5,
		"script=" .. tostring(script), "rockets=" .. n, "rising with gravity up=" .. up, "sum vx=" .. fmt(sum_vx),
		"bolt alive=" .. tostring(b and EntityGetIsAlive(b)))
	quiet_cleanup()

	-- O11 Laser emitter wider -> narrower: Plasma beam cross 3.5/0.08/112 per beam, wider adds 2/0.025/36
	local function lasers(cards)
		equip(cards)
		local snap = snapshot()
		fire(1, 0)
		local orb = wait_new(snap, "orb_laseremitter_four", 10)
		wait(3)
		local out = {}
		for _, lc in ipairs(orb and EntityGetIsAlive(orb) and EntityGetComponentIncludingDisabled(orb, "LaserEmitterComponent") or {}) do
			out[#out + 1] = { ComponentObjectGetValue2(lc, "laser", "beam_radius"), ComponentObjectGetValue2(lc, "laser", "damage_to_entities"),
				ComponentObjectGetValue2(lc, "laser", "max_length") }
		end
		local left = orb and has_script(orb, "laser_emitter_narrower.lua")
		quiet_cleanup()
		return out, left
	end
	local function beams_are(list, rad, dmg, len)
		if #list ~= 4 then
			return false
		end
		for _, l in ipairs(list) do
			if not (near(l[1], rad, 1e-3) and near(l[2], dmg, 1e-3) and near(l[3], len, 1e-3)) then
				return false
			end
		end
		return true
	end
	local function show(list)
		local l = list[1]
		return l and (fmt(l[1]) .. "/" .. fmt(l[2]) .. "/" .. fmt(l[3])) or "none"
	end
	local wide = lasers({ "LASER_EMITTER_WIDER", "LASER_EMITTER_FOUR" })
	local narrow, left = lasers({ "SIGN_FLIP", "LASER_EMITTER_WIDER", "LASER_EMITTER_FOUR" })
	result("O11 flipped Laser emitter wider narrows", beams_are(wide, 5.5, 0.105, 148) and beams_are(narrow, 1.5, 0.055, 76)
		and not left, "plain " .. show(wide), "flipped " .. show(narrow), "(want 5.5/0.105/148 and 1.5/0.055/76)",
		"script left=" .. tostring(left))

	-- O12 critical on wet -> on not wet: the boost is disarmed just before hitting a wet sheep, armed before a dry one
	for _, t in ipairs({ { "HITFX_CRITICAL_OIL", "oil" }, { "HITFX_CRITICAL_BLOOD", "blood" },
		{ "HITFX_BURNING_CRITICAL_HIT", "burning" } }) do
		local id = t[1]
		r = cast({ "SIGN_FLIP", id, "LIGHT_BULLET" })
		local boosts = r.bolts[1] and EntityGetComponentIncludingDisabled(r.bolts[1], "HitEffectComponent") or {}
		local eff = boosts[1] and ComponentGetValue2(boosts[1], "effect_hit")
		result("O12 flipped " .. id .. " carries a disarmable crit boost", #boosts == 1 and eff == "CRITICAL_HIT_BOOST"
			and has_script(r.bolts[1], "hitfx_critical_not_" .. t[2] .. ".lua"),
			"HitEffectComponents=" .. #boosts, "effect_hit=" .. tostring(eff))
		quiet_cleanup()
	end
	local seen = {}
	for _, wet in ipairs({ true, false }) do
		local sheep, bolt = shoot_sheep({ "SIGN_FLIP", "HITFX_CRITICAL_WATER", "LIGHT_BULLET" }, 40, wet and function(s)
			LoadGameEffectEntityTo(s, "data/entities/misc/effect_wet.xml")
		end)
		local boost = bolt and EntityGetFirstComponentIncludingDisabled(bolt, "HitEffectComponent", "hitfx_critical_not_WET")
		local lowest
		for _ = 1, 40 do
			if not bolt or not EntityGetIsAlive(bolt) then
				break
			end
			lowest = math.min(lowest or 1000, ComponentGetValue2(boost, "value"))
			wait(1)
		end
		wait(10)
		seen[wet] = { lowest = lowest, lost = 40 - hp(sheep), wet = GameGetGameEffectCount(sheep, "WET") }
		kill(sheep)
		quiet_cleanup()
	end
	-- the hp lost is only logged: the Spark bolt's own 5 % crit chance can crit the wet sheep too
	result("O12 flipped Critical on wet: crit on dry targets only", seen[true].lowest == 0 and seen[false].lowest == 100,
		"boost value near wet sheep=" .. fmt(seen[true].lowest), "near dry=" .. fmt(seen[false].lowest), "(want 0 and 100)",
		"hp lost wet/dry=" .. fmt(seen[true].lost) .. "/" .. fmt(seen[false].lost), "WET effects=" .. tostring(seen[true].wet))

	-- O13 explosive slime / alcohol on hit -> the target implodes: each carries the implode blast, which implodes
	for _, t in ipairs({ { "HITFX_EXPLOSION_SLIME", "" }, { "HITFX_EXPLOSION_SLIME_GIGA", "_giga" },
		{ "HITFX_EXPLOSION_ALCOHOL", "" }, { "HITFX_EXPLOSION_ALCOHOL_GIGA", "_giga" } }) do
		r = cast({ "SIGN_FLIP", t[1], "LIGHT_BULLET" })
		local fx = hit_effects(r.bolts[1])
		result("O13 flipped " .. t[1] .. " loads the implosion", fx == SF .. "entities/hitfx_implode_explosion" .. t[2] .. ".xml",
			"hit effects=" .. fx)
		quiet_cleanup()
	end
	local blast = EntityLoad(SF .. "entities/hitfx_implode_explosion.xml", PX + 150, PY)
	local imp, pull, br, bd
	for _ = 1, 10 do
		wait(1)
		imp = (EntityGetInRadiusWithTag(PX + 150, PY, 8, "sf_implosion") or {})[1]
		if imp then
			local ic = EntityGetFirstComponentIncludingDisabled(imp, "ProjectileComponent")
			br = ic and ComponentObjectGetValue2(ic, "config_explosion", "explosion_radius")
			bd = ic and ComponentObjectGetValue2(ic, "config_explosion", "damage")
			local pv = EntityGetFirstComponentIncludingDisabled(imp, "VariableStorageComponent", "imp_pull_r")
			pull = pv and ComponentGetValue2(pv, "value_float")
			break
		end
	end
	result("O13 the slime / alcohol blast implodes", imp ~= nil and near(br, 5, 0.01) and near(bd, 8.25, 0.01) and near(pull, 22.5, 0.01),
		"implosion=" .. tostring(imp), "radius=" .. fmt(br), "damage=" .. fmt(bd), "pull=" .. fmt(pull), "(want 5 / 8.25 / 22.5)")
	kill(blast)
	quiet_cleanup()

	-- O14 Toxic charm -> a toxic target goes berserk; vanilla's charm on the same target as the control
	local fx14 = {}
	for i, cards in ipairs({ { "HITFX_TOXIC_CHARM", "LIGHT_BULLET" }, { "SIGN_FLIP", "HITFX_TOXIC_CHARM", "LIGHT_BULLET" } }) do
		local sheep = shoot_sheep(cards, 40, function(s)
			LoadGameEffectEntityTo(s, "data/entities/misc/effect_radioactive.xml")
			EntityAddRandomStains(s, CellFactory_GetType("radioactive_liquid"), 300)
		end)
		wait(30)
		fx14[i] = { charm = GameGetGameEffectCount(sheep, "CHARM"), berserk = GameGetGameEffectCount(sheep, "BERSERK") }
		kill(sheep)
		quiet_cleanup()
	end
	result("O14 flipped Toxic charm drives a toxic target berserk", fx14[2].berserk > 0 and fx14[2].charm == 0,
		"flipped: berserk=" .. fx14[2].berserk, "charm=" .. fx14[2].charm,
		"| vanilla control: charm=" .. fx14[1].charm, "berserk=" .. fx14[1].berserk)

	-- O15 Area damage -> heals: a bolt held still 10 px from a sheep at 39/40 heals it to 40, never past
	r = cast({ "SIGN_FLIP", "AREA_DAMAGE", "LIGHT_BULLET" })
	b = r.bolts[1]
	local sheep = spawn_sheep(PX + 100, PY - 60, 39)
	local hp_max = 0
	if b and EntityGetIsAlive(b) then
		local pc = EntityGetFirstComponentIncludingDisabled(b, "ProjectileComponent")
		ComponentSetValue2(pc, "collide_with_entities", false)
		ComponentSetValue2(pc, "lifetime", 300)
		ComponentSetValue2(EntityGetFirstComponentIncludingDisabled(b, "VelocityComponent"), "mVelocity", 0, 0)
		pin(b, PX + 100, PY - 50)
		for _ = 1, 20 do
			wait(1)
			hp_max = math.max(hp_max, hp(sheep))
		end
	end
	local damagers = b and EntityGetIsAlive(b) and #(EntityGetComponentIncludingDisabled(b, "AreaDamageComponent") or {}) or -1
	result("O15 flipped Area damage heals", has_script(b, "area_heal.lua") and near(hp(sheep), 40) and hp_max <= 40 and damagers == 0,
		"sheep hp 39 -> " .. fmt(hp(sheep)), "highest=" .. fmt(hp_max), "AreaDamageComponents=" .. damagers)
	kill(sheep, b)
	quiet_cleanup()

	-- O16 Curse -> blessing: the init on a hurt sheep blesses it, and it heals 0.08 every 30 frames
	r = cast({ "SIGN_FLIP", "CURSE", "LIGHT_BULLET" })
	local fx = hit_effects(r.bolts[1])
	quiet_cleanup()
	sheep = spawn_sheep(PX + 100, PY - 60, 20)
	local init = EntityLoad(SF .. "entities/hitfx_bless_init.xml", PX + 100, PY - 60)
	EntityAddChild(sheep, init)
	wait(75)
	local blessed = #(EntityGetAllChildren(sheep, "sf_blessing") or {})
	result("O16 flipped Curse blesses", fx == SF .. "entities/hitfx_bless_init.xml" and blessed == 1 and hp(sheep) > 20.1,
		"hit effects=" .. fx, "blessings=" .. blessed, "hp 20 -> " .. fmt(hp(sheep)) .. " after 75 frames (want about 20.16-20.24)")
	kill(sheep)

	-- O17 wither curses -> wards: the multiplier drops by 0.25 and comes back exactly when the ward ends
	for _, ty in ipairs({ "projectile", "explosion", "melee", "electricity" }) do
		r = cast({ "SIGN_FLIP", "CURSE_WITHER_" .. ty:upper(), "LIGHT_BULLET" })
		fx = hit_effects(r.bolts[1])
		quiet_cleanup()
		sheep = spawn_sheep(PX + 100, PY - 60, 40)
		local dm = EntityGetFirstComponentIncludingDisabled(sheep, "DamageModelComponent")
		local before = ComponentObjectGetValue2(dm, "damage_multipliers", ty)
		local ward = EntityLoad(SF .. "entities/hitfx_ward_" .. ty .. "_effect.xml", PX + 100, PY - 60)
		EntityAddChild(sheep, ward)
		wait(3)
		local during = ComponentObjectGetValue2(dm, "damage_multipliers", ty)
		EntityKill(ward)
		wait(3)
		local after = ComponentObjectGetValue2(dm, "damage_multipliers", ty)
		result("O17 flipped " .. ty .. " curse wards", fx == SF .. "entities/hitfx_ward_" .. ty .. "_effect.xml"
			and near(during, before - math.min(0.25, math.max(0, before))) and near(after, before),
			"hit effects=" .. fx, ty .. " multiplier " .. fmt(before) .. " -> " .. fmt(during) .. " -> " .. fmt(after))
		kill(sheep)
	end

	-- O18 Remove bounce -> doubles: the bolt's own bounces (B) double, at least 1, on top of the shot's flipped ones
	local function bounces(cards)
		local res = cast(cards)
		wait(2)
		local st = bolt_stats(res.bolts[1])
		local pc = res.bolts[1] and EntityGetIsAlive(res.bolts[1]) and EntityGetFirstComponentIncludingDisabled(res.bolts[1], "ProjectileComponent")
		local cfg = pc and ComponentObjectGetValue2(pc, "config", "bounces")
		local left = has_script(res.bolts[1], "double_bounce.lua")
		quiet_cleanup()
		return st and st.bounces, cfg, left
	end
	local own = bounces({ "LIGHT_BULLET" })
	local with_bounce, cfg_bounce = bounces({ "BOUNCE", "LIGHT_BULLET" })
	local one, _, left1 = bounces({ "SIGN_FLIP", "REMOVE_BOUNCE", "LIGHT_BULLET" })
	local more, cfg_more = bounces({ "BOUNCE", "SIGN_FLIP", "REMOVE_BOUNCE", "LIGHT_BULLET" })
	local want1 = own and math.max(2 * own, 1)
	result("O18 flipped Remove bounce doubles bounces", want1 and one == want1 and more == want1 + 20 and not left1,
		"own=" .. fmt(own), "flipped=" .. fmt(one) .. " (want " .. fmt(want1) .. ")", "with Bounce first=" .. fmt(more)
		.. " (want " .. fmt(want1 and want1 + 20) .. ")", "config.bounces=" .. fmt(cfg_more),
		"| plain Bounce: bounces_left=" .. fmt(with_bounce) .. " config.bounces=" .. fmt(cfg_bounce))

	-- O19 Crumbling earth -> solidify: when the bolt is removed it leaves the hardening burst behind
	r = cast({ "SIGN_FLIP", "CRUMBLING_EARTH_PROJECTILE", "LIGHT_BULLET" })
	b = r.bolts[1]
	local script19 = has_script(b, "solidify_earth.lua")
	local bx, by = PX, PY
	if b and EntityGetIsAlive(b) then
		bx, by = EntityGetTransform(b)
		EntityKill(b)
	end
	local burst, from
	for _ = 1, 5 do
		wait(1)
		for _, e in ipairs(EntityGetInRadius(bx, by, 40) or {}) do
			if (EntityGetFilename(e) or ""):find("solidify_earth_burst", 1, true) then
				burst = e
				local mc = EntityGetFirstComponentIncludingDisabled(e, "MagicConvertMaterialComponent")
				from = mc and ComponentGetValue2(mc, "from_material_array")
			end
		end
		if burst then
			break
		end
	end
	local loose = 0
	for _, e in ipairs(EntityGetInRadius(bx, by, 40) or {}) do
		loose = loose + #(EntityGetComponentIncludingDisabled(e, "LooseGroundComponent") or {})
	end
	result("O19 flipped Crumbling earth solidifies", script19 and burst ~= nil and loose == 0, "script=" .. tostring(script19),
		"burst=" .. tostring(burst), "from=" .. tostring(from), "LooseGroundComponents=" .. loose)
	quiet_cleanup()

	-- O20 Matter eater -> matter maker, last: it leaves rock in the air. Shot down-left, away from where later tests fire.
	r = cast({ "SIGN_FLIP", "MATTER_EATER", "LIGHT_BULLET" }, { dx = -1, dy = 1 })
	b = r.bolts[1]
	local script20 = has_script(b, "matter_maker.lua")
	local eaters = b and #(EntityGetComponentIncludingDisabled(b, "CellEaterComponent") or {}) or -1
	local path, emitters = {}, 0
	for _ = 1, 30 do
		if not b or not EntityGetIsAlive(b) then
			break
		end
		local x, y = EntityGetTransform(b)
		local d = math.sqrt((x - PX) ^ 2 + (y - PY) ^ 2)
		emitters = math.max(emitters, #(EntityGetComponentIncludingDisabled(b, "ParticleEmitterComponent", "matter_maker") or {}))
		-- the player is pinned in the air, so the flight is through open air until the bolt hits something
		if d > 40 then
			path[#path + 1] = { x, y }
		end
		wait(1)
	end
	wait(5)
	-- the last points are where the bolt hit: that terrain was there before
	for _ = 1, 2 do
		path[#path] = nil
	end
	local solid = 0
	for i = 1, #path - 1 do
		local x, y = path[i][1], path[i][2]
		if RaytraceSurfaces(x - 3, y - 3, x + 3, y + 3) then
			solid = solid + 1
		end
	end
	result("O20 flipped Matter eater leaves rock", script20 and eaters == 0 and #path > 2 and solid >= (#path - 1) / 2,
		"script=" .. tostring(script20), "CellEaterComponents=" .. eaters, "rock emitters=" .. emitters,
		"path points with rock=" .. solid .. "/" .. math.max(0, #path - 1))
	quiet_cleanup()
end

-- Random modifier: whatever it picks must come out exactly like the sweep's flipped cast of that modifier
local RANDOM_KEYS = { "damage_projectile_add", "speed_multiplier", "lifetime_add", "bounces", "gravity", "explosion_radius",
	"spread_degrees", "damage_ice_add", "damage_electricity_add" }
-- The pick is forced (probe/files/gun_append.lua wraps Random), so a pick that isn't flipped fails the check.
local function run_random()
	for _, id in ipairs({ "DAMAGE", "SPEED", "ORBIT_SHOT", "GRAVITY", "BOUNCE" }) do
		GlobalsSetValue("sfprobe_pick", id)
		local r = cast({ "SIGN_FLIP", "RANDOM_MODIFIER", "LIGHT_BULLET" })
		local ref = sweep[id]
		local bad = {}
		for _, k in ipairs(RANDOM_KEYS) do
			if not ref or not near(r.root[k], ref.flip[k]) then
				bad[#bad + 1] = ("%s=%s(want %s)"):format(k, fmt(r.root[k]), fmt(ref and ref.flip[k]))
			end
		end
		result("S8 Random modifier picks " .. id, #bad == 0 and r.root.sf_negated == id .. ",",
			"sf_negated=" .. tostring(r.root.sf_negated), table.concat(bad, " "))
		quiet_cleanup()
	end
	GlobalsSetValue("sfprobe_pick", "HOMING")
	local r = cast({ "SIGN_FLIP", "RANDOM_MODIFIER", "LIGHT_BULLET" })
	local h = r.bolts[1] and homing_coeffs(r.bolts[1]) or {}
	result("S8b Random modifier picks Homing: anti homing", #h == 1 and near(h[1], -130), "homing=" .. table.concat(h, ","))
	quiet_cleanup()
	GlobalsSetValue("sfprobe_pick", "SIGN_FLIP")
	r = cast({ "SIGN_FLIP", "RANDOM_MODIFIER", "DAMAGE", "LIGHT_BULLET" })
	result("S8c Random modifier picks Sign flip: cancels", near(damage_of(r), 0.4), "damage=" .. fmt(damage_of(r)))
	quiet_cleanup()
	GlobalsSetValue("sfprobe_pick", "")
end

-- wand economy: the "wand_numbers" setting, switched at runtime (read on every flip)
local function run_economy()
	local function both(cards, mode, opts)
		ModSettingSet("sign_flip.wand_numbers", mode)
		local plain = cast(cards, opts)
		quiet_cleanup()
		local with = { "SIGN_FLIP" }
		for _, id in ipairs(cards) do
			with[#with + 1] = id
		end
		local flip = cast(with, opts)
		quiet_cleanup()
		return plain, flip
	end
	for _, mode in ipairs({ "bonuses", "all", "none" }) do
		local p, f = both({ "RECHARGE", "LIGHT_BULLET" }, mode)
		local flips = mode ~= "none"
		result("E1 Reduce recharge time, " .. mode, near(f.root.fire_rate_wait, p.root.fire_rate_wait + (flips and 20 or 0))
			and near(f.root.reload, p.root.reload + (flips and 40 or 0)),
			"cast delay " .. fmt(p.root.fire_rate_wait) .. " -> " .. fmt(f.root.fire_rate_wait),
			"recharge " .. fmt(p.root.reload) .. " -> " .. fmt(f.root.reload),
			"(measured cast delay " .. p.cast_delay .. " -> " .. f.cast_delay .. ", recharge " .. p.recharge .. " -> " .. f.recharge .. ")")
		p, f = both({ "HEAVY_SHOT", "LIGHT_BULLET" }, mode)
		flips = mode == "all"
		result("E2 Heavy shot's cast delay, " .. mode, near(f.root.fire_rate_wait, p.root.fire_rate_wait - (flips and 20 or 0)),
			"cast delay " .. fmt(p.root.fire_rate_wait) .. " -> " .. fmt(f.root.fire_rate_wait),
			"(measured " .. p.cast_delay .. " -> " .. f.cast_delay .. ")")
		p, f = both({ "MANA_REDUCE", "LIGHT_BULLET" }, mode, { mana = 5000, charge = 0 })
		flips = mode ~= "none"
		-- the flipped cast also pays 10 for the Sign flip card
		result("E3 Add mana, " .. mode, near(f.root.mana, p.root.mana - 10 - (flips and 60 or 0)),
			"mana " .. fmt(p.root.mana) .. " -> " .. fmt(f.root.mana), "(wand after: " .. fmt(p.mana_after) .. " -> " .. fmt(f.mana_after) .. ")")
		p, f = both({ "DAMAGE_FOREVER", "LIGHT_BULLET" }, mode, { mana = 5000, charge = 0 })
		flips = mode == "all"
		-- "all": the spend turns into a gain, capped at the mana the shot started with (5000), then the Spark bolt's 5
		result("E4 Mana to damage, " .. mode, near(f.root.mana, flips and (5000 - 5) or p.root.mana)
			and near(damage_of(f), -0.025 * (5000 - 10 - 50)),
			"mana " .. fmt(p.root.mana) .. " -> " .. fmt(f.root.mana), "damage " .. fmt(damage_of(p)) .. " -> "
			.. fmt(damage_of(f)), "(wand after: " .. fmt(f.mana_after) .. ")")
	end
	ModSettingSet("sign_flip.wand_numbers", "bonuses")
end

-- what the engine does with flipped (negative) results; the user decided: no clamps, so these are observations
local function track(e, frames)
	local alive, last = 0, nil
	for t = 1, frames do
		if not EntityGetIsAlive(e) then
			break
		end
		alive = t
		last = bolt_stats(e)
		wait(1)
	end
	return alive, last
end

-- spell flip and implosions (files/scripts/implode_lib.lua) -------------------------------------------------------

local function imp_state(e)
	local v = e and EntityGetIsAlive(e) and EntityGetFirstComponentIncludingDisabled(e, "VariableStorageComponent", "sf_imp")
	if not v then
		return nil, ""
	end
	return ComponentGetValue2(v, "value_int"), ComponentGetValue2(v, "value_string")
end

local function run_implosions()
	-- I1 Black hole -> White hole
	equip({ "SIGN_FLIP", "BLACK_HOLE" })
	local snap = snapshot()
	fire(1, 0)
	local hole
	for _ = 1, 10 do
		for _, e in ipairs(EntityGetWithTag("projectile") or {}) do
			if not snap[e] and (EntityGetFilename(e) or ""):find("_hole", 1, true) then
				hole = e
			end
		end
		if hole then
			break
		end
		wait(1)
	end
	result("I1 flipped Black hole is a White hole", hole and (EntityGetFilename(hole) or ""):find("white_hole", 1, true) ~= nil,
		"spawned=" .. tostring(hole and EntityGetFilename(hole)))
	quiet_cleanup()

	-- I2 flipped Explosive projectile: the bolt implodes. At the implosion's centre a pinned 40-hp sheep (it must take
	-- the 3x blast), 22 px to the side a free one (it must be pulled in while the implosion lasts)
	local sheep = spawn_sheep(PX + 150, PY, 40)
	wait(3)
	local r = cast({ "SIGN_FLIP", "EXPLOSIVE_PROJECTILE", "LIGHT_BULLET" }, { dx = 150, dy = 0 })
	local bolt = r.bolts[1]
	local st = imp_state(bolt)
	wait(2)
	local st2, stash2 = imp_state(bolt)
	local pc = bolt and EntityGetIsAlive(bolt) and EntityGetFirstComponentIncludingDisabled(bolt, "ProjectileComponent")
	local rad = pc and ComponentObjectGetValue2(pc, "config_explosion", "explosion_radius")
	local imp, centre, victim, x0, xmin, blast_r, blast_d
	for _ = 1, 40 do
		if not imp then
			imp = EntityGetWithTag("sf_implosion")[1]
			if imp then
				local ix, iy = EntityGetTransform(imp)
				local ic = EntityGetFirstComponentIncludingDisabled(imp, "ProjectileComponent")
				blast_r = ic and ComponentObjectGetValue2(ic, "config_explosion", "explosion_radius")
				blast_d = ic and ComponentObjectGetValue2(ic, "config_explosion", "damage")
				centre = spawn_sheep(ix, iy, 40)
				victim = EntityLoad("data/entities/animals/sheep.xml", ix + 22, iy)
				local dm = EntityGetFirstComponentIncludingDisabled(victim, "DamageModelComponent")
				ComponentSetValue2(dm, "max_hp", 40)
				ComponentSetValue2(dm, "hp", 40)
				x0 = ix + 22
			end
		elseif victim and EntityGetIsAlive(victim) then
			local vx = EntityGetTransform(victim)
			xmin = math.min(xmin or vx, vx)
		end
		wait(1)
	end
	local R, D = stash2:match("^([^,]*),([^,]*),")
	local centre_hp = hp(centre)
	log("I2 marker state", tostring(st), "->", tostring(st2), "stash=" .. stash2, "neutered radius=" .. fmt(rad),
		"blast radius=" .. fmt(blast_r), "damage=" .. fmt(blast_d), "centre sheep hp=" .. fmt(centre_hp),
		"free sheep nearest x offset=" .. fmt(xmin and x0 and (xmin - x0)))
	result("I2 flipped Explosive projectile implodes", st2 == 2 and near(tonumber(R), 17, 0.01) and near(tonumber(D), 0.2, 0.01)
		and near(rad, 0) and near(blast_r, 17 / 3, 0.01) and near(blast_d, 0.6, 0.01) and centre_hp < 39.5,
		"stash R,D=" .. tostring(R) .. "," .. tostring(D), "blast " .. fmt(blast_r) .. "/" .. fmt(blast_d), "centre hp=" .. fmt(centre_hp))
	result("I2b the implosion pulls", xmin ~= nil and xmin < x0 - 3, "free sheep came " .. fmt(xmin and x0 and (x0 - xmin)) .. " px closer")
	kill(sheep, centre, victim)
	quiet_cleanup()

	-- I3 the spell's marker only acts on its own file: a double cast with a flipped Spark bolt and a Bubble spark
	local r = cast({ "BURST_2", "SIGN_FLIP", "LIGHT_BULLET", "BUBBLESHOT" })
	local spark = r.bolts[1]
	local bubble
	for _, p in ipairs(EntityGetWithTag("projectile") or {}) do
		if (EntityGetFilename(p) or ""):find("bubbleshot", 1, true) then
			bubble = p
		end
	end
	wait(2)
	local s1, s2 = imp_state(spark), imp_state(bubble)
	result("I3 spell marker acts on its own spell only", s1 == 2 and s2 == -1, "spark state=" .. tostring(s1),
		"bubble state=" .. tostring(s2), "(want 2 and -1)")
	quiet_cleanup()
end

local function run_behaviour()
	-- negative damage on a hurt sheep: a flipped Damage plus / Heavy shot heals it (net of the bolt's own 0.12)
	for _, test in ipairs({ { 0.48, "DAMAGE", "LIGHT_BULLET" }, { 1.28, "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET" },
		{ 2.63, "SIGN_FLIP", "HEAVY_SHOT", "LIGHT_BULLET" } }) do
		local cards = { unpack(test, 2) }
		local sheep = spawn_sheep(PX + 150, PY, 1.0)
		wait(3)
		local r = cast(cards, { dx = 150, dy = 0 })
		wait(30)
		-- a critical hit (5 % for a Spark bolt) multiplies the result, so only the direction is asserted
		local after = hp(sheep)
		result("B1 sheep at 1.0/40 hit by " .. table.concat(cards, ","), (test[1] > 1) == (after > 1.0) and after ~= 1.0,
			"bolt damage=" .. fmt(r.stats[1] and r.stats[1].damage), "healing=" .. fmt(r.stats[1] and r.stats[1].heal),
			"hp after=" .. fmt(after), "(expected about " .. test[1] .. ")")
		kill(sheep)
		quiet_cleanup()
	end
	-- negative lifetime, compared with vanilla's own (two Reduce lifetime: 40 - 84)
	for _, cards in ipairs({ { "LIGHT_BULLET" }, { "LIFETIME_DOWN", "LIFETIME_DOWN", "LIGHT_BULLET" },
		{ "SIGN_FLIP", "LIFETIME", "LIGHT_BULLET" } }) do
		local r = cast(cards, { dx = 0, dy = -1 })
		local frames = r.bolts[1] and track(r.bolts[1], 300) or -1
		log("B2 lifetime " .. table.concat(cards, ","), "lifetime=" .. fmt(r.stats[1] and r.stats[1].lifetime),
			"frames alive=" .. frames .. (frames >= 300 and "+" or ""))
		quiet_cleanup()
	end
	-- negative bounces: shot down at the ground
	for _, cards in ipairs({ { "BOUNCE", "LIGHT_BULLET" }, { "SIGN_FLIP", "BOUNCE", "LIGHT_BULLET" } }) do
		local r = cast(cards, { dx = 1, dy = 3 })
		local b = r.bolts[1]
		local first = r.stats[1]
		local frames, last = -1, nil
		if b then
			frames, last = track(b, 120)
		end
		log("B3 bounces " .. table.concat(cards, ","), "bounces_left=" .. fmt(first and first.bounces),
			"later=" .. fmt(last and last.bounces), "frames alive=" .. frames)
		quiet_cleanup()
	end
	-- explosion radius and damage, on the first frame and 5 frames later (Explosive tiny's script sets radius 5,
	-- Remove explosion's turns the explosion off); vanilla's own radius-32 spark for comparison
	for _, cards in ipairs({ { "EXPLOSIVE_PROJECTILE", "EXPLOSIVE_PROJECTILE", "LIGHT_BULLET" }, { "EXPLOSION_TINY", "LIGHT_BULLET" },
		{ "SIGN_FLIP", "EXPLOSION_TINY", "LIGHT_BULLET" }, { "SIGN_FLIP", "EXPLOSION_REMOVE", "LIGHT_BULLET" },
		{ "SIGN_FLIP", "EXPLOSIVE_PROJECTILE", "LIGHT_BULLET" } }) do
		local r = cast(cards, { dx = 0, dy = -1 })
		local s0 = r.stats[1]
		wait(5)
		local s5 = bolt_stats(r.bolts[1])
		log("B4 explosion " .. table.concat(cards, ","), "shot radius_add=" .. fmt(r.root.explosion_radius),
			"damage_add=" .. fmt(r.root.damage_explosion_add), "| frame 0: radius=" .. fmt(s0 and s0.expl_radius),
			"damage=" .. fmt(s0 and s0.expl_damage), "| frame 5: radius=" .. fmt(s5 and s5.expl_radius), "damage=" .. fmt(s5 and s5.expl_damage))
		quiet_cleanup()
	end
	-- does a negative explosion damage heal (it is not moved to healing: explosions have no healing type), and how hard
	-- does a flipped Explosive tiny hit (radius-32 damage, then radius 5)? Sheep at 1.0 and at full 40.
	for _, test in ipairs({ { 1.0, "EXPLOSIVE_PROJECTILE", "LIGHT_BULLET" }, { 1.0, "SIGN_FLIP", "EXPLOSIVE_PROJECTILE", "LIGHT_BULLET" },
		{ 40, "EXPLOSION_TINY", "LIGHT_BULLET" }, { 40, "SIGN_FLIP", "EXPLOSION_TINY", "LIGHT_BULLET" },
		{ 40, "EXPLOSIVE_PROJECTILE", "EXPLOSIVE_PROJECTILE", "LIGHT_BULLET" } }) do
		local cards = { unpack(test, 2) }
		local sheep = spawn_sheep(PX + 150, PY, test[1])
		wait(3)
		local r = cast(cards, { dx = 150, dy = 0 })
		wait(30)
		log("B5 hp of a sheep at " .. fmt(test[1]) .. "/40 hit by " .. table.concat(cards, ","), "bolt damage=" .. fmt(r.stats[1] and r.stats[1].damage),
			"explosion damage=" .. fmt(r.stats[1] and r.stats[1].expl_damage), "hp after=" .. fmt(hp(sheep)))
		kill(sheep)
		quiet_cleanup()
	end
end

-- Field Imbue together with Sign flip ("fi" / "fi-first" suites: Field Imbue loaded after / before sign_flip) -------

-- casts `cards` (ending in Circle of fervour) and parks the field in the bolt path; returns the field and its payload
local function cast_field(cards)
	equip(cards)
	local snap = snapshot()
	fire(1, 0)
	local field = wait_new(snap, "berserk_field", 20)
	if not field then
		return nil, nil, snap
	end
	EntitySetTransform(field, PX + 90, PY)
	wait(3) -- field_init.lua
	return field, vsc_str(field, "fi_payload"), snap
end

-- A spark bolt through the parked field: its stats on the frame before it was imbued and on the frame it was (the
-- field marks it with fi_mods), so air friction doesn't blur the speed factor; nil, stats if it was never imbued.
local function bolt_through()
	equip({ "LIGHT_BULLET" })
	local snap = snapshot()
	fire(1, 0)
	local bolt = own_bolts(snap, 1)[1]
	local before, after
	for _ = 1, 40 do
		if not bolt or not EntityGetIsAlive(bolt) then
			break
		end
		local now = bolt_stats(bolt)
		now.fi_mods = vsc_str(bolt, "fi_mods")
		if now.fi_mods or EntityGetTransform(bolt) > PX + 125 then
			after = now
			break
		end
		before = now
		wait(1)
	end
	return before, after, bolt
end

local function run_fi()
	local ok_r, R = pcall(dofile_once, "mods/field_imbue/files/gen/recipes.lua")
	local ok_s, S = pcall(dofile_once, "mods/field_imbue/files/gen/skipped.lua")
	result("F0 Sign flip has no Field Imbue recipe", ok_r and ok_s and R.SIGN_FLIP == nil and S.SIGN_FLIP ~= nil,
		"skipped: " .. tostring(ok_s and S.SIGN_FLIP))
	local cases = {
		{ "F1 flipped Damage plus field heals", { "FIELD_IMBUE", "SIGN_FLIP", "DAMAGE", "BERSERK_FIELD" }, "-DAMAGE", 0.12, -0.4 },
		{ "F2 plain Damage plus field", { "FIELD_IMBUE", "DAMAGE", "BERSERK_FIELD" }, "DAMAGE", 0.52, 0 },
		{ "F3 flipped and plain Damage plus", { "FIELD_IMBUE", "SIGN_FLIP", "DAMAGE", "DAMAGE", "BERSERK_FIELD" }, "-DAMAGE,DAMAGE", 0.52, -0.4 },
		{ "F5 flip wasted on Light", { "FIELD_IMBUE", "SIGN_FLIP", "LIGHT", "BERSERK_FIELD" }, "LIGHT" },
		{ "F7 flipped Homing field", { "FIELD_IMBUE", "SIGN_FLIP", "HOMING", "BERSERK_FIELD" }, "-HOMING" },
	}
	for _, case in ipairs(cases) do
		local field, payload = cast_field(case[2])
		if not field then
			result(case[1], false, "no field")
		else
			local sorted = {}
			for id in (payload or ""):gmatch("[^,]+") do
				sorted[#sorted + 1] = id
			end
			table.sort(sorted)
			payload = table.concat(sorted, ",")
			local _, after, bolt = bolt_through()
			local ok = payload == case[3] and after ~= nil
			if ok and case[4] then
				ok = near(after.damage, case[4]) and near(after.heal, case[5])
			end
			local h = bolt and EntityGetIsAlive(bolt) and homing_coeffs(bolt) or {}
			-- the circle itself carries none of the modifier's pieces (it must not steer away from enemies)
			local field_homing = #homing_coeffs(field)
			if ok and case[3] == "-HOMING" then
				ok = #h == 1 and near(h[1], -130) and field_homing == 0
			end
			result(case[1], ok, "payload=" .. tostring(payload), "(want " .. case[3] .. ")", "bolt after field: damage=" ..
				fmt(after and after.damage), "healing=" .. fmt(after and after.heal), "homing=" .. table.concat(h, ","),
				"field HomingComponents=" .. field_homing, "fi_mods=" .. tostring(after and after.fi_mods))
			kill(field)
		end
		quiet_cleanup()
	end
	-- the speed factor is inverted: x2.5 -> x0.4
	local field, payload = cast_field({ "FIELD_IMBUE", "SIGN_FLIP", "SPEED", "BERSERK_FIELD" })
	if field then
		local before, after = bolt_through()
		local ratio = before and after and after.speed / before.speed
		-- one frame of air friction (spark: 1.7) on top of x0.4
		result("F4 flipped Speed up field slows", payload == "-SPEED" and ratio and math.abs(ratio - 0.39) < 0.03,
			"payload=" .. tostring(payload), ("speed %s -> %s (ratio %s, want ~0.4)"):format(fmt(before and before.speed),
				fmt(after and after.speed), fmt(ratio)))
		kill(field)
	else
		result("F4 flipped Speed up field slows", false, "no field")
	end
	quiet_cleanup()
	-- a flipped Water to poison field runs poison -> water over its whole circle
	field, payload = cast_field({ "FIELD_IMBUE", "SIGN_FLIP", "WATER_TO_POISON", "BERSERK_FIELD" })
	local conv = field and converters(field) or ""
	result("F8 flipped converter field", payload == "-WATER_TO_POISON" and conv == "poison>water",
		"payload=" .. tostring(payload), "field converters=" .. conv, "(want one poison>water)")
	kill(field)
	quiet_cleanup()
	-- a flipped Fire trail field eats fire over its circle and hands the eater to bolts, without fire on hit
	field, payload = cast_field({ "FIELD_IMBUE", "SIGN_FLIP", "FIRE_TRAIL", "BERSERK_FIELD" })
	conv = field and converters(field) or ""
	local _, after, bolt = bolt_through()
	local bconv = bolt and EntityGetIsAlive(bolt) and converters(bolt) or ""
	local fx = bolt and EntityGetIsAlive(bolt) and ComponentGetValue2(EntityGetFirstComponentIncludingDisabled(bolt, "ProjectileComponent"),
		"damage_game_effect_entities") or "?"
	local fext, bext = field and extinguishes(field) or false, bolt and EntityGetIsAlive(bolt) and extinguishes(bolt) or false
	result("F9 flipped Fire trail field", payload == "-FIRE_TRAIL" and conv == "fire>air" and bconv == "fire>air" and fext
		and bext and not fx:find("on_fire", 1, true), "payload=" .. tostring(payload), "field converters=" .. conv,
		"extinguishes field/bolt=" .. tostring(fext) .. "/" .. tostring(bext), "bolt converters=" .. bconv, "bolt on-hit=" .. fx,
		"fi_mods=" .. tostring(after and after.fi_mods))
	kill(field)
	quiet_cleanup()
	-- a flip passes over Field resonance: "Sign flip -> Field resonance -> Damage plus" flips Damage plus too
	field, payload = cast_field({ "SIGN_FLIP", "FIELD_IMBUE", "DAMAGE", "BERSERK_FIELD" })
	result("F10 flip passes over Field resonance", payload == "-DAMAGE", "payload=" .. tostring(payload), "(want -DAMAGE)")
	kill(field)
	quiet_cleanup()
	-- ... also when Random modifier picks Field resonance (forced pick, probe/files/gun_append.lua)
	GlobalsSetValue("sfprobe_pick", "FIELD_IMBUE")
	local r = cast({ "SIGN_FLIP", "RANDOM_MODIFIER", "DAMAGE", "LIGHT_BULLET" })
	GlobalsSetValue("sfprobe_pick", "")
	result("F11 Random modifier's Field resonance passes the flip on", near(damage_of(r), -0.4), "damage=" .. fmt(damage_of(r)),
		"sf_negated=" .. tostring(r.root.sf_negated))
	quiet_cleanup()
	-- a flipped Explosive projectile circle makes the bolts crossing it implode
	field, payload = cast_field({ "FIELD_IMBUE", "SIGN_FLIP", "EXPLOSIVE_PROJECTILE", "BERSERK_FIELD" })
	local _, after12, bolt12 = bolt_through()
	wait(2)
	local st12 = bolt12 and EntityGetIsAlive(bolt12) and EntityGetFirstComponentIncludingDisabled(bolt12, "VariableStorageComponent", "sf_imp")
	local fst = field and EntityGetFirstComponentIncludingDisabled(field, "VariableStorageComponent", "sf_imp")
	result("F12 flipped Explosive projectile circle: bolts implode", payload == "-EXPLOSIVE_PROJECTILE"
		and st12 and ComponentGetValue2(st12, "value_int") == 2, "payload=" .. tostring(payload),
		"bolt state=" .. tostring(st12 and ComponentGetValue2(st12, "value_int")), "circle marker=" .. tostring(fst ~= nil),
		"fi_mods=" .. tostring(after12 and after12.fi_mods))
	kill(field)
	quiet_cleanup()
	-- a bolt in the same multicast as the imbuing field gets the shot's (flipped) gravity back on its first frame
	equip({ "BURST_2", "FIELD_IMBUE", "SIGN_FLIP", "GRAVITY", "LIGHT_BULLET", "BERSERK_FIELD" })
	local snap = snapshot()
	fire(1, 0)
	local bolt = own_bolts(snap, 1)[1]
	wait(3)
	local st = bolt_stats(bolt)
	result("F6 multicast sibling gets flipped gravity back", st and near(st.gravity, 200 - 600), "gravity_y=" .. fmt(st and st.gravity),
		"(want -400)", "fi_mods=" .. tostring(bolt and EntityGetIsAlive(bolt) and vsc_str(bolt, "fi_mods")))
	quiet_cleanup()
end

local function calibrate_fire()
	for _, mode in ipairs({ "hold", "force" }) do
		equip({ "LIGHT_BULLET" })
		local snap = snapshot()
		local ok = fire(0, -1, mode)
		local bolt = own_bolts(snap, 1)[1]
		log("CAL", mode, "shot_counter_up=" .. tostring(ok), "bolt_found=" .. tostring(bolt ~= nil))
		quiet_cleanup()
		if ok or bolt then
			FIRE_MODE = mode
			return true
		end
	end
	return false
end

local function run_all()
	log("START token=" .. TOKEN, "suite=" .. SUITE, "frame=" .. GameGetFrameNum(), ("player pinned at %.0f,%.0f"):format(PX, PY),
		"sign_flip enabled=" .. tostring(ModIsEnabled("sign_flip")), "field_imbue enabled=" .. tostring(ModIsEnabled("field_imbue")))
	if not calibrate_fire() then
		log("ABORT no fire method worked")
		log("DONE")
		return
	end
	local card = CreateItemActionEntity("SIGN_FLIP", PX, PY)
	result("C1 Sign flip card exists", card ~= 0, "entity=" .. card)
	kill(card)
	if SUITE == "main" then
		run_sweep()
		if next(ONLY) == nil then
			run_semantics()
			run_opposites()
			run_parts()
			run_random()
			run_economy()
			run_behaviour()
			run_implosions()
		end
	elseif SUITE == "fi" or SUITE == "fi-first" then
		run_fi()
	end
	log(("SUMMARY %d passed, %d failed"):format(n_pass, n_fail))
	log("DONE")
end

-- setup -----------------------------------------------------------------------------------------------------------

local function find_clear_spot(x, y)
	-- climb until a 260px-wide horizontal band is free of cells
	for step = 0, 12 do
		local ty = y - 200 - step * 60
		local clear = true
		for _, oy in ipairs({ -70, -40, 0, 30 }) do
			if Raytrace(x - 40, ty + oy, x + 260, ty + oy) then
				clear = false
			end
		end
		if clear then
			return x, ty
		end
	end
	return x, y - 300
end

local started = false

function OnPlayerSpawned(player_entity)
	player = player_entity
end

function OnWorldPostUpdate()
	if not player or not EntityGetIsAlive(player) then
		return
	end
	if not started then
		if GameGetFrameNum() < 180 then
			return
		end
		started = true
		local x, y = EntityGetTransform(player)
		PX, PY = find_clear_spot(x, y)
		local comp, _ = GetGameEffectLoadTo(player, "PROTECTION_ALL", true)
		if comp then
			ComponentSetValue2(comp, "frames", -1)
		end
		local inv = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
		current_wand = ComponentGetValue2(inv, "mActualActiveItem")
		if current_wand == 0 or not ability() then
			log("START token=" .. TOKEN, "suite=" .. SUITE) -- so tools/probe-run.sh sees this run's ABORT
			log("ABORT player holds no wand")
			log("DONE")
			return
		end
		ctrl = EntityGetFirstComponentIncludingDisabled(player, "ControlsComponent")
		ComponentSetValue2(ctrl, "enabled", false)
		pin(player, PX, PY)
		runner = coroutine.create(run_all)
	end
	apply_pins()
	if runner and coroutine.status(runner) ~= "dead" then
		local ok, err = coroutine.resume(runner)
		if not ok then
			log("ERROR", err)
		end
	end
end
