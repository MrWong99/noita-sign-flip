-- Offline check of Sign flip against vanilla's real wand code: loads data/scripts/gun/gun.lua (with this mod's appends,
-- and optionally Entangled Worlds' and Field Imbue's) under LuaJIT with the engine stubbed, casts wands through the
-- deck code and compares each shot's final state with what a flip should give.
--   usage: luajit tools/sim.lua <dir containing data/ (tools/unwak.py output)> [mod order, e.g. ew,fi,sf]
--   SIM_TABLE=1 also prints what each vanilla modifier changes and what the flipped cast gets.
-- Prints "FAIL" lines for mismatches and a summary; exit code 1 if anything failed.
local WAK = assert(arg[1], "usage: luajit tools/sim.lua <unpacked data.wak dir> [ew,fi,sf]")
local REPO = arg[0]:match("^(.*)/tools/[^/]*$") or "."
local ORDER = arg[2] or "sf"
local HOME = os.getenv("HOME")
local NOITA = os.getenv("NOITA") or (HOME .. "/.local/share/Steam/steamapps/common/Noita")
local ROOTS = {
	{ "data/", WAK .. "/data/" },
	{ "mods/sign_flip/", REPO .. "/" },
	{ "mods/quant.ew/", NOITA .. "/mods/quant.ew/" },
	{ "mods/field_imbue/", HOME .. "/field_imbue/" },
}
local MOD_APPENDS = {
	sf = { { "data/scripts/gun/gun_actions.lua", "mods/sign_flip/files/actions.lua" },
		{ "data/scripts/gun/gun.lua", "mods/sign_flip/files/gun_append.lua" } },
	ew = { { "data/scripts/gun/gun.lua", "mods/quant.ew/files/resource/append/gun.lua" },
		{ "data/scripts/gun/gun_actions.lua", "mods/quant.ew/files/resource/append/action_fix.lua" } },
	fi = { { "data/scripts/gun/gun_actions.lua", "mods/field_imbue/files/actions.lua" },
		{ "data/scripts/gun/gun.lua", "mods/field_imbue/files/gun_append.lua" } },
}
local APPENDS = {}
for mod in ORDER:gmatch("[^,]+") do
	for _, ap in ipairs(assert(MOD_APPENDS[mod], "unknown mod " .. mod)) do
		APPENDS[ap[1]] = APPENDS[ap[1]] or {}
		table.insert(APPENDS[ap[1]], ap[2])
	end
end

