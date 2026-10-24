-- The pull of an implosion (files/entities/implosion.xml), every frame for 15 frames: creatures, projectiles and
-- physics bodies within imp_pull_r are steered towards the centre so that they arrive as it explodes. Terrain is not
-- eaten. Runs on every Entangled Worlds peer's copy: each peer pulls only what it owns (its own player, the enemies
-- and items it simulates); only the age counter times it.

local FRAMES = 15
local VMAX = 900 -- px/s
local BLEND_CHAR = 0.6 -- how hard a creature's velocity is steered each frame
local BLEND_PROJ = 0.35 -- projectiles keep more of their own momentum
local PHYS_ACCEL = 39.2 * 6 -- black_hole_gravity.lua's 39.2, six times: a snap, not a drift
local PHYS_MASS_CAP = 4
local BOSS_SCALE = 0.25

local me = GetUpdatedEntityID()
local cx, cy = EntityGetTransform(me)
local function var(tag)
	return EntityGetFirstComponentIncludingDisabled(me, "VariableStorageComponent", tag)
end
local c_r, c_sh, c_age = var("imp_pull_r"), var("imp_shooter"), var("imp_age")
if not c_r or not c_age then
	return
end
local R = ComponentGetValue2(c_r, "value_float")
local shooter = c_sh and ComponentGetValue2(c_sh, "value_int") or 0
local age = ComponentGetValue2(c_age, "value_int") + 1
ComponentSetValue2(c_age, "value_int", age)
if age > FRAMES or R <= 0 then
	return
end
local snap = 60 / (FRAMES - age + 1) -- speed = distance * snap covers it in the frames left

-- Entangled Worlds: other players only with friendly fire or PvP on; synced entities only where they are owned
local ew = ModIsEnabled("quant.ew") and CrossCall ~= nil
local pull_players = not ew
if ew then
	local ok, ff = pcall(CrossCall, "ew_ff")
	local ok2, pvp = pcall(CrossCall, "ew_pvp")
	pull_players = (ok and ff == true) or (ok2 and pvp == true)
end
local function owned(id)
	if not ew then
		return true
	end
	local ok, mine = pcall(CrossCall, "ew_do_i_own", id)
	return not ok or mine ~= false
end

local function target_vel(px, py, scale)
	local dx, dy = cx - px, cy - py
	local d = math.sqrt(dx * dx + dy * dy)
	if d < 1.5 or d > R then
		return nil
	end
	local s = math.min(VMAX, d * snap) * scale
	return dx / d * s, dy / d * s
end

local function skip(id)
	return id == me or id == shooter or EntityGetRootEntity(id) ~= id or EntityHasTag(id, "ew_client")
		or (not pull_players and (EntityHasTag(id, "player_unit") or EntityHasTag(id, "polymorphed_player"))) or not owned(id)
end

-- creatures: CharacterDataComponent.mVelocity
for _, id in ipairs(EntityGetInRadiusWithTag(cx, cy, R, "mortal") or {}) do
	if not skip(id) then
		local cdc = EntityGetFirstComponent(id, "CharacterDataComponent")
		if cdc then
			local px, py = EntityGetTransform(id)
			local scale = 1 / math.sqrt(math.max(0.5, ComponentGetValue2(cdc, "mass")))
			if EntityHasTag(id, "boss") then
				scale = scale * BOSS_SCALE
			end
			local tvx, tvy = target_vel(px, py, scale)
			if tvx then
				local vx, vy = ComponentGetValue2(cdc, "mVelocity")
				ComponentSetValue2(cdc, "mVelocity", vx + (tvx - vx) * BLEND_CHAR, vy + (tvy - vy) * BLEND_CHAR)
			end
		end
	end
end

-- projectiles without a physics body (not fields, not holes): VelocityComponent.mVelocity
for _, id in ipairs(EntityGetInRadiusWithTag(cx, cy, R, "projectile") or {}) do
	if id ~= me and not EntityHasTag(id, "black_hole") and not EntityHasTag(id, "fi_field")
		and not EntityGetFirstComponent(id, "PhysicsBodyComponent") and not EntityGetFirstComponent(id, "PhysicsBody2Component") then
		local pc = EntityGetFirstComponentIncludingDisabled(id, "ProjectileComponent")
		local vc = EntityGetFirstComponent(id, "VelocityComponent")
		if vc and not (pc and ComponentGetValue2(pc, "speed_max") == 0) and owned(id) then
			local px, py = EntityGetTransform(id)
			local tvx, tvy = target_vel(px, py, 1)
			if tvx then
				local vx, vy = ComponentGetValue2(vc, "mVelocity")
				ComponentSetValue2(vc, "mVelocity", vx + (tvx - vx) * BLEND_PROJ, vy + (tvy - vy) * BLEND_PROJ)
			end
		end
	end
end

-- physics bodies (items, props, ragdolls, physics projectiles, loose debris)
local function force_for_body(ent, mass, bx, by)
	if ent and ent ~= 0 and (ent == shooter or EntityGetFirstComponent(ent, "CharacterDataComponent") or not owned(ent)) then
		return bx, by, 0, 0, 0
	end
	local dx, dy = cx - bx, cy - by
	local d = math.sqrt(dx * dx + dy * dy)
	if d < 1.5 or d > R then
		return bx, by, 0, 0, 0
	end
	local f = PHYS_ACCEL * math.min(mass, PHYS_MASS_CAP) * (0.4 + 0.6 * (1 - d / R))
	if ent and ent ~= 0 and EntityHasTag(ent, "boss") then
		f = f * BOSS_SCALE
	end
	return bx, by, dx / d * f, dy / d * f, 0
end
PhysicsApplyForceOnArea(force_for_body, me, cx - R, cy - R, cx + R, cy + R)
