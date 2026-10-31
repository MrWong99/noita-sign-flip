-- A flipped Laser Emitter Wider (files/entities/laser_emitter_narrower.xml), once: every LaserEmitterComponent on the
-- projectile loses what data/scripts/projectiles/laser_emitter_wider.lua adds (2 beam radius, 0.025 damage, 36 length),
-- so a wider and a narrower cancel out. Floors keep the beam valid: radius 1 is the thinnest beam vanilla uses for a
-- damaging laser (boss_ghost), so it is known to render and hit.

local MIN_RADIUS = 1.0
local MIN_DAMAGE = 0.01
local MIN_LENGTH = 16

local proj = EntityGetRootEntity(GetUpdatedEntityID())
for _, comp in ipairs(EntityGetComponent(proj, "LaserEmitterComponent") or {}) do
	local width = ComponentObjectGetValue2(comp, "laser", "beam_radius") or 0
	local dmg = ComponentObjectGetValue2(comp, "laser", "damage_to_entities") or 0
	local length = ComponentObjectGetValue2(comp, "laser", "max_length") or 0
	ComponentObjectSetValue2(comp, "laser", "beam_radius", math.max(math.min(width, MIN_RADIUS), width - 2.0))
	ComponentObjectSetValue2(comp, "laser", "damage_to_entities", math.max(math.min(dmg, MIN_DAMAGE), dmg - 0.025))
	ComponentObjectSetValue2(comp, "laser", "max_length", math.max(math.min(length, MIN_LENGTH), length - 36))
end
