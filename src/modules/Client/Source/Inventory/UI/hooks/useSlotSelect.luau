local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

local Ease = require("Ease")
local React: any = require(ReplicatedStorage.Packages.React)

export type SlotSelectOptions = {
	enabled: boolean?,
	normalScale: number?,
	selectedScale: number?,
	duration: number?,
}

local DEFAULT_NORMAL_SCALE = 1
local DEFAULT_SELECTED_SCALE = 1.12
local DEFAULT_DURATION = 0.16
local SCALE_EPSILON = 0.001

local function coerceScale(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw or valueRaw <= 0 then
		return fallback
	end
	return valueRaw
end

local function coerceDuration(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw or valueRaw <= 0 then
		return DEFAULT_DURATION
	end
	return math.clamp(valueRaw, 0.01, 1)
end

local function useSlotSelect(options: SlotSelectOptions?): number
	local enabled = if options and options.enabled ~= nil then options.enabled else false
	local normalScale = coerceScale(if options then options.normalScale else nil, DEFAULT_NORMAL_SCALE)
	local selectedScale = coerceScale(if options then options.selectedScale else nil, DEFAULT_SELECTED_SCALE)
	local duration = coerceDuration(if options then options.duration else nil)
	local targetScale = if enabled then selectedScale else normalScale
	local targetRef = React.useRef(targetScale)
	local animationRef = React.useRef(nil :: { fromScale: number, toScale: number, startedAt: number }?)
	local scale, setScale = React.useState(targetScale)
	local scaleRef = React.useRef(scale)

	React.useEffect(function()
		scaleRef.current = scale
	end, { scale })

	React.useEffect(function()
		if math.abs(targetRef.current - targetScale) <= SCALE_EPSILON then
			return
		end

		targetRef.current = targetScale
		animationRef.current = {
			fromScale = scaleRef.current,
			toScale = targetScale,
			startedAt = os.clock(),
		}
	end, { targetScale })

	React.useEffect(function()
		local connection = RunService.RenderStepped:Connect(function(_deltaTime: number)
			local animation = animationRef.current
			if animation == nil then
				return
			end

			local alpha = math.clamp((os.clock() - animation.startedAt) / duration, 0, 1)
			local nextScale = animation.toScale
			if alpha < 1 then
				local easedAlpha = Ease.OutBack(alpha)
				nextScale = animation.fromScale + (animation.toScale - animation.fromScale) * easedAlpha
			else
				animationRef.current = nil
			end

			if math.abs(scaleRef.current - nextScale) <= SCALE_EPSILON then
				return
			end

			scaleRef.current = nextScale
			setScale(nextScale)
		end)

		return function()
			connection:Disconnect()
		end
	end, { duration })

	return scale
end

return useSlotSelect
