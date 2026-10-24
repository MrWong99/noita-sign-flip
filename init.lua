ModLuaFileAppend("data/scripts/gun/gun_actions.lua", "mods/sign_flip/files/actions.lua")
-- the flipping itself: wraps every modifier once all mods' spells exist (see the file's header)
ModLuaFileAppend("data/scripts/gun/gun.lua", "mods/sign_flip/files/gun_append.lua")

-- every mod's spells are registered by now: work out the opposites of what modifiers add (files/gen/)
function OnModPostInit()
	dofile("mods/sign_flip/files/scripts/opposites_build.lua")
end
