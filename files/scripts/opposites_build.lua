-- Runs once from init.lua's OnModPostInit, after every mod's spells exist. Works out what a flipped modifier does to
-- the things it adds to the shot (files/gun_append.lua applies it) and writes the files for that:
--   mods/sign_flip/files/gen/opposites.lua    { extra = { [file] = replacement file },
--                                               eat = { [trail material] = eater file },
--                                               drops_effects = { [file] = true } }
--   mods/sign_flip/files/gen/flip/<path>      an extra entity with its homing reversed / converters run backwards
--   mods/sign_flip/files/gen/eat/<mat>.xml    turns that material back into air around the projectile
-- Every modifier is evaluated the way vanilla builds spell tooltips (reflecting = true), so other mods' modifiers are
-- covered too. The same mods give every Entangled Worlds peer the same files.

local GEN = "mods/sign_flip/files/gen/"

-- vanilla pairs that differ in a script, not in a number
local PAIRS = {
	["data/entities/misc/fly_upwards.xml"] = "data/entities/misc/fly_downwards.xml",
	["data/entities/misc/fly_downwards.xml"] = "data/entities/misc/fly_upwards.xml",
	["data/entities/misc/larpa_upwards.xml"] = "data/entities/misc/larpa_downwards.xml",
	["data/entities/misc/larpa_downwards.xml"] = "data/entities/misc/larpa_upwards.xml",
}

-- The spell flip (files/gun_append.lua, run_spell_flipped): Black hole <-> White hole, as files. Each pair differs only
-- in the sign of its pull and in looks.
local HOLES = {
	["data/entities/projectiles/deck/black_hole.xml"] = "data/entities/projectiles/deck/white_hole.xml",
	["data/entities/projectiles/deck/black_hole_big.xml"] = "data/entities/projectiles/deck/white_hole_big.xml",
	["data/entities/projectiles/deck/black_hole_giga.xml"] = "data/entities/projectiles/deck/white_hole_giga.xml",
}
-- The implode marker for one spell's file: merged into the whole shot like any extra entity, it only acts on
-- projectiles made from that file (files/scripts/implode.lua). Flipped explosion modifiers use the unfiltered
-- files/entities/implode.xml.
local IMPLODE = "mods/sign_flip/files/entities/implode.xml"
local SPELL_MARKER = '<Entity>\n\t<VariableStorageComponent _tags="sf_implode" name="sf_implode" value_string="%s" />\n'
	.. '\t<LuaComponent _tags="sf_implode" script_source_file="mods/sign_flip/files/scripts/implode.lua" '
	.. 'execute_on_added="1" execute_every_n_frame="-1" />\n'
	.. '\t<LuaComponent _tags="sf_implode" script_source_file="mods/sign_flip/files/scripts/implode_arm.lua" '
	.. 'execute_every_n_frame="1" remove_after_executed="1" />\n'
	.. '\t<LuaComponent _tags="sf_implode" script_source_file="mods/sign_flip/files/scripts/implode_death.lua" '
	.. 'execute_on_removed="1" execute_every_n_frame="-1" />\n</Entity>\n'

local ENGINE_STUBS = { "EntityLoad", "BeginProjectile", "EndProjectile", "RegisterProjectile", "RegisterGunAction",
	"RegisterGunShotEffects", "BeginTriggerTimer", "BeginTriggerHitWorld", "BeginTriggerDeath", "EndTrigger",
	"SetProjectileConfigs", "StartReload", "ActionUsesRemainingChanged", "ActionUsed", "LogAction", "OnActionPlayed",
	"OnNotEnoughManaForAction", "Reflection_RegisterProjectile" }

local backup = {}
for k, v in pairs(_G) do
	backup[k] = v
end
-- dofile/dofile_once caches: entries added while loading gun.lua must go too (see the restore below)
local cache_keys = {}
for _, name in ipairs({ "__loadonce", "__loaded" }) do
	cache_keys[name] = {}
	for k in pairs(type(_G[name]) == "table" and _G[name] or {}) do
		cache_keys[name][k] = true
	end
end

local function file_text(path)
	local ok, text = pcall(ModTextFileGetContent, path)
	return ok and text or nil
end

local function lit(s) -- a string used as a gsub replacement
	return (s:gsub("%%", "%%%%"))
end

