-- A flipped Boomerang (files/entities/repel_players.xml), every frame: a slight anti homing away from every player
-- within R, the nearer the stronger. Only the direction turns; the speed stays. Players are the local one, polymorphed
-- ones and Entangled Worlds' other peers. Each peer steers its own copy of the projectile from the same positions.

local R = 150 -- px, Boomerang's own detect_distance is 300
local TURN = 0.08 -- at most this much of the speed is turned away per frame, right next to a player

local proj = EntityGetRootEntity(GetUpdatedEntityID())
local vc = EntityGetFirstComponent(proj, "VelocityComponent")
if not vc then
	return
end
local vx, vy = ComponentGetValue2(vc, "mVelocity")
local speed = math.sqrt(vx * vx + vy * vy)
if speed < 1 then
	return
end
local x, y = EntityGetTransform(proj)

local ax, ay, seen = 0, 0, {}
for _, tag in ipairs({ "player_unit", "polymorphed_player", "ew_peer" }) do
	for _, p in ipairs(EntityGetWithTag(tag) or {}) do
		if not seen[p] then
			seen[p] = true
			local px, py = EntityGetTransform(p)
			local dx, dy = x - px, y - (py - 4) -- from the player's middle, not their feet
			local d = math.sqrt(dx * dx + dy * dy)
			if d > 0.5 and d < R then
				local w = 1 - d / R
				ax, ay = ax + dx / d * w, ay + dy / d * w
			end
		end
	end
end
if ax == 0 and ay == 0 then
	return
end

vx, vy = vx + ax * speed * TURN, vy + ay * speed * TURN
local s = math.sqrt(vx * vx + vy * vy)
if s > 0 then
	ComponentSetValue2(vc, "mVelocity", vx / s * speed, vy / s * speed)
end
