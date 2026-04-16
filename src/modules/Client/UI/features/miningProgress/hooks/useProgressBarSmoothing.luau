--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Damp = require(script:FindFirstAncestor("game").Shared.Modules.Math.Damp)

export type ProgressBarSmoothingOptions = {
	progress: number?,
	visible: boolean?,
	gainRate: number?,
	depletionRate: number?,
}

local DEFAULT_GAIN_RATE = 22
local DEFAULT_DEPLETION_RATE = 10
local EPSILON = 0.0005

local function sanitizeProgress(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return 0
	end
	return math.clamp(valueRaw, 0, 1)
end

local function sanitizePositiveRate(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw or valueRaw <= 0 then
		return fallback
	end
	return valueRaw
end

local function smoothStep(current: number, target: number, rate: number, deltaTime: number): number
	local alpha = Damp.factor(rate, deltaTime)
	return current + ((target - current) * alpha)
end

local function useProgressBarSmoothing(options: ProgressBarSmoothingOptions?): number
	local visible = if options and options.visible ~= nil then options.visible else true
	local gainRate = sanitizePositiveRate(if options then options.gainRate else nil, DEFAULT_GAIN_RATE)
	local depletionRate = sanitizePositiveRate(if options then options.depletionRate else nil, DEFAULT_DEPLETION_RATE)
	local target = if visible then sanitizeProgress(if options then options.progress else nil) else 0

	local currentRef = React.useRef(target)
	local targetRef = React.useRef(target)
	local smoothProgress, setSmoothProgress = React.useState(target)

	React.useEffect(function()
		targetRef.current = target
	end, { target })

	React.useEffect(function()
		local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			local current = currentRef.current
			local nextTarget = targetRef.current
			local rate = if nextTarget >= current then gainRate else depletionRate
			local nextValue = smoothStep(current, nextTarget, rate, deltaTime)

			if math.abs(nextValue - nextTarget) <= EPSILON then
				nextValue = nextTarget
			end

			if math.abs(nextValue - currentRef.current) > EPSILON then
				currentRef.current = nextValue
				setSmoothProgress(nextValue)
			end
		end)

		return function()
			connection:Disconnect()
		end
	end, { gainRate, depletionRate })

	return smoothProgress
end

return useProgressBarSmoothing
