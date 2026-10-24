-- The Sign flip card. Its own action only draws the next card: files/gun_append.lua wraps it and every other
-- modifier once all mods' spells exist, and does the flipping there.
table.insert(actions, {
	id = "SIGN_FLIP",
	name = "Sign flip",
	description = "Negates the next modifier: +damage becomes -damage, faster becomes slower, gravity pulls upwards",
	sprite = "mods/sign_flip/files/ui_gfx/sign_flip.png",
	type = ACTION_TYPE_MODIFIER,
	spawn_level = "2,3,4,5,6",
	spawn_probability = "0.3,0.4,0.4,0.4,0.3",
	price = 150,
	mana = 10,
	action = function()
		draw_actions(1, true)
	end,
})
