--!strict

local Animations = require(script.Parent.Animations)

local axeAnimationIds = (((Animations :: any).Items or {}).Axes or {}) :: { [string]: any }

local function buildAxeAnimations(sourceRaw: any): { [string]: any }?
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
	local enrichedDefinition = table.clone(definition)
	local axeAnimations = buildAxeAnimations(axeAnimationIds[itemId])
	if axeAnimations ~= nil then
		enrichedDefinition.melee = {
			animations = axeAnimations,
		}
	end
	axes[itemId] = enrichedDefinition
end

return axes
