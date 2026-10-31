-- A blessing tick (files/entities/hitfx_bless_effect.xml), every 30 frames, the opposite of
-- data/scripts/projectiles/curse.lua: heals the blessed creature by the stacked amount, up to its max hp. Every
-- Entangled Worlds peer has a copy of the blessing; only the peer that owns the creature heals it (its own player, the
-- enemies it simulates), and the healed hp syncs from there. Other players are only hit (and so blessed) with friendly
-- fire or PvP on, so the hit already respects those settings.

local me = GetUpdatedEntityID()
local root = EntityGetRootEntity(me)
if root == me or EntityHasTag(root, "ew_client") then
	return
end
if ModIsEnabled("quant.ew") and CrossCall ~= nil then
	local ok, mine = pcall(CrossCall, "ew_do_i_own", root)
	if ok and mine == false then
		return
	end
end

local vc = EntityGetFirstComponentIncludingDisabled(me, "VariableStorageComponent", "sf_bless_heal")
local dm = EntityGetFirstComponent(root, "DamageModelComponent")
if not vc or not dm then
	return
end
local hp, max_hp = ComponentGetValue2(dm, "hp"), ComponentGetValue2(dm, "max_hp")
if hp > 0 and hp < max_hp then
	ComponentSetValue2(dm, "hp", math.min(max_hp, hp + ComponentGetValue2(vc, "value_float")))
end
