-- Implosions (decided with the user: "negative explosions are implosions"). The implode marker
-- (files/entities/implode.xml, or a spell's generated marker) rides on a projectile whose explosion a flip made negative.
-- When the projectile dies, it doesn't explode: files/entities/implosion.xml pulls things in for 0.25 s and then
-- explodes with 3x the damage in 1/3 of the radius.
-- Everything runs on every Entangled Worlds peer's copy of the projectile (casts are replayed): deterministic only.
--
-- State on the projectile, VariableStorageComponent "sf_imp": value_int -1 not imploding, 1 claimed, 2 armed, 3 done;
-- value_string "R,D,ray_energy,max_durability,hole,source" (source "f": the ProjectileComponent flags, "c": an
-- ExplosionComponent / ExplodeOnDamageComponent).

local M = {}

local function vsc(e, tag)
	return EntityGetFirstComponentIncludingDisabled(e, "VariableStorageComponent", tag)
end

local function cfg(comp, field)
	local ok, v = pcall(ComponentObjectGetValue2, comp, "config_explosion", field)
	return ok and v or nil
end

local function read(comp)
	return { R = cfg(comp, "explosion_radius") or 0, D = cfg(comp, "damage") or 0, ray = cfg(comp, "ray_energy") or 0,
		dur = cfg(comp, "max_durability_to_destroy") or 0, hole = cfg(comp, "hole_enabled") ~= false }
end

local function save(st, s)
	ComponentSetValue2(st, "value_string", ("%.6g,%.6g,%.6g,%.6g,%d,%s"):format(s.R, s.D, s.ray, s.dur,
		s.hole and 1 or 0, s.src or "f"))
end

local function load(st)
	local R, D, ray, dur, hole, src = (ComponentGetValue2(st, "value_string") or ""):match(
		"^([^,]*),([^,]*),([^,]*),([^,]*),(%d),(%a)$")
	return { R = tonumber(R) or 0, D = tonumber(D) or 0, ray = tonumber(ray) or 0, dur = tonumber(dur) or 0,
		hole = hole == "1", src = src or "f" }
end

-- The native explosion stays switched on but does nothing (radius 0, no damage, no hole, no effects), rather than
-- switching the flags off: Detonator re-arms flagged projectiles, and Entangled Worlds only forgets a recorded terrain
-- cut while a flag is on and the radius is small.
local NEUTER = { explosion_radius = 0, damage = 0, hole_enabled = false, ray_energy = 0, camera_shake = 0,
	explosion_sprite = "", load_this_entity = "", sparks_enabled = false, light_enabled = false, audio_enabled = false,
	stains_enabled = false, physics_throw_enabled = false, create_cell_probability = 0, damage_mortals = false,
	particle_effect = false }
local function neuter(pc)
	for field, v in pairs(NEUTER) do
		pcall(ComponentObjectSetValue2, pc, "config_explosion", field, v)
	end
end

local function flags_on(pc)
	return ComponentGetValue2(pc, "on_death_explode") or ComponentGetValue2(pc, "on_lifetime_out_explode")
end

-- Is this projectile one the marker means? The flipped-modifier marker means every projectile of the shot; a spell's
-- marker only those made from that spell's file.
local function wanted(p)
	local file = EntityGetFilename(p)
	for _, v in ipairs(EntityGetComponentIncludingDisabled(p, "VariableStorageComponent", "sf_implode") or {}) do
		local f = ComponentGetValue2(v, "value_string")
		if f == "" or f == file then
			return true
		end
	end
	return false
end

-- on added (merged at creation, or loaded mid-flight by Field Imbue): claim the projectile and keep its explosion
function M.claim()
	local p = GetUpdatedEntityID()
	local st = vsc(p, "sf_imp")
	if st and ComponentGetValue2(st, "value_int") ~= -1 then
		return -- another copy of the marker got here first
	end
	-- -1 (a marker that didn't mean it, or no explosion yet): a later marker, e.g. from a Field Imbue circle, may claim it
	st = st or EntityAddComponent2(p, "VariableStorageComponent", { _tags = "sf_imp", name = "sf_imp", value_int = -1 })
	local pc = EntityGetFirstComponentIncludingDisabled(p, "ProjectileComponent")
	if not pc or not wanted(p) then
		return
	end
	local s = read(pc)
	s.src = flags_on(pc) and "f" or nil
	for _, kind in ipairs({ "ExplosionComponent", "ExplodeOnDamageComponent" }) do
		for _, comp in ipairs(EntityGetComponent(p, kind) or {}) do -- enabled ones only
			local x = read(comp)
			s.R, s.D = math.max(s.R, x.R), math.max(s.D, x.D)
			s.ray, s.dur = math.max(s.ray, x.ray), math.max(s.dur, x.dur)
			s.src = s.src or "c"
			neuter(comp) -- stays enabled, so death() can see whether something switched it off meanwhile
		end
	end
	if not s.src then
		return -- it never explodes: nothing to turn into an implosion
	end
	save(st, s)
	neuter(pc)
	ComponentSetValue2(st, "value_int", 1)
end

-- first frame: whatever the shot (or Field Imbue) added after the marker landed is in the config now
function M.arm()
	local p = GetUpdatedEntityID()
	local st = vsc(p, "sf_imp")
	local pc = EntityGetFirstComponentIncludingDisabled(p, "ProjectileComponent")
	if not st or not pc or ComponentGetValue2(st, "value_int") ~= 1 then
		return
	end
	local s, now = load(st), read(pc)
	s.R, s.D = s.R + now.R, s.D + now.D
	s.ray, s.dur = math.max(s.ray, now.ray), math.max(s.dur, now.dur)
	save(st, s)
	neuter(pc)
	ComponentSetValue2(st, "value_int", 2)
end

-- a projectile can be removed because its chunk streamed out or the game is quitting: only implode near a player
local PLAYER_TAGS = { "player_unit", "ew_client", "ew_peer", "polymorphed_player" }
local function player_near(x, y)
	for _, tag in ipairs(PLAYER_TAGS) do
		if #(EntityGetInRadiusWithTag(x, y, 1500, tag) or {}) > 0 then
			return true
		end
	end
	return false
end

-- on removed: the projectile died; implode where it was
function M.death()
	local p = GetUpdatedEntityID()
	local st = vsc(p, "sf_imp")
	local pc = EntityGetFirstComponentIncludingDisabled(p, "ProjectileComponent")
	local state = st and ComponentGetValue2(st, "value_int")
	if not pc or (state ~= 1 and state ~= 2) then
		return
	end
	local s = load(st)
	if s.src == "f" and not flags_on(pc) then
		return -- Remove explosion, Null shot and the like switched the explosion off meanwhile
	end
	if s.src == "c" then
		local live = false
		for _, kind in ipairs({ "ExplosionComponent", "ExplodeOnDamageComponent" }) do
			live = live or #(EntityGetComponent(p, kind) or {}) > 0
		end
		if not live then
			return
		end
	end
	if state == 1 then -- died before its first frame
		local now = read(pc)
		s.R, s.D = s.R + now.R, s.D + now.D
	end
	local x, y = EntityGetTransform(p)
	if s.R <= 0 or not x or not player_near(x, y) then
		return
	end
	ComponentSetValue2(st, "value_int", 3) -- only now: one implosion even if the marker came twice
	local e = EntityLoad("mods/sign_flip/files/entities/implosion.xml", x, y)
	local ic = EntityGetFirstComponentIncludingDisabled(e, "ProjectileComponent")
	if not ic then
		return
	end
	ComponentObjectSetValue2(ic, "config_explosion", "explosion_radius", s.R / 3)
	ComponentObjectSetValue2(ic, "config_explosion", "damage", 3 * s.D)
	ComponentObjectSetValue2(ic, "config_explosion", "ray_energy", s.ray) -- 0 is real: the original broke no terrain
	ComponentObjectSetValue2(ic, "config_explosion", "max_durability_to_destroy", s.dur)
	ComponentObjectSetValue2(ic, "config_explosion", "hole_enabled", s.hole)
	-- credited like the original: kills count for the caster, and it spares the caster when the original would have
	local who = ComponentGetValue2(pc, "mWhoShot")
	ComponentSetValue2(ic, "mWhoShot", who)
	ComponentSetValue2(ic, "mShooterHerdId", ComponentGetValue2(pc, "mShooterHerdId"))
	local spare = ComponentGetValue2(pc, "explosion_dont_damage_shooter")
	ComponentSetValue2(ic, "explosion_dont_damage_shooter", spare)
	if spare and who ~= 0 then
		pcall(ComponentObjectSetValue2, ic, "config_explosion", "dont_damage_this", who)
	end
	ComponentSetValue2(vsc(e, "imp_pull_r"), "value_float", 1.5 * s.R)
	ComponentSetValue2(vsc(e, "imp_shooter"), "value_int", who)
end

return M
