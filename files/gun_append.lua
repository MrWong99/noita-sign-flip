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
-- The engine ignores negative damage of these types; only the healing type heals (vanilla's Healing bolt has
-- damage_by_type healing = -0.35). So a flip that takes damage away goes to damage_healing_add instead: a spark bolt
-- (3 damage) with a flipped Damage plus (+10) deals 3 and heals 10.
local DAMAGE = { damage_projectile_add = true, damage_melee_add = true, damage_electricity_add = true,
	damage_fire_add = true, damage_ice_add = true, damage_slice_add = true, damage_curse_add = true, damage_drill_add = true }
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

-- The wand's mana when the shot started. A flip never gives back more than that: the engine doesn't cap a wand's
-- mana at its maximum, so a flipped Mana to damage in "all" mode would otherwise double it on every cast.
local shot_mana
local sf_start_shot = _start_shot
function _start_shot(current_mana, ...)
	shot_mana = current_mana
	return sf_start_shot(current_mana, ...)
end

local function snapshot(state)
	local s = { cards = state_cards_drawn, fire_rate_wait = state.fire_rate_wait, reload = current_reload_time, mana = mana,
		recoil = shot_effects and shot_effects.recoil_knockback, extra_entities = state.extra_entities,
		game_effect_entities = state.game_effect_entities, trail_material = state.trail_material,
		trail_material_amount = state.trail_material_amount }
	for _, k in ipairs(ADD) do
		s[k] = state[k]
	end
	for _, k in ipairs(MUL) do
		s[k] = state[k]
	end
	return s
end

-- A flip that would make an explosion negative turns it into an implosion instead (decided with the user): the numbers
-- the modifier added stay, and the projectiles get the implode marker (files/entities/implode.xml). That is the case
-- when the modifier made the explosion bigger, or stronger without changing its size.
local function implodes(s, state)
	local dr = (state.explosion_radius or 0) - (s.explosion_radius or 0)
	local dd = (state.damage_explosion_add or 0) - (s.damage_explosion_add or 0)
	return dr > 0 or (dr == 0 and dd > 0)
end

-- Applies every change made since snapshot `s` the other way round. Returns whether a projectile number was flipped
-- (cast delay, recharge, mana and recoil are flipped too, but don't count: Field Imbue only cares about the
-- projectile), and whether the explosion became an implosion.
local function flip_since(state, s, can_implode)
	local flipped, heal = false, 0
	local implosion = can_implode and implodes(s, state)
	for _, k in ipairs(ADD) do
		local was, now = s[k], state[k]
		if implosion and (k == "explosion_radius" or k == "damage_explosion_add") then
			flipped = true -- kept: the implosion uses them
		elseif num(was) and num(now) and now ~= was then
			local v = was - (now - was)
			if DAMAGE[k] and v < was then
				heal = heal + (v - was)
				v = was
			end
			state[k] = v
			flipped = true
		end
	end
	if heal ~= 0 then -- after the loop, which also flips the healing a modifier itself added
		state.damage_healing_add = (state.damage_healing_add or 0) + heal
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
	end
	was, now = s.reload, current_reload_time
	if num(was) and num(now) and now ~= was and flips_wand_change(was - now) then
		current_reload_time = was - (now - was)
	end
	was, now = s.mana, mana
	if num(was) and num(now) and now ~= was and flips_wand_change(now - was) then
		local v = math.max(0, was - (now - was)) -- a drain takes at most what the wand has
		if v > was then -- a spend turned into a gain gives back at most what the shot started with
			v = math.min(v, math.max(was, shot_mana or was))
		end
		mana = v
	end
	was, now = s.recoil, shot_effects and shot_effects.recoil_knockback
	if num(was) and num(now) and now ~= was then -- a flipped Recoil pushes forwards
		shot_effects.recoil_knockback = was - (now - was)
	end
	return flipped, implosion
end

-- Add mana's bonus is its negative mana cost, which draw_action paid out before the action ran
local function flip_card_mana(id)
	local a = current_action
	if a and a.id == id and num(a.mana) and a.mana < 0 and flips_wand_change(-a.mana) then
		mana = math.max(0, mana + 2 * a.mana)
	end
end

-- what flipped modifiers add becomes its opposite: files/scripts/opposites_build.lua works it out at mod init
local opposites
local function get_opposites()
	if opposites == nil then
		local ok, o = pcall(dofile_once, "mods/sign_flip/files/gen/opposites.lua")
		opposites = ok and type(o) == "table" and o or false
	end
	return opposites
end

