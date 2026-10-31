-- A ward starts (files/entities/hitfx_ward_<type>_effect.xml), the opposite of
-- data/scripts/projectiles/curse_wither_start.lua: the target's damage multiplier for the type goes down by 0.25 where
-- vanilla's goes up by 0.25. It stops at 0, since a negative multiplier would turn that damage into healing; the
-- amount really taken off is kept so hitfx_ward_end.lua gives back exactly that. Like the wither curse, every Entangled
-- Worlds peer changes its own copy of the target; the owner's copy is the one that takes the damage.

local DELTA = 0.25

local me = GetUpdatedEntityID()
local root = EntityGetRootEntity(me)
local tc = EntityGetFirstComponentIncludingDisabled(me, "VariableStorageComponent", "sf_ward_type")
local dc = EntityGetFirstComponentIncludingDisabled(me, "VariableStorageComponent", "sf_ward_delta")
local dm = EntityGetFirstComponent(root, "DamageModelComponent")
if root == me or not tc or not dc or not dm then
	return
end

local name = ComponentGetValue2(tc, "value_string")
local mult = ComponentObjectGetValue2(dm, "damage_multipliers", name)
if mult == nil then
	return
end
local d = math.min(DELTA, math.max(0, mult))
ComponentObjectSetValue2(dm, "damage_multipliers", name, mult - d)
ComponentSetValue2(dc, "value_float", d)
