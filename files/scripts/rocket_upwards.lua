-- A flipped Rocket Downwards (files/entities/rocket_upwards.xml): vanilla's data/scripts/projectiles/rocket_downwards.lua
-- mirrored vertically. Once the projectile moves upwards it is replaced by five rockets fanned out upwards, which
-- fall up (files/entities/rocket_upwards_shot.xml). Like vanilla, every peer bursts its own copy of the projectile.
dofile_once("data/scripts/lib/utilities.lua")

local proj = EntityGetRootEntity(GetUpdatedEntityID())
local vc = EntityGetFirstComponent(proj, "VelocityComponent")
if not vc then
	return
end
local _, vel_y = ComponentGetValue2(vc, "mVelocity")
if vel_y >= -10 then
	return
end

local x, y = EntityGetTransform(proj)
local velocities = { { -100, -100 }, { -50, -140 }, { 0, -160 }, { 50, -140 }, { 100, -100 } }
for _, v in ipairs(velocities) do
	shoot_projectile_from_projectile(proj, "mods/sign_flip/files/entities/rocket_upwards_shot.xml",
		x + v[1] * 0.05, y + v[2] * 0.05, v[1], v[2])
end
EntityKill(proj)
