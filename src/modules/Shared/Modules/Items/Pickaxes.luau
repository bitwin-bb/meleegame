--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)


local Animations = require(script.Parent.Animations)
local BuildAnimationMelee = require(script.Parent.Parent.Game.BuildAnimationMelee)

local pickaxeAnimationIds = (((Animations :: any).Items or {}).Pickaxes or {}) :: { [string]: any }

local rawPickaxes = {
	["CopperPickaxe"] = {
		name = "Copper Pickaxe",
		description = "If you want to get powerful, then you better start mining!",
		damage = 3,
		power = "50%",
		swingSpeed = 1.3,
		itemType = "pickaxe",
	},
}

local pickaxes = {}
for itemId, definition in rawPickaxes do
	local enrichedDefinition = Sift.Dictionary.copy(definition)
	local pickaxeAnimations = BuildAnimationMelee(pickaxeAnimationIds[itemId], {
		swingPriority = Enum.AnimationPriority.Action,
		returnNilIfEmpty = true,
	})
	if pickaxeAnimations ~= nil then
		enrichedDefinition.melee = {
			animations = pickaxeAnimations,
		}
	end
	pickaxes[itemId] = enrichedDefinition
end

return pickaxes
