--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Animations = require(gameRoot.Shared.Features.item.modules.Animations)
local BuildAnimationMelee = require(gameRoot.Shared.Game.Render.BuildAnimationMelee)

local weaponAnimationIds = (((Animations :: any).Items or ({} :: any)).Weapons or ({} :: any)) :: { [string]: any }

return {
	["CopperShortSword"] = {
		name = "Copper Shortsword",
		description = "Your very first weapon!",
		functionality = "Weapon",
		damage = 10,
		melee = {
			animations = BuildAnimationMelee(weaponAnimationIds.CopperShortSword),
		},
	},
	["CopperBroadSword"] = {
		name = "Copper Broadsword",
		description = "Apparently this weapon is quite the heavy hitter! Although time your attacks or else you'll die terribly",
		functionality = "Weapon",
		damage = 10,
		melee = {
			animations = BuildAnimationMelee(weaponAnimationIds.CopperBroadSword),
		},
	},
	["Katana"] = {
		name = "Katana",
		description = "A weapon used by legendary ninjas or samurai. You feel like Bruce Lee",
		functionality = "Weapon",
		damage = 10,
		melee = {
			animations = BuildAnimationMelee(weaponAnimationIds.Katana),
		},
	},
}
