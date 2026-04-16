--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)


local Animations = require(script.Parent.Animations)
local BuildAnimationMelee = require(script.Parent.Parent.Game.BuildAnimationMelee)

local axeAnimationIds = (((Animations :: any).Items or {}).Axes or {}) :: { [string]: any }

local rawAxes = {
	["CopperAxe"] = {
		name = "Copper Axe",
		description = "This is your starter axe. May not be the best axe in the world, but use it to chop wood",
		damage = 5,
		power = "50%",
		swingSpeed = 1,
		itemType = "axe",
	},
}

local axes = {}
for itemId, definition in rawAxes do
	local enrichedDefinition = Sift.Dictionary.copy(definition)
	local axeAnimations = BuildAnimationMelee(axeAnimationIds[itemId], {
		swingPriority = Enum.AnimationPriority.Action,
		returnNilIfEmpty = true,
	})
	if axeAnimations ~= nil then
		enrichedDefinition.melee = {
			animations = axeAnimations,
		}
	end
	axes[itemId] = enrichedDefinition
end

return axes