-- the comma-separated entries a modifier appended to a list
local function added(before, after)
	local out = {}
	if type(before) == "string" and type(after) == "string" and after:sub(1, #before) == before then
		for entry in after:sub(#before + 1):gmatch("[^,]+") do
			out[#out + 1] = entry
		end
	end
	return out
end

-- what one modifier adds: extra entities, trail materials
local function evaluate(a)
	local base = {}
	ConfigGunActionInfo_Init(base)
	c = {}
	ConfigGunActionInfo_Init(c)
	shot_effects = {}
	ConfigGunShotEffects_Init(shot_effects)
	current_reload_time, mana = 0, 1000
	reflecting, dont_draw_actions = true, true
	local ok = pcall(a.action, 1, 1)
	reflecting, dont_draw_actions = false, false
	if not ok then
		return {}, {}
	end
	return added(base.extra_entities, c.extra_entities), added(base.trail_material, c.trail_material)
end

-- the entity files a projectile spell adds; spells that pick one at random (Firework, Summon egg) run with a few seeds
local function spell_files(a)
	local files, known, seed = {}, {}, 0
	Reflection_RegisterProjectile = function(f)
		if type(f) == "string" and not known[f] then
			known[f] = true
			files[#files + 1] = f
		end
	end
	GameGetFrameNum = function()
		return seed * 37
	end
	-- the i-th run picks the i-th option wherever the spell rolls (the backup/restore after build() puts these back)
	SetRandomSeed = function() end
	Random = function(a, b)
		if not a then
			return ((seed - 1) % 8) / 8
		elseif not b then
			a, b = 1, a
		end
		return a + (seed - 1) % (b - a + 1)
	end
	for i = 1, 8 do
		seed = i
		c = {}
		ConfigGunActionInfo_Init(c)
		shot_effects = {}
		ConfigGunShotEffects_Init(shot_effects)
		current_reload_time, mana = 0, 1000
		reflecting, dont_draw_actions = true, true
		pcall(a.action, 1, 1)
		reflecting, dont_draw_actions = false, false
	end
	Reflection_RegisterProjectile = function() end
	return files
end

-- MagicConvertMaterialComponent from one material to another: run it backwards. Anything else (a material tag, a
-- converter waiting for a script, no target) can't be reversed and is left out.
local function reverse_converter(attrs)
	local from = attrs:match('%sfrom_material%s*=%s*"([^"]*)"')
	local to = attrs:match('%sto_material%s*=%s*"([^"]*)"')
	if not from or not to or from == "" or to == "" or attrs:find("from_material_tag", 1, true)
		or attrs:find('_enabled%s*=%s*"0"') then
		return nil
	end
	attrs = attrs:gsub('(%sfrom_material%s*=%s*")[^"]*"', "%1" .. lit(to) .. '"')
	return (attrs:gsub('(%sto_material%s*=%s*")[^"]*"', "%1" .. lit(from) .. '"'))
end

local flipped_xml

-- The flipped version of an extra entity file, written to gen/flip/<file>; nil if nothing in it can be flipped. Files
-- it includes (<Base file="...">) are flipped too, up to a few levels deep.
local flip_paths = {} -- file -> generated path, or false
local function flip_path(f, depth)
	if flip_paths[f] == nil then
		flip_paths[f] = false -- also ends a file that includes itself
		local text = depth <= 4 and file_text(f)
		local flipped = text and flipped_xml(text, depth)
		if flipped then
			flip_paths[f] = GEN .. "flip/" .. f
			ModTextFileSetContent(flip_paths[f], flipped)
		end
	end
	return flip_paths[f] or nil
end

-- the flipped version of an extra entity's XML, or nil if nothing in it can be flipped
function flipped_xml(text, depth)
	local changed = false
	text = text:gsub('(<Base%s[^>]-file%s*=%s*")([^"]+)(")', function(a, p, b)
		local fp = flip_path(p, depth + 1)
		if fp then
			changed = true
			return a .. fp .. b
		end
	end)
	-- Homing <-> Anti homing: vanilla's Anti homing is Homing with the targeting coefficient's sign flipped
	text = text:gsub('(<HomingComponent[^>]-%shoming_targeting_coeff%s*=%s*")([^"]*)(")', function(a, v, b)
		local n = tonumber(v)
		if n and n ~= 0 then
			changed = true
			return a .. tostring(-n) .. b
		end
	end)
	-- Converters run backwards. One that can't stays as it is (like a modifier with no opposite); a later one from the
	-- same material is dropped (Water to poison turns water, ice and static water into poison: backwards it is poison to
	-- water).
	local reversed, from_seen = 0, {}
	local function convert(attrs, rest)
		local r = reverse_converter(attrs)
		if not r then
			return nil -- gsub keeps the original
		end
		local from = r:match('%sfrom_material%s*=%s*"([^"]*)"')
		if from_seen[from] then
			return ""
		end
		from_seen[from] = true
		reversed = reversed + 1
		return "<MagicConvertMaterialComponent" .. r .. rest
	end
	text = text:gsub("<MagicConvertMaterialComponent([^>]-)(/>)", convert)
	text = text:gsub("<MagicConvertMaterialComponent([^>]-[^/])(>.-</MagicConvertMaterialComponent>)", convert)
	if reversed > 0 then
		changed = true
	end
	return changed and text or nil
end

-- a projectile part that pours a real material (Burning trail's fire): the material it pours
local function poured_material(text)
	for tag in text:gmatch("<ParticleEmitterComponent[^>]*>") do
		local m = tag:match('%semitted_material_name%s*=%s*"([%w_]+)"')
		if m and (tag:find('create_real_particles%s*=%s*"1"') or tag:find('emit_real_particles%s*=%s*"1"')) then
			return m
		end
	end
	return nil
end

local O = { extra = {}, eat = {}, drops_effects = {} }

local function eater(material)
	if not material:match("^[%w_]+$") then
		return nil
	end
	local path = GEN .. "eat/" .. material .. ".xml"
	if not O.eaters_written then
		O.eaters_written = {}
	end
	if not O.eaters_written[path] then
		O.eaters_written[path] = true
		-- Burning grass or wood stays its own material: taking the fire pixels away is not enough, so fire eaters also
		-- put out what burns, the way vanilla's Ice ball does (extinguish_fire)
		local extinguish = material:find("fire", 1, true) and ('\t<MagicConvertMaterialComponent extinguish_fire="1" '
			.. 'radius="12" is_circle="1" loop="1" kill_when_finished="0" />\n') or ""
		ModTextFileSetContent(path, ('<Entity>\n\t<MagicConvertMaterialComponent from_material="%s" to_material="air" '
			.. 'radius="12" is_circle="1" loop="1" steps_per_frame="12" kill_when_finished="0" clean_stains="0" />\n'
			.. '%s</Entity>\n'):format(material, extinguish))
	end
	return path
end

local function build()
	for _, name in ipairs(ENGINE_STUBS) do
		_G[name] = function() end
	end
	dofile("data/scripts/gun/gun_enums.lua")
	dofile("data/scripts/gun/gun.lua") -- defines the shot helpers and loads gun_actions.lua with all appends
	draw_actions = function() end -- gun.lua defines these, so they are stubbed afterwards
	draw_action = function() end

	local seen = {}
	for _, a in ipairs(actions or {}) do
		if a.type == ACTION_TYPE_MODIFIER and a.id ~= "SIGN_FLIP" then
			local extras, trails = evaluate(a)
			for _, m in ipairs(trails) do
				if O.eat[m] == nil then
					O.eat[m] = eater(m) or false
				end
			end
			for _, f in ipairs(extras) do
				if not seen[f] then
					seen[f] = true
					local pair = PAIRS[f]
					local text = file_text(f)
					-- particles/ holds sparkles that many modifiers share, never a poured material (but Freeze charge's
					-- converters live there too)
					local shared = f:find("data/entities/particles/", 1, true) ~= nil
					if pair and ModDoesFileExist(pair) then
						O.extra[f] = pair
					elseif text then
						local material = not shared and poured_material(text)
						if material then
							O.extra[f] = eater(material)
							O.drops_effects[f] = O.extra[f] ~= nil or nil
						else
							O.extra[f] = flip_path(f, 0)
						end
					end
				end
			end
		end
	end
	O.eaters_written = nil
	for m, file in pairs(O.eat) do
		if not file then
			O.eat[m] = nil
		end
	end

	-- the spell flip: hole pairs, and an implode marker for every other file a projectile spell adds
	O.holes, O.spell, O.implode = {}, {}, IMPLODE
	for black, white in pairs(HOLES) do
		if ModDoesFileExist(black) and ModDoesFileExist(white) then
			O.holes[black], O.holes[white] = white, black
		end
	end
	for _, a in ipairs(actions or {}) do
		if a.type == ACTION_TYPE_PROJECTILE or a.type == ACTION_TYPE_STATIC_PROJECTILE or a.type == ACTION_TYPE_MATERIAL then
			for _, f in ipairs(spell_files(a)) do
				if not O.holes[f] and not O.spell[f] and f:match('^[^"<>&]+$') then
					O.spell[f] = GEN .. "implode/" .. f
					ModTextFileSetContent(O.spell[f], SPELL_MARKER:format(f))
				end
			end
		end
	end
end

local ok, err = pcall(build)

-- undo everything gun.lua / gun_actions.lua defined in this (init.lua) Lua state, including other mods' overrides
for k in pairs(_G) do
	if backup[k] == nil then
		_G[k] = nil
	end
end
for k, v in pairs(backup) do
	if _G[k] ~= v then
		_G[k] = v
	end
end
for name, keys in pairs(cache_keys) do
	local cache = _G[name]
	if type(cache) == "table" then
		for k in pairs(cache) do
			if not keys[k] then
				cache[k] = nil
			end
		end
	end
end

local function serialize(v, indent)
	indent = indent or ""
	if type(v) == "string" then
		return ("%q"):format(v)
	elseif type(v) ~= "table" then
		return tostring(v)
	end
	local keys = {}
	for k in pairs(v) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		parts[#parts + 1] = indent .. "\t[" .. ("%q"):format(k) .. "] = " .. serialize(v[k], indent .. "\t")
	end
	return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

if not ok then
	print("[sign_flip] could not work out the modifiers' opposites, flips only change numbers: " .. tostring(err))
	O = { extra = {}, eat = {}, drops_effects = {} }
end
ModTextFileSetContent(GEN .. "opposites.lua", "return " .. serialize(O) .. "\n")
