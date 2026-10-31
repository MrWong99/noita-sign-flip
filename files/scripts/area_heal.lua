-- A flipped Area damage (files/entities/area_heal.xml), every frame: heals every creature within R of the projectile
-- by Area damage's own damage_per_frame, up to its max hp, players and enemies alike (AreaDamageComponent only takes
-- damage_per_frame >= 0). hp is raised directly, like hitfx_bless.lua: a healing EntityInflictDamage would spawn the
-- heal effect every frame and its damage type name is undocumented. Entangled Worlds: every peer heals only what it
-- owns on its own copy of the projectile, which covers each player exactly once; no friendly fire needed, it never hurts.

local R = 16 -- area_damage.xml's circle_radius
local HEAL = 0.14 -- its damage_per_frame (3.5 hp per frame as the UI counts)

local proj = EntityGetRootEntity(GetUpdatedEntityID())
local x, y = EntityGetTransform(proj)

local ew = ModIsEnabled("quant.ew") and CrossCall ~= nil
local function owned(id)
	if not ew then
		return true
	end
	local ok, mine = pcall(CrossCall, "ew_do_i_own", id)
	return not ok or mine ~= false
end

local seen = {}
for _, tag in ipairs({ "mortal", "homing_target" }) do
	for _, id in ipairs(EntityGetInRadiusWithTag(x, y, R, tag) or {}) do
		if not seen[id] then
			seen[id] = true
			if id ~= proj and EntityGetRootEntity(id) == id and not EntityHasTag(id, "ew_client") and owned(id) then
				local dm = EntityGetFirstComponent(id, "DamageModelComponent")
				if dm then
					local hp, max_hp = ComponentGetValue2(dm, "hp"), ComponentGetValue2(dm, "max_hp")
					-- dead creatures are left alone: no reviving
					if hp > 0 and hp < max_hp then
						ComponentSetValue2(dm, "hp", math.min(max_hp, hp + HEAL))
					end
				end
			end
		end
	end
end
