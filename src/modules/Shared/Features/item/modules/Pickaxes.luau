--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local Animations = require(gameRoot.Shared.Features.item.modules.Animations)
local BuildAnimationMelee = require(gameRoot.Shared.Game.Render.BuildAnimationMelee)

local pickaxeAnimationIds = (((Animations :: any).Items or ({} :: any)).Pickaxes or ({} :: any)) :: { [string]: any }

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
	local enrichedDefinition = Sift.Dictionary.copy(definition :: any)
	local pickaxeAnimations = BuildAnimationMelee((pickaxeAnimationIds :: any)[itemId], {
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
