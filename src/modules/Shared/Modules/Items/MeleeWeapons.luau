--!strict

local Animations = require(script.Parent.Animations)
local BuildAnimationMelee = require(script.Parent.Parent.Game.BuildAnimationMelee)

local weaponAnimationIds = (((Animations :: any).Items or {}).Weapons or {}) :: { [string]: any }

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
