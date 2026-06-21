local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

local Ease = require("Ease")
local React = require(ReplicatedStorage.Packages.React)

export type SlotSelectOptions = {
	enabled: boolean?,
	normalScale: number?,
	selectedScale: number?,
	duration: number?,
}

local DEFAULT_NORMAL_SCALE = 1
local DEFAULT_SELECTED_SCALE = 1.12
local DEFAULT_DURATION = 0.16
local PROGRESS_EPSILON = 0.001

local function sanitizeScale(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw or valueRaw <= 0 then
		return fallback
	end
	return valueRaw
end

local function sanitizeDuration(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw or valueRaw <= 0 then
		return DEFAULT_DURATION
	end
	return math.clamp(valueRaw, 0.01, 1)
end

local function useSlotSelect(options: SlotSelectOptions?): number
	local enabled = if options and options.enabled ~= nil then options.enabled else false
	local normalScale = sanitizeScale(if options then options.normalScale else nil, DEFAULT_NORMAL_SCALE)
	local selectedScale =
		math.max(normalScale, sanitizeScale(if options then options.selectedScale else nil, DEFAULT_SELECTED_SCALE))
	local duration = sanitizeDuration(if options then options.duration else nil)
	local targetProgress = if enabled then 1 else 0
	local targetRef = React.useRef(targetProgress)
	local animationRef = React.useRef(nil :: { fromProgress: number, toProgress: number, startedAt: number }?)
	local progress, setProgress = React.useState(targetProgress)
	local progressRef = React.useRef(progress)

	React.useEffect(function()
		progressRef.current = progress
	end, { progress })

	React.useEffect(function()
		if targetRef.current == targetProgress then
			return
		end

		targetRef.current = targetProgress
		animationRef.current = {
			fromProgress = progressRef.current,
			toProgress = targetProgress,
			startedAt = os.clock(),
		}
	end, { targetProgress })

	React.useEffect(function()
		local connection = RunService.RenderStepped:Connect(function(_deltaTime: number)
			local animation = animationRef.current
			if animation == nil then
				return
			end

			local alpha = math.clamp((os.clock() - animation.startedAt) / duration, 0, 1)
			local nextProgress = animation.toProgress
			if alpha < 1 then
				local easedAlpha = Ease.outBack(alpha)
				nextProgress = animation.fromProgress + (animation.toProgress - animation.fromProgress) * easedAlpha
			else
				animationRef.current = nil
			end

			if math.abs(progressRef.current - nextProgress) <= PROGRESS_EPSILON then
				return
			end

			progressRef.current = nextProgress
			setProgress(nextProgress)
		end)

		return function()
			connection:Disconnect()
		end
	end, { duration })

	return normalScale + (selectedScale - normalScale) * progress
end

return useSlotSelect
