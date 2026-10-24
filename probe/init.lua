-- sign_flip probes: in-game checks for Sign flip, run automatically after the player spawns. Every result is an
-- "SFPROBE" line in logger.txt. Meant for an isolated prefix (tools/probe-run.sh): it rewrites the player's held
-- starting wand, pins the player in the air and fires by driving ControlsComponent. The harness (pinning, firing,
-- rewriting the wand, calibration) comes from Field Imbue's probe, which found out what works.

local MOD = "mods/sign_flip_probe/"

ModMagicNumbersFileAdd(MOD .. "files/magic_numbers.xml") -- makes Lua print() reach logger.txt
ModLuaFileAppend("data/scripts/gun/gun.lua", MOD .. "files/gun_append.lua")

-- suite.txt (written by tools/probe-run.sh): line 1 suite ("main", "fi"), line 2 optional sweep ids, line 3 run token
local ok_suite, SUITE_TEXT = pcall(ModTextFileGetContent, MOD .. "suite.txt")
if not ok_suite or not SUITE_TEXT then
	SUITE_TEXT = "main"
end
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

local function sweep_one(id, base)
	local plain = cast({ id, "LIGHT_BULLET" })
	quiet_cleanup()
	local flip = cast({ "SIGN_FLIP", id, "LIGHT_BULLET" })
	quiet_cleanup()
	sweep[id] = { plain = plain.root, flip = flip.root }
	local bad = {}
	local b, p, f = base.root, plain.root, flip.root
	local heal = 0
	for _, k in ipairs(SHOT_ADD) do
		if not near(p[k], b[k]) then
			local want = 2 * b[k] - p[k]
			if SHOT_DAMAGE[k] and p[k] > b[k] then
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
		if not near(p[k], b[k]) and p[k] ~= 0 and not near(f[k], b[k] * b[k] / p[k]) then
			bad[#bad + 1] = ("shot.%s=%s(want %s)"):format(k, fmt(f[k]), fmt(b[k] * b[k] / p[k]))
		end
	end
	for _, k in ipairs({ "fire_rate_wait", "reload" }) do
		local d = p[k] - b[k]
		local want = b[k] + (d < 0 and -d or d) -- default setting: only a bonus flips
		if d ~= 0 and not near(f[k], want) then
			bad[#bad + 1] = ("shot.%s=%s(want %s)"):format(k, fmt(f[k]), fmt(want))
		end
	end
	if not result("SWEEP-SHOT " .. id, #bad == 0 and f.sf_negated == id .. ",", "sf_negated=" .. tostring(f.sf_negated),
		table.concat(bad, " ")) then
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
	r = cast({ "SIGN_FLIP", "HOMING", "DAMAGE", "LIGHT_BULLET" })
	want("S10 nothing to flip: wasted", damage_of(r), 0.4)
	quiet_cleanup()
end

-- Random modifier: whatever it picks must come out exactly like the sweep's flipped cast of that modifier
local RANDOM_KEYS = { "damage_projectile_add", "speed_multiplier", "lifetime_add", "bounces", "gravity", "explosion_radius",
	"spread_degrees", "damage_ice_add", "damage_electricity_add" }
local function run_random()
	local seen = 0
	for i = 1, 16 do
		local r = cast({ "SIGN_FLIP", "RANDOM_MODIFIER", "LIGHT_BULLET" })
		local id = (r.root.sf_negated or ""):match("^([%w_]+),$")
		local ref = id and sweep[id]
		if ref then
			local bad = {}
			for _, k in ipairs(RANDOM_KEYS) do
				if not near(r.root[k], ref.flip[k]) then
					bad[#bad + 1] = ("%s=%s(want %s)"):format(k, fmt(r.root[k]), fmt(ref.flip[k]))
				end
			end
			seen = seen + 1
			result("S8 Random modifier picked " .. id, #bad == 0, table.concat(bad, " "))
		else
			log("S8 Random modifier shot " .. i, "sf_negated=" .. tostring(r.root.sf_negated), "(pick without a sweep entry)")
		end
		quiet_cleanup()
	end
	log("S8 Random modifier: " .. seen .. "/16 picks checked against the sweep")
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
		result("E4 Mana to damage, " .. mode, near(f.root.mana, flips and (2 * (5000 - 10) - 50 - 5) or p.root.mana)
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

local function run_behaviour()
	-- negative damage on a hurt sheep
	for _, cards in ipairs({ { "DAMAGE", "LIGHT_BULLET" }, { "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET" },
		{ "SIGN_FLIP", "HEAVY_SHOT", "LIGHT_BULLET" } }) do
		local sheep = spawn_sheep(PX + 150, PY, 1.0)
		wait(3)
		local r = cast(cards, { dx = 150, dy = 0 })
		wait(30)
		log("B1 hp of a sheep at 1.0/40 hit by " .. table.concat(cards, ","), "bolt damage=" .. fmt(r.stats[1] and r.stats[1].damage),
			"healing=" .. fmt(r.stats[1] and r.stats[1].heal), "hp after=" .. fmt(hp(sheep)))
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
	return before, after
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
		{ "F5 flip wasted on Homing", { "FIELD_IMBUE", "SIGN_FLIP", "HOMING", "BERSERK_FIELD" }, "HOMING" },
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
			local _, after = bolt_through()
			local ok = payload == case[3] and after ~= nil
			if ok and case[4] then
				ok = near(after.damage, case[4]) and near(after.heal, case[5])
			end
			result(case[1], ok, "payload=" .. tostring(payload), "(want " .. case[3] .. ")", "bolt after field: damage=" ..
				fmt(after and after.damage), "healing=" .. fmt(after and after.heal), "fi_mods=" .. tostring(after and after.fi_mods))
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
			run_random()
			run_economy()
			run_behaviour()
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
