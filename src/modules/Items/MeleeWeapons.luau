--!strict

local Animations = require(script.Parent.Animations)

local weaponAnimationIds = (((Animations :: any).Items or {}).Weapons or {}) :: { [string]: any }

local function buildWeaponAnimations(sourceRaw: any): { [string]: any }?
	if typeof(sourceRaw) ~= "table" then
		return nil
	end

	local source = sourceRaw :: { [string]: any }
	local swings = {}
	if typeof(source.Swings) == "table" then
		for index, animationId in source.Swings do
			if typeof(index) == "number" and typeof(animationId) == "string" and animationId ~= "" then
				table.insert(swings, {
					name = ("Swing%d"):format(index),
					id = animationId,
				})
			end
		end
	end

	table.sort(swings, function(lhs, rhs)
		return lhs.name < rhs.name
	end)

	local namedAnimations = {}
	if typeof(source.Equip) == "string" and source.Equip ~= "" then
		namedAnimations.Equip = {
			id = source.Equip,
			looped = false,
		}
	end
	if typeof(source.Idle) == "string" and source.Idle ~= "" then
		namedAnimations.Idle = {
			id = source.Idle,
			looped = true,
		}
	end

	return {
		mode = "Sequence",
		namedAnimations = namedAnimations,
		clips = swings,
	}
end

return {
	["CopperShortSword"] = {
		name = "Copper Shortsword",
		description = "Your very first weapon!",
		functionality = "Weapon",
		damage = 10,
		melee = {
			animations = buildWeaponAnimations(weaponAnimationIds.CopperShortSword),
		},
	},
	["CopperBroadSword"] = {
		name = "Copper Broadsword",
		description = "Apparently this weapon is quite the heavy hitter! Although time your attacks or else you'll die terribly",
		functionality = "Weapon",
		damage = 10,
		melee = {
			animations = buildWeaponAnimations(weaponAnimationIds.CopperBroadSword),
		},
	},
	["Katana"] = {
		name = "Katana",
		description = "A weapon used by legendary ninjas or samurai. You feel like Bruce Lee",
		functionality = "Weapon",
		damage = 10,
		melee = {
			animations = buildWeaponAnimations(weaponAnimationIds.Katana),
		},
	},
}
