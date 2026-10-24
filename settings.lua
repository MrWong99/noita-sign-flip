dofile("data/scripts/lib/mod_settings.lua")

-- Only takes effect when a new run starts (MOD_SETTING_SCOPE_NEW_GAME), so it can't change in the middle of a run.
-- With Entangled Worlds every player needs the same value: EW does not sync other mods' settings.

local mod_id = "sign_flip" -- must match the mod folder name
mod_settings_version = 1
mod_settings = {
	{
		id = "wand_numbers",
		ui_name = "Flip cast delay, recharge and mana",
		ui_description = "Most modifiers add cast delay as their price. What Sign flip does with cast delay,\n"
			.. "recharge time and mana:\n"
			.. "Bonuses only: only a bonus flips (Reduce recharge time gets slower, Add mana drains mana);\n"
			.. "a price stays, so a flipped Heavy shot still adds its cast delay.\n"
			.. "Everything: prices flip too (a flipped Static to sand casts 60 frames faster). Very strong.\n"
			.. "Never: only the projectile's numbers flip.",
		value_default = "bonuses",
		values = { { "bonuses", "Bonuses only" }, { "all", "Everything" }, { "none", "Never" } },
		scope = MOD_SETTING_SCOPE_NEW_GAME,
	},
}

function ModSettingsUpdate(init_scope)
	mod_settings_update(mod_id, mod_settings, init_scope)
end

function ModSettingsGuiCount()
	return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui(gui, in_main_menu)
	mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end