-- the part of a comma-separated list appended since the snapshot
local function appended(was, now)
	if type(was) == "string" and type(now) == "string" and #now > #was and now:sub(1, #was) == was then
		return now:sub(#was + 1)
	end
	return nil
end

-- What the modifier added to the shot since snapshot `s` becomes its opposite: Homing steers away, converters run
-- backwards, Fly upwards flies down, and a trail (or Burning trail's fire) takes its material away instead of pouring
-- it, without its on-hit effect. True if anything changed.
local function opposites_since(state, s)
	local O = get_opposites()
	if not O then
		return false
	end
	local changed, drop_effects = false, false
	local extras = appended(s.extra_entities, state.extra_entities)
	if extras then
		local out = {}
		for f in extras:gmatch("[^,]+") do
			local r = O.extra[f]
			if r then
				changed = true
				drop_effects = drop_effects or O.drops_effects[f] == true
				f = r
			end
			out[#out + 1] = f .. ","
		end
		if changed then
			state.extra_entities = s.extra_entities .. table.concat(out)
		end
	end
	local trails = appended(s.trail_material, state.trail_material)
	if trails then
		local eaters = {}
		for m in trails:gmatch("[^,]+") do
			if O.eat[m] then
				eaters[#eaters + 1] = O.eat[m] .. ","
			end
		end
		if #eaters > 0 then
			state.trail_material = s.trail_material
			state.trail_material_amount = s.trail_material_amount
			state.extra_entities = state.extra_entities .. table.concat(eaters)
			changed, drop_effects = true, true
		end
	end
	if drop_effects and appended(s.game_effect_entities, state.game_effect_entities) then
		state.game_effect_entities = s.game_effect_entities -- no burning, wet, oiled or poisoned targets either
	end
	return changed
end

-- The flipped modifier that is running and hasn't drawn a card yet. A modifier it runs directly takes the flip instead
-- (Random modifier runs the modifier it picked).
local open
local function still_open()
	return open and not open.drawn and open.s.cards == state_cards_drawn
end

-- Runs a modifier that takes a pending flip. Both draw functions are hooked, so a modifier that draws with
-- draw_action directly is measured the same way as one that calls draw_actions.
local function run_flipped(state, id, fresh, action, ...)
	flip_card_mana(id)
	local frame = { id = id, s = snapshot(state), fresh = fresh } -- after flip_card_mana: that drain is not the modifier's own change
	local real_draw, real_one, outer = draw_actions, draw_action, open
	local flipped, dead = false, false -- flipped: anything that matters to the projectile (numbers or opposites)
	local function flip()
		-- cards drawn past the hooks (a draw function the modifier captured itself) mix their changes in: the flip is
		-- used up; a Random modifier pick of Field resonance passes it on (frame.pass)
		if dead or frame.pass or state_cards_drawn ~= frame.s.cards then
			dead = true
			return
		end
		local O = get_opposites()
		local numbers, implosion = flip_since(state, frame.s, O and O.implode ~= nil)
		local opposite = opposites_since(state, frame.s)
		if implosion then
			state.extra_entities = state.extra_entities .. O.implode .. ","
		end
		flipped = flipped or numbers or opposite
	end
	local hook, hook_one
	-- It draws the next cards: what it changed so far is its own. Put the real draw functions back first, so the
	-- modifiers drawn now don't run into these hooks; hook them again afterwards, in case it draws again.
	local function enter()
		draw_actions, draw_action = real_draw, real_one
		frame.drawn = true
		if open == frame then
			open = outer
		end
		flip()
	end
	local function leave()
		frame.s = snapshot(state)
		draw_actions, draw_action = hook, hook_one
	end
	hook = function(...)
		enter()
		real_draw(...)
		leave()
	end
	hook_one = function(...)
		enter()
		local r = { real_one(...) } -- draw_actions retries when it returns false
		leave()
		return unpack(r, 1, table.maxn(r))
	end
	open = frame
	draw_actions, draw_action = hook, hook_one
	local result = { pcall(action, ...) }
	if draw_actions == hook then
		draw_actions = real_draw
	end
	if draw_action == hook_one then
		draw_action = real_one
	end
	open = outer
	if not result[1] then
		error(result[2], 0) -- the cast is aborted: nothing left to flip
	end
	-- what it changed after its last draw, or everything if it never drew
	flip()
	if flipped then
		-- the modifiers of this shot whose projectile numbers or parts were flipped; Field Imbue's register_action
		-- wrapper reads it
		state.sf_negated = (state.sf_negated or "") .. frame.id .. ","
	end
	return unpack(result, 2, table.maxn(result))
end

local function sign_flip(state)
	if still_open() then
		-- this Sign flip is the modifier being flipped (Random modifier picked it): a flipped Sign flip does nothing
		open.id = "SIGN_FLIP"
		return
	end
	-- a Sign flip right after another one is the modifier that one flips: the two cancel out
	local n = state.sf_pending or 0
	state.sf_pending = n > 0 and n - 1 or 1
	-- until the next card plays, a projectile spell can still take the flip (run_spell_flipped)
	state.sf_fresh = n == 0 or nil
end

-- The projectile spell played right after a Sign flip takes the flip (decided with the user), even when it has nothing
-- to flip: a Black hole becomes a White hole and back (the files are swapped as the spell adds them), and the spell's
-- own explosion becomes an implosion. The implode marker for each file it adds goes into the shot; the marker only
-- acts on projectiles made from that file (files/scripts/implode.lua), so the shot's other spells keep exploding.
local SPAWNERS = { "add_projectile", "add_projectile_trigger_timer", "add_projectile_trigger_hit_world",
	"add_projectile_trigger_death" }
local function run_spell_flipped(state, action, ...)
	local O = get_opposites() or {}
	local real, hooks, files = {}, {}, {}
	for i, name in ipairs(SPAWNERS) do
		real[i] = _G[name]
	end
	local function set(list)
		for i, name in ipairs(SPAWNERS) do
			_G[name] = list[i]
		end
	end
	for i in ipairs(SPAWNERS) do
		hooks[i] = function(file, ...)
			local hole = O.holes and O.holes[file]
			if hole then
				file = hole
			elseif not files[file] then
				files[file] = true
				files[#files + 1] = file
			end
			-- a trigger draws its payload inside: that is another shot, so it sees the real functions
			set(real)
			local r = { pcall(real[i], file, ...) }
			set(hooks)
			if not r[1] then
				error(r[2], 0)
			end
			return unpack(r, 2, table.maxn(r))
		end
	end
	set(hooks)
	local result = { pcall(action, ...) }
	set(real)
	if not result[1] then
		error(result[2], 0)
	end
	for _, file in ipairs(files) do
		local marker = O.spell and O.spell[file]
		if marker then
			state.extra_entities = state.extra_entities .. marker .. ","
		end
	end
	return unpack(result, 2, table.maxn(result))
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
		elseif id == "FIELD_IMBUE" then
			-- Field Imbue's Field resonance has nothing to flip, and a pending flip passes over it to the next modifier
			-- (decided with the user): "Sign flip -> Field resonance -> X" flips X, like "Field resonance -> Sign flip -> X".
			a.action = function(...)
				if not reflecting and c and still_open() then
					open.pass = true -- Random modifier picked it: hand the flip on as well, still fresh if it was
					c.sf_pending = (c.sf_pending or 0) + 1
					c.sf_fresh = open.fresh
				end
				return action(...)
			end
			a.sf_wrapped = true
		elseif a.type == ACTION_TYPE_MODIFIER then
			a.action = function(...)
				if reflecting or not c then
					return action(...)
				end
				local fresh = c.sf_fresh
				c.sf_fresh = nil
				if still_open() then
					open.id = id -- run directly by the flipped modifier (Random modifier's pick): this one is flipped
					return action(...)
				end
				local n = c.sf_pending or 0
				if n <= 0 then
					return action(...)
				end
				c.sf_pending = n - 1
				return run_flipped(c, id, fresh, action, ...)
			end
			a.sf_wrapped = true
		elseif a.type == ACTION_TYPE_PROJECTILE or a.type == ACTION_TYPE_STATIC_PROJECTILE
			or a.type == ACTION_TYPE_MATERIAL then
			a.action = function(...)
				if reflecting or not c then
					return action(...)
				end
				local fresh, n = c.sf_fresh, c.sf_pending or 0
				c.sf_fresh = nil
				if not fresh or n <= 0 then
					return action(...)
				end
				c.sf_pending = n - 1
				return run_spell_flipped(c, action, ...)
			end
			a.sf_wrapped = true
		else
			-- any other card (multicast, trigger adders, ...) in between: the flip waits for the next modifier again
			a.action = function(...)
				if reflecting or not c then
					return action(...)
				end
				local shot = c
				shot.sf_fresh = nil
				local r = { action(...) }
				-- a Sign flip it replayed without drawing (Add trigger, Omega, Divide by) is in front of no spell either
				shot.sf_fresh = nil
				return unpack(r, 1, table.maxn(r))
			end
			a.sf_wrapped = true
		end
	end
end
