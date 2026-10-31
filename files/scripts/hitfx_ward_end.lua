-- A ward ends (files/entities/hitfx_ward_<type>_effect.xml), the opposite of
-- data/scripts/projectiles/curse_wither_end.lua: gives back the multiplier hitfx_ward_start.lua took off.

local me = GetUpdatedEntityID()
local root = EntityGetRootEntity(me)
local tc = EntityGetFirstComponentIncludingDisabled(me, "VariableStorageComponent", "sf_ward_type")
local dc = EntityGetFirstComponentIncludingDisabled(me, "VariableStorageComponent", "sf_ward_delta")
local dm = EntityGetFirstComponentIncludingDisabled(root, "DamageModelComponent")
if root == me or not tc or not dc or not dm then
	return
end

local d = ComponentGetValue2(dc, "value_float")
if d <= 0 then
	return
end
local name = ComponentGetValue2(tc, "value_string")
local mult = ComponentObjectGetValue2(dm, "damage_multipliers", name)
if mult ~= nil then
	ComponentObjectSetValue2(dm, "damage_multipliers", name, mult + d)
	ComponentSetValue2(dc, "value_float", 0)
end
