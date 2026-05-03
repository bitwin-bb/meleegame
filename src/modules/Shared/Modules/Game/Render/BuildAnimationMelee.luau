--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

export type Options = {
	swingPriority: Enum.AnimationPriority?,
	returnNilIfEmpty: boolean?,
}

local function BuildAnimationMelee(sourceRaw: any, optionsRaw: any): { [string]: any }?
	if typeof(sourceRaw) ~= "table" then
		return nil
	end

	local options = if typeof(optionsRaw) == "table" then (optionsRaw :: Options) else nil
	local source = sourceRaw :: { [string]: any }
	local swingPriority = if options ~= nil then options.swingPriority else nil
	local returnNilIfEmpty = if options ~= nil then options.returnNilIfEmpty == true else false

	local swings: { [number]: { [string]: any } } = {}
	if typeof(source.Swings) == "table" then
		for index, animationId in source.Swings do
			if typeof(index) == "number" and typeof(animationId) == "string" and animationId ~= "" then
				local clip: { [string]: any } = {
					name = ("Swing%d"):format(index),
					id = animationId,
				}
				if swingPriority ~= nil then
					clip.priority = swingPriority
				end
				swings = Sift.Array.append(swings, clip)
			end
		end
	end

	swings = Sift.Array.sort(swings, function(lhs, rhs)
		return lhs.name < rhs.name
	end)

	local namedAnimations: { [string]: any } = {}
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

	if returnNilIfEmpty and #swings <= 0 and next(namedAnimations) == nil then
		return nil
	end

	return {
		mode = "Sequence",
		namedAnimations = namedAnimations,
		clips = swings,
	}
end

return BuildAnimationMelee
