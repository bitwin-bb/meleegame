--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local Animations = require(gameRoot.Shared.Features.item.modules.Animations)
local BuildAnimationMelee = require(gameRoot.Shared.Game.Render.BuildAnimationMelee)

local axeAnimationIds = (((Animations :: any).Items or ({} :: any)).Axes or ({} :: any)) :: { [string]: any }

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
	local enrichedDefinition = Sift.Dictionary.copy(definition :: any)
	local axeAnimations = BuildAnimationMelee((axeAnimationIds :: any)[itemId], {
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
