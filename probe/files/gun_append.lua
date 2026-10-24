-- sign_flip probe: makes Random modifier pick the action named in the global "sfprobe_pick" (probe/init.lua's S8)
local sfprobe_random = Random
function Random(a, b)
	local want = GlobalsGetValue("sfprobe_pick", "")
	if want ~= "" and a == 1 and b == #actions then
		for i, act in ipairs(actions) do
			if act.id == want then
				return i
			end
		end
	end
	return sfprobe_random(a, b)
end

-- sign_flip probe: records each shot's final state, as the wand code hands it to the engine, in the global
-- "sfprobe_shots" (one line per registered shot; a trigger's payload comes before its outer shot)
local sfprobe_register = register_action
function register_action(state)
	if not reflecting then
		local parts = {}
		for _, k in ipairs({ "damage_projectile_add", "damage_electricity_add", "damage_explosion_add", "damage_ice_add",
			"damage_healing_add",
			"damage_critical_chance", "explosion_radius", "knockback_force", "lifetime_add", "bounces", "gravity",
			"spread_degrees", "speed_multiplier", "child_speed_multiplier", "fire_rate_wait" }) do
			parts[#parts + 1] = k .. "=" .. tostring(state[k])
		end
		parts[#parts + 1] = "reload=" .. tostring(current_reload_time)
		parts[#parts + 1] = "mana=" .. tostring(mana)
		parts[#parts + 1] = "recoil=" .. tostring(shot_effects and shot_effects.recoil_knockback)
		parts[#parts + 1] = "sf_negated=" .. tostring(state.sf_negated)
		parts[#parts + 1] = "sf_pending=" .. tostring(state.sf_pending)
		GlobalsSetValue("sfprobe_shots", GlobalsGetValue("sfprobe_shots", "") .. table.concat(parts, " ") .. "\n")
	end
	return sfprobe_register(state)
end
