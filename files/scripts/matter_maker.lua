-- A flipped Matter eater (files/entities/matter_maker.xml), every frame: keeps the rock laying emitters
-- (files/entities/matter_maker_emitter.xml, three parallel trail lines) on the projectile, BACK px behind it so the
-- projectile never hits its own rock. Matter eater stops eating after about 200 frames; the maker stops building then
-- too. No rock within PLAYER_CLEAR of a player or CREATURE_CLEAR of any creature: the emitters are removed there and fresh ones are loaded
-- once clear, because a re-enabled trail emitter would join its old position to the new one, right past the player.
-- Each Entangled Worlds peer lays its own copy's rock from the same positions; nothing is pushed or damaged.

local FRAMES = 200
local BACK = 6 -- px behind the projectile, clear of its hitbox
local PLAYER_CLEAR = 20
local CREATURE_CLEAR = 10
local EMITTER = "mods/sign_flip/files/entities/matter_maker_emitter.xml"

local proj = EntityGetRootEntity(GetUpdatedEntityID())
local pes = EntityGetComponentIncludingDisabled(proj, "ParticleEmitterComponent", "matter_maker")
local function stop()
	for _, pe in ipairs(pes or {}) do
		EntityRemoveComponent(proj, pe)
	end
end

if ComponentGetValue2(GetUpdatedComponentID(), "mTimesExecuted") >= FRAMES then
	stop()
	return
end
local vc = EntityGetFirstComponent(proj, "VelocityComponent")
if not vc then
	stop()
	return
end
local vx, vy = ComponentGetValue2(vc, "mVelocity")
local speed = math.sqrt(vx * vx + vy * vy)
if speed < 1 then
	stop()
	return
end
local dx, dy = vx / speed, vy / speed
local ox, oy = -dx * BACK, -dy * BACK
local px, py = EntityGetTransform(proj)
local x, y = px + ox, py + oy

local function near(tag, r)
	for _, e in ipairs(EntityGetInRadiusWithTag(x, y + 4, r, tag) or {}) do
		if e ~= proj then
			return true
		end
	end
	return false
end
-- creatures' transforms are at their feet, so searching 4 px below the point measures from their middle
if near("player_unit", PLAYER_CLEAR) or near("polymorphed_player", PLAYER_CLEAR) or near("ew_peer", PLAYER_CLEAR)
	or near("mortal", CREATURE_CLEAR) then
	stop()
	return
end

if not pes or #pes == 0 then
	EntityLoadToEntity(EMITTER, proj)
	pes = EntityGetComponentIncludingDisabled(proj, "ParticleEmitterComponent", "matter_maker")
	-- start each fresh trail here, not at whatever position it was created with
	for _, pe in ipairs(pes or {}) do
		ComponentSetValue2(pe, "mExPosition", px, py)
	end
end
-- the lines sit -1, 0 and +1 px across the flight direction
for i, pe in ipairs(pes or {}) do
	local k = i - 2
	ComponentSetValue2(pe, "offset", ox - dy * k, oy + dx * k)
end
