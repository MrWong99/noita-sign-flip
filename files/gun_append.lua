-- Appended to data/scripts/gun/gun.lua: runs after gun_actions.lua and every mod's appends, so every modifier exists,
-- and before the deck is built (it clones `action`), so always-casts and Random modifier go through these wrappers
-- too. Runs in the wand's Lua state on every Entangled Worlds peer (each peer replays the cast), so everything here
-- only depends on the shot itself: no Random(), frame numbers or entity ids.
--
-- A Sign flip leaves a pending flip on the shot (c.sf_pending). The next modifier that plays takes it: whatever it
-- changes on the shot is applied the other way round. A modifier changes the shot and then calls draw_actions, which
-- plays the next cards inside the same call, so its change is measured when it draws (and again when it returns:
-- Orbit shot, Fly upwards and a few others change the shot after drawing).

-- added by modifiers: +x becomes -x
local ADD = {
	"damage_projectile_add", "damage_melee_add", "damage_electricity_add", "damage_fire_add", "damage_explosion_add",
	"damage_ice_add", "damage_slice_add", "damage_healing_add", "damage_curse_add", "damage_drill_add",
	"damage_critical_chance", "damage_critical_multiplier", "explosion_radius", "explosion_damage_to_materials",
	"knockback_force", "lifetime_add", "bounces", "gravity", "spread_degrees", "pattern_degrees", "physics_impulse_coeff",
}
-- multiplied by modifiers: x2.5 becomes x0.4
local MUL = { "speed_multiplier", "child_speed_multiplier", "dampening" }
-- Never flipped: cosmetics (screenshake, gore, blood, light), counts (lightning_count, trail and material amounts),
-- the damage_null_all flag and the cards' own mana costs. Cast delay, recharge time and mana: see flips_wand_change.

local function num(v)
	return type(v) == "number"
end

-- Cast delay, recharge time and mana are the wand's economy, and most modifiers add cast delay as their price. The
-- "wand_numbers" setting (settings.lua, new-game scope): "bonuses" (default) flips only changes that helped the wand,
-- "all" flips every change, "none" never touches them.
local function flips_wand_change(gain) -- gain > 0: the modifier made the wand better (less delay, more mana)
	local ok, mode = pcall(ModSettingGet, "sign_flip.wand_numbers")
	if not ok or (mode ~= "all" and mode ~= "none") then
		mode = "bonuses"
	end
	return mode == "all" or (mode == "bonuses" and gain > 0)
end

local function snapshot(state)
	local s = { fire_rate_wait = state.fire_rate_wait, reload = current_reload_time, mana = mana,
		recoil = shot_effects and shot_effects.recoil_knockback }
	for _, k in ipairs(ADD) do
		s[k] = state[k]
	end
	for _, k in ipairs(MUL) do
		s[k] = state[k]
	end
	return s
end

-- applies every change made since snapshot `s` the other way round; true if anything was flipped
local function flip_since(state, s)
	local flipped = false
	for _, k in ipairs(ADD) do
		local was, now = s[k], state[k]
		if num(was) and num(now) and now ~= was then
			state[k] = was - (now - was)
			flipped = true
		end
	end
	for _, k in ipairs(MUL) do
		local was, now = s[k], state[k]
		if num(was) and num(now) and now ~= was and was ~= 0 and now ~= 0 then -- a factor of 0 can't be undone
			state[k] = was * was / now
			flipped = true
		end
	end
	local was, now = s.fire_rate_wait, state.fire_rate_wait
	if num(was) and num(now) and now ~= was and flips_wand_change(was - now) then
		state.fire_rate_wait = was - (now - was)
		flipped = true
	end
	was, now = s.reload, current_reload_time
	if num(was) and num(now) and now ~= was and flips_wand_change(was - now) then
		current_reload_time = was - (now - was)
		flipped = true
	end
	was, now = s.mana, mana
	if num(was) and num(now) and now ~= was and flips_wand_change(now - was) then
		mana = math.max(0, was - (now - was)) -- a drain takes at most what the wand has
		flipped = true
	end
	was, now = s.recoil, shot_effects and shot_effects.recoil_knockback
	if num(was) and num(now) and now ~= was then -- a flipped Recoil pushes forwards
		shot_effects.recoil_knockback = was - (now - was)
		flipped = true
	end
	return flipped
end

-- Add mana's bonus is its negative mana cost, which draw_action paid out before the action ran
local function flip_card_mana(id)
	local a = current_action
	if a and a.id == id and num(a.mana) and a.mana < 0 and flips_wand_change(-a.mana) then
		mana = math.max(0, mana + 2 * a.mana)
		return true
	end
	return false
end

-- The flipped modifier that is running and hasn't drawn yet. A modifier it runs directly takes the flip instead (Random
-- modifier runs the modifier it picked).
local open

-- runs a modifier that takes a pending flip
local function run_flipped(state, id, action, ...)
	local flipped = flip_card_mana(id)
	local frame = { id = id, s = snapshot(state) } -- after flip_card_mana: that drain is not the modifier's own change
	local real_draw, outer = draw_actions, open
	local hook
	hook = function(...)
		-- It draws the next cards: what it changed so far is its own. Put the real draw_actions back first, so the
		-- modifiers drawn now don't run into this hook.
		draw_actions = real_draw
		frame.drawn = true
		if open == frame then
			open = outer
		end
		flipped = flip_since(state, frame.s) or flipped
		real_draw(...)
		frame.s = snapshot(state)
		draw_actions = hook -- in case it draws again
	end
	open = frame
	draw_actions = hook
	local result = { pcall(action, ...) }
	if draw_actions == hook then
		draw_actions = real_draw
	end
	open = outer
	-- what it changed after its last draw, or everything if it never drew
	flipped = flip_since(state, frame.s) or flipped
	if flipped then
		-- which modifiers of this shot were flipped; Field Imbue's register_action wrapper reads it
		state.sf_negated = (state.sf_negated or "") .. frame.id .. ","
	end
	if not result[1] then
		error(result[2], 0)
	end
	return unpack(result, 2, table.maxn(result))
end

local function sign_flip(state)
	if open and not open.drawn then
		-- this Sign flip is the modifier being flipped (Random modifier picked it): a flipped Sign flip does nothing
		open.id = "SIGN_FLIP"
		return
	end
	-- a Sign flip right after another one is the modifier that one flips: the two cancel out
	local n = state.sf_pending or 0
	state.sf_pending = n > 0 and n - 1 or 1
end

-- Pass straight through while reflecting (spell tooltips, Entangled Worlds' action_fix, Field Imbue's recipe builder)
-- and when no flip is pending. sf_wrapped: gun.lua can be loaded twice in one Lua state.
for _, a in ipairs(actions or {}) do
	if not a.sf_wrapped and type(a.action) == "function" then
		local action, id = a.action, a.id
		if id == "SIGN_FLIP" then
			a.action = function(...)
				if not reflecting and c then
					sign_flip(c)
				end
				return action(...)
			end
			a.sf_wrapped = true
		elseif a.type == ACTION_TYPE_MODIFIER then
			a.action = function(...)
				if reflecting or not c then
					return action(...)
				end
				if open and not open.drawn then
					open.id = id -- run directly by the flipped modifier (Random modifier's pick): this one is flipped
					return action(...)
				end
				local n = c.sf_pending or 0
				if n <= 0 then
					return action(...)
				end
				c.sf_pending = n - 1
				return run_flipped(c, id, action, ...)
			end
			a.sf_wrapped = true
		end
	end
end
