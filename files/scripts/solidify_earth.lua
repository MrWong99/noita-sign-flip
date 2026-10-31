-- A flipped Crumbling earth (files/entities/solidify_earth.xml), when the projectile is removed: leaves the hardening
-- converter where it ended, as vanilla's crumbling_earth_projectile.lua leaves the loose ground.

local x, y = EntityGetTransform(EntityGetRootEntity(GetUpdatedEntityID()))
EntityLoad("mods/sign_flip/files/entities/solidify_earth_burst.xml", x, y)
