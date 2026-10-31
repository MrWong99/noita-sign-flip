-- Shared by the flipped critical modifiers (files/entities/hitfx_critical_not_*.xml), the opposites of
-- data/entities/misc/hitfx_critical_{water,oil,blood}.xml and hitfx_burning_critical_hit.xml: hits are critical
-- against targets that do NOT have the game effect. The engine's HitEffectComponent can only require an effect, so
-- each flipped file carries an unconditional CRITICAL_HIT_BOOST (same mechanism as vanilla) tagged with its effect,
-- and this script arms it (value 100) or disarms it (value 0) every frame from the creature the projectile is about
-- to hit. It only changes the projectile's own component, so every Entangled Worlds peer does the same from the same
-- world state and the hit itself stays the engine's.

local LOOKAHEAD = 2 -- frames of travel ahead that count as "about to hit"
local MARGIN = 12 -- px around that path: roughly a creature hitbox, measured from its middle
local BOOST = 100 -- the vanilla files' value

function hitfx_critical_not(effect)
	local proj = EntityGetRootEntity(GetUpdatedEntityID())
	local hits = EntityGetComponentIncludingDisabled(proj, "HitEffectComponent", "hitfx_critical_not_" .. effect)
	local vc = EntityGetFirstComponent(proj, "VelocityComponent")
	if not hits or not vc then
		return
	end
	local pc = EntityGetFirstComponentIncludingDisabled(proj, "ProjectileComponent")
	local shooter = pc and ComponentGetValue2(pc, "mWhoShot") or 0

	local x, y = EntityGetTransform(proj)
	local vx, vy = ComponentGetValue2(vc, "mVelocity")
	local len = math.sqrt(vx * vx + vy * vy) / 60 * LOOKAHEAD
	local ux, uy = 0, 0
	if len > 0.01 then
		ux, uy = vx / 60 * LOOKAHEAD / len, vy / 60 * LOOKAHEAD / len
	end

	-- the creature nearest along the path; none ahead keeps the last decision (armed at first)
	local target, best_t = nil, math.huge
	local mx, my = x + ux * len * 0.5, y + uy * len * 0.5
	for _, id in ipairs(EntityGetInRadiusWithTag(mx, my, len * 0.5 + MARGIN, "hittable") or {}) do
		if id ~= proj and id ~= shooter and EntityGetRootEntity(id) == id
			and EntityGetFirstComponent(id, "DamageModelComponent") then
			local ex, ey = EntityGetTransform(id)
			local dx, dy = ex - x, ey - 4 - y -- from the creature's middle, not its feet
			local t = dx * ux + dy * uy
			local px, py = dx - ux * t, dy - uy * t
			if t > -MARGIN and t < len + MARGIN and px * px + py * py < MARGIN * MARGIN and t < best_t then
				target, best_t = id, t
			end
		end
	end
	if not target then
		return
	end

	local has = GameGetGameEffectCount(target, effect) > 0
	if not has and effect == "ON_FIRE" then
		-- burning from fire materials is also flagged on the damage model; count either as burning
		local dm = EntityGetFirstComponent(target, "DamageModelComponent")
		has = dm ~= nil and ComponentGetValue2(dm, "is_on_fire")
	end
	local value = has and 0 or BOOST
	for _, c in ipairs(hits) do
		ComponentSetValue2(c, "value", value)
	end
end
