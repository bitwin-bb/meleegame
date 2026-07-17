local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

local Maid = require("Maid")

local React: any = require(ReplicatedStorage.Packages.React)

type MaidClass = any

export type CrossFadeOptions = {
	id: string,
	targetTransparency: number,
	fadeSeconds: number?,
}

local DEFAULT_FADE_SECONDS = 0.4
local TRANSPARENCY_EPSILON = 0.002

local function coerceTransparency(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return 1
	end
	return math.clamp(valueRaw, 0, 1)
end

local function getFadeSeconds(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return DEFAULT_FADE_SECONDS
	end
	return math.max(valueRaw, 0.001)
end

local function useCrossFade(options: CrossFadeOptions): number
	local targetTransparency = coerceTransparency(options.targetTransparency)
	local fadeSeconds = getFadeSeconds(options.fadeSeconds)
	local transparencyRef = React.useRef(targetTransparency)
	local targetRef = React.useRef(targetTransparency)
	local transparency, setTransparency = React.useState(transparencyRef.current)

	React.useEffect(function()
		targetRef.current = targetTransparency
	end, { targetTransparency })

	React.useEffect(function()
		local maid = Maid.new() :: MaidClass
		maid:GiveTask(RunService.RenderStepped:Connect(function(deltaTime: number)
			local currentTransparency = transparencyRef.current
			local nextTarget = targetRef.current
			local alpha = math.clamp(deltaTime / fadeSeconds, 0, 1)
			local nextTransparency = currentTransparency + (nextTarget - currentTransparency) * alpha

			if math.abs(nextTransparency - nextTarget) <= TRANSPARENCY_EPSILON then
				nextTransparency = nextTarget
			end

			if nextTransparency ~= currentTransparency then
				transparencyRef.current = nextTransparency
				setTransparency(nextTransparency)
			end
		end))

		return function()
			maid:DoCleaning()
		end
	end, { options.id, fadeSeconds } :: { any })

	return transparency
end

return useCrossFade