local function resolve(p)
	for _, r in ipairs(ROOTS) do
		if p:sub(1, #r[1]) == r[1] then
			return r[2] .. p:sub(#r[1] + 1)
		end
	end
	return p
end
local real_dofile = dofile
function dofile(p)
	local r = real_dofile(resolve(p))
	for _, extra in ipairs(APPENDS[p] or {}) do
		real_dofile(resolve(extra))
	end
	return r
end
local once = {}
function dofile_once(p)
	if once[p] == nil then
		once[p] = { dofile(p) }
	end
	return unpack(once[p])
end

-- engine stubs ------------------------------------------------------------------------------------------------------

setmetatable(_G, { __index = function(_, k)
	if type(k) == "string" and k:match("^[A-Z]") then
		return function() end
	end
end })
local settings = {}
function ModSettingGet(k)
	return settings[k]
end
function GameGetFrameNum() return 100 end
function GetUpdatedEntityID() return 1 end
function EntityGetRootEntity(e) return e end
function EntityGetTransform() return 10, 20 end
function EntityHasTag() return false end
function EntityGetName() return "" end
function EntityGetWithTag() return {} end
function EntityGetInRadiusWithTag() return {} end
function EntityGetAllChildren() return {} end
function GlobalsGetValue(_, d) return d end
function HasFlagPersistent() return true end
function ActionUsesRemainingChanged() return true end
local rng = 1
function SetRandomSeed(a, b) rng = math.floor((a or 0) * 31 + (b or 0)) % 2147483648 end
local force_pick -- action id Random modifier must pick
function Random(a, b)
	if force_pick and a == 1 and b == #actions then
		for i, act in ipairs(actions) do
			if act.id == force_pick then
				return i
			end
		end
	end
	rng = (rng * 1103515245 + 12345) % 2147483648
	if not a then
		return rng / 2147483648
	end
	return a + rng % (b - a + 1)
end

local shots, reload_frames, recoil, depth
local function copy(t)
	local o = {}
	for k, v in pairs(t) do
		o[k] = v
	end
	return o
end
function BeginTriggerTimer() depth = depth + 1 end
BeginTriggerHitWorld, BeginTriggerDeath = BeginTriggerTimer, BeginTriggerTimer
function EndTrigger() depth = depth - 1 end
function SetProjectileConfigs() table.insert(shots, { state = copy(c), depth = depth }) end
function StartReload(t) reload_frames = t end
function RegisterGunShotEffects(r) recoil = r end

dofile("data/scripts/gun/gun.lua")

-- casting -----------------------------------------------------------------------------------------------------------

local WAND_DELAY, WAND_RELOAD, WAND_MANA, SF_MANA = 10, 20, 1000, 10

local function cast(cards, opts)
	opts = opts or {}
	shots, reload_frames, recoil, depth = {}, nil, nil, 0
	settings["sign_flip.wand_numbers"] = opts.mode
	force_pick = opts.pick
	_clear_deck(false)
	for i, id in ipairs(cards) do
		_add_card_to_deck(id, i, -1, true)
	end
	gun.actions_per_round = opts.per_round or 1
	gun.shuffle_deck_when_empty = false
	gun.reload_time = WAND_RELOAD
	state_from_game = {}
	ConfigGunActionInfo_Init(state_from_game)
	state_from_game.fire_rate_wait = WAND_DELAY
	_start_shot(WAND_MANA)
	for _, id in ipairs(opts.always or {}) do
		_play_permanent_card(id)
	end
	_draw_actions_for_shot(true)
	local root = shots[#shots]
	return { c = root and root.state or {}, shots = shots, mana = mana, reload = reload_frames, recoil = recoil }
end

-- checks ------------------------------------------------------------------------------------------------------------

local fails, checks = 0, 0
local function near(a, b)
	return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 * math.max(1, math.abs(b))
end
local function check(tag, what, got, want)
	checks = checks + 1
	local ok = (type(want) == "number" and near(got, want)) or got == want
	if not ok then
		fails = fails + 1
		print(("FAIL %s %s = %s (want %s)"):format(tag, what, tostring(got), tostring(want)))
	end
	return ok
end

local ADD = { "damage_projectile_add", "damage_electricity_add", "damage_explosion_add", "damage_ice_add",
	"damage_critical_chance", "explosion_radius", "knockback_force", "lifetime_add", "bounces", "gravity",
	"spread_degrees" }
-- a flip that takes damage of these types away goes to damage_healing_add (files/gun_append.lua, DAMAGE)
local DAMAGE = { damage_projectile_add = true, damage_electricity_add = true, damage_ice_add = true }
-- depend on things the flipped cast changes on its own: the Sign flip card's mana cost, the pick, the frame number
local SWEEP_SKIP = { SIGN_FLIP = true, RANDOM_MODIFIER = true, DAMAGE_RANDOM = true, DAMAGE_FOREVER = true }

-- every vanilla modifier: [SIGN_FLIP, X, LIGHT_BULLET] against [X, LIGHT_BULLET] and [LIGHT_BULLET]
local base = cast({ "LIGHT_BULLET" })
local rows, errors = {}, 0
for _, a in ipairs(actions) do
	if a.type == ACTION_TYPE_MODIFIER and not SWEEP_SKIP[a.id] and a.id:sub(1, 3) ~= "FI_" then
		for _, mode in ipairs({ "bonuses", "all", "none" }) do
			local ok1, plain = pcall(cast, { a.id, "LIGHT_BULLET" }, { mode = mode })
			local ok2, flip = pcall(cast, { "SIGN_FLIP", a.id, "LIGHT_BULLET" }, { mode = mode })
			local tag = a.id .. "/" .. mode
			if not (ok1 and ok2) then
				errors = errors + 1
				print("ERROR " .. tag .. " " .. tostring(ok1 and flip or plain))
				break
			end
			local row, flips_any, heal = {}, false, 0
			for _, k in ipairs(ADD) do
				local b, p = base.c[k], plain.c[k]
				-- a modifier that clamps (Light shot: radius >= 0) is flipped by what it actually changed
				if not near(p, b) then
					local want = 2 * b - p
					if DAMAGE[k] and p > b then
						heal, want = heal + (b - p), b
					end
					check(tag, k, flip.c[k], want)
					row[#row + 1] = ("%s %+g->%+g"):format(k, p - b, flip.c[k] - b)
					flips_any = true
				end
			end
			check(tag, "damage_healing_add", flip.c.damage_healing_add, base.c.damage_healing_add + heal)
			if heal ~= 0 then
				row[#row + 1] = ("healing %+g"):format(heal)
			end
			for _, k in ipairs({ "speed_multiplier", "child_speed_multiplier" }) do
				local b, p = base.c[k], plain.c[k]
				if not near(p, b) and p ~= 0 then
					check(tag, k, flip.c[k], b * b / p)
					row[#row + 1] = ("%s x%.4g->x%.4g"):format(k, p / b, flip.c[k] / b)
					flips_any = true
				end
			end
			local d = plain.c.fire_rate_wait - base.c.fire_rate_wait
			if d ~= 0 then
				local flips = mode == "all" or (mode == "bonuses" and d < 0)
				check(tag, "fire_rate_wait", flip.c.fire_rate_wait, base.c.fire_rate_wait + (flips and -d or d))
				row[#row + 1] = ("cast_delay %+g->%+g"):format(d, flip.c.fire_rate_wait - base.c.fire_rate_wait)
				flips_any = flips_any or flips
			end
			local r = (plain.reload or 0) - (base.reload or 0)
			if r ~= 0 then
				local flips = mode == "all" or (mode == "bonuses" and r < 0)
				check(tag, "reload", flip.reload, base.reload + (flips and -r or r))
				row[#row + 1] = ("recharge %+g->%+g"):format(r, flip.reload - base.reload)
				flips_any = flips_any or flips
			end
			if (a.mana or 0) < 0 then -- Add mana: paid out at draw time
				local flips = mode ~= "none"
				local m = plain.mana - base.mana
				check(tag, "mana", flip.mana - base.mana + SF_MANA, flips and -m or m)
				row[#row + 1] = ("mana %+g->%+g"):format(m, flip.mana - base.mana + SF_MANA)
				flips_any = flips_any or flips
			end
			local rk = (plain.recoil or 0) - (base.recoil or 0)
			if rk ~= 0 then
				check(tag, "recoil", flip.recoil, base.recoil - rk)
				row[#row + 1] = ("recoil %+g->%+g"):format(rk, flip.recoil - base.recoil)
				flips_any = true
			end
			check(tag, "sf_negated", flip.c.sf_negated, flips_any and (a.id .. ",") or nil)
			if mode == "bonuses" then
				rows[#rows + 1] = ("%-28s %s"):format(a.id, #row > 0 and table.concat(row, "  ") or "(nothing to flip)")
			end
		end
	end
end
if os.getenv("SIM_TABLE") then
	print(table.concat(rows, "\n"))
end

-- semantics ---------------------------------------------------------------------------------------------------------

-- damage net of healing (a flip that takes damage away heals instead)
local function net(state)
	return state.damage_projectile_add + state.damage_healing_add
end
local dmg = net(base.c)
local plus = net(cast({ "DAMAGE", "LIGHT_BULLET" }).c) - dmg -- +0.4
local heavy = net(cast({ "HEAVY_SHOT", "LIGHT_BULLET" }).c) - dmg -- +1.75

local r = cast({ "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET" })
check("S0 flipped damage heals", "damage", r.c.damage_projectile_add, base.c.damage_projectile_add)
check("S0", "healing", r.c.damage_healing_add, base.c.damage_healing_add - plus)

r = cast({ "SIGN_FLIP", "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET" })
check("S1 two Sign flips cancel", "damage", net(r.c), dmg + plus)
check("S1", "sf_negated", r.c.sf_negated, nil)

r = cast({ "SIGN_FLIP", "DAMAGE", "SIGN_FLIP", "HEAVY_SHOT", "LIGHT_BULLET" })
check("S2 each flips its next", "damage", net(r.c), dmg - plus - heavy)
check("S2", "speed", r.c.speed_multiplier, 1 / 0.3)
check("S2", "sf_negated", r.c.sf_negated, "HEAVY_SHOT,DAMAGE,")

r = cast({ "SIGN_FLIP", "SIGN_FLIP", "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET" })
check("S3 three Sign flips = one", "damage", net(r.c), dmg - plus)

r = cast({ "SIGN_FLIP", "DAMAGE", "HEAVY_SHOT", "LIGHT_BULLET" })
check("S4 only the next modifier", "damage", net(r.c), dmg - plus + heavy)

r = cast({ "SIGN_FLIP", "BURST_2", "DAMAGE", "LIGHT_BULLET", "LIGHT_BULLET" })
check("S5 through a multicast", "damage", net(r.c), 2 * dmg - plus)
r = cast({ "BURST_2", "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET", "LIGHT_BULLET" })
check("S5b inside a multicast", "damage", net(r.c), 2 * dmg - plus)
r = cast({ "SIGN_FLIP", "LIGHT_BULLET", "DAMAGE", "LIGHT_BULLET" }, { per_round = 2 })
check("S5c projectile in between", "damage", net(r.c), 2 * dmg - plus)

r = cast({ "SIGN_FLIP", "LIGHT_BULLET_TRIGGER", "DAMAGE", "LIGHT_BULLET" })
check("S6 trigger payload not flipped", "payload damage", net(r.shots[1].state), dmg + plus)
check("S6", "outer flip left unused", r.shots[#r.shots].state.sf_pending, 1)
r = cast({ "LIGHT_BULLET_TRIGGER", "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET" })
check("S6b flip inside the payload", "payload damage", net(r.shots[1].state), dmg - plus)

r = cast({ "DAMAGE", "LIGHT_BULLET" }, { always = { "SIGN_FLIP" } })
check("S7 always-cast Sign flip", "damage", net(r.c), dmg - plus)
r = cast({ "SIGN_FLIP", "LIGHT_BULLET" }, { always = { "DAMAGE" } })
check("S7b always-cast modifier plays first", "damage", net(r.c), dmg + plus)
r = cast({ "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET" }, { always = { "SIGN_FLIP" } })
check("S7c always-cast + deck Sign flip cancel", "damage", net(r.c), dmg + plus)

r = cast({ "SIGN_FLIP", "RANDOM_MODIFIER", "LIGHT_BULLET" }, { pick = "DAMAGE" })
check("S8 Random modifier's pick is flipped", "damage", net(r.c), dmg - plus)
check("S8", "sf_negated", r.c.sf_negated, "DAMAGE,")
r = cast({ "SIGN_FLIP", "RANDOM_MODIFIER", "DAMAGE", "LIGHT_BULLET" }, { pick = "SIGN_FLIP" })
check("S8b Random modifier picks Sign flip: cancels", "damage", net(r.c), dmg + plus)
r = cast({ "RANDOM_MODIFIER", "DAMAGE", "LIGHT_BULLET" }, { pick = "SIGN_FLIP" })
check("S8c unflipped Random modifier picks Sign flip", "damage", net(r.c), dmg - plus)

local orbit = cast({ "ORBIT_SHOT", "LIGHT_BULLET" })
r = cast({ "SIGN_FLIP", "ORBIT_SHOT", "LIGHT_BULLET" })
check("S9 change after drawing (Orbit shot)", "lifetime", r.c.lifetime_add, 2 * base.c.lifetime_add - orbit.c.lifetime_add)
check("S9", "damage", net(r.c), 2 * dmg - net(orbit.c))

r = cast({ "SIGN_FLIP", "HOMING", "DAMAGE", "LIGHT_BULLET" })
check("S10 nothing to flip: wasted", "damage", net(r.c), dmg + plus)
check("S10", "sf_negated", r.c.sf_negated, nil)

r = cast({ "SIGN_FLIP", "LIGHT_BULLET" })
check("S11 no modifier after it", "damage", net(r.c), dmg)

local addmana = cast({ "MANA_REDUCE", "LIGHT_BULLET" })
r = cast({ "SIGN_FLIP", "MANA_REDUCE", "LIGHT_BULLET" })
check("S12 Add mana drains", "mana", r.mana, addmana.mana - SF_MANA - 60)
r = cast({ "SIGN_FLIP", "MANA_REDUCE", "LIGHT_BULLET" }, { mode = "none" })
check("S12b setting none", "mana", r.mana, addmana.mana - SF_MANA)

-- Mana to damage turns the wand's mana above 50 into damage; the Sign flip card's own cost comes out of that mana
local m2d = cast({ "DAMAGE_FOREVER", "LIGHT_BULLET" })
r = cast({ "SIGN_FLIP", "DAMAGE_FOREVER", "LIGHT_BULLET" })
check("S13 Mana to damage, bonuses: mana use stays", "mana", r.mana, m2d.mana)
check("S13", "damage", net(r.c), dmg - 0.025 * (WAND_MANA - SF_MANA - 50))
r = cast({ "SIGN_FLIP", "DAMAGE_FOREVER", "LIGHT_BULLET" }, { mode = "all" })
check("S13b Mana to damage, all: hands out mana", "mana", r.mana, (WAND_MANA - SF_MANA) * 2 - 50 - 5)

print(("%d checks, %d failed, %d modifiers errored (order %s)"):format(checks, fails, errors, ORDER))
os.exit((fails == 0 and errors == 0) and 0 or 1)
