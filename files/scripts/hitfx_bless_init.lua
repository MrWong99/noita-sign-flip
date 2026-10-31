-- A flipped Curse hit (files/entities/hitfx_bless_init.xml), the opposite of data/scripts/projectiles/curse_init.lua:
-- the first hit blesses the target (files/entities/hitfx_bless_effect.xml), each further hit while blessed adds 0.08
-- heal per tick and restarts the 300 frames, as curse stacks.

local HEAL = 0.08
local FRAMES = 300

local me = GetUpdatedEntityID()
local root = EntityGetRootEntity(me)

local blessing
for _, c in ipairs(EntityGetAllChildren(root) or {}) do
	if EntityHasTag(c, "sf_blessing") then
		blessing = c
		break
	end
end

if blessing then
	local lc = EntityGetFirstComponentIncludingDisabled(blessing, "LifetimeComponent", "sf_bless_lifetime")
	local vc = EntityGetFirstComponentIncludingDisabled(blessing, "VariableStorageComponent", "sf_bless_heal")
	if lc and vc then
		local now = GameGetFrameNum()
		ComponentSetValue2(lc, "creation_frame", now)
		ComponentSetValue2(lc, "kill_frame", now + FRAMES)
		ComponentSetValue2(vc, "value_float", ComponentGetValue2(vc, "value_float") + HEAL)
	end
elseif root ~= me then
	local x, y = EntityGetTransform(root)
	EntityAddChild(root, EntityLoad("mods/sign_flip/files/entities/hitfx_bless_effect.xml", x, y))
end

EntityKill(me)
