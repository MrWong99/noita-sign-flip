-- Offline check of Sign flip against vanilla's real wand code: loads data/scripts/gun/gun.lua (with this mod's appends,
-- and optionally Entangled Worlds' and Field Imbue's) under LuaJIT with the engine stubbed, runs the mods' init
-- builders, casts wands through the deck code and compares each shot's final state with what a flip should give.
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
-- the sim's own mod (below): loaded first, so every mod sees its modifiers
local sim_actions
local APPENDS = { ["data/scripts/gun/gun_actions.lua"] = { function() sim_actions() end } }
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
-- virtual files written by ModTextFileSetContent (the mods' init-time builders)
local vfs = {}
local function read(p)
	if vfs[p] then
		return vfs[p]
	end
	local f = io.open(resolve(p), "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end
function ModTextFileGetContent(p)
	return read(p)
end
function ModTextFileSetContent(p, s)
	vfs[p] = s
end
function ModDoesFileExist(p)
	return read(p) ~= nil
end
local real_dofile = dofile
function dofile(p)
	local r
	if vfs[p] then
		r = assert(loadstring(vfs[p], p))()
	else
		r = real_dofile(resolve(p))
	end
	for _, extra in ipairs(APPENDS[p] or {}) do
		if type(extra) == "function" then
			extra()
		else
			real_dofile(resolve(extra))
		end
	end
	return r
end
-- the cache lives where Noita keeps it, so the builders' cleanup (which empties it) works here too
__loadonce = {}
function dofile_once(p)
	if __loadonce[p] == nil then
		__loadonce[p] = { dofile(p) }
	end
	return unpack(__loadonce[p])
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

-- the sim's own mod: modifiers that draw the way some modded ones do (S15), one that raises (S16b), and parts with edge
-- cases for the opposites builder (O10, O11)
local SIM = "mods/sim/files/"
ModTextFileSetContent(SIM .. "homing_tag.xml", [[<Entity>
	<HomingComponent homing_targeting_coeff="40" />
	<MagicConvertMaterialComponent from_material_tag="[liquid]" to_material="blood" radius="8" />
	<MagicConvertMaterialComponent from_material="water" to_material="oil" radius="8" />
</Entity>
]])
ModTextFileSetContent(SIM .. "base_homing.xml", '<Entity>\n\t<Base file="data/entities/misc/homing.xml" />\n</Entity>\n')
function sim_actions()
	local function mk(id, action)
		table.insert(actions, { id = id, name = id, description = "", sprite = "", type = ACTION_TYPE_MODIFIER,
			spawn_level = "1", spawn_probability = "0", price = 100, mana = 0, action = action })
	end
	local function damage()
		c.damage_projectile_add = c.damage_projectile_add + 0.4
	end
	mk("XM_NORMAL", function()
		damage()
		draw_actions(1, true)
	end)
	mk("XM_DIRECT", function()
		damage()
		draw_action(true)
	end)
	local captured = draw_action -- at load time: draws past Sign flip's hooks
	mk("XM_LOCAL1", function()
		damage()
		captured(true)
	end)
	mk("XM_RAISE", function()
		damage()
		current_reload_time = current_reload_time + 30
		error("sim: XM_RAISE")
	end)
	for _, part in ipairs({ { "XM_HOMING_TAG", "homing_tag.xml" }, { "XM_BASE_HOMING", "base_homing.xml" } }) do
		mk(part[1], function()
			c.extra_entities = c.extra_entities .. SIM .. part[2] .. ","
			draw_actions(1, true)
		end)
	end
end

-- mod init: each mod's OnModPostInit (init.lua), in mod order
local BUILDERS = { sf = "mods/sign_flip/files/scripts/opposites_build.lua",
	fi = "mods/field_imbue/files/scripts/recipes_build.lua" }
for mod in ORDER:gmatch("[^,]+") do
	if BUILDERS[mod] then
		dofile(BUILDERS[mod])
	end
end
dofile("data/scripts/gun/gun.lua")
local OPP = vfs["mods/sign_flip/files/gen/opposites.lua"] and dofile_once("mods/sign_flip/files/gen/opposites.lua")
local FI = vfs["mods/field_imbue/files/gen/recipes.lua"] and dofile_once("mods/field_imbue/files/scripts/fi_lib.lua")
local real_draw_actions, real_draw_action = draw_actions, draw_action

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
local function has(str, piece)
	return str:find(piece, 1, true) ~= nil
end
-- a whole entry of a comma-separated list (flipped files contain the vanilla path: gen/flip/data/entities/...)
local function entry(list, e)
	return ("," .. list):find("," .. e .. ",", 1, true) ~= nil
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
	if a.type == ACTION_TYPE_MODIFIER and not SWEEP_SKIP[a.id] and a.id:sub(1, 3) ~= "FI_" and a.id:sub(1, 3) ~= "XM_" then
		for _, mode in ipairs({ "bonuses", "all", "none" }) do
			local ok1, plain = pcall(cast, { a.id, "LIGHT_BULLET" }, { mode = mode })
			local ok2, flip = pcall(cast, { "SIGN_FLIP", a.id, "LIGHT_BULLET" }, { mode = mode })
			local tag = a.id .. "/" .. mode
			if not (ok1 and ok2) then
				errors = errors + 1
				print("ERROR " .. tag .. " " .. tostring(ok1 and flip or plain))
				break
			end
			-- recorded for Field Imbue: projectile numbers or parts flipped (not cast delay, recharge, mana, recoil)
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
			end
			local r = (plain.reload or 0) - (base.reload or 0)
			if r ~= 0 then
				local flips = mode == "all" or (mode == "bonuses" and r < 0)
				check(tag, "reload", flip.reload, base.reload + (flips and -r or r))
				row[#row + 1] = ("recharge %+g->%+g"):format(r, flip.reload - base.reload)
			end
			if (a.mana or 0) < 0 then -- Add mana: paid out at draw time
				local flips = mode ~= "none"
				local m = plain.mana - base.mana
				check(tag, "mana", flip.mana - base.mana + SF_MANA, flips and -m or m)
				row[#row + 1] = ("mana %+g->%+g"):format(m, flip.mana - base.mana + SF_MANA)
			end
			local rk = (plain.recoil or 0) - (base.recoil or 0)
			if rk ~= 0 then
				check(tag, "recoil", flip.recoil, base.recoil - rk)
				row[#row + 1] = ("recoil %+g->%+g"):format(rk, flip.recoil - base.recoil)
			end
			-- opposites: the extras / trail the flipped cast ends up with
			if flip.c.extra_entities ~= plain.c.extra_entities or flip.c.trail_material ~= plain.c.trail_material then
				flips_any = true
				local e = {}
				for f in flip.c.extra_entities:sub(#base.c.extra_entities + 1):gmatch("[^,]+") do
					e[#e + 1] = (f:gsub("^mods/sign_flip/files/gen/", "gen:"):gsub("data/entities/misc/", ""))
				end
				row[#row + 1] = "parts=" .. table.concat(e, ", ")
				if flip.c.trail_material ~= plain.c.trail_material then
					row[#row + 1] = "no trail"
				end
				if flip.c.game_effect_entities ~= plain.c.game_effect_entities then
					row[#row + 1] = "no on-hit effect"
				end
			end
			check(tag, "sf_negated", flip.c.sf_negated, flips_any and (a.id .. ",") or nil)
			if mode == "bonuses" and os.getenv("SIM_TABLE") == "md" then
				local cells = {}
				for i, cell in ipairs(row) do
					cell = cell:gsub("%->", " → "):gsub("gen:flip/data/entities/particles/", "flipped ")
					cells[i] = "`" .. cell:gsub("gen:flip/", "flipped "):gsub("gen:eat/", "eater of ")
						:gsub("data/entities/particles/", "") .. "`"
				end
				rows[#rows + 1] = ("| `%s` | %s |"):format(a.id, #cells > 0 and table.concat(cells, " · ") or "nothing to flip (wasted)")
			elseif mode == "bonuses" then
				rows[#rows + 1] = ("%-28s %s"):format(a.id, #row > 0 and table.concat(row, "  ") or "(nothing to flip)")
			end
		end
	end
end
if os.getenv("SIM_TABLE") == "md" then -- docs/modifier-flips.md
	print([[# What Sign flip does to each vanilla modifier

Generated with `SIM_TABLE=md luajit tools/sim.lua <unpacked data.wak> | sed '/^-- opposites/,$d' > docs/modifier-flips.md`
(default setting "Bonuses only"). Each entry reads *what the modifier does → what the flipped modifier does*, relative to
a plain Spark bolt.
- `healing`: damage moved to the healing type, because the engine ignores negative damage.
- `parts`: the extra entities the flipped cast carries. `flipped X` is X with its homing reversed or its converters run
  backwards; `eater of M` takes material M away around the projectile.
- Cast delay and recharge only flip when they were a bonus; `mana` is Add mana's gain.

Not in the table: Sign flip itself, Random modifier (its pick is flipped), Random damage and Mana to damage (their
numbers depend on the frame and on the wand's mana; they flip like any other).

| Modifier | Flipped |
|---|---|]])
	print(table.concat(rows, "\n"))
elseif os.getenv("SIM_TABLE") then
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

r = cast({ "SIGN_FLIP", "LIGHT", "DAMAGE", "LIGHT_BULLET" })
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
-- "all": the spend turns into a gain, but a flip gives back at most the mana the shot started with (so the wand's mana
-- doesn't grow on every cast), or what the wand had before the modifier if that was more
r = cast({ "SIGN_FLIP", "DAMAGE_FOREVER", "LIGHT_BULLET" }, { mode = "all" })
check("S13b Mana to damage, all: gives back up to the shot's mana", "mana", r.mana, base.mana)
r = cast({ "MANA_REDUCE", "SIGN_FLIP", "DAMAGE_FOREVER", "LIGHT_BULLET" }, { mode = "all" })
check("S13c ... or up to the mana before it", "mana", r.mana, addmana.mana - SF_MANA)

-- Field Imbue's Field resonance is not a flip consumer: a pending flip passes over it to the next modifier
if ORDER:find("fi", 1, true) then
	local FIELD = "mods/field_imbue/files/entities/field_imbue.xml"
	r = cast({ "SIGN_FLIP", "FIELD_IMBUE", "DAMAGE", "LIGHT_BULLET" })
	check("S14 flip passes over Field resonance", "damage", net(r.c), dmg - plus)
	check("S14", "sf_negated", r.c.sf_negated, "DAMAGE,")
	check("S14", "field part kept", entry(r.c.extra_entities, FIELD), true)
	r = cast({ "SIGN_FLIP", "FIELD_IMBUE", "LIGHT_BULLET" })
	check("S14b nothing after it: the flip stays pending", "sf_pending", r.c.sf_pending, 1)
	check("S14b", "sf_negated", r.c.sf_negated, nil)
	r = cast({ "SIGN_FLIP", "RANDOM_MODIFIER", "DAMAGE", "LIGHT_BULLET" }, { pick = "FIELD_IMBUE" })
	check("S14c Random modifier picks Field resonance: hands the flip on", "damage", net(r.c), dmg - plus)
	check("S14c", "sf_negated", r.c.sf_negated, "DAMAGE,")
	check("S14c", "field part kept", entry(r.c.extra_entities, FIELD), true)
end

-- modded modifiers (the sim's own mod) that draw with draw_action, or with a draw function they captured at load time,
-- which goes past the hooks: their changes mix with the drawn cards', so that flip is used up
local ref = cast({ "SIGN_FLIP", "XM_NORMAL", "LIGHT_BULLET" })
check("S15 modded modifier", "damage", ref.c.damage_projectile_add, base.c.damage_projectile_add)
check("S15", "healing", ref.c.damage_healing_add, base.c.damage_healing_add - plus)
r = cast({ "SIGN_FLIP", "XM_DIRECT", "LIGHT_BULLET" })
check("S15b one drawing with draw_action flips the same", "damage", r.c.damage_projectile_add, ref.c.damage_projectile_add)
check("S15b", "healing", r.c.damage_healing_add, ref.c.damage_healing_add)
check("S15b", "spark's own crit", r.c.damage_critical_chance, base.c.damage_critical_chance)
check("S15b", "sf_negated", r.c.sf_negated, "XM_DIRECT,")
r = cast({ "SIGN_FLIP", "RANDOM_MODIFIER", "LIGHT_BULLET" }, { pick = "XM_DIRECT" })
check("S15c ... as Random modifier's pick", "healing", r.c.damage_healing_add, ref.c.damage_healing_add)
check("S15c", "sf_negated", r.c.sf_negated, "XM_DIRECT,")
r = cast({ "SIGN_FLIP", "XM_LOCAL1", "LIGHT_BULLET" })
check("S15d one drawing past the hooks: flip used up", "damage", net(r.c), dmg + plus)
check("S15d", "spark's own crit", r.c.damage_critical_chance, base.c.damage_critical_chance)
check("S15d", "sf_negated", r.c.sf_negated, nil)
r = cast({ "SIGN_FLIP", "XM_LOCAL1", "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET" })
check("S15e ... a Sign flip it draws still flips", "healing", r.c.damage_healing_add, base.c.damage_healing_add - plus)
check("S15e", "sf_negated", r.c.sf_negated, "DAMAGE,")
r = cast({ "SIGN_FLIP", "RANDOM_MODIFIER", "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET" }, { pick = "XM_LOCAL1" })
check("S15f ... also as Random modifier's pick", "healing", r.c.damage_healing_add, base.c.damage_healing_add - plus)
check("S15f", "sf_negated", r.c.sf_negated, "DAMAGE,")

-- An error aborts the cast: the flipped modifier rethrows it without flipping or recording anything more, and puts the
-- draw functions back. Spark bolt raises after changing the shot and the wand (restored afterwards).
local delay = cast({ "DAMAGE", "LIGHT_BULLET" }).c.fire_rate_wait - base.c.fire_rate_wait -- Damage plus' cast delay
local spark
for _, a in ipairs(actions) do
	if a.id == "LIGHT_BULLET" then
		spark = a
	end
end
local spark_action, seed = spark.action, SetRandomSeed
spark.action = function()
	c.damage_projectile_add = c.damage_projectile_add + 5
	c.fire_rate_wait = c.fire_rate_wait + 7
	c.speed_multiplier = c.speed_multiplier * 2
	current_reload_time = current_reload_time + 30
	error("sim: spark")
end
local function raising(cards, mode)
	local ok, err = pcall(cast, cards, { mode = mode })
	SetRandomSeed = seed -- Entangled Worlds' action wrapper doesn't put it back on an error
	return { err = not ok and tostring(err) or "", c = c, mana = mana, reload = current_reload_time,
		hooked = draw_actions ~= real_draw_actions or draw_action ~= real_draw_action }
end
for _, mode in ipairs({ "bonuses", "all" }) do
	local tag = "S16 error in a flipped cast (" .. mode .. ")"
	local p, f = raising({ "DAMAGE", "LIGHT_BULLET" }, mode), raising({ "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET" }, mode)
	check(tag, "rethrown", has(f.err, "sim: spark"), true)
	check(tag, "draw functions put back", f.hooked, false)
	-- Damage plus' own changes were flipped when it drew; the spark's stay as they are
	check(tag, "damage", f.c.damage_projectile_add, p.c.damage_projectile_add - plus)
	check(tag, "healing", f.c.damage_healing_add, p.c.damage_healing_add - plus)
	check(tag, "speed", f.c.speed_multiplier, p.c.speed_multiplier)
	check(tag, "cast delay", f.c.fire_rate_wait, p.c.fire_rate_wait - (mode == "all" and 2 * delay or 0))
	check(tag, "recharge", f.reload, p.reload)
	check(tag, "mana", f.mana, p.mana - SF_MANA)
	check(tag, "sf_negated", f.c.sf_negated, nil)
	-- the modifier itself raises before drawing, with the hooks in place
	tag = "S16b error in the flipped modifier (" .. mode .. ")"
	p, f = raising({ "XM_RAISE", "LIGHT_BULLET" }, mode), raising({ "SIGN_FLIP", "XM_RAISE", "LIGHT_BULLET" }, mode)
	check(tag, "rethrown", has(f.err, "sim: XM_RAISE"), true)
	check(tag, "draw functions put back", f.hooked, false)
	check(tag, "damage", net(f.c), net(p.c))
	check(tag, "recharge", f.reload, p.reload)
	check(tag, "mana", f.mana, p.mana - SF_MANA)
	check(tag, "sf_negated", f.c.sf_negated, nil)
end
spark.action = spark_action
r = cast({ "SIGN_FLIP", "DAMAGE", "LIGHT_BULLET" })
check("S16c casts after the errors", "healing", r.c.damage_healing_add, base.c.damage_healing_add - plus)
check("S16c", "spark's own crit", r.c.damage_critical_chance, base.c.damage_critical_chance)

-- opposites (files/scripts/opposites_build.lua) -----------------------------------------------------------------------

local function parts(cards)
	local s = cast(cards).c
	return s.extra_entities .. "|" .. s.trail_material .. "|" .. s.game_effect_entities
end
local GEN = "mods/sign_flip/files/gen/"
local GENF = GEN .. "flip/data/entities/misc/"
if OPP then
	local p = parts({ "SIGN_FLIP", "HOMING", "LIGHT_BULLET" })
	check("O1 Homing -> anti", "parts", entry(p, GENF .. "homing.xml") and not entry(p, "data/entities/misc/homing.xml"), true)
	check("O1", "coefficient", (vfs[GENF .. "homing.xml"] or ""):match('homing_targeting_coeff="([^"]*)"'), "-130")
	p = parts({ "SIGN_FLIP", "ANTI_HOMING", "LIGHT_BULLET" })
	check("O2 Anti homing -> homing", "coefficient", (vfs[GENF .. "anti_homing.xml"] or ""):match('homing_targeting_coeff="([^"]*)"'), "130")
	check("O2", "parts", has(p, GENF .. "anti_homing.xml,"), true)
	p = parts({ "SIGN_FLIP", "WATER_TO_POISON", "LIGHT_BULLET" })
	local w2p = vfs[GENF .. "water_to_poison.xml"] or ""
	check("O3 Water to poison runs backwards", "parts", has(p, GENF .. "water_to_poison.xml,"), true)
	check("O3", "converters", select(2, w2p:gsub("<MagicConvertMaterialComponent", "")), 1)
	check("O3", "poison to water", w2p:match('from_material="([^"]*)"') .. ">" .. w2p:match('to_material="([^"]*)"'), "poison>water")
	p = parts({ "SIGN_FLIP", "FIRE_TRAIL", "LIGHT_BULLET" })
	local plain_fire = parts({ "FIRE_TRAIL", "LIGHT_BULLET" })
	check("O4 Fire trail eats fire", "parts", has(p, "mods/sign_flip/files/gen/eat/fire.xml,") and not has(p, "fire,|")
		and has(plain_fire, "effect_apply_on_fire") and not has(p, "effect_apply_on_fire"), true)
	p = parts({ "SIGN_FLIP", "BURN_TRAIL", "LIGHT_BULLET" })
	check("O5 Burning trail eats fire", "parts", has(p, "mods/sign_flip/files/gen/eat/fire.xml,") and not has(p, "misc/burn.xml")
		and not has(p, "effect_apply_on_fire"), true)
	p = parts({ "SIGN_FLIP", "FLY_UPWARDS", "LIGHT_BULLET" })
	check("O6 Fly upwards -> downwards", "parts", has(p, "misc/fly_downwards.xml,") and not has(p, "misc/fly_upwards.xml"), true)
	p = parts({ "SIGN_FLIP", "LARPA_UPWARDS", "LIGHT_BULLET" })
	check("O7 Larpa upwards -> downwards", "parts", has(p, "misc/larpa_downwards.xml,") and not has(p, "misc/larpa_upwards.xml"), true)
	p = parts({ "SIGN_FLIP", "SIGN_FLIP", "HOMING", "LIGHT_BULLET" })
	check("O8 cancelled flip keeps Homing", "parts", has(p, "data/entities/misc/homing.xml,") and not has(p, GENF), true)
	p = parts({ "SIGN_FLIP", "FREEZE", "LIGHT_BULLET" })
	local fc = vfs["mods/sign_flip/files/gen/flip/data/entities/particles/freeze_charge.xml"] or ""
	check("O9 Freeze charge melts", "parts", has(p, "gen/flip/data/entities/particles/freeze_charge.xml,"), true)
	check("O9", "converter", (fc:match('to_material="([^"]*)"') or "?") .. "<" .. (fc:match('from_material="([^"]*)"') or "?"),
		"water<ice_static")
	-- edge cases (the sim's own parts): a converter that can't run backwards stays as it is next to the flipped homing;
	-- an included file (<Base>) is flipped in its own file
	local ht = GEN .. "flip/" .. SIM .. "homing_tag.xml"
	local htx = vfs[ht] or ""
	check("O10 homing + tag converter", "replacement", OPP.extra[SIM .. "homing_tag.xml"], ht)
	check("O10", "coefficient", htx:match('homing_targeting_coeff="([^"]*)"'), "-40")
	check("O10", "tag converter kept", has(htx, 'from_material_tag="[liquid]" to_material="blood"'), true)
	check("O10", "converter reversed", has(htx, 'from_material="oil" to_material="water"'), true)
	p = parts({ "SIGN_FLIP", "XM_HOMING_TAG", "LIGHT_BULLET" })
	check("O10", "parts", entry(p, ht) and not entry(p, SIM .. "homing_tag.xml"), true)
	local bh = GEN .. "flip/" .. SIM .. "base_homing.xml"
	check("O11 <Base> homing", "replacement", OPP.extra[SIM .. "base_homing.xml"], bh)
	check("O11", "base", (vfs[bh] or ""):match('<Base file="([^"]*)"'), GENF .. "homing.xml")
	p = parts({ "SIGN_FLIP", "XM_BASE_HOMING", "LIGHT_BULLET" })
	check("O11", "parts", entry(p, bh) and not entry(p, SIM .. "base_homing.xml"), true)
	-- burning grass or wood stays its own material: a fire eater also puts out what burns
	local fire, water = vfs[GEN .. "eat/fire.xml"] or "", vfs[GEN .. "eat/water.xml"]
	check("O12 fire eater puts fires out", "extinguish_fire", has(fire, 'extinguish_fire="1"'), true)
	check("O12", "water eater doesn't", water ~= nil and not has(water, "extinguish_fire"), true)
	if os.getenv("SIM_TABLE") then
		print("-- opposites")
		for _, kind in ipairs({ "extra", "eat" }) do
			local keys = {}
			for k in pairs(OPP[kind]) do
				if k:sub(1, #SIM) ~= SIM then -- not the sim's own parts
					keys[#keys + 1] = k
				end
			end
			table.sort(keys)
			for _, k in ipairs(keys) do
				print(("%-6s %-50s -> %s%s"):format(kind, k, OPP[kind][k], OPP.drops_effects[k] and " (drops on-hit effects)" or ""))
			end
		end
	end
end

-- Field Imbue (files/scripts/fi_lib.lua): a field cast with a flipped modifier carries "-<ID>", and that recipe must do
-- to the projectiles crossing the field what the flip does in a cast ------------------------------------------------

if FI and OPP then
	-- the shot fields a recipe carries (Field Imbue's files/scripts/recipes_build.lua)
	local FI_ADD = { "damage_projectile_add", "damage_melee_add", "damage_electricity_add", "damage_fire_add",
		"damage_explosion_add", "damage_ice_add", "damage_slice_add", "damage_healing_add", "damage_curse_add",
		"damage_drill_add", "explosion_radius", "damage_critical_chance", "knockback_force", "lifetime_add", "bounces",
		"gravity" }
	local function list(t) -- a recipe's list the way the shot carries it
		return #(t or {}) > 0 and table.concat(t, ",") .. "," or ""
	end
	local function since(now, was) -- what the cast appended
		return now:sub(#was + 1)
	end
	local R, ids = FI.recipes(), {}
	for id in pairs(R) do
		if id ~= "XM_LOCAL1" then -- draws past the hooks: its flip is used up (S15d)
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local tag, n = "F " .. id, FI.recipe("-" .. id)
		local ok, flip = pcall(cast, { "SIGN_FLIP", id, "LIGHT_BULLET" })
		if not ok then
			errors = errors + 1
			print("ERROR " .. tag .. " " .. tostring(flip))
		else
			local s = flip.c
			for _, k in ipairs(FI_ADD) do -- healing included: damage the flip takes away heals
				local d, want = s[k] - base.c[k], (n.add or {})[k] or 0
				if d ~= 0 or want ~= 0 then
					check(tag, k, d, want)
				end
			end
			check(tag, "speed", s.speed_multiplier / base.c.speed_multiplier, n.speed or 1)
			check(tag, "extras", since(s.extra_entities, base.c.extra_entities), list(n.extra_entities))
			check(tag, "trail", since(s.trail_material, base.c.trail_material), list(n.trail_material))
			check(tag, "on-hit effects", since(s.game_effect_entities, base.c.game_effect_entities),
				list(n.game_effect_entities))
			-- recorded in the cast (so the field gets the .neg marker) iff the negation is a recipe of its own
			check(tag, "sf_negated", s.sf_negated ~= nil, n.negated == true)
		end
	end
	-- what Field Imbue's register_action hook leaves on an imbuing field's shot
	local MARK = "mods/field_imbue/files/gen/mod/"
	local e = cast({ "FIELD_IMBUE", "SIGN_FLIP", "HOMING", "BERSERK_FIELD" }).c.extra_entities
	check("F1 field with a flipped Homing", "marker", entry(e, MARK .. "HOMING.neg.xml") and not entry(e, MARK .. "HOMING.xml"),
		true)
	check("F1", "homing kept off", entry(e, GENF .. "homing.xml") or entry(e, "data/entities/misc/homing.xml"), false)
	e = cast({ "FIELD_IMBUE", "SIGN_FLIP", "DAMAGE", "DAMAGE", "BERSERK_FIELD" }).c.extra_entities
	check("F2 Damage plus flipped and not", "markers", entry(e, MARK .. "DAMAGE.neg.xml") and entry(e, MARK .. "DAMAGE.xml"),
		true)
	e = cast({ "SIGN_FLIP", "FIELD_IMBUE", "DAMAGE", "BERSERK_FIELD" }).c.extra_entities
	check("F3 flip passes over Field resonance", "marker",
		entry(e, MARK .. "DAMAGE.neg.xml") and not entry(e, MARK .. "DAMAGE.xml"), true)
	e = cast({ "FIELD_IMBUE", "SIGN_FLIP", "FIRE_TRAIL", "BERSERK_FIELD" }).c.extra_entities
	check("F4 field with a flipped Fire trail", "marker", entry(e, MARK .. "FIRE_TRAIL.neg.xml"), true)
	check("F4", "fire eater kept off", entry(e, GEN .. "eat/fire.xml"), false)
end

print(("%d checks, %d failed, %d modifiers errored (order %s)"):format(checks, fails, errors, ORDER))
os.exit((fails == 0 and errors == 0) and 0 or 1)
