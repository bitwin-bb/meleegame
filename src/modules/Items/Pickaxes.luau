--!strict

local Animations = require(script.Parent.Animations)

local pickaxeAnimationIds = (((Animations :: any).Items or {}).Pickaxes or {}) :: { [string]: any }

local function buildPickaxeAnimations(sourceRaw: any): { [string]: any }?
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
					priority = Enum.AnimationPriority.Action,
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

	if #swings <= 0 and next(namedAnimations) == nil then
		return nil
	end

	return {
		mode = "Sequence",
		namedAnimations = namedAnimations,
		clips = swings,
	}
end

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
	local enrichedDefinition = table.clone(definition)
	local pickaxeAnimations = buildPickaxeAnimations(pickaxeAnimationIds[itemId])
	if pickaxeAnimations ~= nil then
		enrichedDefinition.melee = {
			animations = pickaxeAnimations,
		}
	end
	pickaxes[itemId] = enrichedDefinition
end

return pickaxes
