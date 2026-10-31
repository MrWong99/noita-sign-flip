-- A flipped critical modifier (files/entities/hitfx_critical_not_water.xml), every frame: arms the critical hit unless
-- the creature about to be hit is wet. See hitfx_critical_not_lib.lua.

dofile_once("mods/sign_flip/files/scripts/hitfx_critical_not_lib.lua")
hitfx_critical_not("WET")
