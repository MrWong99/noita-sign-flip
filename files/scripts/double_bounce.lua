-- A flipped Remove bounce (files/entities/double_bounce.xml), once on the projectile's first frame: doubles the bounces
-- the projectile has of its own, at least 1. Each copy of the file doubles once and removes itself, so two flipped
-- Remove bounce in one shot double twice (x4), like two vanilla ones would both remove.

local proj = EntityGetRootEntity(GetUpdatedEntityID())
local pc = EntityGetFirstComponentIncludingDisabled(proj, "ProjectileComponent")
if not pc then
	return
end
-- bounces_left already holds the shot's bounces (config.bounces) on top of the projectile's own. Those are flipped
-- by the number code, so only the rest is doubled here.
local left = ComponentGetValue2(pc, "bounces_left") or 0
local shot = math.max(0, ComponentObjectGetValue2(pc, "config", "bounces") or 0)
local own = math.max(0, left - shot)
ComponentSetValue2(pc, "bounces_left", math.min(math.max(own * 2, 1) + math.min(shot, left), 100000000))
